import 'package:capsula_core/domain/bookmarks/bookmark.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_repository.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_service.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_source.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_view.dart';
import 'package:capsula_core/domain/organization/label.dart';
import 'package:capsula_core/testing/in_memory_bookmark_repository.dart';
import 'package:capsula_core/testing/in_memory_label_repository.dart';
import 'package:flutter_test/flutter_test.dart';

Label _c(String id, String name, [String? parent]) =>
    Label(id: id, kind: LabelKind.collection, name: name, parentId: parent);

Bookmark _b(String id, int day) {
  final t = DateTime(2026, 1, day);
  return Bookmark(
    id: id,
    url: 'https://example.com/$id',
    canonicalUrl: 'https://example.com/$id',
    title: id,
    source: BookmarkSource.website,
    sourceDomain: 'example.com',
    createdAt: t,
    updatedAt: t,
  );
}

void main() {
  final work = _c('w', 'Work');
  final reports = _c('r', 'Reports', 'w');
  final q1 = _c('q', 'Q1', 'r');
  final home = _c('h', 'Home');
  final orphan = _c('o', 'Orphan', 'missing');
  final all = [q1, home, reports, work, orphan];

  test('labelTree orders parents before children, by name', () {
    expect(labelTree(all).map((e) => '${'  ' * e.$2}${e.$1.name}'), [
      'Home',
      'Orphan',
      'Work',
      '  Reports',
      '    Q1',
    ]);
  });

  test('labelTree survives cycles', () {
    final a = _c('a', 'A', 'b');
    final b = _c('b', 'B', 'a');
    expect(labelTree([a, b]).map((e) => e.$1.id).toSet(), {'a', 'b'});
  });

  test('descendants and paths', () {
    expect(labelWithDescendants('w', all), {'w', 'r', 'q'});
    expect(labelWithDescendants('h', all), {'h'});
    expect(labelPath(q1, all), 'Work / Reports / Q1');
  });

  group('service', () {
    late InMemoryBookmarkRepository repo;
    late InMemoryLabelRepository labels;
    late BookmarkService service;

    setUp(() {
      repo = InMemoryBookmarkRepository();
      labels = InMemoryLabelRepository(repo)..addAll(all);
      service = BookmarkService(repo, labels);
    });

    test('same name is allowed under different parents', () {
      final top = service.createLabel(
        LabelKind.collection,
        'Reports',
        labels.items.values.toList(),
      );
      expect(top!.id, isNot('r'));
      expect(top.parentId, isNull);

      final again = service.createLabel(
        LabelKind.collection,
        'reports',
        labels.items.values.toList(),
        parentId: 'w',
      );
      expect(again!.id, 'r');
    });

    test('moving refuses to create a loop', () async {
      final current = labels.items.values.toList();
      expect(await service.moveCollection(work, 'q', current), isFalse);
      expect(await service.moveCollection(work, 'w', current), isFalse);
      expect(await service.moveCollection(q1, 'h', current), isTrue);
      expect(labels.items['q']!.parentId, 'h');
      expect(await service.moveCollection(q1, null, current), isTrue);
      expect(labels.items['q']!.parentId, isNull);
    });

    test('deleting a parent moves its children up', () async {
      await labels.delete(reports);
      expect(labels.items['q']!.parentId, 'w');
    });

    test('bulk edits', () async {
      repo.addAll([_b('a', 1), _b('b', 2)]);
      final items = repo.items.values.toList();

      await service.updateMany(items, (b) => b.copyWith(favorite: true));
      expect(repo.items.values.every((b) => b.favorite), isTrue);

      await service.addLabelToMany(repo.items.values, LabelKind.tag, 't1');
      await service.addLabelToMany(repo.items.values, LabelKind.tag, 't1');
      expect(repo.items['a']!.tagIds, ['t1'], reason: 'no duplicates');

      await service.deleteMany(repo.items.values.toList());
      expect(repo.items, isEmpty);
    });
  });

  test('favorites view and oldest-first sort', () async {
    final repo = InMemoryBookmarkRepository()
      ..addAll([
        _b('old', 1),
        _b('new', 3).copyWith(favorite: true),
        _b('mid', 2).copyWith(favorite: true),
      ]);

    final favs = await repo
        .watchList(const BookmarkQuery(view: BookmarkView.favorites), limit: 10)
        .first;
    expect(favs.map((b) => b.id), ['new', 'mid']);

    final oldest = await repo
        .watchList(
          const BookmarkQuery(
            view: BookmarkView.all,
            sort: BookmarkSort.oldest,
          ),
          limit: 10,
        )
        .first;
    expect(oldest.map((b) => b.id), ['old', 'mid', 'new']);
    expect(BookmarkView.parse('favorites'), BookmarkView.favorites);
  });
}
