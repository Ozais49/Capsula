import 'dart:async';

import '../domain/highlights/highlight.dart';

/// In-memory [HighlightRepository], used by tests and to hold the on-device
/// library.
class InMemoryHighlightRepository implements HighlightRepository {
  final Map<String, Highlight> items = {};
  final _changes = StreamController<void>.broadcast();
  int _nextId = 0;

  void addAll(Iterable<Highlight> highlights) {
    for (final h in highlights) {
      items[h.id] = h;
    }
    _changes.add(null);
  }

  Stream<T> _watch<T>(T Function() read) async* {
    yield read();
    await for (final _ in _changes.stream) {
      yield read();
    }
  }

  @override
  String newId() => 'h${_nextId++}';

  @override
  Stream<List<Highlight>> watchForBookmark(String bookmarkId) => _watch(
    () =>
        items.values.where((h) => h.bookmarkId == bookmarkId).toList()
          ..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
  );

  @override
  Stream<List<Highlight>> watchAll({required int limit}) => _watch(
    () =>
        (items.values.toList()
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt)))
            .take(limit)
            .toList(),
  );

  @override
  Future<void> save(Highlight highlight) async {
    items[highlight.id] = highlight;
    _changes.add(null);
  }

  @override
  Future<void> delete(String id) async {
    items.remove(id);
    _changes.add(null);
  }

  @override
  Future<void> deleteForBookmark(String bookmarkId) async {
    items.removeWhere((_, h) => h.bookmarkId == bookmarkId);
    _changes.add(null);
  }
}
