import 'url_normalizer.dart';

/// Text another app shared with us (Android `EXTRA_TEXT` / `EXTRA_SUBJECT`).
class SharedContent {
  const SharedContent({this.text, this.subject});

  final String? text;
  final String? subject;
}

/// Links found in shared content, plus a title when one can be inferred.
class SharedLinks {
  const SharedLinks(this.urls, this.title);

  final List<Uri> urls;

  /// Only set when exactly one link was shared.
  final String? title;
}

SharedLinks extractSharedLinks(SharedContent content) {
  final text = content.text ?? '';
  final subject = content.subject?.trim() ?? '';

  var urls = _findUrls('$text\n$subject');
  if (urls.isEmpty) urls = _findBareDomains(text);

  String? title;
  if (urls.length == 1) {
    if (subject.isNotEmpty && parseWebUrl(subject) == null) {
      title = subject;
    } else {
      final rest = text
          .replaceAll(_urlPattern, ' ')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim()
          .replaceAll(RegExp(r'^[\s\-–—:|]+|[\s\-–—:|]+$'), '')
          .trim();
      if (rest.length >= 3 && rest.length <= 300) title = rest;
    }
  }
  return SharedLinks(urls, title);
}

final _urlPattern = RegExp(r'''https?://[^\s<>"'`]+''', caseSensitive: false);

List<Uri> _findUrls(String text) => _unique(
  _urlPattern.allMatches(text).map((m) => _trimTrailing(m.group(0)!)),
);

List<Uri> _findBareDomains(String text) => _unique(
  RegExp(
    r'''\bwww\.[^\s<>"'`]+''',
    caseSensitive: false,
  ).allMatches(text).map((m) => _trimTrailing(m.group(0)!)),
);

List<Uri> _unique(Iterable<String> candidates) {
  final seen = <String>{};
  final result = <Uri>[];
  for (final candidate in candidates) {
    final uri = parseWebUrl(candidate);
    if (uri != null && seen.add(canonicalizeUrl(uri))) result.add(uri);
  }
  return result;
}

/// Removes punctuation that ends a sentence rather than the URL, keeping
/// balanced parentheses such as in Wikipedia links.
String _trimTrailing(String url) {
  var result = url;
  while (result.isNotEmpty) {
    final last = result[result.length - 1];
    if ('.,;:!?\'"'.contains(last)) {
      result = result.substring(0, result.length - 1);
    } else if (last == ')' &&
        '('.allMatches(result).length < ')'.allMatches(result).length) {
      result = result.substring(0, result.length - 1);
    } else {
      break;
    }
  }
  return result;
}
