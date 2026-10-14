import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/bookmarks/bookmark.dart';
import '../../domain/bookmarks/bookmark_repository.dart';
import '../../domain/bookmarks/bookmark_source.dart';
import '../../domain/bookmarks/search_tokens.dart';

/// Stores bookmarks at `users/{uid}/bookmarks/{id}`. Security rules enforce
/// that only the owner can read or write that path.
class FirestoreBookmarkRepository implements BookmarkRepository {
  FirestoreBookmarkRepository(this._db, this._currentUserId);

  final FirebaseFirestore _db;
  final String? Function() _currentUserId;

  CollectionReference<Map<String, Object?>> get _collection {
    final uid = _currentUserId();
    if (uid == null) throw StateError('No signed-in user');
    return _db.collection('users').doc(uid).collection('bookmarks');
  }

  @override
  String newId() => _collection.doc().id;

  @override
  Future<void> create(Bookmark bookmark) =>
      _collection.doc(bookmark.id).set(bookmarkToFirestore(bookmark));

  @override
  Future<void> update(Bookmark bookmark) =>
      _collection.doc(bookmark.id).set(bookmarkToFirestore(bookmark));

  @override
  Future<void> delete(String id) => _collection.doc(id).delete();

  @override
  Stream<Bookmark?> watch(String id) => _collection
      .doc(id)
      .snapshots()
      .map((s) => s.exists ? bookmarkFromFirestore(s.id, s.data()!) : null);

  @override
  Stream<List<Bookmark>> watchList(BookmarkQuery query, {required int limit}) {
    Query<Map<String, Object?>> q = _collection.where(
      'archived',
      isEqualTo: query.archived,
    );
    final token = primarySearchToken(query.search);
    if (token != null) q = q.where('searchTokens', arrayContains: token);
    q = q.orderBy('createdAt', descending: true).limit(limit);

    return q.snapshots().map((snapshot) {
      final bookmarks = snapshot.docs.map(
        (d) => bookmarkFromFirestore(d.id, d.data()),
      );
      return token == null
          ? bookmarks.toList()
          : bookmarks
                .where((b) => matchesSearch(b.searchableText, query.search))
                .toList();
    });
  }

  @override
  Future<Bookmark?> findByCanonicalUrl(String canonicalUrl) async {
    final q = _collection
        .where('canonicalUrl', isEqualTo: canonicalUrl)
        .limit(1);
    // Prefer the server, but don't keep a save waiting when offline.
    final snapshot = await q.get().timeout(
      const Duration(seconds: 3),
      onTimeout: () => q.get(const GetOptions(source: Source.cache)),
    );
    if (snapshot.docs.isEmpty) return null;
    final doc = snapshot.docs.first;
    return bookmarkFromFirestore(doc.id, doc.data());
  }
}

Map<String, Object?> bookmarkToFirestore(Bookmark b) => {
  'url': b.url,
  'canonicalUrl': b.canonicalUrl,
  'title': b.title,
  'description': ?b.description,
  'imageUrl': ?b.imageUrl,
  'source': b.source.id,
  'sourceDomain': b.sourceDomain,
  'readingStatus': b.readingStatus.name,
  'archived': b.archived,
  'inInbox': b.inInbox,
  'createdAt': Timestamp.fromDate(b.createdAt),
  'updatedAt': Timestamp.fromDate(b.updatedAt),
  'searchTokens': buildSearchTokens(b.searchableText),
};

Bookmark bookmarkFromFirestore(String id, Map<String, Object?> data) {
  DateTime time(String field) =>
      (data[field] as Timestamp?)?.toDate() ??
      DateTime.fromMillisecondsSinceEpoch(0);

  return Bookmark(
    id: id,
    url: data['url'] as String? ?? '',
    canonicalUrl: data['canonicalUrl'] as String? ?? '',
    title: data['title'] as String? ?? '',
    description: data['description'] as String?,
    imageUrl: data['imageUrl'] as String?,
    source: BookmarkSource.fromId(data['source'] as String?),
    sourceDomain: data['sourceDomain'] as String? ?? '',
    readingStatus: ReadingStatus.fromName(data['readingStatus'] as String?),
    archived: data['archived'] as bool? ?? false,
    inInbox: data['inInbox'] as bool? ?? false,
    createdAt: time('createdAt'),
    updatedAt: time('updatedAt'),
  );
}
