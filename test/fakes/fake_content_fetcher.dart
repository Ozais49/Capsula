import 'package:capsula/domain/reader/content_fetcher.dart';

/// Serves canned responses by URL prefix; anything else fails as offline.
class FakeContentFetcher implements ContentFetcher {
  final Map<String, FetchedPage Function(Uri url)> routes = {};
  final List<Uri> requests = [];
  final List<Map<String, String>> requestHeaders = [];

  /// When set, every fetch throws this.
  FetchException? failure;

  void html(String urlPrefix, String body, {int status = 200, Uri? finalUrl}) =>
      routes[urlPrefix] = (url) => FetchedPage(
        statusCode: status,
        body: body,
        finalUrl: finalUrl ?? url,
        contentType: 'text/html; charset=utf-8',
      );

  void json(String urlPrefix, String body, {int status = 200}) =>
      routes[urlPrefix] = (url) => FetchedPage(
        statusCode: status,
        body: body,
        finalUrl: url,
        contentType: 'application/json',
      );

  void raw(String urlPrefix, FetchedPage page) =>
      routes[urlPrefix] = (_) => page;

  @override
  Future<FetchedPage> fetch(
    Uri url, {
    Map<String, String> headers = const {},
  }) async {
    requests.add(url);
    requestHeaders.add(headers);
    if (failure case final f?) throw f;
    final key = routes.keys
        .where((prefix) => url.toString().startsWith(prefix))
        .fold<String?>(
          null,
          (best, k) => best == null || k.length > best.length ? k : best,
        );
    if (key == null) throw const FetchException(FetchFailure.network);
    return routes[key]!(url);
  }
}
