import 'dart:async';
import 'dart:io' show HttpDate;

import 'package:capsula_core/api/api_json.dart';
import 'package:capsula_core/domain/bookmarks/bookmark.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_repository.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_service.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_source.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_view.dart';
import 'package:capsula_core/domain/bookmarks/url_normalizer.dart';
import 'package:capsula_core/domain/highlights/highlight.dart';
import 'package:capsula_core/domain/maintenance/maintenance.dart';
import 'package:capsula_core/domain/organization/label.dart';
import 'package:capsula_core/domain/reader/page_info_service.dart';
import 'package:capsula_core/domain/reader/reader_content.dart';
import 'package:capsula_core/domain/reader/reader_service.dart';
import 'package:capsula_core/domain/search/full_text.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf_router/shelf_router.dart';

import 'auth.dart';
import 'http.dart';
import 'sharing.dart';

/// A user's data, scoped so callers can't reach anyone else's.
class UserData {
  const UserData(this.bookmarks, this.labels, this.highlights, this.contents);

  final BookmarkRepository bookmarks;
  final LabelRepository labels;
  final HighlightRepository highlights;
  final ContentIndex contents;
}

typedef UserDataFactory = UserData Function(String uid);

const _maxListLimit = 500;

/// The Capsula REST API (v1).
class CapsulaApi {
  CapsulaApi({
    required this.authenticator,
    required this.userData,
    required this.tokens,
    required this.shares,
    required this.pageInfo,
    required this.reader,
    required this.linkChecker,
    required this.rateLimiter,
    this.corsOrigins = const ['*'],
    this.log,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final Authenticator authenticator;
  final UserDataFactory userData;
  final TokenStore tokens;
  final ShareStore shares;
  final PageInfoSource pageInfo;
  final ReaderSource reader;
  final LinkChecker linkChecker;
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
    r.get('/v1/search', _authed(_searchContent));
    r.post('/v1/bookmarks/<id>/index', _authedWithId(_indexBookmark));
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

    // Highlights
    r.get('/v1/highlights', _authed(_listHighlights));
    r.post('/v1/highlights', _authed(_createHighlight));
    r.patch('/v1/highlights/<id>', _authedWithId(_updateHighlight));
    r.delete('/v1/highlights/<id>', _authedWithId(_deleteHighlight));

    // Server-side fetching (no browser CORS limits)
    r.get('/v1/page-info', _authed(_pageInfo));
    r.get('/v1/reader', _authed(_reader));
    r.get('/v1/link-status', _authed(_linkStatus));

    // Public collection links
    r.post('/v1/collections/<id>/share', _authedWithId(_shareCollection));
    r.delete('/v1/collections/<id>/share', _authedWithId(_unshareCollection));
    r.get('/v1/public/<shareId>', _publicJson);
    r.get('/p/<shareId>', _publicHtml);

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
    return BookmarkService(
      data.bookmarks,
      data.labels,
      highlights: data.highlights,
      contentIndex: data.contents,
      now: _now,
    );
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

  Future<Response> _searchContent(Request req, Principal p) async {
    final params = req.url.queryParameters;
    final q = params['q'] ?? '';
    if (q.trim().isEmpty) throw const ApiError.badRequest('"q" is required');
    final found = await _service(p).searchContent(
      q,
      view: BookmarkView.parse(params['view'] ?? 'all'),
      limit: (int.tryParse(params['limit'] ?? '') ?? 50).clamp(1, 200),
    );
    return jsonResponse({'bookmarks': found.map(bookmarkToJson).toList()});
  }

  /// Reads the bookmark's page on the server and indexes its text.
  Future<Response> _indexBookmark(Request req, Principal p, String id) async {
    final bookmark = await userData(p.uid).bookmarks.watch(id).first;
    if (bookmark == null) {
      throw const ApiError.notFound('No bookmark with this ID');
    }
    final content = await reader.load(bookmark);
    final indexed = await _service(p).indexContent(bookmark, content);
    return jsonResponse({'indexed': indexed});
  }

  Future<Response> _getBookmark(Request req, Principal p, String id) async {
    final b = await userData(p.uid).bookmarks.watch(id).first;
    if (b == null) throw const ApiError.notFound('No bookmark with this ID');
    return jsonResponse(
      bookmarkToJson(b),
      headers: {'last-modified': HttpDate.format(b.updatedAt)},
    );
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
        // Index the page text in the background for full-text search.
        final service0 = service;
        final created = saved;
        unawaited(
          reader
              .load(created)
              .then((c) => service0.indexContent(created, c))
              .catchError((Object _) => false),
        );
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
    final since = req.headers['if-unmodified-since'];
    DateTime? unmodifiedSince;
    if (since != null) {
      try {
        unmodifiedSince = HttpDate.parse(since);
      } on Exception {
        // HttpDate.parse throws HttpException for malformed dates.
        throw const ApiError.badRequest(
          '"If-Unmodified-Since" must be an HTTP date',
        );
      }
    }
    final updated = await _applyChanges(
      _service(p),
      p,
      existing,
      body,
      unmodifiedSince: unmodifiedSince,
    );
    return jsonResponse(
      bookmarkToJson(updated),
      headers: {'last-modified': HttpDate.format(updated.updatedAt)},
    );
  }

  /// Applies the editable fields present in [body] and saves once.
  Future<Bookmark> _applyChanges(
    BookmarkService service,
    Principal p,
    Bookmark b,
    Map<String, Object?> body, {
    DateTime? unmodifiedSince,
  }) async {
    // Each edit is applied to the latest stored copy, so fields the request
    // doesn't mention keep any change made meanwhile by another client.
    final edits = <Bookmark Function(Bookmark)>[];

    if (_optionalString(body, 'title', 1000) case final title?) {
      if (title.trim().isEmpty) {
        throw const ApiError.badRequest('"title" can\'t be empty');
      }
      edits.add((b) => b.copyWith(title: title.trim()));
    }
    if (_optionalString(body, 'description', 5000) case final d?) {
      edits.add((b) => b.copyWith(description: d));
    }
    if (body['readingStatus'] case final Object status) {
      final match = ReadingStatus.values.where((s) => s.name == status);
      if (match.isEmpty) {
        throw ApiError.badRequest(
          '"readingStatus" must be one of '
          '${ReadingStatus.values.map((s) => s.name).join(', ')}',
        );
      }
      edits.add((b) => b.copyWith(readingStatus: match.single));
    }
    if (body.containsKey('note')) {
      final note = _optionalString(body, 'note', maxNoteLength)?.trim() ?? '';
      edits.add(
        (b) =>
            note.isEmpty ? b.copyWith(clearNote: true) : b.copyWith(note: note),
      );
    }
    if (body.containsKey('remindAt')) {
      final raw = body['remindAt'];
      final when = raw is String ? DateTime.tryParse(raw) : null;
      if (raw != null && when == null) {
        throw const ApiError.badRequest(
          '"remindAt" must be an ISO 8601 date-time or null',
        );
      }
      edits.add(
        (b) => when == null
            ? b.copyWith(clearReminder: true)
            : b.copyWith(remindAt: when),
      );
    }
    if (body['favorite'] case final Object favorite) {
      final f = _bool(favorite, 'favorite');
      edits.add((b) => b.copyWith(favorite: f));
    }
    if (body['inInbox'] case final Object inbox) {
      final i = _bool(inbox, 'inInbox');
      edits.add((b) => b.copyWith(inInbox: i));
    }
    if (body['archived'] case final Object archived) {
      final a = _bool(archived, 'archived');
      edits.add((b) => b.copyWith(archived: a, inInbox: a ? false : b.inInbox));
    }
    for (final kind in LabelKind.values) {
      final ids = await _labelIds(p, kind, body);
      if (ids != null) {
        edits.add(
          (b) => switch (kind) {
            LabelKind.tag => b.copyWith(tagIds: ids),
            LabelKind.collection => b.copyWith(collectionIds: ids),
          },
        );
      }
    }

    if (edits.isEmpty) return b;
    final now = _now();
    Bookmark change(Bookmark current) {
      // Optimistic concurrency: refuse to apply edits made against a copy
      // that has changed since the client read it.
      if (unmodifiedSince != null &&
          current.updatedAt.difference(unmodifiedSince).inSeconds > 0) {
        throw const ApiError(
          412,
          'conflict',
          'The bookmark changed since it was read',
        );
      }
      var next = current;
      for (final edit in edits) {
        next = edit(next);
      }
      return next.copyWith(updatedAt: now);
    }

    final repo = userData(p.uid).bookmarks;
    await repo.modify(b.id, change);
    return await repo.watch(b.id).first ?? change(b);
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
    List<Label> existing, {
    String? parentId,
  }) async {
    final name = normalizeLabelName(rawName);
    if (name == null) throw ApiError.badRequest('Label names can\'t be empty');
    // Names are unique among siblings, as in the app.
    final match = existing.where(
      (l) =>
          l.parentId == parentId && l.name.toLowerCase() == name.toLowerCase(),
    );
    if (match.isNotEmpty) return match.first;
    final label = Label(
      id: labels.newId(kind),
      kind: kind,
      name: name,
      parentId: parentId,
    );
    await labels.create(label);
    existing.add(label);
    return label;
  }

  Future<Response> _deleteBookmark(Request req, Principal p, String id) async {
    final repo = userData(p.uid).bookmarks;
    if (await repo.watch(id).first == null) {
      throw const ApiError.notFound('No bookmark with this ID');
    }
    final existing = (await repo.watch(id).first)!;
    await _service(p).delete(existing);
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
    final parentId = _optionalString(body, 'parentId', 100);
    if (parentId != null) {
      if (kind != LabelKind.collection) {
        throw const ApiError.badRequest('Only collections can be nested');
      }
      if (!existing.any((l) => l.id == parentId)) {
        throw const ApiError.badRequest('Unknown "parentId"');
      }
    }
    final before = existing.length;
    final label = await _ensureLabel(
      labels,
      kind,
      name,
      existing,
      parentId: parentId,
    );
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
    final labels = userData(p.uid).labels;
    final all = await labels.watch(kind).first;
    var label = all.where((l) => l.id == id).firstOrNull;
    if (label == null) throw const ApiError.notFound();
    final service = _service(p);

    if (body.containsKey('parentId')) {
      final parentId = _optionalString(body, 'parentId', 100);
      if (parentId != null && !all.any((l) => l.id == parentId)) {
        throw const ApiError.badRequest('Unknown "parentId"');
      }
      if (!await service.moveCollection(label, parentId, all)) {
        throw const ApiError.badRequest(
          'Can\'t move a collection into itself or a tag into anything',
        );
      }
      label = label.moveTo(parentId);
    }
    if (body['name'] case final Object name) {
      if (name is! String) {
        throw const ApiError.badRequest('"name" must be a string');
      }
      if (!await service.renameLabel(label, name, all)) {
        throw const ApiError(
          409,
          'name_taken',
          'Name is empty or already used',
        );
      }
      label = label.rename(normalizeLabelName(name)!);
    }
    return jsonResponse(labelToJson(label));
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
  // Highlights

  Future<Response> _listHighlights(Request req, Principal p) async {
    final params = req.url.queryParameters;
    final highlights = userData(p.uid).highlights;
    final bookmarkId = params['bookmarkId'];
    final list = bookmarkId != null
        ? await highlights.watchForBookmark(bookmarkId).first
        : await highlights
              .watchAll(
                limit: (int.tryParse(params['limit'] ?? '') ?? 100).clamp(
                  1,
                  _maxListLimit,
                ),
              )
              .first;
    return jsonResponse({'highlights': list.map(highlightToJson).toList()});
  }

  Future<Highlight> _findHighlight(Principal p, String id) async {
    // Highlights are few per user; look the ID up among them.
    final all = await userData(p.uid).highlights.watchAll(limit: 10000).first;
    final h = all.where((h) => h.id == id).firstOrNull;
    if (h == null) throw const ApiError.notFound('No highlight with this ID');
    return h;
  }

  HighlightColor? _color(Map<String, Object?> body) {
    final raw = body['color'];
    if (raw == null) return null;
    final match = HighlightColor.values.where((c) => c.name == raw);
    if (match.isEmpty) {
      throw ApiError.badRequest(
        '"color" must be one of '
        '${HighlightColor.values.map((c) => c.name).join(', ')}',
      );
    }
    return match.single;
  }

  Future<Response> _createHighlight(Request req, Principal p) async {
    final body = await readJson(req);
    final bookmarkId = _optionalString(body, 'bookmarkId', 100);
    final text = _optionalString(body, 'text', maxHighlightLength);
    if (bookmarkId == null || text == null) {
      throw const ApiError.badRequest('"bookmarkId" and "text" are required');
    }
    final bookmark = await userData(p.uid).bookmarks.watch(bookmarkId).first;
    if (bookmark == null) {
      throw const ApiError.notFound('No bookmark with this ID');
    }
    final service = _service(p);
    var highlight = service.addHighlight(
      bookmark,
      text,
      color: _color(body) ?? HighlightColor.yellow,
    );
    if (highlight == null) throw const ApiError.badRequest('"text" is empty');
    final note = _optionalString(body, 'note', maxNoteLength);
    if (note != null && note.trim().isNotEmpty) {
      highlight = highlight.copyWith(note: note.trim());
    }
    await userData(p.uid).highlights.save(highlight);
    return jsonResponse(highlightToJson(highlight), status: 201);
  }

  Future<Response> _updateHighlight(Request req, Principal p, String id) async {
    final existing = await _findHighlight(p, id);
    final body = await readJson(req);
    final note = body.containsKey('note')
        ? (_optionalString(body, 'note', maxNoteLength) ?? '')
        : null;
    final color = _color(body);
    await _service(p).updateHighlight(existing, note: note, color: color);
    final trimmed = note?.trim();
    return jsonResponse(
      highlightToJson(
        existing.copyWith(
          note: trimmed,
          clearNote: trimmed != null && trimmed.isEmpty,
          color: color,
        ),
      ),
    );
  }

  Future<Response> _deleteHighlight(Request req, Principal p, String id) async {
    await _findHighlight(p, id);
    await userData(p.uid).highlights.delete(id);
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

  Future<Response> _linkStatus(Request req, Principal p) async {
    final check = await linkChecker.check(_urlParam(req));
    return jsonResponse({
      'health': check.health.name,
      'statusCode': ?check.statusCode,
      'reason': ?check.reason,
    });
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
  // Sharing

  Future<Label> _collectionOf(Principal p, String id) async {
    final all = await userData(p.uid).labels.watch(LabelKind.collection).first;
    final label = all.where((l) => l.id == id).firstOrNull;
    if (label == null) {
      throw const ApiError.notFound('No collection with this ID');
    }
    return label;
  }

  /// Public URLs are built from the request, so they match how the server
  /// is reached (e.g. behind a reverse proxy with X-Forwarded-* headers).
  Uri _publicUrl(Request req, String shareId) {
    final proto = req.headers['x-forwarded-proto'] ?? req.requestedUri.scheme;
    final host = req.headers['x-forwarded-host'] ?? req.requestedUri.authority;
    return Uri.parse('$proto://$host/p/$shareId');
  }

  Future<Response> _shareCollection(Request req, Principal p, String id) async {
    final label = await _collectionOf(p, id);
    var shareId = label.shareId;
    if (shareId == null) {
      shareId = generateShareId();
      await shares.create(shareId, ShareTarget(p.uid, id));
    }
    return jsonResponse({
      'shareId': shareId,
      'url': _publicUrl(req, shareId).toString(),
    });
  }

  Future<Response> _unshareCollection(
    Request req,
    Principal p,
    String id,
  ) async {
    final label = await _collectionOf(p, id);
    if (label.shareId case final shareId?) {
      await shares.delete(shareId, ShareTarget(p.uid, id));
    }
    return Response(204);
  }

  /// The shared collection's name and visible bookmarks, or null when the
  /// link doesn't exist (or was revoked).
  Future<(String, List<Bookmark>)?> _shared(String shareId) async {
    if (!rateLimiter.allow('public:$shareId')) {
      throw const ApiError(429, 'rate_limited', 'Too many requests');
    }
    final target = await shares.find(shareId);
    if (target == null) return null;
    final data = userData(target.uid);
    final collection = (await data.labels.watch(LabelKind.collection).first)
        .where((l) => l.id == target.collectionId && l.shareId == shareId)
        .firstOrNull;
    if (collection == null) return null;
    final bookmarks = await data.bookmarks
        .watchList(
          BookmarkQuery(view: LabelView(LabelKind.collection, collection.id)),
          limit: _maxListLimit,
        )
        .first;
    return (collection.name, bookmarks);
  }

  Future<Response> _publicJson(Request req, String shareId) async {
    final shared = await _shared(shareId);
    if (shared == null) throw const ApiError.notFound('This link was removed');
    final (name, bookmarks) = shared;
    return jsonResponse({
      'collection': {'name': name},
      'bookmarks': bookmarks.map(publicBookmarkJson).toList(),
    });
  }

  Future<Response> _publicHtml(Request req, String shareId) async {
    final shared = await _shared(shareId);
    if (shared == null) {
      return Response.notFound(
        '<!doctype html><meta charset="utf-8"><title>Not found</title>'
        '<p style="font-family:system-ui;padding:24px">This link was removed '
        'or never existed.</p>',
        headers: {'content-type': 'text/html; charset=utf-8'},
      );
    }
    final (name, bookmarks) = shared;
    return Response.ok(
      publicCollectionHtml(name, bookmarks),
      headers: {
        'content-type': 'text/html; charset=utf-8',
        'cache-control': 'public, max-age=60',
        'x-content-type-options': 'nosniff',
        'referrer-policy': 'no-referrer',
      },
    );
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
