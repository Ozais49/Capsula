import 'dart:async';

import 'package:capsula_core/api/api_json.dart';
import 'package:capsula_core/domain/bookmarks/bookmark.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_repository.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_service.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_source.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_view.dart';
import 'package:capsula_core/domain/bookmarks/url_normalizer.dart';
import 'package:capsula_core/domain/organization/label.dart';
import 'package:capsula_core/domain/reader/page_info_service.dart';
import 'package:capsula_core/domain/reader/reader_content.dart';
import 'package:capsula_core/domain/reader/reader_service.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'auth.dart';
import 'http.dart';

/// A user's data, scoped so callers can't reach anyone else's.
class UserData {
  const UserData(this.bookmarks, this.labels);

  final BookmarkRepository bookmarks;
  final LabelRepository labels;
}

typedef UserDataFactory = UserData Function(String uid);

const _maxListLimit = 500;

/// The Capsula REST API (v1).
class CapsulaApi {
  CapsulaApi({
    required this.authenticator,
    required this.userData,
    required this.tokens,
    required this.pageInfo,
    required this.reader,
    required this.rateLimiter,
    this.corsOrigins = const ['*'],
    this.log,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Authenticator authenticator;
  final UserDataFactory userData;
  final TokenStore tokens;
  final PageInfoSource pageInfo;
  final ReaderSource reader;
  final RateLimiter rateLimiter;
  final List<String> corsOrigins;
  final void Function(Object error, StackTrace stack)? log;
  final DateTime Function() _now;

  Handler get handler => const Pipeline()
      .addMiddleware(cors(corsOrigins))
      .addMiddleware(errorHandling(log: log))
      .addHandler(_router.call);

  Router get _router {
    final r = Router(notFoundHandler: (_) => throw const ApiError.notFound());
    r.get('/v1/health', (Request _) => jsonResponse({'status': 'ok'}));

    r.get(
      '/v1/me',
      _authed((req, p) async {
        return jsonResponse({
          'uid': p.uid,
          'auth': p.viaApiToken ? 'api_token' : 'firebase',
        });
      }),
    );

    // Bookmarks
    r.get('/v1/bookmarks', _authed(_listBookmarks));
    r.get('/v1/bookmarks/export', _authed(_exportBookmarks));
    r.post('/v1/bookmarks', _authed(_createBookmark));
    r.get('/v1/bookmarks/<id>', _authedWithId(_getBookmark));
    r.patch('/v1/bookmarks/<id>', _authedWithId(_updateBookmark));
    r.delete('/v1/bookmarks/<id>', _authedWithId(_deleteBookmark));

    // Tags and collections
    for (final kind in LabelKind.values) {
      final path = '/v1/${_labelPath(kind)}';
      r.get(path, _authed((req, p) => _listLabels(p, kind)));
      r.post(path, _authed((req, p) => _createLabel(req, p, kind)));
      r.patch(
        '$path/<id>',
        _authedWithId((req, p, id) => _renameLabel(req, p, kind, id)),
      );
      r.delete(
        '$path/<id>',
        _authedWithId((req, p, id) => _deleteLabel(p, kind, id)),
      );
    }

    // Server-side fetching (no browser CORS limits)
    r.get('/v1/page-info', _authed(_pageInfo));
    r.get('/v1/reader', _authed(_reader));

    // Personal API tokens
    r.get('/v1/tokens', _authed(_listTokens));
    r.post('/v1/tokens', _authed(_createToken));
    r.delete('/v1/tokens/<id>', _authedWithId(_deleteToken));
    return r;
  }

  // ---------------------------------------------------------------------------
  // Auth plumbing

  Handler _authed(
    FutureOr<Response> Function(Request request, Principal principal) handler,
  ) => (Request request) async {
    final principal = await authenticator.authenticate(
      request.headers['authorization'],
    );
    if (principal == null) {
      throw const ApiError(
        401,
        'unauthorized',
        'Send "Authorization: Bearer <Firebase ID token or API token>"',
      );
    }
    if (!rateLimiter.allow(principal.uid)) {
      throw const ApiError(429, 'rate_limited', 'Too many requests');
    }
    return handler(request, principal);
  };

  Function _authedWithId(
    FutureOr<Response> Function(Request, Principal, String id) handler,
  ) =>
      (Request request, String id) =>
          _authed((req, p) => handler(req, p, id))(request);

  BookmarkService _service(Principal p) {
    final data = userData(p.uid);
    return BookmarkService(data.bookmarks, data.labels, now: _now);
  }

  // ---------------------------------------------------------------------------
  // Bookmarks

  Future<Response> _listBookmarks(Request req, Principal p) async {
    final params = req.url.queryParameters;
    final limit = (int.tryParse(params['limit'] ?? '') ?? 50).clamp(
      1,
      _maxListLimit,
    );
    final query = BookmarkQuery(
      view: BookmarkView.parse(params['view'] ?? 'all'),
      search: params['q'] ?? '',
    );
    final list = await userData(p.uid).bookmarks
        .watchList(query, limit: limit)
        .first;
    return jsonResponse({
      'bookmarks': list.map(bookmarkToJson).toList(),
      'view': query.view.key,
    });
  }

  Future<Response> _exportBookmarks(Request req, Principal p) async {
    final all = await userData(p.uid).bookmarks.fetchAll();
    return jsonResponse({'bookmarks': all.map(bookmarkToJson).toList()});
  }

  Future<Response> _getBookmark(Request req, Principal p, String id) async {
    final b = await userData(p.uid).bookmarks.watch(id).first;
    if (b == null) throw const ApiError.notFound('No bookmark with this ID');
    return jsonResponse(bookmarkToJson(b));
  }

  Future<Response> _createBookmark(Request req, Principal p) async {
    final body = await readJson(req);
    final url = body['url'];
    if (url is! String) throw const ApiError.badRequest('"url" is required');
    final title = _optionalString(body, 'title', 1000);
    final service = _service(p);

    final result = await service.save(url, title: title);
    switch (result) {
      case InvalidUrl():
        throw const ApiError.badRequest('"url" is not a web address');
      case AlreadySaved(:final existing):
        return jsonResponse({
          'error': {
            'code': 'already_saved',
            'message': 'This link is already saved',
          },
          'bookmark': bookmarkToJson(existing),
        }, status: 409);
      case Saved(:final bookmark, :final committed):
        await committed;
        var saved = bookmark;
        saved = await _applyChanges(service, p, saved, body);
        if (body['fetchDetails'] != false) {
          saved =
              await service
                  .fetchDetails(saved, pageInfo)
                  .timeout(
                    const Duration(seconds: 10),
                    onTimeout: () => null,
                  ) ??
              saved;
        }
        // Return what was written; re-reading could race the background
        // write of fetched details.
        return jsonResponse(bookmarkToJson(saved), status: 201);
    }
  }

  Future<Response> _updateBookmark(Request req, Principal p, String id) async {
    final repo = userData(p.uid).bookmarks;
    final existing = await repo.watch(id).first;
    if (existing == null) {
      throw const ApiError.notFound('No bookmark with this ID');
    }
    final body = await readJson(req);
    final updated = await _applyChanges(_service(p), p, existing, body);
    return jsonResponse(bookmarkToJson(updated));
  }

  /// Applies the editable fields present in [body] and saves once.
  Future<Bookmark> _applyChanges(
    BookmarkService service,
    Principal p,
    Bookmark b,
    Map<String, Object?> body,
  ) async {
    var next = b;
    var changed = false;

    if (_optionalString(body, 'title', 1000) case final title?) {
      if (title.trim().isEmpty) {
        throw const ApiError.badRequest('"title" can\'t be empty');
      }
      next = next.copyWith(title: title.trim());
      changed = true;
    }
    if (_optionalString(body, 'description', 5000) case final d?) {
      next = next.copyWith(description: d);
      changed = true;
    }
    if (body['readingStatus'] case final Object status) {
      final match = ReadingStatus.values.where((s) => s.name == status);
      if (match.isEmpty) {
        throw ApiError.badRequest(
          '"readingStatus" must be one of '
          '${ReadingStatus.values.map((s) => s.name).join(', ')}',
        );
      }
      next = next.copyWith(readingStatus: match.single);
      changed = true;
    }
    if (body['inInbox'] case final Object inbox) {
      next = next.copyWith(inInbox: _bool(inbox, 'inInbox'));
      changed = true;
    }
    if (body['archived'] case final Object archived) {
      final a = _bool(archived, 'archived');
      next = next.copyWith(archived: a, inInbox: a ? false : next.inInbox);
      changed = true;
    }
    for (final kind in LabelKind.values) {
      final ids = await _labelIds(p, kind, body);
      if (ids != null) {
        next = switch (kind) {
          LabelKind.tag => next.copyWith(tagIds: ids),
          LabelKind.collection => next.copyWith(collectionIds: ids),
        };
        changed = true;
      }
    }

    if (!changed) return b;
    next = next.copyWith(updatedAt: _now());
    await userData(p.uid).bookmarks.update(next);
    return next;
  }

  /// Label IDs from `tagIds`/`collectionIds`, or from `tags`/`collections`
  /// names (created when missing). Null when neither is present.
  Future<List<String>?> _labelIds(
    Principal p,
    LabelKind kind,
    Map<String, Object?> body,
  ) async {
    final idsKey = kind == LabelKind.tag ? 'tagIds' : 'collectionIds';
    final namesKey = _labelPath(kind);
    final labels = userData(p.uid).labels;

    if (body[idsKey] case final Object raw) {
      final ids = _stringList(raw, idsKey);
      final known = (await labels.watch(kind).first).map((l) => l.id).toSet();
      final unknown = ids.where((id) => !known.contains(id));
      if (unknown.isNotEmpty) {
        throw ApiError.badRequest('Unknown $idsKey: ${unknown.join(', ')}');
      }
      return ids.toSet().toList();
    }
    if (body[namesKey] case final Object raw) {
      final existing = await labels.watch(kind).first;
      final ids = <String>{};
      for (final name in _stringList(raw, namesKey)) {
        ids.add((await _ensureLabel(labels, kind, name, existing)).id);
      }
      return ids.toList();
    }
    return null;
  }

  Future<Label> _ensureLabel(
    LabelRepository labels,
    LabelKind kind,
    String rawName,
    List<Label> existing,
  ) async {
    final name = normalizeLabelName(rawName);
    if (name == null) throw ApiError.badRequest('Label names can\'t be empty');
    final match = existing.where(
      (l) => l.name.toLowerCase() == name.toLowerCase(),
    );
    if (match.isNotEmpty) return match.first;
    final label = Label(id: labels.newId(kind), kind: kind, name: name);
    await labels.create(label);
    existing.add(label);
    return label;
  }

  Future<Response> _deleteBookmark(Request req, Principal p, String id) async {
    final repo = userData(p.uid).bookmarks;
    if (await repo.watch(id).first == null) {
      throw const ApiError.notFound('No bookmark with this ID');
    }
    await repo.delete(id);
    return Response(204);
  }

  // ---------------------------------------------------------------------------
  // Labels

  static String _labelPath(LabelKind kind) => switch (kind) {
    LabelKind.tag => 'tags',
    LabelKind.collection => 'collections',
  };

  Future<Response> _listLabels(Principal p, LabelKind kind) async {
    final labels = await userData(p.uid).labels.watch(kind).first;
    return jsonResponse({_labelPath(kind): labels.map(labelToJson).toList()});
  }

  Future<Response> _createLabel(
    Request req,
    Principal p,
    LabelKind kind,
  ) async {
    final body = await readJson(req);
    final name = body['name'];
    if (name is! String) throw const ApiError.badRequest('"name" is required');
    final labels = userData(p.uid).labels;
    final existing = await labels.watch(kind).first;
    final before = existing.length;
    final label = await _ensureLabel(labels, kind, name, existing);
    return jsonResponse(
      labelToJson(label),
      status: existing.length > before ? 201 : 200,
    );
  }

  Future<Response> _renameLabel(
    Request req,
    Principal p,
    LabelKind kind,
    String id,
  ) async {
    final body = await readJson(req);
    final name = body['name'];
    if (name is! String) throw const ApiError.badRequest('"name" is required');
    final labels = userData(p.uid).labels;
    final all = await labels.watch(kind).first;
    final label = all.where((l) => l.id == id).firstOrNull;
    if (label == null) throw const ApiError.notFound();
    final renamed = await _service(p).renameLabel(label, name, all);
    if (!renamed) {
      throw const ApiError(409, 'name_taken', 'Name is empty or already used');
    }
    return jsonResponse(labelToJson(label.rename(normalizeLabelName(name)!)));
  }

  Future<Response> _deleteLabel(Principal p, LabelKind kind, String id) async {
    final labels = userData(p.uid).labels;
    final label = (await labels.watch(kind).first)
        .where((l) => l.id == id)
        .firstOrNull;
    if (label == null) throw const ApiError.notFound();
    await labels.delete(label);
    return Response(204);
  }

  // ---------------------------------------------------------------------------
  // Fetching

  Uri _urlParam(Request req) {
    final raw = req.url.queryParameters['url'];
    final url = raw == null ? null : parseWebUrl(raw);
    if (url == null) {
      throw const ApiError.badRequest('"url" must be a web address');
    }
    return url;
  }

  Future<Response> _pageInfo(Request req, Principal p) async {
    final info = await pageInfo.lookup(_urlParam(req));
    return jsonResponse(metadataToJson(info ?? const PageMetadata()));
  }

  Future<Response> _reader(Request req, Principal p) async {
    final url = _urlParam(req);
    final host = displayHost(url);
    final now = _now();
    final content = await reader.load(
      Bookmark(
        id: '',
        url: url.toString(),
        canonicalUrl: canonicalizeUrl(url),
        title: titleFromUrl(url),
        source: BookmarkSource.fromHost(host),
        sourceDomain: host,
        createdAt: now,
        updatedAt: now,
      ),
    );
    return jsonResponse(readerContentToJson(content));
  }

  // ---------------------------------------------------------------------------
  // Tokens

  void _requireFirebaseSignIn(Principal p) {
    if (p.viaApiToken) {
      throw const ApiError(
        403,
        'forbidden',
        'API tokens can only be managed from a signed-in app',
      );
    }
  }

  Future<Response> _listTokens(Request req, Principal p) async {
    _requireFirebaseSignIn(p);
    final list = await tokens.forUser(p.uid);
    return jsonResponse({'tokens': list.map((t) => t.toJson()).toList()});
  }

  Future<Response> _createToken(Request req, Principal p) async {
    _requireFirebaseSignIn(p);
    final body = await readJson(req);
    final name = (_optionalString(body, 'name', 100) ?? '').trim();
    if (name.isEmpty) throw const ApiError.badRequest('"name" is required');
    if ((await tokens.forUser(p.uid)).length >= 20) {
      throw const ApiError(409, 'too_many_tokens', 'Delete an old token first');
    }
    final secret = generateTokenSecret();
    final token = ApiToken(
      id: hashToken(secret),
      uid: p.uid,
      name: name,
      createdAt: _now(),
    );
    await tokens.save(token);
    return jsonResponse({
      ...token.toJson(),
      // Shown once; only its hash is stored.
      'token': secret,
    }, status: 201);
  }

  Future<Response> _deleteToken(Request req, Principal p, String id) async {
    _requireFirebaseSignIn(p);
    final token = await tokens.find(id);
    if (token == null || token.uid != p.uid) throw const ApiError.notFound();
    await tokens.delete(id);
    return Response(204);
  }

  // ---------------------------------------------------------------------------
  // Validation helpers

  static String? _optionalString(
    Map<String, Object?> body,
    String key,
    int maxLength,
  ) {
    final value = body[key];
    if (value == null) return null;
    if (value is! String) throw ApiError.badRequest('"$key" must be a string');
    if (value.length > maxLength) {
      throw ApiError.badRequest('"$key" is longer than $maxLength characters');
    }
    return value;
  }

  static bool _bool(Object value, String key) {
    if (value is bool) return value;
    throw ApiError.badRequest('"$key" must be true or false');
  }

  static List<String> _stringList(Object value, String key) {
    if (value is List &&
        value.every((v) => v is String) &&
        value.length <= 100) {
      return value.cast<String>();
    }
    throw ApiError.badRequest('"$key" must be a list of up to 100 strings');
  }
}
