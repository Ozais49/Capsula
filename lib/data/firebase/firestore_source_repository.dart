import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:capsula_core/domain/sources/custom_source.dart';

/// Stores the user's own sources at `users/{uid}/sources`.
class FirestoreSourceRepository implements SourceRepository {
  FirestoreSourceRepository(this._db, this._currentUserId);

  final FirebaseFirestore _db;
  final String? Function() _currentUserId;

  CollectionReference<Map<String, Object?>> get _collection {
    final uid = _currentUserId();
    if (uid == null) throw StateError('No signed-in user');
    return _db.collection('users').doc(uid).collection('sources');
  }

  @override
  String newId() => _collection.doc().id;

  @override
  Stream<List<CustomSource>> watch() => _collection.snapshots().map(
    (s) => sortSources(s.docs.map((d) => decodeSource(d.id, d.data()))),
  );

  @override
  Future<void> create(CustomSource source) => _collection.doc(source.id).set({
    ...encodeSource(source),
    'createdAt': Timestamp.now(),
  });

  @override
  Future<void> update(CustomSource source) =>
      _collection.doc(source.id).update(encodeSource(source));

  @override
  Future<void> delete(String id) => _collection.doc(id).delete();
}
