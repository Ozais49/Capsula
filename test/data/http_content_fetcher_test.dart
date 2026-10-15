import 'dart:convert';

import 'package:capsula_core/net/http_content_fetcher.dart';
import 'package:capsula_core/domain/reader/content_fetcher.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('follows redirects and reports the final URL', () async {
    final fetcher = HttpContentFetcher(
      client: MockClient((request) async {
        if (request.url.path == '/private') {
          return http.Response(
            '',
            302,
            headers: {'location': '/login?next=/private'},
          );
        }
        return http.Response(
          '<html>login</html>',
          200,
          headers: {'content-type': 'text/html'},
        );
      }),
    );

    final page = await fetcher.fetch(Uri.parse('https://example.com/private'));
    expect(page.statusCode, 200);
    expect(page.finalUrl.toString(), 'https://example.com/login?next=/private');
    expect(page.isHtml, isTrue);
  });

  test('stops after too many redirects', () async {
    var calls = 0;
    final fetcher = HttpContentFetcher(
      client: MockClient((request) async {
        calls++;
        return http.Response('', 301, headers: {'location': '/loop'});
      }),
    );
    final page = await fetcher.fetch(Uri.parse('https://example.com/loop'));
    expect(page.statusCode, 301);
    expect(calls, 6);
  });

  test(
    'decodes UTF-8 when no charset is given, and honors a charset',
    () async {
      final fetcher = HttpContentFetcher(
        client: MockClient((request) async {
          if (request.url.path == '/latin') {
            return http.Response.bytes(
              latin1.encode('café'),
              200,
              headers: {'content-type': 'text/html; charset=ISO-8859-1'},
            );
          }
          return http.Response.bytes(
            utf8.encode('नेपाल'),
            200,
            headers: {'content-type': 'text/html'},
          );
        }),
      );
      expect(
        (await fetcher.fetch(Uri.parse('https://example.com/utf'))).body,
        'नेपाल',
      );
      expect(
        (await fetcher.fetch(Uri.parse('https://example.com/latin'))).body,
        'café',
      );
    },
  );

  test('sends a browser user agent and caller headers', () async {
    late http.BaseRequest seen;
    final fetcher = HttpContentFetcher(
      client: MockClient((request) async {
        seen = request;
        return http.Response('{}', 200);
      }),
    );
    await fetcher.fetch(
      Uri.parse('https://api.example.com/x'),
      headers: {'Accept': 'application/json'},
    );
    expect(seen.headers['User-Agent'], contains('Mozilla'));
    expect(seen.headers['Accept'], 'application/json');
  });

  test('connection errors become network failures', () async {
    final fetcher = HttpContentFetcher(
      client: MockClient((_) async => throw http.ClientException('offline')),
    );
    await expectLater(
      fetcher.fetch(Uri.parse('https://example.com')),
      throwsA(
        isA<FetchException>().having(
          (e) => e.failure,
          'failure',
          FetchFailure.network,
        ),
      ),
    );
  });
}
