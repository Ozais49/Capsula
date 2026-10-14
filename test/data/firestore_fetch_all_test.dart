import 'package:capsula/data/firebase/firestore_bookmark_repository.dart';
import 'package:capsula/domain/bookmarks/bookmark.dart';
import 'package:capsula/domain/bookmarks/bookmark_source.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fetchAll pages past 500 bookmarks, newest first', () async {
    final db = FakeFirebaseFirestore();
    final repo = FirestoreBookmarkRepository(db, () => 'alice');
    final base = DateTime.utc(2020);

    for (var start = 0; start < 1200; start += 500) {
      await repo.createMany([
        for (var i = start; i < (start + 500).clamp(0, 1200); i++)
          Bookmark(
            id: 'b$i',
            url: 'https://example.com/$i',
            canonicalUrl: 'https://example.com/$i',
            title: '$i',
            source: BookmarkSource.website,
            sourceDomain: 'example.com',
            createdAt: base.add(Duration(minutes: i)),
            updatedAt: base,
          ),
      ]);
    }

    final all = await repo.fetchAll();
    expect(all, hasLength(1200));
    expect(all.first.id, 'b1199');
    expect(all.last.id, 'b0');
    expect(all.map((b) => b.id).toSet(), hasLength(1200));
  });
}
