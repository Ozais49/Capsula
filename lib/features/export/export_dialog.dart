import 'dart:convert';

import 'package:flutter/material.dart';

import '../../app/dependencies.dart';
import '../../app/theme.dart';

import 'package:capsula_core/domain/export/library_export.dart';
import 'package:capsula_core/domain/organization/label.dart';

Future<void> showExportDialog(BuildContext context) =>
    showDialog<void>(context: context, builder: (_) => const _ExportDialog());

class _ExportDialog extends StatefulWidget {
  const _ExportDialog();

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  ExportFormat _format = ExportFormat.json;
  bool _working = false;
  String? _error;

  Future<void> _export() async {
    final deps = AppDependencies.of(context);
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _working = true;
      _error = null;
    });
    try {
      final bookmarks = await deps.bookmarks.repository.fetchAll();
      final labels = [
        ...await deps.bookmarks.labels.watch(LabelKind.tag).first,
        ...await deps.bookmarks.labels.watch(LabelKind.collection).first,
      ];
      final now = DateTime.now();
      final text = exportLibrary(_format, bookmarks, labels, now: now);
      final saved = await deps.fileSaver.save(
        exportFileName(_format, now),
        _format.mimeType,
        utf8.encode(text),
      );
      if (!saved) {
        if (mounted) setState(() => _working = false);
        return;
      }
      navigator.pop();
      messenger.showSnackBar(
        SnackBar(content: Text('Exported ${bookmarks.length} bookmarks')),
      );
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _working = false;
          _error = 'Export failed: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Export library'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RadioGroup<ExportFormat>(
            groupValue: _format,
            onChanged: (f) {
              if (!_working && f != null) setState(() => _format = f);
            },
            child: Column(
              children: [
                for (final format in ExportFormat.values)
                  RadioListTile<ExportFormat>(
                    value: format,
                    contentPadding: EdgeInsets.zero,
                    title: Text(format.label),
                    subtitle: Text(switch (format) {
                      ExportFormat.json =>
                        'Everything, including status and dates',
                      ExportFormat.html =>
                        'Import into a browser or another bookmark app',
                    }),
                  ),
              ],
            ),
          ),
          if (_working) ...[
            const SizedBox(height: Gap.md),
            const LinearProgressIndicator(),
          ],
          if (_error case final error?) ...[
            const SizedBox(height: Gap.md),
            Text(error, style: TextStyle(color: theme.colorScheme.error)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: _working ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(88, 40)),
          onPressed: _working ? null : _export,
          child: const Text('Export'),
        ),
      ],
    );
  }
}
