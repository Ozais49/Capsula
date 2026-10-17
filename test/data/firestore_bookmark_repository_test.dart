import 'package:capsula/data/firebase/firestore_bookmark_repository.dart';
import 'package:capsula_core/domain/bookmarks/bookmark.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_repository.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_source.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_view.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

Bookmark _bookmark(
  String id, {
  String title = 'Title',
  int minute = 0,
  bool archived = false,
}) {
  final time = DateTime.utc(2026, 10, 14, 12, minute);
  return Bookmark(
    id: id,
    url: 'https://example.com/$id',
    canonicalUrl: 'https://example.com/$id',
    title: title,
    source: BookmarkSource.website,
    sourceDomain: 'example.com',
    createdAt: time,
    updatedAt: time,
    archived: archived,
  );
}

void main() {
  late FakeFirebaseFirestore db;
  String? uid;
  late FirestoreBookmarkRepository repo;

  setUp(() {
    db = FakeFirebaseFirestore();
    uid = 'alice';
    repo = FirestoreBookmarkRepository(db, () => uid);
  });

  test('stores bookmarks under the signed-in user', () async {
    await repo.create(_bookmark('b1', title: 'Flutter tips'));

    final doc = await db.doc('users/alice/bookmarks/b1').get();
    expect(doc.exists, isTrue);
    expect(doc['title'], 'Flutter tips');
    expect(doc['source'], 'website');
    expect(doc['readingStatus'], 'saved');
    expect(doc['inInbox'], isTrue);
    expect(doc['searchTokens'], containsAll(['f', 'flutter', 'tips']));
  });

  test('round-trips every field', () async {
    final original = Bookmark(
      id: 'b1',
      url: 'https://youtu.be/abc?si=1',
      canonicalUrl: 'https://youtube.com/watch?v=abc',
      title: 'Video',
      description: 'A description',
      imageUrl: 'https://img.example.com/x.png',
      source: BookmarkSource.youtube,
      sourceDomain: 'youtu.be',
      readingStatus: ReadingStatus.reading,
      archived: true,
      inInbox: false,
      createdAt: DateTime.utc(2026, 1, 2, 3, 4, 5),
      updatedAt: DateTime.utc(2026, 2, 3, 4, 5, 6),
    );
    await repo.create(original);

    final loaded = await repo.watch('b1').first;
    expect(loaded!.url, original.url);
    expect(loaded.canonicalUrl, original.canonicalUrl);
    expect(loaded.description, original.description);
    expect(loaded.imageUrl, original.imageUrl);
    expect(loaded.source, BookmarkSource.youtube);
    expect(loaded.readingStatus, ReadingStatus.reading);
    expect(loaded.archived, isTrue);
    expect(loaded.inInbox, isFalse);
    expect(loaded.createdAt.toUtc(), original.createdAt);
    expect(loaded.updatedAt.toUtc(), original.updatedAt);
  });

  test('omits absent optional fields', () {
    final data = bookmarkToFirestore(_bookmark('b1'));
    expect(data.containsKey('description'), isFalse);
    expect(data.containsKey('imageUrl'), isFalse);
  });

  test('lists newest first, filtered by archived, limited', () async {
    for (var i = 0; i < 5; i++) {
      await repo.create(_bookmark('b$i', minute: i));
    }
    await repo.create(_bookmark('old', minute: 59, archived: true));

    final list = await repo.watchList(const BookmarkQuery(), limit: 3).first;
    expect(list.map((b) => b.id), ['b4', 'b3', 'b2']);

    final archived = await repo
        .watchList(const BookmarkQuery(view: BookmarkView.archived), limit: 10)
        .first;
    expect(archived.map((b) => b.id), ['old']);
  });

  test('searches by word prefixes', () async {
    await repo.create(_bookmark('a', title: 'Flutter state management'));
    await repo.create(_bookmark('b', title: 'React state'));
    await repo.create(_bookmark('c', title: 'Cooking rice'));

    Future<List<String>> search(String q) async =>
        (await repo.watchList(BookmarkQuery(search: q), limit: 10).first)
            .map((b) => b.id)
            .toList();

    expect(await search('state'), unorderedEquals(['a', 'b']));
    expect(await search('flut sta'), ['a']);
    expect(await search('ric'), ['c']);
    expect(await search('python'), isEmpty);
  });

  test('finds by canonical URL', () async {
    await repo.create(_bookmark('b1'));
    expect((await repo.findByCanonicalUrl('https://example.com/b1'))?.id, 'b1');
    expect(await repo.findByCanonicalUrl('https://example.com/zz'), isNull);
  });

  test('updates and deletes', () async {
    await repo.create(_bookmark('b1'));
    await repo.update(
      _bookmark('b1').copyWith(readingStatus: ReadingStatus.read),
    );
    expect((await repo.watch('b1').first)!.readingStatus, ReadingStatus.read);

    await repo.delete('b1');
    expect(await repo.watch('b1').first, isNull);
  });

  test('never touches another user\'s data', () async {
    await repo.create(_bookmark('mine'));
    uid = 'bob';
    expect(
      await repo.watchList(const BookmarkQuery(), limit: 10).first,
      isEmpty,
    );
    expect(await repo.findByCanonicalUrl('https://example.com/mine'), isNull);
  });

  test('requires a signed-in user', () {
    uid = null;
    expect(() => repo.newId(), throwsStateError);
  });

  group('concurrent changes', () {
    DocumentReference<Map<String, Object?>> doc(String id) =>
        db.collection('users').doc('alice').collection('bookmarks').doc(id);

    test('modify writes only the changed fields', () async {
      await repo.create(_bookmark('a'));
      // Another device writes a note straight to the server.
      await doc('a').update({'note': 'from phone'});

      await repo.modify('a', (b) => b.copyWith(favorite: true));

      final data = (await doc('a').get()).data()!;
      expect(data['favorite'], isTrue);
      expect(data['note'], 'from phone');
    });

    test('label changes merge with changes from elsewhere', () async {
      await repo.create(_bookmark('a').copyWith(tagIds: ['x']));
      await doc('a').update({
        'tagIds': FieldValue.arrayUnion(['theirs']),
      });

      // This device last saw only "x" and adds "mine".
      await repo.modify('a', (b) => b.copyWith(tagIds: [...b.tagIds, 'mine']));

      expect((await doc('a').get()).data()!['tagIds'], ['x', 'theirs', 'mine']);
    });

    test('modify does nothing for a missing bookmark', () async {
      await repo.modify('missing', (b) => b.copyWith(favorite: true));
      expect((await doc('missing').get()).exists, isFalse);
    });

    test('rewrites stored values that are out of date', () async {
      await repo.create(_bookmark('a', title: 'Biryani recipe'));
      await doc('a').update({'searchTokens': <String>[]});

      await repo.modifyMany(['a'], (b) => b);

      expect(
        (await doc('a').get()).data()!['searchTokens'],
        contains('biryani'),
      );
    });

    test('bulk changes and deletes are batched', () async {
      await repo.createMany([for (var i = 0; i < 20; i++) _bookmark('b$i')]);
      final progress = <int>[];
      await repo.modifyMany(
        [for (var i = 0; i < 20; i++) 'b$i'],
        (b) => b.copyWith(favorite: true),
        onProgress: (done, _) => progress.add(done),
      );
      expect(progress, [20]);
      expect((await repo.fetchAll()).every((b) => b.favorite), isTrue);

      await repo.deleteMany([for (var i = 0; i < 20; i++) 'b$i']);
      expect(await repo.fetchAll(), isEmpty);
    });

    test('reports writes waiting for the backend', () async {
      final states = <bool>[];
      final sub = repo.watchPendingWrites().listen(states.add);
      await Future<void>.delayed(Duration.zero);
      await repo.create(_bookmark('a'));
      await Future<void>.delayed(Duration.zero);
      await sub.cancel();
      expect(states, [false, true, false]);
    });
  });

  test('trashed bookmarks show only in the Trash, newest first', () async {
    await repo.createMany([
      _bookmark('active'),
      _bookmark('archived', archived: true),
      _bookmark('old').copyWith(archived: true, deletedAt: DateTime.utc(2026)),
      _bookmark('new')
          .copyWith(archived: true, deletedAt: DateTime.utc(2026, 10)),
    ]);
    Future<List<String>> ids(BookmarkView view) async => [
      for (final b
          in await repo.watchList(BookmarkQuery(view: view), limit: 10).first)
        b.id,
    ];

    expect(await ids(BookmarkView.all), ['active']);
    expect(await ids(BookmarkView.archived), ['archived']);
    expect(await ids(BookmarkView.trash), ['new', 'old']);
  });
}
