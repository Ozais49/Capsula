import 'package:capsula_core/domain/bookmarks/bookmark_codec.dart';
import 'package:capsula_core/domain/highlights/highlight.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Highlights at `users/{uid}/highlights/{id}`.
class FirestoreHighlightRepository implements HighlightRepository {
  FirestoreHighlightRepository(this._db, this._currentUserId);

  final FirebaseFirestore _db;
  final String? Function() _currentUserId;

  CollectionReference<Map<String, Object?>> get _col {
    final uid = _currentUserId();
    if (uid == null) throw StateError('No signed-in user');
    return _db.collection('users').doc(uid).collection('highlights');
  }

  Highlight _decode(DocumentSnapshot<Map<String, Object?>> d) =>
      decodeHighlight(d.id, d.data()!, (v) => (v as Timestamp?)?.toDate());

  @override
  String newId() => _col.doc().id;

  @override
  Stream<List<Highlight>> watchForBookmark(String bookmarkId) => _col
      .where('bookmarkId', isEqualTo: bookmarkId)
      .orderBy('createdAt')
      .snapshots()
      .map((s) => s.docs.map(_decode).toList());

  @override
  Stream<List<Highlight>> watchAll({required int limit}) => _col
      .orderBy('createdAt', descending: true)
      .limit(limit)
      .snapshots()
      .map((s) => s.docs.map(_decode).toList());

  @override
  Future<void> save(Highlight h) =>
      _col.doc(h.id).set(encodeHighlight(h, Timestamp.fromDate));

  @override
  Future<void> delete(String id) => _col.doc(id).delete();

  @override
  Future<void> deleteForBookmark(String bookmarkId) async {
    final s = await _col.where('bookmarkId', isEqualTo: bookmarkId).get();
    for (final d in s.docs) {
      await d.reference.delete();
    }
  }
}
