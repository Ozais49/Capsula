import 'dart:async';

import 'package:capsula_core/domain/bookmarks/bookmark.dart';
import 'package:capsula_core/domain/maintenance/maintenance.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/dependencies.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../bookmarks/bookmark_display.dart';

/// Library upkeep: refresh the index, find duplicates, check for dead links.
class MaintenanceScreen extends StatelessWidget {
  const MaintenanceScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Maintenance')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: ListView(
          padding: const EdgeInsets.all(Gap.md),
          children: const [_BrokenLinks(), _Duplicates(), _Reindex()],
        ),
      ),
    ),
  );
}

class _Section extends StatelessWidget {
  const _Section({
    required this.icon,
    required this.title,
    required this.description,
    required this.action,
    required this.onRun,
    this.running = false,
    this.progress,
    this.children = const [],
  });

  final IconData icon;
  final String title;
  final String description;
  final String action;
  final VoidCallback? onRun;
  final bool running;
  final double? progress;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: Gap.md),
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(icon, color: theme.colorScheme.primary),
                const SizedBox(width: Gap.md),
                Expanded(
                  child: Text(title, style: theme.textTheme.titleMedium),
                ),
                FilledButton(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(88, 40),
                  ),
                  onPressed: running ? null : onRun,
                  child: Text(action),
                ),
              ],
            ),
            const SizedBox(height: Gap.sm),
            Text(description, style: theme.textTheme.bodySmall),
            if (running) ...[
              const SizedBox(height: Gap.md),
              LinearProgressIndicator(value: progress),
            ],
            ...children,
          ],
        ),
      ),
    );
  }
}

// -----------------------------------------------------------------------------

class _BrokenLinks extends StatefulWidget {
  const _BrokenLinks();

  @override
  State<_BrokenLinks> createState() => _BrokenLinksState();
}

class _BrokenLinksState extends State<_BrokenLinks> {
  bool _running = false;
  int _done = 0;
  int _total = 0;
  int _unknown = 0;
  List<(Bookmark, LinkCheck)>? _broken;

  Future<void> _run() async {
    final deps = AppDependencies.of(context);
    setState(() {
      _running = true;
      _done = 0;
      _unknown = 0;
      _broken = null;
    });
    final all = (await deps.bookmarks.repository.fetchAll())
        .where((b) => !b.archived)
        .toList();
    final broken = <(Bookmark, LinkCheck)>[];
    var unknown = 0;
    _total = all.length;

    // A few at a time: fast, without hammering any one site.
    var next = 0;
    Future<void> worker() async {
      while (next < all.length) {
        final b = all[next++];
        final url = Uri.tryParse(b.url);
        final check = url == null
            ? const LinkCheck(LinkHealth.broken, reason: 'Invalid link')
            : await deps.linkChecker.check(url);
        if (check.health == LinkHealth.broken) broken.add((b, check));
        if (check.health == LinkHealth.unknown) unknown++;
        if (mounted) setState(() => _done++);
      }
    }

    await Future.wait([for (var i = 0; i < 4; i++) worker()]);
    if (!mounted) return;
    setState(() {
      _running = false;
      _unknown = unknown;
      _broken = broken;
    });
  }

  Future<void> _resolve(Bookmark b, {required bool delete}) async {
    final service = AppDependencies.of(context).bookmarks;
    await (delete ? service.delete(b) : service.setArchived(b, true));
    setState(() => _broken!.removeWhere((e) => e.$1.id == b.id));
  }

