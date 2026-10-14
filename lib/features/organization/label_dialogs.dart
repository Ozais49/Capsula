import 'package:flutter/material.dart';

import '../../app/dependencies.dart';
import '../../domain/organization/label.dart';
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
Future<Label?> createLabelWithPrompt(
  BuildContext context,
  LabelKind kind,
  List<Label> existing,
) async {
  final service = AppDependencies.of(context).bookmarks;
  final name = await promptLabelName(
    context,
    title: 'New ${kind.singular.toLowerCase()}',
    action: 'Create',
  );
  if (name == null) return null;
  return service.createLabel(kind, name, existing);
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
