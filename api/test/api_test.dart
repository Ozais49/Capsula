import 'dart:convert';

import 'package:capsula_api/capsula_api.dart';
import 'package:capsula_core/domain/bookmarks/bookmark.dart';
import 'package:capsula_core/domain/maintenance/maintenance.dart';
import 'package:capsula_core/domain/reader/page_info_service.dart';
import 'package:capsula_core/domain/reader/reader_content.dart';
import 'package:capsula_core/domain/reader/reader_service.dart';
import 'package:capsula_core/testing/in_memory_bookmark_repository.dart';
import 'package:capsula_core/testing/in_memory_content_index.dart';
import 'package:capsula_core/testing/in_memory_highlight_repository.dart';
import 'package:capsula_core/testing/in_memory_label_repository.dart';
import 'package:dart_firebase_admin/firestore.dart';
import 'package:shelf/shelf.dart';
import 'package:test/test.dart';

class _FakeVerifier implements IdTokenVerifier {
  final tokens = {'alice-id-token': 'alice', 'bob-id-token': 'bob'};

  @override
  Future<String?> verify(String idToken) async => tokens[idToken];
}

class _MemoryTokens implements TokenStore {
  final items = <String, ApiToken>{};

  @override
  Future<void> save(ApiToken t) async => items[t.id] = t;
  @override
  Future<ApiToken?> find(String id) async => items[id];
  @override
  Future<List<ApiToken>> forUser(String uid) async =>
      items.values.where((t) => t.uid == uid).toList();
  @override
  Future<void> delete(String id) async => items.remove(id);
  @override
  Future<void> touch(String id, DateTime when) async {}
}

class _MemoryShares implements ShareStore {
  _MemoryShares(this.labels);

  final Map<String, InMemoryLabelRepository> labels;
  final items = <String, ShareTarget>{};

  void _mark(ShareTarget t, String? shareId) {
    final repo = labels[t.uid]!;
    repo.addAll([repo.items[t.collectionId]!.withShare(shareId)]);
  }

  @override
  Future<ShareTarget?> find(String shareId) async => items[shareId];

  @override
  Future<void> create(String shareId, ShareTarget t) async {
    items[shareId] = t;
    _mark(t, shareId);
  }

  @override
  Future<void> delete(String shareId, ShareTarget t) async {
    items.remove(shareId);
    _mark(t, null);
  }
}

class _FakePageInfo implements PageInfoSource {
  final titles = <String, String>{};

  @override
  Future<PageMetadata?> lookup(Uri url) async => titles[url.toString()] == null
      ? null
      : PageMetadata(title: titles[url.toString()]);
}

class _FakeLinks implements LinkChecker {
  @override
  Future<LinkCheck> check(Uri url) async => url.path.contains('gone')
      ? const LinkCheck(
          LinkHealth.broken,
          statusCode: 404,
          reason: 'Page not found',
        )
      : const LinkCheck(LinkHealth.ok, statusCode: 200);
}

class _FakeReader implements ReaderSource {
  @override
  Future<ReaderContent> load(Bookmark b) async => ArticleContent(
    title: 'Read: ${b.url}',
    blocks: const [
      ParagraphBlock([InlineRun('Hello '), InlineRun('world', bold: true)]),
    ],
  );
}

class _Server {
  _Server({int perMinute = 1000}) {
    api = CapsulaApi(
      authenticator: Authenticator(_FakeVerifier(), tokens),
      userData: (uid) {
        final b = bookmarks.putIfAbsent(uid, InMemoryBookmarkRepository.new);
        final l = labels.putIfAbsent(uid, () => InMemoryLabelRepository(b));
        final h = highlights.putIfAbsent(uid, InMemoryHighlightRepository.new);
        final c = contents.putIfAbsent(uid, InMemoryContentIndex.new);
        return UserData(b, l, h, c);
      },
      tokens: tokens,
      shares: _MemoryShares(labels),
      pageInfo: pageInfo,
      reader: _FakeReader(),
      linkChecker: _FakeLinks(),
      rateLimiter: RateLimiter(perMinute),
    );
  }

