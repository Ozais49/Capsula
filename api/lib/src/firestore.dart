import 'package:capsula_core/domain/bookmarks/bookmark.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_codec.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_repository.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_view.dart';
import 'package:capsula_core/domain/bookmarks/search_tokens.dart';
import 'package:capsula_core/domain/organization/label.dart';
import 'package:dart_firebase_admin/auth.dart';
import 'package:dart_firebase_admin/firestore.dart';

import 'auth.dart';

DateTime? _readTime(Object? value) => switch (value) {
  Timestamp(:final seconds, :final nanoseconds) =>
    DateTime.fromMicrosecondsSinceEpoch(
      seconds * 1000000 + nanoseconds ~/ 1000,
      isUtc: true,
    ),
  DateTime() => value,
  _ => null,
};

Object _writeTime(DateTime date) => Timestamp.fromDate(date);

/// Bookmarks of one user, through the admin SDK. Admin access bypasses
/// security rules, so every query is built under `users/{uid}`.
class AdminBookmarkRepository implements BookmarkRepository {
  AdminBookmarkRepository(this._db, this._uid);

  final Firestore _db;
  final String _uid;

  CollectionReference<DocumentData> get _col =>
      _db.collection('users').doc(_uid).collection('bookmarks');

  Bookmark _decode(DocumentSnapshot<DocumentData> d) =>
      decodeBookmark(d.id, d.data()!, _readTime);

  @override
  String newId() => _col.doc().id;

  @override
  Future<void> create(Bookmark b) =>
      _col.doc(b.id).set(encodeBookmark(b, _writeTime));

  @override
  Future<void> update(Bookmark b) =>
      _col.doc(b.id).set(encodeBookmark(b, _writeTime));

  @override
  Future<void> delete(String id) => _col.doc(id).delete();

  @override
  Stream<Bookmark?> watch(String id) => Stream.fromFuture(
    _col.doc(id).get().then((d) => d.exists ? _decode(d) : null),
  );

  @override
  Stream<List<Bookmark>> watchList(BookmarkQuery query, {required int limit}) {
    final view = query.view;
    final active = _col.where('archived', WhereFilter.equal, false);
    var q = switch (view) {
      InboxView() => active.where('inInbox', WhereFilter.equal, true),
      AllView() => active,
      FavoritesView() => active.where('favorite', WhereFilter.equal, true),
      ArchivedView() => _col.where('archived', WhereFilter.equal, true),
      SourceView(:final source) => active.where(
        'source',
        WhereFilter.equal,
        source.id,
      ),
      LabelView(:final kind, :final labelId) => active.where(
        labelField(kind),
        WhereFilter.arrayContains,
        labelId,
      ),
    };
    final token = view is LabelView ? null : primarySearchToken(query.search);
    if (token != null) {
      q = q.where('searchTokens', WhereFilter.arrayContains, token);
    }
    final searching = searchWords(query.search).isNotEmpty;
    return Stream.fromFuture(
      q
          .orderBy('createdAt', descending: query.sort == BookmarkSort.newest)
          .limit(limit)
          .get()
          .then((s) {
            final list = s.docs.map(_decode);
            return searching
                ? list
                      .where(
                        (b) => matchesSearch(b.searchableText, query.search),
                      )
                      .toList()
                : list.toList();
          }),
    );
  }

  @override
  Future<Bookmark?> findByCanonicalUrl(String canonicalUrl) async {
    final s = await _col
        .where('canonicalUrl', WhereFilter.equal, canonicalUrl)
        .limit(1)
        .get();
    return s.docs.isEmpty ? null : _decode(s.docs.first);
  }

  @override
  Future<Set<String>> existingCanonicalUrls(
    Iterable<String> canonicalUrls,
  ) async {
    final unique = canonicalUrls.toSet().toList();
    final found = <String>{};
    for (var i = 0; i < unique.length; i += 30) {
      final chunk = unique.sublist(i, (i + 30).clamp(0, unique.length));
      final s = await _col.where('canonicalUrl', WhereFilter.isIn, chunk).get();
      for (final d in s.docs) {
        if (d.data()['canonicalUrl'] case final String url) found.add(url);
      }
    }
    return found;
  }

  @override
  Future<void> createMany(List<Bookmark> bookmarks) async {
    if (bookmarks.length > 500) {
      throw ArgumentError('At most 500 bookmarks per call');
    }
    // The admin SDK has no public write batch yet; a transaction gives the
    // same all-or-nothing write.
    await _db.runTransaction((tx) async {
      for (final b in bookmarks) {
        tx.set(_col.doc(b.id), encodeBookmark(b, _writeTime));
      }
    });
  }

