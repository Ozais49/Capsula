import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/bookmarks/bookmark.dart';
import '../../domain/bookmarks/bookmark_repository.dart';
import '../../domain/bookmarks/bookmark_source.dart';
import '../../domain/bookmarks/bookmark_view.dart';
import '../../domain/organization/label.dart';
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
    final view = query.view;
    var q = _viewQuery(view);
    // Firestore allows one array-contains per query, so label views
    // search on the client instead.
    final token = view is LabelView ? null : primarySearchToken(query.search);
    if (token != null) q = q.where('searchTokens', arrayContains: token);
    q = q.orderBy('createdAt', descending: true).limit(limit);

    final searching = searchWords(query.search).isNotEmpty;
    return q.snapshots().map((snapshot) {
      final bookmarks = snapshot.docs.map(
        (d) => bookmarkFromFirestore(d.id, d.data()),
      );
      return searching
          ? bookmarks
                .where((b) => matchesSearch(b.searchableText, query.search))
                .toList()
          : bookmarks.toList();
    });
  }

  Query<Map<String, Object?>> _viewQuery(BookmarkView view) {
    final active = _collection.where('archived', isEqualTo: false);
    return switch (view) {
      InboxView() => active.where('inInbox', isEqualTo: true),
      AllView() => active,
      ArchivedView() => _collection.where('archived', isEqualTo: true),
      SourceView(:final source) => active.where('source', isEqualTo: source.id),
      LabelView(:final kind, :final labelId) => active.where(
        labelField(kind),
        arrayContains: labelId,
      ),
    };
  }

  @override
  Future<Set<String>> existingCanonicalUrls(
    Iterable<String> canonicalUrls,
  ) async {
    final unique = canonicalUrls.toSet().toList();
    final found = <String>{};
    // whereIn accepts at most 30 values.
    for (var i = 0; i < unique.length; i += 30) {
      final chunk = unique.sublist(i, (i + 30).clamp(0, unique.length));
      final snapshot = await _collection
          .where('canonicalUrl', whereIn: chunk)
          .get();
      for (final doc in snapshot.docs) {
        if (doc.data()['canonicalUrl'] case final String url) found.add(url);
      }
    }
    return found;
  }

  @override
  Future<void> createMany(List<Bookmark> bookmarks) async {
    if (bookmarks.length > 500) {
      throw ArgumentError('At most 500 bookmarks per call');
    }
    final batch = _db.batch();
    for (final b in bookmarks) {
      batch.set(_collection.doc(b.id), bookmarkToFirestore(b));
    }
    await batch.commit();
  }

  @override
  Future<int?> countInbox() async {
    try {
      final snapshot = await _viewQuery(BookmarkView.inbox).count().get();
      return snapshot.count;
    } on Object {
      return null;
    }
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
  'tagIds': b.tagIds,
  'collectionIds': b.collectionIds,
  'importedFrom': ?b.importedFrom,
  if (b.importedAt case final at?) 'importedAt': Timestamp.fromDate(at),
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
    tagIds: _strings(data['tagIds']),
    collectionIds: _strings(data['collectionIds']),
    importedFrom: data['importedFrom'] as String?,
    importedAt: (data['importedAt'] as Timestamp?)?.toDate(),
    createdAt: time('createdAt'),
    updatedAt: time('updatedAt'),
  );
}

List<String> _strings(Object? value) =>
    value is List ? value.whereType<String>().toList() : const [];

/// Bookmark field holding the IDs of labels of [kind].
String labelField(LabelKind kind) => switch (kind) {
  LabelKind.tag => 'tagIds',
  LabelKind.collection => 'collectionIds',
};