  @override
  Widget build(BuildContext context) {
    final broken = _broken;
    return _Section(
      icon: Icons.link_off,
      title: 'Broken links',
      description:
          'Checks every bookmark that isn\'t archived for pages that no '
          'longer exist or can\'t be reached.',
      action: 'Check',
      onRun: _run,
      running: _running,
      progress: _total == 0 ? null : _done / _total,
      children: [
        if (_running)
          Padding(
            padding: const EdgeInsets.only(top: Gap.xs),
            child: Text('Checked $_done of $_total'),
          ),
        if (broken != null) ...[
          const SizedBox(height: Gap.md),
          Text(
            broken.isEmpty
                ? 'No broken links found.'
                : '${broken.length} broken link${broken.length == 1 ? '' : 's'}',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          if (_unknown > 0)
            Text(
              '$_unknown couldn\'t be checked (the site blocks checks or '
              'needs sign-in).',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          for (final (b, check) in broken)
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                b.displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${b.sourceDomain} · ${check.reason ?? 'Broken'}'
                '${check.statusCode == null ? '' : ' (${check.statusCode})'}',
              ),
              onTap: () => context.push(AppRoutes.bookmark(b.id)),
              trailing: PopupMenuButton<String>(
                tooltip: 'Fix ${b.displayTitle}',
                onSelected: (a) => _resolve(b, delete: a == 'delete'),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'archive', child: Text('Archive')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ),
        ],
      ],
    );
  }
}

// -----------------------------------------------------------------------------

class _Duplicates extends StatefulWidget {
  const _Duplicates();

  @override
  State<_Duplicates> createState() => _DuplicatesState();
}

class _DuplicatesState extends State<_Duplicates> {
  bool _running = false;
  List<List<Bookmark>>? _groups;

  Future<void> _run() async {
    final repo = AppDependencies.of(context).bookmarks.repository;
    setState(() {
      _running = true;
      _groups = null;
    });
    final groups = findDuplicates(await repo.fetchAll());
    if (mounted) {
      setState(() {
        _running = false;
        _groups = groups;
      });
    }
  }

  /// Keeps [keep] and deletes the rest of its group.
  Future<void> _keep(List<Bookmark> group, Bookmark keep) async {
    final service = AppDependencies.of(context).bookmarks;
    await service.deleteMany(group.where((b) => b.id != keep.id));
    setState(() => _groups!.remove(group));
  }

  Future<void> _keepAllOldest() async {
    for (final group in List.of(_groups!)) {
      await _keep(group, group.first);
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = _groups;
    final theme = Theme.of(context);
    return _Section(
      icon: Icons.content_copy_outlined,
      title: 'Duplicates',
      description:
          'Finds bookmarks that point to the same page, for example from '
          'imports or different share links.',
      action: 'Find',
      onRun: _run,
      running: _running,
      children: [
        if (groups != null) ...[
          const SizedBox(height: Gap.md),
          Row(
            children: [
              Expanded(
                child: Text(
                  groups.isEmpty
                      ? 'No duplicates found.'
                      : '${groups.length} page${groups.length == 1 ? '' : 's'} saved more than once',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              if (groups.isNotEmpty)
                TextButton(
                  onPressed: _keepAllOldest,
                  child: const Text('Keep oldest of each'),
                ),
            ],
          ),
          for (final group in groups) ...[
            const Divider(),
            for (final b in group)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  b.displayTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  'Saved ${formatSavedDate(b.createdAt).toLowerCase()}'
                  '${b.importedFrom == null ? '' : ' · from ${b.importedFrom}'}',
                ),
                trailing: TextButton(
                  onPressed: () => _keep(group, b),
                  child: const Text('Keep this'),
                ),
              ),
          ],
        ],
      ],
    );
  }
}

// -----------------------------------------------------------------------------

class _Reindex extends StatefulWidget {
  const _Reindex();

  @override
  State<_Reindex> createState() => _ReindexState();
}

class _ReindexState extends State<_Reindex> {
  bool _running = false;
  double? _progress;
  String? _result;

  Future<void> _run() async {
    final service = AppDependencies.of(context).bookmarks;
    setState(() {
      _running = true;
      _result = null;
    });
    final count = await service.reindexAll(
      onProgress: (done, total) {
        if (mounted && total > 0) setState(() => _progress = done / total);
      },
    );
    if (mounted) {
      setState(() {
        _running = false;
        _result = 'Refreshed $count bookmarks.';
      });
    }
  }

  @override
  Widget build(BuildContext context) => _Section(
    icon: Icons.refresh,
    title: 'Refresh library index',
    description:
        'Updates search words and content types for every bookmark. Run '
        'this once after updating Capsula so older bookmarks appear in type '
        'filters.',
    action: 'Refresh',
    onRun: _run,
    running: _running,
    progress: _progress,
    children: [
      if (_result case final r?)
        Padding(
          padding: const EdgeInsets.only(top: Gap.sm),
          child: Text(r),
        ),
    ],
  );
}