  @override
  Future<List<Bookmark>> fetchAll() async {
    final all = <Bookmark>[];
    QueryDocumentSnapshot<DocumentData>? last;
    while (true) {
      var q = _col.orderBy('createdAt', descending: true);
      if (last != null) q = q.startAfterDocument(last);
      final page = await q.limit(500).get();
      all.addAll(page.docs.map(_decode));
      if (page.docs.length < 500) return all;
      last = page.docs.last;
    }
  }

  @override
  Future<int?> countInbox() async => null;
}

/// Tags and collections of one user, through the admin SDK.
class AdminLabelRepository implements LabelRepository {
  AdminLabelRepository(this._db, this._uid);

  final Firestore _db;
  final String _uid;

  DocumentReference<DocumentData> get _user =>
      _db.collection('users').doc(_uid);

  CollectionReference<DocumentData> _labels(LabelKind kind) =>
      _user.collection(labelCollection(kind));

  @override
  String newId(LabelKind kind) => _labels(kind).doc().id;

  @override
  Stream<List<Label>> watch(LabelKind kind) => Stream.fromFuture(
    _labels(kind).get().then(
      (s) => sortLabels(
        s.docs.map(
          (d) => Label(
            id: d.id,
            kind: kind,
            name: d.data()['name'] as String? ?? '',
            parentId: d.data()['parentId'] as String?,
          ),
        ),
      ),
    ),
  );

  @override
  Future<void> create(Label label) => _labels(label.kind).doc(label.id).set({
    'name': label.name,
    'parentId': ?label.parentId,
    'createdAt': _writeTime(DateTime.now()),
  });

  @override
  Future<void> setParent(Label label, String? parentId) =>
      _labels(label.kind).doc(label.id).update({
        FieldPath(const ['parentId']): parentId ?? FieldValue.delete,
      });

  @override
  Future<void> rename(Label label, String name) =>
      _labels(label.kind).doc(label.id).update({
        FieldPath(const ['name']): name,
      });

  @override
  Future<void> delete(Label label) async {
    final field = labelField(label.kind);
    final tagged = await _user
        .collection('bookmarks')
        .where(field, WhereFilter.arrayContains, label.id)
        .get();
    final docs = tagged.docs;
    for (var start = 0; start < docs.length; start += 450) {
      final chunk = docs.skip(start).take(450).toList();
      await _db.runTransaction((tx) async {
        for (final doc in chunk) {
          tx.update(doc.ref, {
            FieldPath([field]): FieldValue.arrayRemove([label.id]),
            FieldPath(const ['updatedAt']): _writeTime(DateTime.now()),
          });
        }
      });
    }
    // Nested collections move up to the deleted one's parent.
    final children = await _labels(label.kind)
        .where('parentId', WhereFilter.equal, label.id)
        .get();
    for (final child in children.docs) {
      await child.ref.update({
        FieldPath(const ['parentId']): label.parentId ?? FieldValue.delete,
      });
    }
    await _labels(label.kind).doc(label.id).delete();
  }
}

/// API tokens at `apiTokens/{sha256}`. Security rules deny all client
/// access; only the server reads them.
class FirestoreTokenStore implements TokenStore {
  FirestoreTokenStore(this._db);

  final Firestore _db;

  CollectionReference<DocumentData> get _col => _db.collection('apiTokens');

  ApiToken _decode(String id, DocumentData d) => ApiToken(
    id: id,
    uid: d['uid'] as String,
    name: d['name'] as String? ?? '',
    createdAt: _readTime(d['createdAt']) ?? DateTime.now(),
    lastUsedAt: _readTime(d['lastUsedAt']),
  );

  @override
  Future<void> save(ApiToken token) => _col.doc(token.id).set({
    'uid': token.uid,
    'name': token.name,
    'createdAt': _writeTime(token.createdAt),
  });

  @override
  Future<ApiToken?> find(String id) async {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(id)) return null;
    final d = await _col.doc(id).get();
    return d.exists ? _decode(d.id, d.data()!) : null;
  }

  @override
  Future<List<ApiToken>> forUser(String uid) async {
    final s = await _col.where('uid', WhereFilter.equal, uid).get();
    return s.docs.map((d) => _decode(d.id, d.data())).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  @override
  Future<void> delete(String id) => _col.doc(id).delete();

  @override
  Future<void> touch(String id, DateTime when) => _col.doc(id).update({
    FieldPath(const ['lastUsedAt']): _writeTime(when),
  });
}

class FirebaseIdTokenVerifier implements IdTokenVerifier {
  FirebaseIdTokenVerifier(this._auth);

  final Auth _auth;

  @override
  Future<String?> verify(String idToken) async {
    try {
      return (await _auth.verifyIdToken(idToken)).uid;
    } on Object {
      return null;
    }
  }
}
