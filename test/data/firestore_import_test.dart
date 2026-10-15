import 'package:capsula/data/firebase/firestore_bookmark_repository.dart';
import 'package:capsula_core/domain/bookmarks/bookmark.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_source.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

Bookmark _bookmark(int i, {String? importedFrom, DateTime? importedAt}) {
  final t = DateTime.utc(2020, 1, 1);
  return Bookmark(
    id: 'b$i',
    url: 'https://example.com/$i',
    canonicalUrl: 'https://example.com/$i',
    title: 'Item $i',
    source: BookmarkSource.website,
    sourceDomain: 'example.com',
    createdAt: t,
    updatedAt: t,
    importedFrom: importedFrom,
    importedAt: importedAt,
  );
}

void main() {
  late FakeFirebaseFirestore db;
  late FirestoreBookmarkRepository repo;

  setUp(() {
    db = FakeFirebaseFirestore();
    repo = FirestoreBookmarkRepository(db, () => 'alice');
  });

  test('createMany writes every bookmark in one batch', () async {
    await repo.createMany([for (var i = 0; i < 50; i++) _bookmark(i)]);
    final docs = await db.collection('users/alice/bookmarks').get();
    expect(docs.size, 50);
  });

  test('createMany refuses more than 500', () {
    expect(
      () => repo.createMany([for (var i = 0; i < 501; i++) _bookmark(i)]),
      throwsArgumentError,
    );
  });

  test('existingCanonicalUrls checks more than 30 URLs in chunks', () async {
    await repo.createMany([for (var i = 0; i < 40; i++) _bookmark(i)]);

    final candidates = [for (var i = 30; i < 70; i++) 'https://example.com/$i'];
    final found = await repo.existingCanonicalUrls(candidates);
    expect(found, {for (var i = 30; i < 40; i++) 'https://example.com/$i'});
  });

  test('stores and reads provenance', () async {
    final at = DateTime.utc(2026, 10, 14);
    await repo.create(_bookmark(1, importedFrom: 'Raindrop', importedAt: at));
    await repo.create(_bookmark(2));

    final imported = (await repo.watch('b1').first)!;
    expect(imported.importedFrom, 'Raindrop');
    expect(imported.importedAt!.toUtc(), at);

    final saved = (await repo.watch('b2').first)!;
    expect(saved.importedFrom, isNull);
    final raw = (await db.doc('users/alice/bookmarks/b2').get()).data()!;
    expect(raw.containsKey('importedFrom'), isFalse);
    expect(raw.containsKey('importedAt'), isFalse);
  });
}
