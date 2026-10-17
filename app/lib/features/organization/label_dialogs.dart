import 'package:flutter/material.dart';

import '../../app/dependencies.dart';

import 'package:capsula_core/domain/organization/label.dart';

import '../common/text_prompt.dart';

/// Asks for a label name. Returns null when cancelled.
Future<String?> promptLabelName(
  BuildContext context, {
  required String title,
  String initial = '',
  String action = 'Save',
}) => promptText(
  context,
  title: title,
  label: 'Name',
  initial: initial,
  action: action,
  maxLength: maxLabelNameLength,
);

/// Creates a label; for collections, optionally nested inside [parent].
Future<Label?> createLabelWithPrompt(
  BuildContext context,
  LabelKind kind,
  List<Label> existing, {
  Label? parent,
}) async {
  final service = AppDependencies.of(context).bookmarks;
  final name = await promptLabelName(
    context,
    title: parent == null
        ? 'New ${kind.singular.toLowerCase()}'
        : 'New collection in ${parent.name}',
    action: 'Create',
  );
  if (name == null) return null;
  return service.createLabel(kind, name, existing, parentId: parent?.id);
}

/// Lets the user move a collection to the top level or into another one
/// (never into itself or its own sub-collections).
Future<void> moveCollectionWithPicker(
  BuildContext context,
  Label label,
  List<Label> all,
) async {
  final service = AppDependencies.of(context).bookmarks;
  final messenger = ScaffoldMessenger.of(context);
  final blocked = labelWithDescendants(label.id, all);
  final targets = [
    for (final (l, _) in labelTree(all))
      if (!blocked.contains(l.id)) l,
  ];

  // A record so "top level" (null) differs from cancelling.
  final choice = await showDialog<({String? parentId})>(
    context: context,
    builder: (context) => SimpleDialog(
      title: Text('Move "${label.name}" to'),
      children: [
        SimpleDialogOption(
          onPressed: () => Navigator.pop(context, (parentId: null)),
          child: const Text('Top level'),
        ),
        for (final t in targets)
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, (parentId: t.id)),
            child: Text(labelPath(t, all)),
          ),
      ],
    ),
  );
  if (choice == null) return;
  try {
    await service.moveCollection(label, choice.parentId, all);
  } on Object catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not move: $e')));
  }
}

Future<void> renameLabelWithPrompt(
  BuildContext context,
  Label label,
  List<Label> existing,
) async {
  final service = AppDependencies.of(context).bookmarks;
  final messenger = ScaffoldMessenger.of(context);
  final name = await promptLabelName(
    context,
    title: 'Rename ${label.kind.singular.toLowerCase()}',
    initial: label.name,
  );
  if (name == null) return;
  try {
    final renamed = await service.renameLabel(label, name, existing);
    if (!renamed) {
      messenger.showSnackBar(
        SnackBar(content: Text('"${name.trim()}" is blank or already used.')),
      );
    }
  } on Object catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not rename: $e')));
  }
}

/// Returns true when the label was deleted.
Future<bool> deleteLabelWithConfirm(BuildContext context, Label label) async {
  final service = AppDependencies.of(context).bookmarks;
  final messenger = ScaffoldMessenger.of(context);
  final kind = label.kind.singular.toLowerCase();
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('Delete $kind "${label.name}"?'),
      content: const Text('Bookmarks are kept. They are only removed from it.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(88, 40)),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  if (confirmed != true) return false;
  service.deleteLabel(label).catchError((Object e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not delete: $e')));
  });
  return true;
}
