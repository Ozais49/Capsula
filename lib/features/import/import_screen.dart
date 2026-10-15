import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/dependencies.dart';
import '../../app/router.dart';
import '../../app/theme.dart';

import 'package:capsula_core/domain/import/import_service.dart';
import 'package:capsula_core/domain/import/imported_item.dart';
import 'package:capsula_core/domain/import/tabular_import.dart';

import '../organization/labels_builder.dart';
import 'import_controller.dart';

class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  ImportController? _controller;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final deps = AppDependencies.of(context);
    _controller ??= ImportController(deps.importer, deps.importFilePicker);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _done() => context.canPop() ? context.pop() : context.go(AppRoutes.home);

  @override
  Widget build(BuildContext context) {
    final controller = _controller!;
    return Scaffold(
      appBar: AppBar(title: const Text('Import bookmarks')),
      body: LabelsBuilder(
        builder: (context, labels) => ListenableBuilder(
          listenable: controller,
          builder: (context, _) => Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 640),
              child: switch (controller.step) {
                ChooseSource(:final error) => _SourceList(
                  error: error,
                  onPick: controller.pickFile,
                ),
                Working(:final message) => _Progress(message: message),
                MapFields(:final table, :final mapping) => _Mapping(
                  table: table,
                  mapping: mapping,
                  onChanged: controller.updateMapping,
                  onContinue: controller.confirmMapping,
                  onCancel: controller.restart,
                ),
                Preview(:final plan) => _PlanPreview(
                  plan: plan,
                  origin: controller.origin,
                  fileName: controller.fileName,
                  onImport: (options) => controller.startImport(
                    options: options,
                    existingLabels: [...labels.tags, ...labels.collections],
                  ),
                  onCancel: controller.restart,
                ),
                Importing(:final done, :final total) => _Progress(
                  message: 'Imported $done of $total',
                  value: total == 0 ? null : done / total,
                ),
                Finished(:final result) => _Result(
                  result: result,
                  onDone: _done,
                  onAgain: controller.restart,
                ),
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _SourceList extends StatelessWidget {
  const _SourceList({required this.error, required this.onPick});

  final String? error;
  final ValueChanged<ImportOrigin> onPick;

  static const _help = {
    ImportOrigin.chrome:
        'Bookmark manager (Ctrl+Shift+O) → ⋮ → Export bookmarks',
    ImportOrigin.firefox: 'Bookmarks → Manage bookmarks → Import and Backup → Export Bookmarks to HTML',
    ImportOrigin.edge: 'Favorites (Ctrl+Shift+O) → ⋯ → Export favorites',
    ImportOrigin.safari: 'File → Export → Bookmarks',
    ImportOrigin.raindrop: 'Settings → Backups → Export as CSV or HTML',
    ImportOrigin.pocket: 'Your Pocket export file (CSV or HTML)',
    ImportOrigin.file: 'Any bookmark HTML, CSV or JSON file',
  };

  static const _icons = {
    ImportOrigin.chrome: Icons.public,
    ImportOrigin.firefox: Icons.public,
    ImportOrigin.edge: Icons.public,
    ImportOrigin.safari: Icons.public,
    ImportOrigin.raindrop: Icons.water_drop_outlined,
    ImportOrigin.pocket: Icons.bookmarks_outlined,
    ImportOrigin.file: Icons.description_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(Gap.md),
      children: [
        Padding(
          padding: const EdgeInsets.all(Gap.sm),
          child: Text(
            'Export your bookmarks from another app, then choose the file. '
            'You\'ll see a preview before anything is imported.',
            style: theme.textTheme.bodyMedium,
          ),
        ),
        if (error case final error?)
          Card(
            color: theme.colorScheme.errorContainer,
            child: ListTile(
              leading: Icon(
                Icons.error_outline,
                color: theme.colorScheme.onErrorContainer,
              ),
              title: Text(
                error,
                style: TextStyle(color: theme.colorScheme.onErrorContainer),
              ),
            ),
          ),
        for (final origin in ImportOrigin.values)
          ListTile(
            leading: Icon(_icons[origin]),
            title: Text(
              origin == ImportOrigin.file ? 'Other file' : origin.label,
            ),
            subtitle: Text(_help[origin]!),
            trailing: const Icon(Icons.upload_file),
            onTap: () => onPick(origin),
          ),
      ],
    );
  }
}

class _Progress extends StatelessWidget {
  const _Progress({required this.message, this.value});

  final String message;
  final double? value;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(Gap.xl),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        LinearProgressIndicator(value: value),
        const SizedBox(height: Gap.md),
        Text(message),
      ],
    ),
  );
}

