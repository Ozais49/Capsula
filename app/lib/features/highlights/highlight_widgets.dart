import 'package:capsula_core/domain/highlights/highlight.dart';
import 'package:flutter/material.dart';

import '../../app/dependencies.dart';
import '../../app/theme.dart';
import '../common/text_prompt.dart';

/// Background tint for a highlight, readable in light and dark themes.
Color highlightColor(HighlightColor color, Brightness brightness) {
  final dark = brightness == Brightness.dark;
  return switch (color) {
    HighlightColor.yellow =>
      dark ? const Color(0x80B59F00) : const Color(0xFFFFF59D),
    HighlightColor.green =>
      dark ? const Color(0x804C8C4A) : const Color(0xFFC5E1A5),
    HighlightColor.blue =>
      dark ? const Color(0x80466FA0) : const Color(0xFFB3D4FC),
    HighlightColor.pink =>
      dark ? const Color(0x80A04A6F) : const Color(0xFFF8BBD0),
  };
}

/// One highlight: the passage with its color, its note, and actions.
class HighlightCard extends StatelessWidget {
  const HighlightCard({super.key, required this.highlight, this.onOpen});

  final Highlight highlight;

  /// Opens the bookmark it belongs to, when shown outside it.
  final VoidCallback? onOpen;

  Future<void> _editNote(BuildContext context) async {
    final service = AppDependencies.of(context).bookmarks;
    final note = await promptText(
      context,
      title: highlight.note == null ? 'Add note' : 'Edit note',
      label: 'Note',
      initial: highlight.note ?? '',
      maxLength: maxNoteLength,
      maxLines: 6,
    );
    if (note == null) return;
    await service.updateHighlight(highlight, note: note);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final service = AppDependencies.of(context).bookmarks;
    final tint = highlightColor(highlight.color, theme.brightness);

    return Card(
      margin: const EdgeInsets.only(bottom: Gap.sm),
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.xs, Gap.sm),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 4,
                height: 40,
                margin: const EdgeInsets.only(right: Gap.md, top: 2),
                decoration: BoxDecoration(
                  color: tint,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      highlight.text,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        backgroundColor: tint,
                      ),
                    ),
                    if (highlight.note case final note?) ...[
                      const SizedBox(height: Gap.sm),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.sticky_note_2_outlined,
                            size: 16,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: Gap.xs),
                          Expanded(
                            child: Text(note, style: theme.textTheme.bodySmall),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              PopupMenuButton<Object>(
                tooltip: 'Highlight options',
                onSelected: (choice) => switch (choice) {
                  'note' => _editNote(context),
                  'delete' => service.deleteHighlight(highlight),
                  final HighlightColor c => service.updateHighlight(
                    highlight,
                    color: c,
                  ),
                  _ => null,
                },
                itemBuilder: (_) => [
                  PopupMenuItem(
                    value: 'note',
                    child: Text(
                      highlight.note == null ? 'Add note' : 'Edit note',
                    ),
                  ),
                  for (final c in HighlightColor.values)
                    CheckedPopupMenuItem(
                      value: c,
                      checked: highlight.color == c,
                      child: Text(
                        '${c.name[0].toUpperCase()}${c.name.substring(1)}',
                      ),
                    ),
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