  late final CapsulaApi api;
  final bookmarks = <String, InMemoryBookmarkRepository>{};
  final labels = <String, InMemoryLabelRepository>{};
  final highlights = <String, InMemoryHighlightRepository>{};
  final contents = <String, InMemoryContentIndex>{};
  final tokens = _MemoryTokens();
  final pageInfo = _FakePageInfo();

  Future<(int, Map<String, Object?>)> call(
    String method,
    String path, {
    String? auth = 'alice-id-token',
    Object? body,
    Map<String, String> headers = const {},
  }) async {
    final response = await api.handler(
      Request(
        method,
        Uri.parse('http://localhost$path'),
        headers: {
          if (auth != null) 'authorization': 'Bearer $auth',
          ...headers,
        },
        body: body == null ? null : (body is String ? body : jsonEncode(body)),
      ),
    );
    final text = await response.readAsString();
    return (
      response.statusCode,
      text.isEmpty
          ? <String, Object?>{}
          : jsonDecode(text) as Map<String, Object?>,
    );
  }
}

void main() {
  late _Server s;
  setUp(() => s = _Server());

  test('health needs no auth', () async {
    final (status, body) = await s.call('GET', '/v1/health', auth: null);
    expect(status, 200);
    expect(body['status'], 'ok');
  });

  test('rejects missing or invalid credentials', () async {
    expect((await s.call('GET', '/v1/me', auth: null)).$1, 401);
    expect((await s.call('GET', '/v1/me', auth: 'forged')).$1, 401);
    expect((await s.call('GET', '/v1/me', auth: 'cap_unknown')).$1, 401);
    final (_, body) = await s.call('GET', '/v1/me', auth: null);
    expect((body['error'] as Map)['code'], 'unauthorized');
  });

  test('identifies the caller', () async {
    final (status, body) = await s.call('GET', '/v1/me');
    expect(status, 200);
    expect(body, {'uid': 'alice', 'auth': 'firebase'});
  });

  group('bookmarks', () {
    test('creates with the real title, tags and collections', () async {
      s.pageInfo.titles['https://youtu.be/abc'] = 'Flutter in 100 Seconds';
      final (status, body) = await s.call(
        'POST',
        '/v1/bookmarks',
        body: {
          'url': 'https://youtu.be/abc',
          'tags': ['Dev', 'video'],
          'collections': ['Learning'],
        },
      );
      expect(status, 201);
      expect(body['title'], 'Flutter in 100 Seconds');
      expect(body['source'], 'youtube');
      expect(body['inInbox'], isTrue);
      expect(body['tagIds'], hasLength(2));
      expect(body['collectionIds'], hasLength(1));

      final (_, tags) = await s.call('GET', '/v1/tags');
      expect(
        (tags['tags'] as List).map((t) => (t as Map)['name']),
        unorderedEquals(['Dev', 'video']),
      );
    });

    test('a given title wins over the fetched one', () async {
      s.pageInfo.titles['https://example.com/a'] = 'Page title';
      final (_, body) = await s.call(
        'POST',
        '/v1/bookmarks',
        body: {'url': 'https://example.com/a', 'title': 'My title'},
      );
      expect(body['title'], 'My title');
    });

    test('reports duplicates with the existing bookmark', () async {
      await s.call(
        'POST',
        '/v1/bookmarks',
        body: {'url': 'https://example.com/a'},
      );
      final (status, body) = await s.call(
        'POST',
        '/v1/bookmarks',
        body: {'url': 'http://www.example.com/a/'},
      );
      expect(status, 409);
      expect((body['error'] as Map)['code'], 'already_saved');
      expect((body['bookmark'] as Map)['url'], 'https://example.com/a');
    });

    test('validates input', () async {
      expect(
        (await s.call('POST', '/v1/bookmarks', body: {'url': 'not a link'})).$1,
        400,
      );
      expect((await s.call('POST', '/v1/bookmarks', body: {})).$1, 400);
      expect((await s.call('POST', '/v1/bookmarks', body: '{oops')).$1, 400);
      expect(
        (await s.call(
          'POST',
          '/v1/bookmarks',
          body: {'url': 'https://a.com', 'tags': 'not-a-list'},
        )).$1,
        400,
      );
    });

    test('lists by view and search', () async {
      for (final url in [
        'https://a.com/flutter-tips',
        'https://b.com/cooking',
      ]) {
        await s.call('POST', '/v1/bookmarks', body: {'url': url});
      }
      final (_, all) = await s.call('GET', '/v1/bookmarks?view=inbox');
      expect(all['bookmarks'], hasLength(2));

      final (_, found) = await s.call('GET', '/v1/bookmarks?q=flutter');
      expect(found['bookmarks'], hasLength(1));

      final (_, archived) = await s.call('GET', '/v1/bookmarks?view=archived');
      expect(archived['bookmarks'], isEmpty);
    });

    test('gets, updates and deletes', () async {
      final (_, created) = await s.call(
        'POST',
        '/v1/bookmarks',
        body: {'url': 'https://example.com/a'},
      );
      final id = created['id'];

      final (status, updated) = await s.call(
        'PATCH',
        '/v1/bookmarks/$id',
        body: {'readingStatus': 'read', 'archived': true, 'title': 'Renamed'},
      );
      expect(status, 200);
      expect(updated['readingStatus'], 'read');
      expect(updated['archived'], isTrue);
      expect(updated['inInbox'], isFalse, reason: 'archiving leaves the Inbox');
      expect(updated['title'], 'Renamed');

      expect((await s.call('GET', '/v1/bookmarks/$id')).$2['title'], 'Renamed');
      expect(
        (await s.call(
          'PATCH',
          '/v1/bookmarks/$id',
          body: {'readingStatus': 'x'},
        )).$1,
        400,
      );

      // DELETE moves to the Trash.
      expect((await s.call('DELETE', '/v1/bookmarks/$id')).$1, 204);
      var (_, got) = await s.call('GET', '/v1/bookmarks/$id');
      expect(got['deletedAt'], isNotNull);
      expect((await s.call('GET', '/v1/bookmarks')).$2['bookmarks'], isEmpty);
      expect(
        (await s.call('GET', '/v1/bookmarks?view=trash')).$2['bookmarks'],
        hasLength(1),
      );

      (_, got) = await s.call('POST', '/v1/bookmarks/$id/restore');
      expect(got['deletedAt'], isNull);
      expect(
        (await s.call('GET', '/v1/bookmarks')).$2['bookmarks'],
        hasLength(1),
      );

      expect(
        (await s.call('DELETE', '/v1/bookmarks/$id?permanent=true')).$1,
        204,
      );
      expect((await s.call('GET', '/v1/bookmarks/$id')).$1, 404);
    });

    test('users never see each other\'s bookmarks', () async {
      final (_, created) = await s.call(
        'POST',
        '/v1/bookmarks',
        body: {'url': 'https://example.com/private'},
      );
      final id = created['id'];
      const bob = 'bob-id-token';

      expect((await s.call('GET', '/v1/bookmarks/$id', auth: bob)).$1, 404);
      expect(
        (await s.call(
          'PATCH',
          '/v1/bookmarks/$id',
          auth: bob,
          body: {'title': 'x'},
        )).$1,
        404,
      );
      expect((await s.call('DELETE', '/v1/bookmarks/$id', auth: bob)).$1, 404);
      expect(
        (await s.call('GET', '/v1/bookmarks', auth: bob)).$2['bookmarks'],
        isEmpty,
      );
      expect((await s.call('GET', '/v1/bookmarks/$id')).$1, 200);
    });

    test('exports everything', () async {
      for (var i = 0; i < 3; i++) {
        await s.call(
          'POST',
          '/v1/bookmarks',
          body: {'url': 'https://a.com/$i'},
        );
      }
      expect(
        (await s.call('GET', '/v1/bookmarks/export')).$2['bookmarks'],
        hasLength(3),
      );
    });
  });

  group('labels', () {
    test('create, reuse by name, rename and delete', () async {
      final (status, created) = await s.call(
        'POST',
        '/v1/collections',
        body: {'name': ' Japan  Trip '},
      );
      expect(status, 201);
      expect(created['name'], 'Japan Trip');

      final (again, same) = await s.call(
        'POST',
        '/v1/collections',
        body: {'name': 'japan trip'},
      );
      expect(again, 200);
      expect(same['id'], created['id']);

      final id = created['id'];
      final (renamed, body) = await s.call(
        'PATCH',
        '/v1/collections/$id',
        body: {'name': 'Kyoto'},
      );
      expect(renamed, 200);
      expect(body['name'], 'Kyoto');

      expect((await s.call('DELETE', '/v1/collections/$id')).$1, 204);
      expect(
        (await s.call('GET', '/v1/collections')).$2['collections'],
        isEmpty,
      );
    });

    test('assign by ID, rejecting unknown IDs', () async {
      final (_, tag) = await s.call('POST', '/v1/tags', body: {'name': 'AI'});
      final (_, b) = await s.call(
        'POST',
        '/v1/bookmarks',
        body: {'url': 'https://a.com'},
      );
      final (ok, updated) = await s.call(
        'PATCH',
        '/v1/bookmarks/${b['id']}',
        body: {
          'tagIds': [tag['id']],
        },
      );
      expect(ok, 200);
      expect(updated['tagIds'], [tag['id']]);

      final (bad, _) = await s.call(
        'PATCH',
        '/v1/bookmarks/${b['id']}',
        body: {
          'tagIds': ['nope'],
        },
      );
      expect(bad, 400);
    });
  });

  group('API tokens', () {
    test('create once, authenticate with it, delete', () async {
      final (status, created) = await s.call(
        'POST',
        '/v1/tokens',
        body: {'name': 'Browser extension'},
      );
      expect(status, 201);
      final secret = created['token'] as String;
      expect(secret, startsWith('cap_'));
      expect(
        s.tokens.items.keys.single,
        isNot(contains(secret)),
        reason: 'only the hash is stored',
      );

      final (meStatus, me) = await s.call('GET', '/v1/me', auth: secret);
      expect(meStatus, 200);
      expect(me, {'uid': 'alice', 'auth': 'api_token'});

      final (_, list) = await s.call('GET', '/v1/tokens');
      expect((list['tokens'] as List).single, isNot(contains('token')));

      expect((await s.call('DELETE', '/v1/tokens/${created['id']}')).$1, 204);
      expect((await s.call('GET', '/v1/me', auth: secret)).$1, 401);
    });

    test('API tokens can\'t manage tokens', () async {
      final (_, created) = await s.call(
        'POST',
        '/v1/tokens',
        body: {'name': 'Script'},
      );
      final secret = created['token'] as String;
      expect((await s.call('GET', '/v1/tokens', auth: secret)).$1, 403);
      expect(
        (await s.call(
          'POST',
          '/v1/tokens',
          auth: secret,
          body: {'name': 'x'},
        )).$1,
        403,
      );
    });

    test('users can\'t delete each other\'s tokens', () async {
      final (_, created) = await s.call(
        'POST',
        '/v1/tokens',
        body: {'name': 'Mine'},
      );
      expect(
        (await s.call(
          'DELETE',
          '/v1/tokens/${created['id']}',
          auth: 'bob-id-token',
        )).$1,
        404,
      );
    });
  });

  test('page info and reader run on the server', () async {
    s.pageInfo.titles['https://example.com/a'] = 'Server title';
    final (_, info) = await s.call(
      'GET',
      '/v1/page-info?url=${Uri.encodeQueryComponent('https://example.com/a')}',
    );
    expect(info['title'], 'Server title');

    final (status, content) = await s.call(
      'GET',
      '/v1/reader?url=${Uri.encodeQueryComponent('https://example.com/a')}',
    );
    expect(status, 200);
    expect(content['type'], 'article');
    expect((content['blocks'] as List).single, isA<Map>());

    expect((await s.call('GET', '/v1/reader?url=nope')).$1, 400);
  });

  test('rate limits per user', () async {
    s = _Server(perMinute: 3);
    for (var i = 0; i < 3; i++) {
      expect((await s.call('GET', '/v1/me')).$1, 200);
    }
    expect((await s.call('GET', '/v1/me')).$1, 429);
    expect((await s.call('GET', '/v1/me', auth: 'bob-id-token')).$1, 200);
  });

  test('answers CORS preflight and unknown routes', () async {
    final preflight = await s.api.handler(
      Request(
        'OPTIONS',
        Uri.parse('http://localhost/v1/bookmarks'),
        headers: {'origin': 'https://capsula-ygtech.web.app'},
      ),
    );
    expect(preflight.statusCode, 204);
    expect(preflight.headers['access-control-allow-origin'], '*');
    expect(
      preflight.headers['access-control-allow-headers'],
      contains('Authorization'),
    );

    expect((await s.call('GET', '/v1/nothing-here')).$1, 404);
  });

  test('favorites and nested collections', () async {
    final (_, b) = await s.call(
      'POST',
      '/v1/bookmarks',
      body: {'url': 'https://example.com/fav'},
    );
    final (_, starred) = await s.call(
      'PATCH',
      '/v1/bookmarks/${b['id']}',
      body: {'favorite': true},
    );
    expect(starred['favorite'], isTrue);
    expect(
      (await s.call('GET', '/v1/bookmarks?view=favorites')).$2['bookmarks'],
      hasLength(1),
    );

    final (_, parent) = await s.call(
      'POST',
      '/v1/collections',
      body: {'name': 'Work'},
    );
    final (status, child) = await s.call(
      'POST',
      '/v1/collections',
      body: {'name': 'Reports', 'parentId': parent['id']},
    );
    expect(status, 201);
    expect(child['parentId'], parent['id']);

    // The same name under a different parent is a separate collection.
    final (_, top) = await s.call(
      'POST',
      '/v1/collections',
      body: {'name': 'Reports'},
    );
    expect(top['id'], isNot(child['id']));

    // No loops: a parent can't move into its own child.
    final (loop, _) = await s.call(
      'PATCH',
      '/v1/collections/${parent['id']}',
      body: {'parentId': child['id']},
    );
    expect(loop, 400);

    final (moved, body) = await s.call(
      'PATCH',
      '/v1/collections/${child['id']}',
      body: {'parentId': null},
    );
    expect(moved, 200);
    expect(body.containsKey('parentId'), isFalse);

    expect(
      (await s.call(
        'POST',
        '/v1/tags',
        body: {'name': 'x', 'parentId': parent['id']},
      )).$1,
      400,
    );
  });

  test('notes and highlights', () async {
    final (_, b) = await s.call(
      'POST',
      '/v1/bookmarks',
      body: {'url': 'https://example.com/article'},
    );
    final id = b['id'];

    final (_, noted) = await s.call(
      'PATCH',
      '/v1/bookmarks/$id',
      body: {'note': '  Read before Friday  '},
    );
    expect(noted['note'], 'Read before Friday');
    final (_, cleared) = await s.call(
      'PATCH',
      '/v1/bookmarks/$id',
      body: {'note': ''},
    );
    expect(cleared.containsKey('note'), isFalse);

    final (status, h) = await s.call(
      'POST',
      '/v1/highlights',
      body: {
        'bookmarkId': id,
        'text': '  A key   point ',
        'note': 'Why',
        'color': 'green',
      },
    );
    expect(status, 201);
    expect(h['text'], 'A key point');
    expect(h['note'], 'Why');
    expect(h['color'], 'green');

    expect(
      (await s.call(
        'POST',
        '/v1/highlights',
        body: {'bookmarkId': id, 'text': 'x', 'color': 'red'},
      )).$1,
      400,
    );
    expect(
      (await s.call(
        'POST',
        '/v1/highlights',
        body: {'bookmarkId': 'nope', 'text': 'x'},
      )).$1,
      404,
    );

    final (_, updated) = await s.call(
      'PATCH',
      '/v1/highlights/${h['id']}',
      body: {'note': 'Because'},
    );
    expect(updated['note'], 'Because');

    final (_, forBookmark) = await s.call(
      'GET',
      '/v1/highlights?bookmarkId=$id',
    );
    expect(forBookmark['highlights'], hasLength(1));

    // Other users can't see or delete them.
    expect(
      (await s.call(
        'DELETE',
        '/v1/highlights/${h['id']}',
        auth: 'bob-id-token',
      )).$1,
      404,
    );

    // The Trash keeps highlights; deleting for good removes them.
    await s.call('DELETE', '/v1/bookmarks/$id');
    expect(
      (await s.call('GET', '/v1/highlights')).$2['highlights'],
      isNotEmpty,
    );
    expect((await s.call('DELETE', '/v1/trash')).$2, {'deleted': 1});
    expect((await s.call('GET', '/v1/highlights')).$2['highlights'], isEmpty);
  });

  test('public collection links', () async {
    final (_, work) = await s.call(
      'POST',
      '/v1/collections',
      body: {'name': 'Reading <list>'},
    );
    final (_, other) = await s.call(
      'POST',
      '/v1/collections',
      body: {'name': 'Private'},
    );
    await s.call(
      'POST',
      '/v1/bookmarks',
      body: {
        'url': 'https://example.com/shared',
        'collections': ['Reading <list>'],
      },
    );
    final (_, private) = await s.call(
      'POST',
      '/v1/bookmarks',
      body: {
        'url': 'https://example.com/private',
        'collections': ['Private'],
      },
    );
    await s.call(
      'PATCH',
      '/v1/bookmarks/${private['id']}',
      body: {'note': 'secret'},
    );

    final (status, share) = await s.call(
      'POST',
      '/v1/collections/${work['id']}/share',
    );
    expect(status, 200);
    final shareId = share['shareId'] as String;
    expect(shareId.length, greaterThanOrEqualTo(16));
    expect(share['url'], 'http://localhost/p/$shareId');

    // Sharing twice keeps the same link.
    expect(
      (await s.call(
        'POST',
        '/v1/collections/${work['id']}/share',
      )).$2['shareId'],
      shareId,
    );
    expect(
      ((await s.call('GET', '/v1/collections')).$2['collections'] as List)
          .firstWhere((c) => (c as Map)['id'] == work['id'])['shareId'],
      shareId,
    );

    // Anyone can view it, without signing in; only public fields appear.
    final (publicStatus, page) = await s.call(
      'GET',
      '/v1/public/$shareId',
      auth: null,
    );
    expect(publicStatus, 200);
    expect((page['collection'] as Map)['name'], 'Reading <list>');
    final items = page['bookmarks'] as List;
    expect(items, hasLength(1));
    expect((items.single as Map).keys, isNot(contains('note')));
    expect((items.single as Map).keys, isNot(contains('tagIds')));

    final html = await s.api.handler(
      Request('GET', Uri.parse('http://localhost/p/$shareId')),
    );
    expect(html.statusCode, 200);
    final body = await html.readAsString();
    expect(body, contains('Reading &lt;list&gt;'), reason: 'escaped');
    expect(body, contains('https://example.com/shared'));
    expect(body, isNot(contains('example.com/private')));

    // Others can't share or unshare someone else's collection.
    expect(
      (await s.call(
        'POST',
        '/v1/collections/${other['id']}/share',
        auth: 'bob-id-token',
      )).$1,
      404,
    );

    // Revoking removes the page immediately.
    expect(
      (await s.call('DELETE', '/v1/collections/${work['id']}/share')).$1,
      204,
    );
    expect((await s.call('GET', '/v1/public/$shareId', auth: null)).$1, 404);
    expect(
      (await s.api.handler(
        Request('GET', Uri.parse('http://localhost/p/$shareId')),
      )).statusCode,
      404,
    );
    expect(
      (await s.call('GET', '/v1/public/not-a-real-share-id', auth: null)).$1,
      404,
    );
  });

  test('link status and content types', () async {
    final (_, gone) = await s.call(
      'GET',
      '/v1/link-status?url=${Uri.encodeQueryComponent('https://example.com/gone')}',
    );
    expect(gone, {
      'health': 'broken',
      'statusCode': 404,
      'reason': 'Page not found',
    });

    await s.call(
      'POST',
      '/v1/bookmarks',
      body: {'url': 'https://youtu.be/abc'},
    );
    await s.call(
      'POST',
      '/v1/bookmarks',
      body: {'url': 'https://example.com/paper.pdf'},
    );
    final (_, videos) = await s.call('GET', '/v1/bookmarks?view=type:video');
    expect(videos['bookmarks'], hasLength(1));
    final (_, docs) = await s.call('GET', '/v1/bookmarks?view=type:document');
    expect(
      ((docs['bookmarks'] as List).single as Map)['url'],
      'https://example.com/paper.pdf',
    );
  });

  test('reminders', () async {
    final (_, b) = await s.call(
      'POST',
      '/v1/bookmarks',
      body: {'url': 'https://example.com/r'},
    );
    final (status, set) = await s.call(
      'PATCH',
      '/v1/bookmarks/${b['id']}',
      body: {'remindAt': '2030-01-02T09:00:00Z'},
    );
    expect(status, 200);
    expect(set['remindAt'], '2030-01-02T09:00:00.000Z');
    expect(
      (await s.call('GET', '/v1/bookmarks?view=reminders')).$2['bookmarks'],
      hasLength(1),
    );
    expect(
      (await s.call(
        'PATCH',
        '/v1/bookmarks/${b['id']}',
        body: {'remindAt': 'soon'},
      )).$1,
      400,
    );
    final (_, cleared) = await s.call(
      'PATCH',
      '/v1/bookmarks/${b['id']}',
      body: {'remindAt': null},
    );
    expect(cleared.containsKey('remindAt'), isFalse);
  });

  test('full-text search over saved pages', () async {
    final (_, b) = await s.call(
      'POST',
      '/v1/bookmarks',
      body: {'url': 'https://example.com/greeting'},
    );
    // Creating indexes the page in the background; let it finish.
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);

    final (_, found) = await s.call('GET', '/v1/search?q=world');
    expect(((found['bookmarks'] as List).single as Map)['id'], b['id']);
    expect(
      (await s.call('GET', '/v1/search?q=nothing+here')).$2['bookmarks'],
      isEmpty,
    );
    expect((await s.call('GET', '/v1/search')).$1, 400);

    final (status, indexed) = await s.call(
      'POST',
      '/v1/bookmarks/${b['id']}/index',
    );
    expect(status, 200);
    expect(indexed['indexed'], isTrue);
    expect(
      (await s.call(
        'GET',
        '/v1/search?q=world',
        auth: 'bob-id-token',
      )).$2['bookmarks'],
      isEmpty,
    );
  });

  group('concurrent changes', () {
    Future<String> create() async {
      final (_, body) = await s.call(
        'POST',
        '/v1/bookmarks',
        body: {'url': 'https://example.com/a', 'fetchDetails': false},
      );
      return body['id']! as String;
    }

    test('PATCH keeps fields another client changed meanwhile', () async {
      final id = await create();
      // Another client sets a note directly in storage.
      await s.bookmarks['alice']!.modify(
        id,
        (b) => b.copyWith(note: 'from phone'),
      );
      final (status, body) = await s.call(
        'PATCH',
        '/v1/bookmarks/$id',
        body: {'favorite': true},
      );
      expect(status, 200);
      expect(body['favorite'], isTrue);
      expect(body['note'], 'from phone');
    });

    test('If-Unmodified-Since refuses stale edits with 412', () async {
      final id = await create();
      final read = await s.api.handler(
        Request(
          'GET',
          Uri.parse('http://localhost/v1/bookmarks/$id'),
          headers: {'authorization': 'Bearer alice-id-token'},
        ),
      );
      final lastModified = read.headers['last-modified']!;

      // Unchanged since it was read: applied.
      var (status, _) = await s.call(
        'PATCH',
        '/v1/bookmarks/$id',
        body: {'title': 'First'},
        headers: {'if-unmodified-since': lastModified},
      );
      expect(status, 200);

      // Changed by someone else afterwards: refused, nothing written.
      await s.bookmarks['alice']!.modify(
        id,
        (b) => b.copyWith(
          title: 'Other',
          updatedAt: DateTime.now().add(const Duration(minutes: 1)),
        ),
      );
      final Map<String, Object?> body;
      (status, body) = await s.call(
        'PATCH',
        '/v1/bookmarks/$id',
        body: {'title': 'Stale'},
        headers: {'if-unmodified-since': lastModified},
      );
      expect(status, 412);
      expect((body['error'] as Map)['code'], 'conflict');
      expect(s.bookmarks['alice']!.items[id]!.title, 'Other');

      (status, _) = await s.call(
        'PATCH',
        '/v1/bookmarks/$id',
        body: {'title': 'x'},
        headers: {'if-unmodified-since': 'yesterday'},
      );
      expect(status, 400);
    });
  });

  test('withRetry retries temporary failures only', () async {
    var calls = 0;
    final waits = <Duration>[];
    Future<void> wait(Duration d) async => waits.add(d);

    final result = await withRetry(() async {
      if (++calls < 3) {
        throw FirebaseFirestoreAdminException(
          FirestoreClientErrorCode.unavailable,
        );
      }
      return 'done';
    }, wait: wait);
    expect(result, 'done');
    expect(calls, 3);
    expect(waits, [
      const Duration(milliseconds: 200),
      const Duration(milliseconds: 800),
    ]);

    calls = 0;
    await expectLater(
      withRetry(() async {
        calls++;
        throw FirebaseFirestoreAdminException(
          FirestoreClientErrorCode.permissionDenied,
        );
      }, wait: wait),
      throwsA(isA<FirebaseFirestoreAdminException>()),
    );
    expect(calls, 1);
  });

  test('lists can be filtered by source, tag, kind and status', () async {
    for (final url in [
      'https://reddit.com/r/a/comments/1',
      'https://youtu.be/xyz',
      'https://example.com/post',
    ]) {
      await s.call(
        'POST',
        '/v1/bookmarks',
        body: {
          'url': url,
          'fetchDetails': false,
          if (url.contains('youtu')) 'tags': ['watch'],
        },
      );
    }
    Future<List<Object?>> urls(String query) async =>
        ((await s.call('GET', '/v1/bookmarks?$query')).$2['bookmarks']! as List)
            .map((b) => (b! as Map)['url'])
            .toList();

    expect(await urls('source=reddit,youtube'), hasLength(2));
    expect(await urls('kind=video'), ['https://youtu.be/xyz']);
    final tagId =
        ((await s.call('GET', '/v1/tags')).$2['tags']! as List).single as Map;
    expect(await urls('tag=${tagId['id']}&source=youtube'), [
      'https://youtu.be/xyz',
    ]);
    expect(await urls('status=read'), isEmpty);
  });
}
