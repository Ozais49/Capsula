import 'dart:async';

import 'package:capsula/domain/organization/label.dart';

import 'in_memory_bookmark_repository.dart';

/// In-memory [LabelRepository] for tests. Deleting a label also removes it
/// from bookmarks in [bookmarks], like the real implementation.
class InMemoryLabelRepository implements LabelRepository {
  InMemoryLabelRepository(this.bookmarks);

  final InMemoryBookmarkRepository bookmarks;
  final Map<String, Label> items = {};
  final _changes = StreamController<void>.broadcast();
  int _nextId = 0;

  void addAll(Iterable<Label> labels) {
    for (final l in labels) {
      items[l.id] = l;
    }
    _changes.add(null);
  }

  List<Label> _of(LabelKind kind) =>
      sortLabels(items.values.where((l) => l.kind == kind));

  @override
  String newId(LabelKind kind) => '${kind.name}${_nextId++}';

  @override
  Stream<List<Label>> watch(LabelKind kind) async* {
    yield _of(kind);
    await for (final _ in _changes.stream) {
      yield _of(kind);
    }
  }

  @override
  Future<void> create(Label label) async {
    items[label.id] = label;
    _changes.add(null);
  }

  @override
  Future<void> rename(Label label, String name) async {
    items[label.id] = label.rename(name);
    _changes.add(null);
  }

  @override
  Future<void> delete(Label label) async {
    items.remove(label.id);
    final updated = bookmarks.items.values
        .where((b) => b.labelIds(label.kind).contains(label.id))
        .map(
          (b) => switch (label.kind) {
            LabelKind.tag => b.copyWith(
              tagIds: b.tagIds.where((id) => id != label.id).toList(),
            ),
            LabelKind.collection => b.copyWith(
              collectionIds: b.collectionIds
                  .where((id) => id != label.id)
                  .toList(),
            ),
          },
        )
        .toList();
    bookmarks.addAll(updated);
    _changes.add(null);
  }
}
