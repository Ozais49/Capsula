import 'package:flutter/material.dart';

/// Asks for one line of text. Returns null when cancelled.
Future<String?> promptText(
  BuildContext context, {
  required String title,
  required String label,
  String initial = '',
  String action = 'Save',
  int? maxLength,
  int maxLines = 1,
}) => showDialog<String>(
  context: context,
  builder: (_) => _TextPromptDialog(
    title: title,
    label: label,
    initial: initial,
    action: action,
    maxLength: maxLength,
    maxLines: maxLines,
  ),
);

/// Owns its text controller so it outlives the dialog's closing animation.
class _TextPromptDialog extends StatefulWidget {
  const _TextPromptDialog({
    required this.title,
    required this.label,
    required this.initial,
    required this.action,
    required this.maxLength,
    required this.maxLines,
  });

  final String title;
  final String label;
  final String initial;
  final String action;
  final int? maxLength;
  final int maxLines;

  @override
  State<_TextPromptDialog> createState() => _TextPromptDialogState();
}

class _TextPromptDialogState extends State<_TextPromptDialog> {
  late final _controller = TextEditingController(text: widget.initial);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.title),
    content: TextField(
      controller: _controller,
      autofocus: true,
      maxLength: widget.maxLength,
      minLines: widget.maxLines > 1 ? 3 : 1,
      maxLines: widget.maxLines,
      keyboardType: widget.maxLines > 1 ? TextInputType.multiline : null,
      decoration: InputDecoration(labelText: widget.label),
      // Multi-line fields use Enter for new lines.
      onSubmitted: widget.maxLines > 1
          ? null
          : (value) => Navigator.pop(context, value),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size(88, 40)),
        onPressed: () => Navigator.pop(context, _controller.text),
        child: Text(widget.action),
      ),
    ],
  );
}
