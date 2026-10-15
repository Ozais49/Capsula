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
  const Label({
    required this.id,
    required this.kind,
    required this.name,
    this.parentId,
    this.shareId,
  });

  final String id;
  final LabelKind kind;
  final String name;

  /// The parent collection, for nested collections. Always null for tags.
  final String? parentId;

  /// Set when the collection has a public read-only link. Only the API
  /// server assigns it.
  final String? shareId;

  Label rename(String newName) => Label(
    id: id,
    kind: kind,
    name: newName,
    parentId: parentId,
    shareId: shareId,
  );

  Label moveTo(String? newParentId) => Label(
    id: id,
    kind: kind,
    name: name,
    parentId: newParentId,
    shareId: shareId,
  );

  Label withShare(String? newShareId) => Label(
    id: id,
    kind: kind,
    name: name,
    parentId: parentId,
    shareId: newShareId,
  );

  @override
  bool operator ==(Object other) =>
      other is Label &&
      other.id == id &&
      other.kind == kind &&
      other.name == name &&
      other.parentId == parentId &&
      other.shareId == shareId;

  @override
  int get hashCode => Object.hash(id, kind, name, parentId, shareId);
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

/// Collections in tree order (each parent followed by its children, by
/// name) with their depth. Collections whose parent is missing are shown at
/// the top level, so nothing is ever hidden.
List<(Label, int)> labelTree(List<Label> labels) {
  final ids = {for (final l in labels) l.id};
  final children = <String?, List<Label>>{};
  for (final l in labels) {
    final parent = ids.contains(l.parentId) ? l.parentId : null;
    children.putIfAbsent(parent, () => []).add(l);
  }
  final result = <(Label, int)>[];
  final visited = <String>{};
  void visit(String? parent, int depth) {
    for (final l in sortLabels(children[parent] ?? const [])) {
      if (!visited.add(l.id)) continue; // Guards against cycles.
      result.add((l, depth));
      visit(l.id, depth + 1);
    }
  }

  visit(null, 0);
  // Anything only reachable through a cycle.
  for (final l in sortLabels(labels)) {
    if (visited.add(l.id)) result.add((l, 0));
  }
  return result;
}

/// IDs of [id] and every collection nested under it.
Set<String> labelWithDescendants(String id, List<Label> labels) {
  final result = {id};
  var added = true;
  while (added) {
    added = false;
    for (final l in labels) {
      if (l.parentId != null &&
          result.contains(l.parentId) &&
          result.add(l.id)) {
        added = true;
      }
    }
  }
  return result;
}

/// "Parent / Child" path of a collection.
String labelPath(Label label, List<Label> labels) {
  final byId = {for (final l in labels) l.id: l};
  final names = <String>[label.name];
  final seen = {label.id};
  var parent = byId[label.parentId];
  while (parent != null && seen.add(parent.id)) {
    names.insert(0, parent.name);
    parent = byId[parent.parentId];
  }
  return names.join(' / ');
}

abstract interface class LabelRepository {
  String newId(LabelKind kind);

  /// Sorted by name.
  Stream<List<Label>> watch(LabelKind kind);

  Future<void> create(Label label);

  Future<void> rename(Label label, String name);

  /// Moves a collection under [parentId], or to the top level when null.
  Future<void> setParent(Label label, String? parentId);

  /// Deletes the label and removes it from every bookmark. Collections
  /// nested in it move up to its parent.
  Future<void> delete(Label label);
}
