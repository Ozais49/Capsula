import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:capsula_core/domain/organization/label.dart';

import 'package:capsula_core/domain/bookmarks/bookmark_codec.dart';

/// Stores tags at `users/{uid}/tags` and collections at
/// `users/{uid}/collections`.
class FirestoreLabelRepository implements LabelRepository {
  FirestoreLabelRepository(this._db, this._currentUserId);

  final FirebaseFirestore _db;
  final String? Function() _currentUserId;

  DocumentReference<Map<String, Object?>> get _user {
    final uid = _currentUserId();
    if (uid == null) throw StateError('No signed-in user');
    return _db.collection('users').doc(uid);
  }

  CollectionReference<Map<String, Object?>> _labels(LabelKind kind) =>
      _user.collection(switch (kind) {
        LabelKind.tag => 'tags',
        LabelKind.collection => 'collections',
      });

  @override
  String newId(LabelKind kind) => _labels(kind).doc().id;

  @override
  Stream<List<Label>> watch(LabelKind kind) => _labels(kind).snapshots().map(
    (s) => sortLabels(
      s.docs.map(
        (d) => Label(
          id: d.id,
          kind: kind,
          name: d.data()['name'] as String? ?? '',
        ),
      ),
    ),
  );

  @override
  Future<void> create(Label label) =>
      _labels(label.kind)
          .doc(label.id)
          .set({'name': label.name, 'createdAt': Timestamp.now()});

  @override
  Future<void> rename(Label label, String name) =>
      _labels(label.kind).doc(label.id).update({'name': name});

  @override
  Future<void> delete(Label label) async {
    final field = labelField(label.kind);
    final tagged = await _user
        .collection('bookmarks')
        .where(field, arrayContains: label.id)
        .get();

    // Batches hold at most 500 writes.
    final docs = tagged.docs;
    for (var start = 0; start < docs.length; start += 450) {
      final batch = _db.batch();
      for (final doc in docs.skip(start).take(450)) {
        batch.update(doc.reference, {
          field: FieldValue.arrayRemove([label.id]),
          'updatedAt': Timestamp.now(),
        });
      }
      await batch.commit();
    }
    await _labels(label.kind).doc(label.id).delete();
  }
}
