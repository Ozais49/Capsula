import 'dart:async';

import 'package:capsula_core/domain/bookmarks/bookmark.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_repository.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_view.dart';
import 'package:capsula_core/domain/bookmarks/search_tokens.dart';

/// In-memory [BookmarkRepository] for tests.
class InMemoryBookmarkRepository implements BookmarkRepository {
  final Map<String, Bookmark> items = {};
  final _changes = StreamController<void>.broadcast();
  int _nextId = 0;

  /// When set, the next write is applied locally but then fails, like a
  /// write the backend rejects.
  Object? nextWriteError;

  void addAll(Iterable<Bookmark> bookmarks) {
    for (final b in bookmarks) {
      items[b.id] = b;
    }
    _changes.add(null);
  }

  @override
  String newId() => 'b${_nextId++}';

  @override
  Future<void> create(Bookmark bookmark) => _write(() {
    items[bookmark.id] = bookmark;
  });

  @override
  Future<void> update(Bookmark bookmark) => _write(() {
    items[bookmark.id] = bookmark;
  });

  @override
  Future<void> delete(String id) => _write(() {
    items.remove(id);
  });

  @override
  Stream<Bookmark?> watch(String id) async* {
    yield items[id];
    await for (final _ in _changes.stream) {
      yield items[id];
    }
  }

  @override
  Stream<List<Bookmark>> watchList(
    BookmarkQuery query, {
    required int limit,
  }) async* {
    yield _query(query, limit);
    await for (final _ in _changes.stream) {
      yield _query(query, limit);
    }
  }

  @override
  Future<Bookmark?> findByCanonicalUrl(String canonicalUrl) async =>
      items.values.where((b) => b.canonicalUrl == canonicalUrl).firstOrNull;

  /// Batches passed to [createMany], for asserting batch sizes.
  final List<int> batchSizes = [];

  /// Fails the batch with this index (0-based) in [createMany].
  int? failBatch;

  @override
  Future<Set<String>> existingCanonicalUrls(
    Iterable<String> canonicalUrls,
  ) async {
    final all = items.values.map((b) => b.canonicalUrl).toSet();
    return canonicalUrls.where(all.contains).toSet();
  }

  @override
  Future<void> createMany(List<Bookmark> bookmarks) async {
    final index = batchSizes.length;
    batchSizes.add(bookmarks.length);
    if (index == failBatch) throw Exception('connection lost');
    addAll(bookmarks);
  }

  @override
  Future<List<Bookmark>> fetchAll() async =>
      items.values.toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  @override
  Future<int?> countInbox() async =>
      items.values.where((b) => bookmarkInView(b, const InboxView())).length;

  List<Bookmark> _query(BookmarkQuery query, int limit) =>
      (items.values
              .where((b) => bookmarkInView(b, query.view))
              .where((b) => matchesSearch(b.searchableText, query.search))
              .toList()
            ..sort((a, b) => b.createdAt.compareTo(a.createdAt)))
          .take(limit)
          .toList();

  Future<void> _write(void Function() apply) async {
    apply();
    _changes.add(null);
    final error = nextWriteError;
    nextWriteError = null;
    if (error != null) throw error;
  }
}
