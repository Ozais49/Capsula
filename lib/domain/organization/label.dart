/// User-defined ways to organize bookmarks. Both are many-to-many and
/// independent of a bookmark's source.
enum LabelKind {
  tag('Tag', 'Tags'),
  collection('Collection', 'Collections');

  const LabelKind(this.singular, this.plural);

  final String singular;
  final String plural;
}

class Label {
  const Label({required this.id, required this.kind, required this.name});

  final String id;
  final LabelKind kind;
  final String name;

  Label rename(String newName) => Label(id: id, kind: kind, name: newName);

  @override
  bool operator ==(Object other) =>
      other is Label &&
      other.id == id &&
      other.kind == kind &&
      other.name == name;

  @override
  int get hashCode => Object.hash(id, kind, name);
}

const maxLabelNameLength = 50;

/// Trims and collapses whitespace. Returns null when nothing is left.
String? normalizeLabelName(String input) {
  final name = input.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (name.isEmpty) return null;
  return name.length > maxLabelNameLength
      ? name.substring(0, maxLabelNameLength).trimRight()
      : name;
}

/// Labels sorted by name, ignoring case.
List<Label> sortLabels(Iterable<Label> labels) =>
    labels.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

abstract interface class LabelRepository {
  String newId(LabelKind kind);

  /// Sorted by name.
  Stream<List<Label>> watch(LabelKind kind);

  Future<void> create(Label label);

  Future<void> rename(Label label, String name);

  /// Deletes the label and removes it from every bookmark.
  Future<void> delete(Label label);
}
