import 'dart:async';
import 'dart:convert';

import 'package:capsula_core/api/api_json.dart';
import 'package:capsula_core/domain/bookmarks/bookmark.dart';
import 'package:capsula_core/domain/maintenance/maintenance.dart';
import 'package:capsula_core/domain/reader/page_info_service.dart';
import 'package:capsula_core/domain/reader/reader_content.dart';
import 'package:capsula_core/domain/reader/reader_service.dart';
import 'package:http/http.dart' as http;

class ApiException implements Exception {
  const ApiException(this.status, this.code, this.message);

  final int status;
  final String code;
  final String message;

  @override
  String toString() => message;
}

/// Talks to a Capsula API server as the signed-in user.
class CapsulaApiClient {
  CapsulaApiClient(this.baseUrl, this._idToken, {http.Client? client})
    : _http = client ?? http.Client();

  final Uri baseUrl;
  final Future<String?> Function() _idToken;
  final http.Client _http;

  static const _timeout = Duration(seconds: 20);

  Uri _uri(String path, [Map<String, String>? query]) => baseUrl.replace(
    path: '${baseUrl.path.replaceFirst(RegExp(r'/+$'), '')}$path',
    queryParameters: query,
  );

  Future<Map<String, Object?>> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
    bool auth = true,
  }) async {
    final request = http.Request(method, _uri(path, query));
    if (auth) {
      final token = await _idToken();
      if (token == null) {
        throw const ApiException(401, 'signed_out', 'Sign in first');
      }
      request.headers['Authorization'] = 'Bearer $token';
    }
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    final response = await http.Response.fromStream(
      await _http.send(request).timeout(_timeout),
    );
    final decoded = response.body.isEmpty
        ? const <String, Object?>{}
        : jsonDecode(response.body);
    final json = decoded is Map<String, Object?>
        ? decoded
        : const <String, Object?>{};
    if (response.statusCode >= 400) {
      final error = json['error'] as Map?;
      throw ApiException(
        response.statusCode,
        error?['code'] as String? ?? 'error',
        error?['message'] as String? ??
            'Request failed (${response.statusCode})',
      );
    }
    return json;
  }

  /// True when the server answers its health check.
  Future<bool> isReachable() async {
    try {
      final json = await _send('GET', '/v1/health', auth: false);
      return json['status'] == 'ok';
    } on Object {
      return false;
    }
  }

  Future<PageMetadata?> pageInfo(Uri url) async {
    final json = await _send(
      'GET',
      '/v1/page-info',
      query: {'url': url.toString()},
    );
    final metadata = metadataFromJson(json);
    return metadata.isEmpty ? null : metadata;
  }

  Future<ReaderContent> reader(Uri url) async => readerContentFromJson(
    await _send('GET', '/v1/reader', query: {'url': url.toString()}),
  );

  Future<LinkCheck> linkStatus(Uri url) async {
    final json = await _send(
      'GET',
      '/v1/link-status',
      query: {'url': url.toString()},
    );
    return LinkCheck(
      LinkHealth.values.firstWhere(
        (h) => h.name == json['health'],
        orElse: () => LinkHealth.unknown,
      ),
      statusCode: json['statusCode'] as int?,
      reason: json['reason'] as String?,
    );
  }

  /// Turns on the collection's public link and returns its URL.
  Future<Uri> shareCollection(String collectionId) async {
    final json = await _send('POST', '/v1/collections/$collectionId/share');
    return Uri.parse(json['url'] as String);
  }

  Future<void> unshareCollection(String collectionId) =>
      _send('DELETE', '/v1/collections/$collectionId/share');

  Future<List<ApiTokenInfo>> tokens() async {
    final json = await _send('GET', '/v1/tokens');
    return [
      for (final t in json['tokens'] as List? ?? const [])
        ApiTokenInfo.fromJson((t as Map).cast<String, Object?>()),
    ];
  }

  /// Returns the new token and its secret, which is only shown once.
  Future<(ApiTokenInfo, String)> createToken(String name) async {
    final json = await _send('POST', '/v1/tokens', body: {'name': name});
    return (ApiTokenInfo.fromJson(json), json['token'] as String);
  }

  Future<void> deleteToken(String id) => _send('DELETE', '/v1/tokens/$id');
}

class ApiTokenInfo {
  const ApiTokenInfo({
    required this.id,
    required this.name,
    required this.createdAt,
    this.lastUsedAt,
  });

  factory ApiTokenInfo.fromJson(Map<String, Object?> json) => ApiTokenInfo(
    id: json['id'] as String,
    name: json['name'] as String? ?? '',
    createdAt:
        DateTime.tryParse(json['createdAt'] as String? ?? '') ?? DateTime(0),
    lastUsedAt: DateTime.tryParse(json['lastUsedAt'] as String? ?? ''),
  );

  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime? lastUsedAt;
}

/// Uses the API when one is configured and reachable, otherwise works on
/// the device. On the web, the API avoids cross-origin restrictions.
class ApiOrLocalPageInfo implements PageInfoSource {
  ApiOrLocalPageInfo(this._api, this._local);

  final CapsulaApiClient? Function() _api;
  final PageInfoSource _local;

  @override
  Future<PageMetadata?> lookup(Uri url) async {
    final api = _api();
    if (api != null) {
      try {
        return await api.pageInfo(url);
      } on Object {
        // Fall back to looking it up on the device.
      }
    }
    return _local.lookup(url);
  }
}

class ApiOrLocalReader implements ReaderSource {
  ApiOrLocalReader(this._api, this._local);

  final CapsulaApiClient? Function() _api;
  final ReaderSource _local;

  @override
  Future<ReaderContent> load(Bookmark bookmark) async {
    final api = _api();
    final url = Uri.tryParse(bookmark.url);
    if (api != null && url != null) {
      try {
        return await api.reader(url);
      } on Object {
        // Fall back to reading it on the device.
      }
    }
    return _local.load(bookmark);
  }
}

class ApiOrLocalLinkChecker implements LinkChecker {
  ApiOrLocalLinkChecker(this._api, this._local);

  final CapsulaApiClient? Function() _api;
  final LinkChecker _local;

  @override
  Future<LinkCheck> check(Uri url) async {
    final api = _api();
    if (api != null) {
      try {
        return await api.linkStatus(url);
      } on Object {
        // Fall back to checking from the device.
      }
    }
    return _local.check(url);
  }
}
