import 'package:capsula/data/firebase/firestore_bookmark_repository.dart';
import 'package:capsula/data/firebase/firestore_label_repository.dart';
import 'package:capsula_core/domain/bookmarks/bookmark.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_repository.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_source.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_view.dart';
import 'package:capsula_core/domain/organization/label.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

Bookmark _bookmark(
  String id, {
  List<String> tagIds = const [],
  List<String> collectionIds = const [],
  BookmarkSource source = BookmarkSource.website,
  bool inInbox = true,
  int minute = 0,
}) {
  final t = DateTime.utc(2026, 10, 14, 12, minute);
  return Bookmark(
    id: id,
    url: 'https://example.com/$id',
    canonicalUrl: 'https://example.com/$id',
    title: id,
    source: source,
    sourceDomain: 'example.com',
    createdAt: t,
    updatedAt: t,
    tagIds: tagIds,
    collectionIds: collectionIds,
    inInbox: inInbox,
  );
}

void main() {
  late FakeFirebaseFirestore db;
  late FirestoreBookmarkRepository bookmarks;
  late FirestoreLabelRepository labels;

  setUp(() {
    db = FakeFirebaseFirestore();
    bookmarks = FirestoreBookmarkRepository(db, () => 'alice');
    labels = FirestoreLabelRepository(db, () => 'alice');
  });

  Future<List<String>> ids(BookmarkView view) async =>
      (await bookmarks.watchList(BookmarkQuery(view: view), limit: 50).first)
          .map((b) => b.id)
          .toList();

  test('stores tags and collections separately under the user', () async {
    await labels.create(const Label(id: 't1', kind: LabelKind.tag, name: 'AI'));
    await labels.create(
      const Label(id: 'c1', kind: LabelKind.collection, name: 'Research'),
    );

    expect((await db.doc('users/alice/tags/t1').get())['name'], 'AI');
    expect(
      (await db.doc('users/alice/collections/c1').get())['name'],
      'Research',
    );
    expect((await labels.watch(LabelKind.tag).first).map((l) => l.name), [
      'AI',
    ]);
  });

  test('lists labels sorted by name, ignoring case', () async {
    for (final (id, name) in [('1', 'beta'), ('2', 'Alpha'), ('3', 'gamma')]) {
      await labels.create(Label(id: id, kind: LabelKind.tag, name: name));
    }
    expect((await labels.watch(LabelKind.tag).first).map((l) => l.name), [
      'Alpha',
      'beta',
      'gamma',
    ]);
  });

  test('renames', () async {
    const label = Label(id: 't1', kind: LabelKind.tag, name: 'AI');
    await labels.create(label);
    await labels.rename(label, 'Machine learning');
    expect(
      (await labels.watch(LabelKind.tag).first).single.name,
      'Machine learning',
    );
  });

  test('filters bookmarks by view', () async {
    await bookmarks.create(_bookmark('a', tagIds: ['t1'], minute: 1));
    await bookmarks.create(
      _bookmark('b', collectionIds: ['c1'], inInbox: false, minute: 2),
    );
    await bookmarks.create(
      _bookmark('c', source: BookmarkSource.reddit, minute: 3),
    );

    // Unsorted: no tags and no collections.
    expect(await ids(BookmarkView.inbox), ['c']);
    expect(await ids(BookmarkView.all), ['c', 'b', 'a']);
    expect(await ids(const SourceView(BookmarkSource.reddit)), ['c']);
    expect(await ids(const LabelView(LabelKind.tag, 't1')), ['a']);
    expect(await ids(const LabelView(LabelKind.collection, 'c1')), ['b']);
  });

  test('searches inside a label view', () async {
    await bookmarks.create(_bookmark('flutter-tips', tagIds: ['t1']));
    await bookmarks.create(_bookmark('react-tips', tagIds: ['t1']));

    final results = await bookmarks
        .watchList(
          const BookmarkQuery(
            view: LabelView(LabelKind.tag, 't1'),
            search: 'flutter',
          ),
          limit: 10,
        )
        .first;
    expect(results.map((b) => b.id), ['flutter-tips']);
  });

  test('counts Unsorted', () async {
    await bookmarks.create(_bookmark('a'));
    await bookmarks.create(_bookmark('b'));
    await bookmarks.create(_bookmark('c', tagIds: ['t1']));
    expect(await bookmarks.countInbox(), 2);
  });

  test('deleting a label removes it from bookmarks, keeping others', () async {
    const ai = Label(id: 't1', kind: LabelKind.tag, name: 'AI');
    await labels.create(ai);
    await bookmarks.create(_bookmark('a', tagIds: ['t1', 't2']));
    await bookmarks.create(_bookmark('b', tagIds: ['t2']));

    await labels.delete(ai);

    expect((await db.doc('users/alice/tags/t1').get()).exists, isFalse);
    expect((await bookmarks.watch('a').first)!.tagIds, ['t2']);
    expect((await bookmarks.watch('b').first)!.tagIds, ['t2']);
  });
}
