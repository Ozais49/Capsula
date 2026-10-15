import '../bookmarks/search_tokens.dart';
import '../reader/reader_content.dart';

/// Full-text search over the text of saved pages. Each bookmark's page is
/// stored as its set of distinct words, which an "array contains" query can
/// look up without a separate search engine.
abstract interface class ContentIndex {
  Future<void> save(String bookmarkId, List<String> words);

  /// Bookmark IDs whose page contains every word of [query].
  Future<List<String>> search(String query, {int limit = 50});

  Future<void> delete(String bookmarkId);
}

const maxIndexedWords = 3000;

const _stopWords = {
  'the',
  'and',
  'for',
  'are',
  'but',
  'not',
  'you',
  'all',
  'any',
  'can',
  'had',
  'her',
  'was',
  'one',
  'our',
  'out',
  'has',
  'him',
  'his',
  'how',
  'its',
  'may',
  'new',
  'now',
  'old',
  'see',
  'two',
  'who',
  'did',
  'get',
  'let',
  'say',
  'she',
  'too',
  'use',
  'that',
  'with',
  'have',
  'this',
  'will',
  'your',
  'from',
  'they',
  'been',
  'were',
  'what',
  'when',
  'than',
  'them',
  'then',
  'there',
  'their',
  'which',
  'would',
  'about',
  'into',
  'more',
  'some',
  'could',
  'other',
  'also',
  'just',
  'only',
  'very',
};

/// Searchable words: lowercase, at least three characters, not common
/// filler words. Used for both indexing and queries.
List<String> fullTextWords(String text) =>
    searchWords(text)
        .where((w) => w.length >= 3 && !_stopWords.contains(w))
        .toList();

/// Distinct words of [texts], most frequent first, capped at
/// [maxIndexedWords].
List<String> contentWords(Iterable<String> texts) {
  final counts = <String, int>{};
  for (final w in texts.expand(fullTextWords)) {
    counts[w] = (counts[w] ?? 0) + 1;
  }
  final words = counts.keys.toList()
    ..sort((a, b) => counts[b]!.compareTo(counts[a]!));
  return words.take(maxIndexedWords).toList();
}

/// All readable text of an article, for indexing.
List<String> articleTexts(ArticleContent article) => [
  article.title,
  ?article.excerpt,
  for (final b in article.blocks) ..._blockTexts(b),
];

Iterable<String> _blockTexts(ReaderBlock b) => switch (b) {
  HeadingBlock(:final runs) ||
  ParagraphBlock(:final runs) => [runs.map((r) => r.text).join()],
  ListBlock(:final items) => items.map((i) => i.map((r) => r.text).join()),
  QuoteBlock(:final blocks) => blocks.expand(_blockTexts),
  CodeBlock(:final text) => [text],
  ImageBlock(:final caption) => [?caption],
};

/// The query word to look up first: the longest, since it's usually the
/// rarest. Null when the query has no searchable words.
String? fullTextLookupWord(String query) {
  final words = fullTextWords(query);
  if (words.isEmpty) return null;
  return words.reduce((a, b) => b.length > a.length ? b : a);
}

/// Whether [indexed] words contain every searchable word of [query].
bool fullTextMatches(Iterable<String> indexed, String query) {
  final set = indexed is Set<String> ? indexed : indexed.toSet();
  final words = fullTextWords(query);
  return words.isNotEmpty && words.every(set.contains);
}
