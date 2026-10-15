import '../domain/search/full_text.dart';

class InMemoryContentIndex implements ContentIndex {
  final Map<String, List<String>> items = {};

  @override
  Future<void> save(String bookmarkId, List<String> words) async =>
      items[bookmarkId] = words;

  @override
  Future<List<String>> search(String query, {int limit = 50}) async => [
    for (final e in items.entries)
      if (fullTextMatches(e.value, query)) e.key,
  ].take(limit).toList();

  @override
  Future<void> delete(String bookmarkId) async => items.remove(bookmarkId);
}
