import 'dart:convert';

import 'package:capsula_api/capsula_api.dart';
import 'package:capsula_core/domain/bookmarks/bookmark.dart';
import 'package:capsula_core/domain/reader/page_info_service.dart';
import 'package:capsula_core/domain/reader/reader_content.dart';
import 'package:capsula_core/domain/reader/reader_service.dart';
import 'package:capsula_core/testing/in_memory_bookmark_repository.dart';
import 'package:capsula_core/testing/in_memory_label_repository.dart';
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

class _FakePageInfo implements PageInfoSource {
  final titles = <String, String>{};

  @override
  Future<PageMetadata?> lookup(Uri url) async => titles[url.toString()] == null
      ? null
      : PageMetadata(title: titles[url.toString()]);
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
        return UserData(b, l);
      },
      tokens: tokens,
      pageInfo: pageInfo,
      reader: _FakeReader(),
      rateLimiter: RateLimiter(perMinute),
    );
  }

  late final CapsulaApi api;
  final bookmarks = <String, InMemoryBookmarkRepository>{};
  final labels = <String, InMemoryLabelRepository>{};
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

      expect((await s.call('DELETE', '/v1/bookmarks/$id')).$1, 204);
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
}