class _Mapping extends StatelessWidget {
  const _Mapping({
    required this.table,
    required this.mapping,
    required this.onChanged,
    required this.onContinue,
    required this.onCancel,
  });

  final ImportTable table;
  final FieldMapping mapping;
  final ValueChanged<FieldMapping> onChanged;
  final VoidCallback onContinue;
  final VoidCallback onCancel;

  Widget _field(
    String label,
    String? value,
    FieldMapping Function(String? column) update,
  ) => Padding(
    padding: const EdgeInsets.only(bottom: Gap.md),
    child: DropdownButtonFormField<String?>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: [
        const DropdownMenuItem(value: null, child: Text('— Not imported —')),
        for (final c in table.columns)
          DropdownMenuItem(value: c, child: Text(c)),
      ],
      onChanged: (column) => onChanged(update(column)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sample = table.rows.take(3).toList();

    return ListView(
      padding: const EdgeInsets.all(Gap.lg),
      children: [
        Text('Match the columns', style: theme.textTheme.titleLarge),
        const SizedBox(height: Gap.xs),
        Text(
          '${table.rows.length} rows found. Choose which column holds each '
          'detail. Only the link is required.',
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: Gap.lg),
        _field(
          'Link (URL) *',
          mapping.url,
          (c) => mapping.copyWith(url: () => c),
        ),
        _field('Title', mapping.title, (c) => mapping.copyWith(title: () => c)),
        _field(
          'Description',
          mapping.description,
          (c) => mapping.copyWith(description: () => c),
        ),
        _field(
          'Folder → Collection',
          mapping.folder,
          (c) => mapping.copyWith(folder: () => c),
        ),
        _field('Tags', mapping.tags, (c) => mapping.copyWith(tags: () => c)),
        _field(
          'Date saved',
          mapping.createdAt,
          (c) => mapping.copyWith(createdAt: () => c),
        ),
        if (mapping.url case final urlColumn? when sample.isNotEmpty) ...[
          Text('Sample', style: theme.textTheme.titleSmall),
          for (final row in sample)
            Text(
              row[urlColumn] ?? '',
              style: theme.textTheme.bodySmall,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: Gap.lg),
        ],
        FilledButton(
          onPressed: mapping.isUsable ? onContinue : null,
          child: const Text('Continue'),
        ),
        TextButton(onPressed: onCancel, child: const Text('Cancel')),
      ],
    );
  }
}

class _PlanPreview extends StatefulWidget {
  const _PlanPreview({
    required this.plan,
    required this.origin,
    required this.fileName,
    required this.onImport,
    required this.onCancel,
  });

  final ImportPlan plan;
  final ImportOrigin origin;
  final String? fileName;
  final ValueChanged<ImportOptions> onImport;
  final VoidCallback onCancel;

  @override
  State<_PlanPreview> createState() => _PlanPreviewState();
}

class _PlanPreviewState extends State<_PlanPreview> {
  bool _inbox = true;
  bool _folders = true;
  bool _tags = true;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final plan = widget.plan;
    final count = plan.newItems.length;

