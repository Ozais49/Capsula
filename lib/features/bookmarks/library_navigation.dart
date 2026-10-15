import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/dependencies.dart';
import '../../app/router.dart';
import '../../app/theme.dart';

import 'package:capsula_core/domain/bookmarks/bookmark_source.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_view.dart';
import 'package:capsula_core/domain/organization/label.dart';

import '../export/export_dialog.dart';
import '../organization/label_dialogs.dart';
import '../organization/labels_builder.dart';
import 'bookmark_display.dart';

/// Lists the library views: Inbox, All, Archived, sources, collections, tags.
class LibraryNavigation extends StatefulWidget {
  const LibraryNavigation({
    super.key,
    required this.selected,
    required this.labels,
    required this.onSelect,
  });

  final BookmarkView selected;
  final Labels labels;
  final ValueChanged<BookmarkView> onSelect;

  @override
  State<LibraryNavigation> createState() => _LibraryNavigationState();
}

class _LibraryNavigationState extends State<LibraryNavigation> {
  Future<int?>? _inboxCount;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _inboxCount ??= AppDependencies.of(context).bookmarks.repository
        .countInbox();
  }

  Widget _item(
    BookmarkView view,
    IconData icon,
    String label, {
    Widget? trailing,
  }) => ListTile(
    dense: true,
    selected: widget.selected == view,
    leading: Icon(icon),
    title: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
    trailing: trailing,
    shape: const StadiumBorder(),
    onTap: () {
      // Closes the drawer when shown in one; no-op beside the list.
      Scaffold.maybeOf(context)?.closeDrawer();
      widget.onSelect(view);
    },
  );

  Widget _header(String text, {VoidCallback? onAdd, String? addTooltip}) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.xs, 0),
      child: Row(
        children: [
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          if (onAdd != null)
            IconButton(
              tooltip: addTooltip,
              icon: const Icon(Icons.add, size: 20),
              onPressed: onAdd,
            ),
        ],
      ),
    );
  }

  List<Widget> _labelSection(LabelKind kind, IconData icon) {
    final labels = widget.labels.of(kind);
    return [
      _header(
        kind.plural,
        addTooltip: 'New ${kind.singular.toLowerCase()}',
        onAdd: () => createLabelWithPrompt(context, kind, labels),
      ),
      if (labels.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.md),
          child: Text('None yet', style: Theme.of(context).textTheme.bodySmall),
        ),
      for (final label in labels)
        _item(
          LabelView(kind, label.id),
          icon,
          label.name,
          trailing: PopupMenuButton<String>(
            tooltip: '${label.name} options',
            icon: const Icon(Icons.more_vert, size: 18),
            onSelected: (action) async {
              if (action == 'rename') {
                await renameLabelWithPrompt(context, label, labels);
              } else if (action == 'delete' &&
                  await deleteLabelWithConfirm(context, label) &&
                  widget.selected == LabelView(kind, label.id)) {
                widget.onSelect(BookmarkView.inbox);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('Rename')),
              PopupMenuItem(value: 'delete', child: Text('Delete')),
            ],
          ),
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final deps = AppDependencies.of(context);

    final views = ListView(
      padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: Gap.md),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.md, 0, Gap.md, Gap.sm),
          child: Text('Capsula', style: Theme.of(context).textTheme.titleLarge),
        ),
        _item(
          BookmarkView.inbox,
          Icons.inbox_outlined,
          'Inbox',
          trailing: FutureBuilder<int?>(
            future: _inboxCount,
            builder: (context, count) => count.data == null || count.data == 0
                ? const SizedBox.shrink()
                : Text('${count.data}'),
          ),
        ),
        _item(BookmarkView.all, Icons.bookmarks_outlined, 'All bookmarks'),
        _item(BookmarkView.archived, Icons.archive_outlined, 'Archived'),
        ..._labelSection(LabelKind.collection, Icons.folder_outlined),
        ..._labelSection(LabelKind.tag, Icons.label_outline),
        _header('Sources'),
        for (final source in BookmarkSource.values)
          _item(SourceView(source), sourceIcon(source), source.label),
      ],
    );

    // Account actions stay visible below the scrolling list of views.
    return Column(
      children: [
        Expanded(child: views),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Gap.sm,
            vertical: Gap.xs,
          ),
          child: Column(
            children: [
              ListTile(
                dense: true,
                leading: const Icon(Icons.upload_file),
                title: const Text('Import bookmarks'),
                onTap: () => context.push(AppRoutes.import),
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.download_outlined),
                title: const Text('Export library'),
                onTap: () => showExportDialog(context),
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.api),
                title: const Text('API & integrations'),
                onTap: () => context.push(AppRoutes.integrations),
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.settings_ethernet),
                title: const Text('Connection settings'),
                onTap: () => context.push(AppRoutes.connection),
              ),
              ListTile(
                dense: true,
                leading: const Icon(Icons.logout),
                title: const Text('Sign out'),
                onTap: deps.authRepository.signOut,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Display name of [view].
String viewTitle(BookmarkView view, Labels labels) => switch (view) {
  InboxView() => 'Inbox',
  AllView() => 'All bookmarks',
  ArchivedView() => 'Archived',
  SourceView(:final source) => source.label,
  LabelView(:final kind, :final labelId) =>
    labels.find(kind, labelId)?.name ?? kind.singular,
};
