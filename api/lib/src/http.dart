import 'dart:convert';

import 'package:shelf/shelf.dart';

const _jsonHeaders = {'content-type': 'application/json; charset=utf-8'};

Response jsonResponse(
  Object? body, {
  int status = 200,
  Map<String, String> headers = const {},
}) => Response(
  status,
  body: jsonEncode(body),
  headers: {..._jsonHeaders, ...headers},
);

/// Errors look like `{"error": {"code": "not_found", "message": "…"}}`.
Response errorResponse(int status, String code, String message) =>
    jsonResponse({
      'error': {'code': code, 'message': message},
    }, status: status);

/// Thrown by handlers to return an error response.
class ApiError implements Exception {
  const ApiError(this.status, this.code, this.message);

  const ApiError.badRequest(String message) : this(400, 'bad_request', message);
  const ApiError.notFound([String message = 'Not found'])
    : this(404, 'not_found', message);

  final int status;
  final String code;
  final String message;
}

/// Reads a JSON object body, or throws [ApiError].
Future<Map<String, Object?>> readJson(Request request) async {
  final text = await request.readAsString();
  if (text.trim().isEmpty) return {};
  try {
    final decoded = jsonDecode(text);
    if (decoded is Map<String, Object?>) return decoded;
  } on FormatException {
    // Fall through.
  }
  throw const ApiError.badRequest('Body must be a JSON object');
}

/// Turns [ApiError]s and unexpected exceptions into JSON error responses.
/// Unexpected errors are logged without request details, which may contain
/// private URLs.
Middleware errorHandling({void Function(Object, StackTrace)? log}) =>
    (inner) => (request) async {
      try {
        return await inner(request);
      } on ApiError catch (e) {
        return errorResponse(e.status, e.code, e.message);
      } on Object catch (e, s) {
        log?.call(e, s);
        return errorResponse(500, 'internal', 'Something went wrong');
      }
    };

/// Answers CORS preflight requests and adds CORS headers for browsers.
Middleware cors(List<String> allowedOrigins) =>
    (inner) => (request) async {
      final origin = request.headers['origin'];
      final allowAny = allowedOrigins.contains('*');
      final allowed =
          origin != null && (allowAny || allowedOrigins.contains(origin));
      final headers = {
        if (allowed) 'access-control-allow-origin': allowAny ? '*' : origin,
        if (allowed && !allowAny) 'vary': 'Origin',
        'access-control-allow-methods': 'GET, POST, PATCH, DELETE, OPTIONS',
        'access-control-allow-headers': 'Authorization, Content-Type',
        'access-control-max-age': '600',
      };
      if (request.method == 'OPTIONS') {
        return Response(allowed ? 204 : 403, headers: headers);
      }
      final response = await inner(request);
      return allowed ? response.change(headers: headers) : response;
    };

/// A simple fixed-window limit per key (the caller's user ID).
class RateLimiter {
  RateLimiter(this.perMinute, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final int perMinute;
  final DateTime Function() _now;
  final _windows = <String, (int minute, int count)>{};

  /// Returns false when [key] has used up this minute's requests.
  bool allow(String key) {
    final minute = _now().millisecondsSinceEpoch ~/ 60000;
    final (current, count) = _windows[key] ?? (minute, 0);
    final used = current == minute ? count : 0;
    if (used >= perMinute) return false;
    _windows[key] = (minute, used + 1);
    if (_windows.length > 10000) {
      _windows.removeWhere((_, w) => w.$1 != minute);
    }
    return true;
  }
}