    return ListView(
      padding: const EdgeInsets.all(Gap.lg),
      children: [
        Text('Import preview', style: theme.textTheme.titleLarge),
        if (widget.fileName case final name?)
          Text(
            '$name · from ${widget.origin.label}',
            style: theme.textTheme.bodySmall,
          ),
        const SizedBox(height: Gap.md),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Gap.md),
            child: Column(
              children: [
                _Stat('Bookmarks found', plan.found),
                _Stat('New', count, emphasize: true),
                _Stat('Already in Capsula', plan.alreadySaved),
                if (plan.repeatedInFile > 0)
                  _Stat('Repeated in file', plan.repeatedInFile),
                _Stat('Invalid links', plan.invalid.length),
              ],
            ),
          ),
        ),
        if (count > 0) ...[
          SwitchListTile(
            title: const Text('Add to Inbox'),
            subtitle: const Text('Review imported bookmarks later'),
            value: _inbox,
            onChanged: (v) => setState(() => _inbox = v),
          ),
          if (plan.folders.isNotEmpty)
            SwitchListTile(
              title: const Text('Keep folders as collections'),
              subtitle: Text('${plan.folders.length} folders'),
              value: _folders,
              onChanged: (v) => setState(() => _folders = v),
            ),
          if (plan.tags.isNotEmpty)
            SwitchListTile(
              title: const Text('Keep tags'),
              subtitle: Text('${plan.tags.length} tags'),
              value: _tags,
              onChanged: (v) => setState(() => _tags = v),
            ),
          const SizedBox(height: Gap.sm),
          Text('First few', style: theme.textTheme.titleSmall),
          for (final p in plan.newItems.take(8))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              title: Text(
                p.item.title ?? p.uri.host,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                [p.uri.host, ?p.item.folder].join(' · '),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          const SizedBox(height: Gap.lg),
          FilledButton(
            onPressed: () => widget.onImport(
              ImportOptions(
                addToInbox: _inbox,
                foldersAsCollections: _folders,
                keepTags: _tags,
              ),
            ),
            child: Text(
              'Import $count ${count == 1 ? 'bookmark' : 'bookmarks'}',
            ),
          ),
        ] else ...[
          const SizedBox(height: Gap.lg),
          const Text('Nothing new to import.', textAlign: TextAlign.center),
          const SizedBox(height: Gap.lg),
        ],
        TextButton(onPressed: widget.onCancel, child: const Text('Cancel')),
      ],
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat(this.label, this.value, {this.emphasize = false});

  final String label;
  final int value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final style = emphasize
        ? Theme.of(context).textTheme.titleMedium
        : Theme.of(context).textTheme.bodyMedium;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gap.xs),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text('$value', style: style),
        ],
      ),
    );
  }
}

class _Result extends StatelessWidget {
  const _Result({
    required this.result,
    required this.onDone,
    required this.onAgain,
  });

  final ImportResult result;
  final VoidCallback onDone;
  final VoidCallback onAgain;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ok = result.failed == 0;
    return ListView(
      padding: const EdgeInsets.all(Gap.lg),
      children: [
        Icon(
          ok ? Icons.check_circle_outline : Icons.warning_amber_outlined,
          size: 56,
          color: ok ? theme.colorScheme.primary : theme.colorScheme.error,
        ),
        const SizedBox(height: Gap.md),
        Text(
          ok ? 'Import complete' : 'Import partly complete',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: Gap.md),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(Gap.md),
            child: Column(
              children: [
                _Stat('Imported', result.imported, emphasize: true),
                _Stat('Duplicates skipped', result.duplicates),
                _Stat('Invalid links', result.invalid),
                if (!ok) _Stat('Failed', result.failed),
              ],
            ),
          ),
        ),
        if (!ok)
          Padding(
            padding: const EdgeInsets.all(Gap.sm),
            child: Text(
              'Some bookmarks couldn\'t be saved. Import the same file again '
              'to add only the missing ones.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: Gap.lg),
        FilledButton(onPressed: onDone, child: const Text('Done')),
        TextButton(
          onPressed: onAgain,
          child: const Text('Import another file'),
        ),
      ],
    );
  }
}
