import 'dart:convert';

import 'package:capsula/app/api_settings.dart';
import 'package:capsula/data/api/api_client.dart';
import 'package:capsula_core/domain/bookmarks/bookmark.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_source.dart';
import 'package:capsula_core/domain/reader/page_info_service.dart';
import 'package:capsula_core/domain/reader/reader_content.dart';
import 'package:capsula_core/domain/reader/reader_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../fakes/memory_api_settings_store.dart';

CapsulaApiClient _client(MockClientHandler handler, {String? token = 't'}) =>
    CapsulaApiClient(
      Uri.parse('https://api.example.com/base/'),
      () async => token,
      client: MockClient(handler),
    );

class _Local implements PageInfoSource, ReaderSource {
  int calls = 0;

  @override
  Future<PageMetadata?> lookup(Uri url) async {
    calls++;
    return const PageMetadata(title: 'Local');
  }

  @override
  Future<ReaderContent> load(Bookmark bookmark) async {
    calls++;
    return const Unavailable(UnavailableReason.blocked);
  }
}

void main() {
  test('sends the bearer token to the right path', () async {
    late http.Request seen;
    final client = _client((r) async {
      seen = r;
      return http.Response(jsonEncode({'title': 'Remote'}), 200);
    });

    final info = await client.pageInfo(Uri.parse('https://example.com/a'));

    expect(info?.title, 'Remote');
    expect(seen.url.path, '/base/v1/page-info');
    expect(seen.url.queryParameters['url'], 'https://example.com/a');
    expect(seen.headers['Authorization'], 'Bearer t');
  });

  test('turns error bodies into ApiException', () async {
    final client = _client(
      (_) async => http.Response(
        jsonEncode({
          'error': {'code': 'forbidden', 'message': 'Nope'},
        }),
        403,
      ),
    );
    await expectLater(
      client.tokens(),
      throwsA(
        isA<ApiException>()
            .having((e) => e.status, 'status', 403)
            .having((e) => e.message, 'message', 'Nope'),
      ),
    );
  });

  test('refuses to call without a signed-in user', () async {
    final client = _client((_) async => http.Response('{}', 200), token: null);
    await expectLater(client.tokens(), throwsA(isA<ApiException>()));
  });

  test('health check needs no token and tolerates failures', () async {
    expect(
      await _client(
        (_) async => http.Response('{"status":"ok"}', 200),
        token: null,
      ).isReachable(),
      isTrue,
    );
    expect(
      await _client((_) async => throw http.ClientException('down'))
          .isReachable(),
      isFalse,
    );
  });

  test('creates and lists tokens', () async {
    final client = _client((r) async {
      if (r.method == 'POST') {
        return http.Response(
          jsonEncode({
            'id': 'abc',
            'name': jsonDecode(r.body)['name'],
            'createdAt': '2026-10-15T00:00:00.000Z',
            'token': 'cap_secret',
          }),
          201,
        );
      }
      return http.Response(
        jsonEncode({
          'tokens': [
            {
              'id': 'abc',
              'name': 'Script',
              'createdAt': '2026-10-15T00:00:00Z',
            },
          ],
        }),
        200,
      );
    });

    final (info, secret) = await client.createToken('Script');
    expect(info.name, 'Script');
    expect(secret, 'cap_secret');
    expect((await client.tokens()).single.id, 'abc');
  });

  group('API or device', () {
    test('uses the API when configured', () async {
      final local = _Local();
      final source = ApiOrLocalPageInfo(
        () => _client(
          (_) async => http.Response(jsonEncode({'title': 'Remote'}), 200),
        ),
        local,
      );
      expect(
        (await source.lookup(Uri.parse('https://a.com')))?.title,
        'Remote',
      );
      expect(local.calls, 0);
    });

    test('falls back to the device when the API fails or is unset', () async {
      final local = _Local();
      final failing = ApiOrLocalPageInfo(
        () => _client((_) async => http.Response('oops', 500)),
        local,
      );
      expect(
        (await failing.lookup(Uri.parse('https://a.com')))?.title,
        'Local',
      );

      final unset = ApiOrLocalPageInfo(() => null, local);
      expect((await unset.lookup(Uri.parse('https://a.com')))?.title, 'Local');
      expect(local.calls, 2);
    });

    test('reader decodes API content', () async {
      final reader = ApiOrLocalReader(
        () => _client(
          (_) async => http.Response(
            jsonEncode({
              'type': 'article',
              'title': 'From the server',
              'blocks': [
                {
                  'k': 'p',
                  'runs': [
                    {'t': 'Hello'},
                  ],
                },
              ],
            }),
            200,
          ),
        ),
        _Local(),
      );
      final t = DateTime(2026);
      final content = await reader.load(
        Bookmark(
          id: 'b',
          url: 'https://a.com',
          canonicalUrl: 'https://a.com',
          title: 'a',
          source: BookmarkSource.website,
          sourceDomain: 'a.com',
          createdAt: t,
          updatedAt: t,
        ),
      );
      expect((content as ArticleContent).title, 'From the server');
      expect(content.blocks.single, isA<ParagraphBlock>());
    });
  });

  group('ApiSettings', () {
    test('parses, saves and clears the address', () async {
      final store = MemoryApiSettingsStore();
      final settings = ApiSettings(store);
      await settings.load();
      expect(settings.baseUrl, isNull);

      expect(await settings.save('https://api.example.com/'), isTrue);
      expect(settings.baseUrl.toString(), 'https://api.example.com');
      expect(store.saved, 'https://api.example.com');

      expect(await settings.save('ftp://nope'), isFalse);
      expect(await settings.save('not a url'), isFalse);
      expect(settings.baseUrl.toString(), 'https://api.example.com');

      expect(await settings.save('  '), isTrue);
      expect(settings.baseUrl, isNull);
    });

    test('the built-in default applies until something is saved', () async {
      final settings = ApiSettings(
        MemoryApiSettingsStore(),
        defaultUrl: Uri.parse('https://built.in'),
      );
      expect(settings.baseUrl.toString(), 'https://built.in');
      await settings.load();
      expect(settings.baseUrl.toString(), 'https://built.in');
    });
  });

  group('when the server keeps failing', () {
    test('stops calling it for a minute, then tries again', () async {
      var now = DateTime(2026, 10, 17, 12);
      var calls = 0;
      var serverUp = false;
      final client = CapsulaApiClient(
        Uri.parse('https://api.example.com/'),
        () async => 't',
        now: () => now,
        client: MockClient((r) async {
          calls++;
          return serverUp
              ? http.Response(jsonEncode({'title': 'Remote'}), 200)
              : http.Response('', 503);
        }),
      );
      final url = Uri.parse('https://example.com/a');

      for (var i = 0; i < 3; i++) {
        await expectLater(client.pageInfo(url), throwsA(isA<ApiException>()));
      }
      expect(client.isUnavailable, isTrue);

      // Skipped without a request while the server is considered down.
      await expectLater(
        client.pageInfo(url),
        throwsA(
          isA<ApiException>().having((e) => e.code, 'code', 'unavailable'),
        ),
      );
      expect(calls, 3);

      now = now.add(const Duration(minutes: 1, seconds: 1));
      serverUp = true;
      expect((await client.pageInfo(url))?.title, 'Remote');
      expect(client.isUnavailable, isFalse);
    });

    test('falls back to the device right away', () async {
      final local = _Local();
      final client = _client((r) async => http.Response('', 502));
      final source = ApiOrLocalPageInfo(() => client, local);
      for (var i = 0; i < 5; i++) {
        expect(
          (await source.lookup(Uri.parse('https://example.com/a')))?.title,
          'Local',
        );
      }
      expect(client.isUnavailable, isTrue);
      expect(local.calls, 5);
    });

    test('network errors count too; client errors do not', () async {
      var fail = true;
      final client = _client((r) async {
        if (fail) throw http.ClientException('offline');
        return http.Response(
          jsonEncode({
            'error': {'code': 'bad'},
          }),
          400,
        );
      });
      final url = Uri.parse('https://example.com/a');
      for (var i = 0; i < 2; i++) {
        await expectLater(client.pageInfo(url), throwsA(anything));
      }
      fail = false;
      await expectLater(client.pageInfo(url), throwsA(isA<ApiException>()));
      fail = true;
      await expectLater(client.pageInfo(url), throwsA(anything));
      expect(client.isUnavailable, isFalse);
    });
  });
}
