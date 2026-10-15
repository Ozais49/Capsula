/// A fetched web resource.
class FetchedPage {
  const FetchedPage({
    required this.statusCode,
    required this.body,
    required this.finalUrl,
    this.contentType,
  });

  final int statusCode;
  final String body;

  /// URL after redirects.
  final Uri finalUrl;
  final String? contentType;

  bool get isHtml {
    final type = contentType?.toLowerCase();
    return type == null || type.contains('html') || type.contains('xml');
  }

  bool get isJson => contentType?.toLowerCase().contains('json') ?? false;
}

enum FetchFailure {
  /// No connection, DNS failure, timeout.
  network,

  /// The browser refused the request (CORS on the web).
  blocked,
}

class FetchException implements Exception {
  const FetchException(this.failure, [this.detail]);

  final FetchFailure failure;
  final Object? detail;

  @override
  String toString() => 'FetchException($failure, $detail)';
}

/// Fetches web content. Throws [FetchException] when no response arrives;
/// HTTP error statuses are returned, not thrown.
abstract interface class ContentFetcher {
  Future<FetchedPage> fetch(Uri url, {Map<String, String> headers});
}
