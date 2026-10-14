import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../domain/reader/content_fetcher.dart';

class HttpContentFetcher implements ContentFetcher {
  HttpContentFetcher([http.Client? client]) : _client = client ?? http.Client();

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
      if (!kIsWeb)
        'User-Agent':
            'Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 '
            '(KHTML, like Gecko) Chrome/130.0 Mobile Safari/537.36',
      'Accept':
          'text/html,application/xhtml+xml,application/json;q=0.9,*/*;q=0.8',
      ...headers,
    };

    try {
      // Follow redirects ourselves so the final URL is known (e.g. to spot a
      // redirect to a login page). Browsers always follow them internally.
      var current = url;
      for (var hop = 0; ; hop++) {
        final request = http.Request('GET', current)
          ..followRedirects = kIsWeb
          ..headers.addAll(allHeaders);
        final response = await _client.send(request).timeout(_timeout);
        final location = response.headers['location'];
        if (!kIsWeb &&
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
        kIsWeb ? FetchFailure.blocked : FetchFailure.network,
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
