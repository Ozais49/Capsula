import 'package:flutter/material.dart';

import 'package:capsula_core/domain/bookmarks/bookmark_source.dart';
import 'package:capsula_core/domain/sources/custom_source.dart';

import '../../app/dependencies.dart';
import '../../app/theme.dart';
import '../bookmarks/bookmark_display.dart';
import '../organization/labels_builder.dart';

/// Lists the built-in sources and the user's own, which can be added,
/// edited and deleted.
class SourcesScreen extends StatelessWidget {
  const SourcesScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Sources')),
    floatingActionButton: LabelsBuilder(
      builder: (context, labels) => FloatingActionButton.extended(
        onPressed: () => _edit(context, null, labels.sources),
        icon: const Icon(Icons.add),
        label: const Text('Add source'),
      ),
    ),
    body: LabelsBuilder(
      builder: (context, labels) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              const Padding(
                padding: EdgeInsets.all(Gap.md),
                child: Text(
                  'Links are sorted by where they come from. Add a source '
                  'for any site, by its domains; links from sites with no '
                  'source are Webpage.',
                ),
              ),
              _Heading('Your sources'),
              if (labels.sources.isEmpty)
                const ListTile(
                  title: Text('None yet'),
                  subtitle: Text('For example "Amazon" for amazon.com'),
                ),
              for (final s in labels.sources)
                ListTile(
                  leading: const Icon(customSourceIcon),
                  title: Text(s.name),
                  subtitle: Text(s.domains.join(', ')),
                  onTap: () => _edit(context, s, labels.sources),
                  trailing: IconButton(
                    tooltip: 'Delete ${s.name}',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => _delete(context, s),
                  ),
                ),
              if (labels.sources.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.all(Gap.md),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text('Apply to saved bookmarks'),
                      onPressed: () => _redetect(context),
                    ),
                  ),
                ),
              _Heading('Built in'),
              for (final s in BookmarkSource.values)
                ListTile(
                  leading: Icon(sourceIcon(s)),
                  title: Text(s.label),
                  subtitle: s == BookmarkSource.website
                      ? const Text('Any other site')
                      : null,
                ),
            ],
          ),
        ),
      ),
    ),
  );

  Future<void> _edit(
    BuildContext context,
    CustomSource? source,
    List<CustomSource> existing,
  ) async {
    final saved = await showDialog<bool>(
      context: context,
      builder: (_) => _SourceDialog(source: source, existing: existing),
    );
    if (saved == true && context.mounted) {
      final redetect = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Apply to saved bookmarks?'),
          content: const Text(
            'New links use this source right away. Saved bookmarks from '
            'these domains move to it when you apply it.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Not now'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(88, 40)),
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Apply'),
            ),
          ],
        ),
      );
      if (redetect == true && context.mounted) await _redetect(context);
    }
  }

  Future<void> _redetect(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final changed = await AppDependencies.of(
        context,
      ).bookmarks.redetectSources();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            changed == 0
                ? 'All bookmarks already have the right source'
                : 'Updated $changed bookmark${changed == 1 ? '' : 's'}',
          ),
        ),
      );
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not update: $e')));
    }
  }

  Future<void> _delete(BuildContext context, CustomSource source) async {
    final service = AppDependencies.of(context).bookmarks;
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete ${source.name}?'),
        content: const Text(
          'Its bookmarks are kept and show as Webpage, or their built-in '
          'source.',
        ),
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
    if (confirmed != true) return;
    try {
      await service.deleteSource(source);
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not delete: $e')));
    }
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.lg, Gap.md, Gap.xs),
      child: Text(
        text,
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.primary,
        ),
      ),
    );
  }
}

class _SourceDialog extends StatefulWidget {
  const _SourceDialog({required this.source, required this.existing});

  final CustomSource? source;
  final List<CustomSource> existing;

  @override
  State<_SourceDialog> createState() => _SourceDialogState();
}

class _SourceDialogState extends State<_SourceDialog> {
  late final _name = TextEditingController(text: widget.source?.name);
  late final _domains = TextEditingController(
    text: widget.source?.domains.join(', '),
  );
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _domains.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final service = AppDependencies.of(context).bookmarks;
    final domains = _domains.text
        .split(RegExp(r'[,\s]+'))
        .where((d) => d.trim().isNotEmpty)
        .toList();
    setState(() => _saving = true);
    final source = widget.source;
    try {
      final error = source == null
          ? await service.addSource(_name.text, domains, widget.existing)
          : await service.updateSource(
              source.copyWith(name: _name.text, domains: domains),
              widget.existing,
            );
      if (!mounted) return;
      if (error != null) {
        setState(() {
          _error = error;
          _saving = false;
        });
        return;
      }
      Navigator.pop(context, true);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not save: $e';
        _saving = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(widget.source == null ? 'Add source' : 'Edit source'),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _name,
          autofocus: widget.source == null,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(
            labelText: 'Name',
            hintText: 'Amazon',
          ),
        ),
        const SizedBox(height: Gap.md),
        TextField(
          controller: _domains,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            labelText: 'Domains',
            hintText: 'amazon.com, amzn.to',
            helperText: 'Separate with commas. Subdomains are included.',
          ),
          onSubmitted: (_) => _save(),
        ),
        if (_error case final error?)
          Padding(
            padding: const EdgeInsets.only(top: Gap.md),
            child: Text(
              error,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context, false),
        child: const Text('Cancel'),
      ),
      FilledButton(
        style: FilledButton.styleFrom(minimumSize: const Size(88, 40)),
        onPressed: _saving ? null : _save,
        child: const Text('Save'),
      ),
    ],
  );
}
