/// Search support that works with simple "array contains" queries:
/// each bookmark stores the prefixes of its words, so typing `fl` matches
/// a bookmark titled "Flutter tips".
library;

const _maxPrefixLength = 20;
const _maxTokens = 400;

// \p{M} keeps combining marks (e.g. Devanagari vowel signs) inside words.
final _wordSplitter = RegExp(r'[^\p{L}\p{M}\p{N}]+', unicode: true);

List<String> searchWords(String text) =>
    text.toLowerCase().split(_wordSplitter).where((w) => w.isNotEmpty).toList();

/// All prefixes of the words in [texts], capped in number and length.
List<String> buildSearchTokens(Iterable<String> texts) {
  final tokens = <String>{};
  for (final word in texts.expand(searchWords)) {
    final limit = word.length < _maxPrefixLength
        ? word.length
        : _maxPrefixLength;
    for (var i = 1; i <= limit; i++) {
      tokens.add(word.substring(0, i));
      if (tokens.length >= _maxTokens) return tokens.toList();
    }
  }
  return tokens.toList();
}

/// The query word used for the database lookup: the longest one, since it
/// narrows results the most. Null when [query] has no words.
String? primarySearchToken(String query) {
  final words = searchWords(query);
  if (words.isEmpty) return null;
  final longest = words.reduce((a, b) => b.length > a.length ? b : a);
  return longest.length > _maxPrefixLength
      ? longest.substring(0, _maxPrefixLength)
      : longest;
}

/// True when every word of [query] starts some word in [texts].
bool matchesSearch(Iterable<String> texts, String query) {
  final queryWords = searchWords(query);
  if (queryWords.isEmpty) return true;
  final words = texts.expand(searchWords).toList();
  return queryWords.every((q) => words.any((w) => w.startsWith(q)));
}
