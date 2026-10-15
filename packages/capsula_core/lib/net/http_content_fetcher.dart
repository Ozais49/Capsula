import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:capsula_core/domain/reader/content_fetcher.dart';

class HttpContentFetcher implements ContentFetcher {
  HttpContentFetcher({http.Client? client, this.inBrowser = false})
    : _client = client ?? http.Client();

  /// Running in a web browser, which follows redirects itself, forbids a
  /// custom user agent and reports blocked cross-origin requests as errors.
  final bool inBrowser;

  final http.Client _client;

  static const _timeout = Duration(seconds: 15);
  static const _maxBytes = 3 * 1024 * 1024;
  static const _maxRedirects = 5;
  static const _redirectStatuses = {301, 302, 303, 307, 308};

  @override
  Future<FetchedPage> fetch(
    Uri url, {
    Map<String, String> headers = const {},
  }) async {
    final allHeaders = {
      // Browsers don't allow setting the user agent.
      if (!inBrowser)
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/130.0 Mobile Safari/537.36',
      'Accept':
          'text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8',
      ...headers,
    };
    // Browsers refuse a custom user agent.
    if (inBrowser) allHeaders.remove('User-Agent');

    try {
      // Follow redirects ourselves so the final URL is known (e.g. to spot a
      // redirect to a login page). Browsers always follow them internally.
      var current = url;
      for (var hop = 0; ; hop++) {
        final request = http.Request('GET', current)
          ..followRedirects = inBrowser
          ..headers.addAll(allHeaders);
        final response = await _client.send(request).timeout(_timeout);
        final location = response.headers['location'];
        if (!inBrowser &&
            _redirectStatuses.contains(response.statusCode) &&
            location != null &&
            hop < _maxRedirects) {
          await response.stream.drain<void>();
          current = current.resolve(location);
          continue;
        }

        final bytes = await _readLimited(response.stream).timeout(_timeout);
        final contentType = response.headers['content-type'];
        return FetchedPage(
          statusCode: response.statusCode,
          body: _decode(bytes, contentType),
          finalUrl: current,
          contentType: contentType,
        );
      }
    } on TimeoutException catch (e) {
      throw FetchException(FetchFailure.network, e);
    } on http.ClientException catch (e) {
      // On the web, a CORS refusal surfaces as a ClientException with no
      // further detail, indistinguishable from being offline.
      throw FetchException(
        inBrowser ? FetchFailure.blocked : FetchFailure.network,
        e,
      );
    }
  }

  static Future<List<int>> _readLimited(Stream<List<int>> stream) async {
    final bytes = <int>[];
    await for (final chunk in stream) {
      bytes.addAll(chunk);
      if (bytes.length > _maxBytes) break;
    }
    return bytes;
  }

  static String _decode(List<int> bytes, String? contentType) {
    final charset = RegExp(
      r'charset=([\w-]+)',
      caseSensitive: false,
    ).firstMatch(contentType ?? '')?.group(1);
    final encoding = charset == null ? null : Encoding.getByName(charset);
    return encoding == null || encoding == utf8
        ? utf8.decode(bytes, allowMalformed: true)
        : encoding.decode(bytes);
  }
}
