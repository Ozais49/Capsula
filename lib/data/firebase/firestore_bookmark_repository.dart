import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:capsula_core/domain/bookmarks/bookmark.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_codec.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_patch.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_repository.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_view.dart';
import 'package:capsula_core/domain/bookmarks/search_tokens.dart';

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

  // Writes this device has sent that the backend hasn't accepted yet.
  int _pending = 0;
  final _pendingChanges = StreamController<bool>.broadcast();

  Future<void> _track(Future<void> write) {
    if (_pending++ == 0) _pendingChanges.add(true);
    return write.whenComplete(() {
      if (--_pending == 0) _pendingChanges.add(false);
    });
  }

  @override
  Stream<bool> watchPendingWrites() async* {
    yield _pending > 0;
    yield* _pendingChanges.stream;
  }

  @override
  Future<void> create(Bookmark bookmark) async {
    final doc = _collection.doc(bookmark.id);
    try {
      await _track(doc.set(bookmarkToFirestore(bookmark)));
    } on FirebaseException catch (e) {
      // IDs come from the link, so another device may have saved the same
      // link first; the rules then refuse this copy. That's the same
      // bookmark, already saved.
      if (e.code == 'permission-denied') {
        final existing = await doc.get();
        if (existing.data()?['canonicalUrl'] == bookmark.canonicalUrl) return;
      }
      rethrow;
    }
  }

  @override
  Future<void> update(Bookmark bookmark) =>
      _track(_collection.doc(bookmark.id).set(bookmarkToFirestore(bookmark)));

  @override
  Future<void> modify(
    String id,
    Bookmark Function(Bookmark current) change,
  ) async {
    final doc = _collection.doc(id);
    final fields = await _patch(await _latest(doc), change);
    if (fields != null) await _track(doc.update(fields));
  }

  @override
  Future<void> modifyMany(
    Iterable<String> ids,
    Bookmark Function(Bookmark current) change, {
    void Function(int done, int total)? onProgress,
  }) async {
    final all = ids.toList();
    for (var i = 0; i < all.length; i += writeBatchSize) {
      final chunk = all.skip(i).take(writeBatchSize).toList();
      final docs = chunk.map(_collection.doc).toList();
      final latest = await Future.wait(docs.map(_latest));
      final batch = _db.batch();
      var writes = 0;
      for (var j = 0; j < docs.length; j++) {
        final fields = await _patch(latest[j], change);
        if (fields == null) continue;
        batch.update(docs[j], fields);
        writes++;
      }
      if (writes > 0) await _track(batch.commit());
      onProgress?.call(i + chunk.length, all.length);
    }
  }

  /// The stored copy, from this device's cache when it has one (so this
  /// works offline), otherwise from the server.
  Future<DocumentSnapshot<Map<String, Object?>>> _latest(
    DocumentReference<Map<String, Object?>> doc,
  ) async {
    try {
      return await doc.get(const GetOptions(source: Source.cache));
    } on FirebaseException {
      return doc.get();
    }
  }

  /// The fields [change] alters in [snapshot], as an update. Compared with
  /// the stored fields, so stored values that are out of date (search
  /// words, type) are rewritten too. Null when nothing changes.
  Future<Map<String, Object?>?> _patch(
    DocumentSnapshot<Map<String, Object?>> snapshot,
    Bookmark Function(Bookmark current) change,
  ) async {
    final data = snapshot.data();
    if (data == null) return null;
    final current = bookmarkFromFirestore(snapshot.id, data);
    final patch = BookmarkPatch.fromDocuments(
      data.map((k, v) => MapEntry(k, v is Timestamp ? v.toDate() : v)),
      encodeBookmark(change(current), (d) => d),
    );
    if (patch.isEmpty) return null;
    Object? toStore(Object? v) => v is DateTime ? Timestamp.fromDate(v) : v;
    return {
      for (final MapEntry(:key, :value) in patch.set.entries)
        key: toStore(value),
      for (final key in patch.removed) key: FieldValue.delete(),
      for (final MapEntry(:key, :value) in patch.added.entries)
        key: FieldValue.arrayUnion(value),
      for (final MapEntry(:key, :value) in patch.pulled.entries)
        key: FieldValue.arrayRemove(value),
    };
  }

  @override
  Future<void> delete(String id) => _track(_collection.doc(id).delete());

  @override
  Future<void> deleteMany(Iterable<String> ids) async {
    final all = ids.toList();
    for (var i = 0; i < all.length; i += writeBatchSize) {
      final batch = _db.batch();
      for (final id in all.skip(i).take(writeBatchSize)) {
        batch.delete(_collection.doc(id));
      }
      await _track(batch.commit());
    }
  }

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
    // Label and reminder views search on the device, avoiding extra indexes.
    final token = view is LabelView || view is RemindersView
        ? null
        : primarySearchToken(query.search);
    if (token != null) q = q.where('searchTokens', arrayContains: token);
    q = view is RemindersView
        ? q.orderBy('remindAt').limit(limit)
        : q
              .orderBy(
                'createdAt',
                descending: query.sort == BookmarkSort.newest,
              )
              .limit(limit);

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
      FavoritesView() => active.where('favorite', isEqualTo: true),
      RemindersView() => active,
      ArchivedView() => _collection.where('archived', isEqualTo: true),
      SourceView(:final source) => active.where('source', isEqualTo: source.id),
      TypeView(:final type) => active.where('type', isEqualTo: type.name),
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
    await _track(batch.commit());
  }

  @override
  Future<List<Bookmark>> fetchAll() async {
    final all = <Bookmark>[];
    DocumentSnapshot<Map<String, Object?>>? last;
    while (true) {
      var q = _collection.orderBy('createdAt', descending: true);
      if (last != null) q = q.startAfterDocument(last);
      final page = await q.limit(500).get();
      all.addAll(page.docs.map((d) => bookmarkFromFirestore(d.id, d.data())));
      if (page.docs.length < 500) return all;
      last = page.docs.last;
    }
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

Map<String, Object?> bookmarkToFirestore(Bookmark b) =>
    encodeBookmark(b, Timestamp.fromDate);

Bookmark bookmarkFromFirestore(String id, Map<String, Object?> data) =>
    decodeBookmark(id, data, (v) => (v as Timestamp?)?.toDate());
