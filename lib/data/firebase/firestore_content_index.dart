import 'package:capsula_core/domain/search/full_text.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

/// Page words at `users/{uid}/contents/{bookmarkId}`.
class FirestoreContentIndex implements ContentIndex {
  FirestoreContentIndex(this._db, this._currentUserId);

  final FirebaseFirestore _db;
  final String? Function() _currentUserId;

  CollectionReference<Map<String, Object?>> get _col {
    final uid = _currentUserId();
    if (uid == null) throw StateError('No signed-in user');
    return _db.collection('users').doc(uid).collection('contents');
  }

  @override
  Future<void> save(String bookmarkId, List<String> words) =>
      _col.doc(bookmarkId).set({'words': words, 'updatedAt': Timestamp.now()});

  @override
  Future<List<String>> search(String query, {int limit = 50}) async {
    final word = fullTextLookupWord(query);
    if (word == null) return const [];
    final s = await _col
        .where('words', arrayContains: word)
        .limit(limit * 2)
        .get();
    return [
      for (final d in s.docs)
        if (fullTextMatches(
          (d.data()['words'] as List? ?? const []).whereType<String>(),
          query,
        ))
          d.id,
    ].take(limit).toList();
  }

  @override
  Future<void> delete(String bookmarkId) => _col.doc(bookmarkId).delete();
}
