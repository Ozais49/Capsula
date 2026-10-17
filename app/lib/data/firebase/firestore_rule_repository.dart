import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:capsula_core/domain/meta/library_meta.dart';
import 'package:capsula_core/domain/rules/rule.dart';

/// Stores the user's rules at `users/{uid}/rules`.
class FirestoreRuleRepository implements RuleRepository {
  FirestoreRuleRepository(this._db, this._currentUserId);

  final FirebaseFirestore _db;
  final String? Function() _currentUserId;

  CollectionReference<Map<String, Object?>> get _collection {
    final uid = _currentUserId();
    if (uid == null) throw StateError('No signed-in user');
    return _db.collection('users').doc(uid).collection('rules');
  }

  @override
  String newId() => _collection.doc().id;

  @override
  Stream<List<Rule>> watch() => _collection.snapshots().map(
    (s) => sortRules(s.docs.map((d) => Rule.fromJson(d.id, d.data()))),
  );

  @override
  Future<void> create(Rule rule) => _collection.doc(rule.id).set({
    ...rule.toJson(),
    'createdAt': Timestamp.now(),
  });

  @override
  Future<void> update(Rule rule) => _collection.doc(rule.id).update({
    ...rule.toJson(),
    // Optional fields the rule no longer has.
    if (rule.collectionId == null) 'collectionId': FieldValue.delete(),
    if (!rule.favorite) 'favorite': FieldValue.delete(),
  });

  @override
  Future<void> delete(String id) => _collection.doc(id).delete();
}

/// Keeps the library's schema version at `users/{uid}/meta/schema`.
class FirestoreLibraryMeta implements LibraryMetaRepository {
  FirestoreLibraryMeta(this._db, this._currentUserId);

  final FirebaseFirestore _db;
  final String? Function() _currentUserId;

  DocumentReference<Map<String, Object?>> get _doc {
    final uid = _currentUserId();
    if (uid == null) throw StateError('No signed-in user');
    return _db.collection('users').doc(uid).collection('meta').doc('schema');
  }

  @override
  Future<int> schemaVersion() async =>
      (await _doc.get()).data()?['version'] as int? ?? 1;

  @override
  Future<void> setSchemaVersion(int version) =>
      _doc.set({'version': version, 'updatedAt': Timestamp.now()});
}
