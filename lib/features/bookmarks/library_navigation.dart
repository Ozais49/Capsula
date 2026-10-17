import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/dependencies.dart';
import '../../app/router.dart';
import '../../app/theme.dart';

import 'package:capsula_core/domain/auth/app_user.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_repository.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_view.dart';
import 'package:capsula_core/domain/organization/label.dart';

import '../organization/label_dialogs.dart';
import '../organization/share_dialog.dart';
import '../organization/labels_builder.dart';

/// Lists the library views: Unsorted, All, Favorites, Archived, Trash, and the
/// user's collections and tags. Sources and kinds are filters in the list.
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
  Future<int>? _dueCount;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repo = AppDependencies.of(context).bookmarks.repository;
    _inboxCount ??= repo.countInbox();
    _dueCount ??= repo
        .watchList(
          const BookmarkQuery(view: BookmarkView.reminders),
          limit: 200,
        )
        .first
        .then((list) => list.where((b) => b.isDue(DateTime.now())).length);
  }

  Widget _item(
    BookmarkView view,
    IconData icon,
    String label, {
    Widget? trailing,
    int depth = 0,
  }) => ListTile(
    dense: true,
    contentPadding: EdgeInsetsDirectional.only(
      start: Gap.md + depth * Gap.md,
      end: Gap.sm,
    ),
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

  /// A section heading. With [collapseKey], tapping it opens or closes the
  /// section, and the choice is remembered.
  Widget _header(
    String text, {
    String? collapseKey,
    VoidCallback? onAdd,
    String? addTooltip,
  }) {
    final theme = Theme.of(context);
    final display = AppDependencies.of(context).display;
    final collapsed = collapseKey != null && display.isCollapsed(collapseKey);
    final label = Text(
      text,
      style: theme.textTheme.titleSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.xs, Gap.md, Gap.xs, 0),
      child: Row(
        children: [
          Expanded(
            child: collapseKey == null
                ? Padding(
                    padding: const EdgeInsets.only(left: Gap.sm),
                    child: label,
                  )
                : Semantics(
                    button: true,
                    expanded: !collapsed,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => display.toggleCollapsed(collapseKey),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Gap.sm,
                          vertical: Gap.sm,
                        ),
                        child: Row(
                          children: [
                            Flexible(child: label),
                            const SizedBox(width: Gap.xs),
                            Icon(
                              collapsed ? Icons.expand_more : Icons.expand_less,
                              size: 20,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ],
                        ),
                      ),
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

  static String _sectionKey(LabelKind kind) => 'section:${kind.name}';

  static String _sectionTitle(LabelKind kind) => switch (kind) {
    LabelKind.collection => 'My collections',
    LabelKind.tag => 'Tags',
  };

  List<Widget> _labelSection(LabelKind kind, IconData icon) {
    final display = AppDependencies.of(context).display;
    final labels = widget.labels.of(kind);
    final header = _header(
      _sectionTitle(kind),
      collapseKey: _sectionKey(kind),
      addTooltip: 'New ${kind.singular.toLowerCase()}',
      onAdd: () => createLabelWithPrompt(context, kind, labels),
    );
    if (display.isCollapsed(_sectionKey(kind))) return [header];

    // Collections nest, and a collection with collections inside can be
    // collapsed; tags are flat.
    final rows = kind == LabelKind.collection
        ? labelTree(labels)
        : [for (final l in labels) (l, 0)];
    final hasChildren = {
      for (final l in labels)
        if (l.parentId != null) l.parentId!,
    };
    final visible = <(Label, int)>[];
    int? hiddenBelow;
    for (final (label, depth) in rows) {
      if (hiddenBelow != null && depth > hiddenBelow) continue;
      hiddenBelow = null;
      visible.add((label, depth));
      if (display.isCollapsed('collection:${label.id}')) hiddenBelow = depth;
    }

    return [
      header,
      if (labels.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gap.md),
          child: Text('None yet', style: Theme.of(context).textTheme.bodySmall),
        ),
      for (final (label, depth) in visible)
        _item(
          LabelView(kind, label.id),
          label.shareId != null
              ? Icons.public
              : depth > 0
              ? Icons.subdirectory_arrow_right
              : icon,
          label.name,
          depth: depth,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (kind == LabelKind.collection &&
                  hasChildren.contains(label.id))
                _expandButton(label),
              _labelMenu(kind, label, labels),
            ],
          ),
        ),
    ];
  }

  Widget _expandButton(Label label) {
    final display = AppDependencies.of(context).display;
    final key = 'collection:${label.id}';
    final collapsed = display.isCollapsed(key);
    return IconButton(
      tooltip: collapsed
          ? 'Show inside ${label.name}'
          : 'Hide inside ${label.name}',
      icon: Icon(collapsed ? Icons.expand_more : Icons.expand_less, size: 18),
      onPressed: () => display.toggleCollapsed(key),
    );
  }

  Widget _labelMenu(LabelKind kind, Label label, List<Label> labels) =>
      PopupMenuButton<String>(
        tooltip: '${label.name} options',
        icon: const Icon(Icons.more_vert, size: 18),
        onSelected: (action) async {
          switch (action) {
            case 'rename':
              await renameLabelWithPrompt(context, label, labels);
            case 'sub':
              await createLabelWithPrompt(context, kind, labels, parent: label);
            case 'move':
              await moveCollectionWithPicker(context, label, labels);
            case 'share':
              await showShareCollectionDialog(context, label);
            case 'delete':
              if (await deleteLabelWithConfirm(context, label) &&
                  widget.selected == LabelView(kind, label.id)) {
                widget.onSelect(BookmarkView.inbox);
              }
          }
        },
        itemBuilder: (_) => [
          const PopupMenuItem(value: 'rename', child: Text('Rename')),
          if (kind == LabelKind.collection) ...const [
            PopupMenuItem(value: 'sub', child: Text('New collection inside')),
            PopupMenuItem(value: 'move', child: Text('Move to…')),
          ],
          // Public links are served by the API for account users.
          if (kind == LabelKind.collection &&
              !AppDependencies.of(context).backend.deviceOnly)
            const PopupMenuItem(value: 'share', child: Text('Share…')),
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      );

  @override
  Widget build(BuildContext context) {
    final deps = AppDependencies.of(context);

    // Rebuilt when a section is opened or closed.
    Widget buildViews() => ListView(
      padding: const EdgeInsets.symmetric(horizontal: Gap.sm, vertical: Gap.sm),
      children: [
        _item(
          BookmarkView.inbox,
          Icons.inbox_outlined,
          'Unsorted',
          trailing: FutureBuilder<int?>(
            future: _inboxCount,
            builder: (context, count) => count.data == null || count.data == 0
                ? const SizedBox.shrink()
                : Text('${count.data}'),
          ),
        ),
        _item(BookmarkView.all, Icons.bookmarks_outlined, 'All bookmarks'),
        _item(BookmarkView.favorites, Icons.star_outline, 'Favorites'),
        _item(
          BookmarkView.reminders,
          Icons.alarm,
          'Reminders',
          trailing: FutureBuilder<int>(
            future: _dueCount,
            builder: (context, due) => (due.data ?? 0) == 0
                ? const SizedBox.shrink()
                : Badge(
                    label: Text('${due.data}'),
                    child: const SizedBox.square(dimension: 8),
                  ),
          ),
        ),
        ListTile(
          dense: true,
          leading: const Icon(Icons.format_quote_outlined),
          title: const Text('Highlights'),
          shape: const StadiumBorder(),
          onTap: () {
            Scaffold.maybeOf(context)?.closeDrawer();
            context.push(AppRoutes.highlights);
          },
        ),
        _item(BookmarkView.archived, Icons.archive_outlined, 'Archived'),
        _item(BookmarkView.trash, Icons.delete_outline, 'Trash'),
        ..._labelSection(LabelKind.collection, Icons.folder_outlined),
        ..._labelSection(LabelKind.tag, Icons.label_outline),
      ],
    );

    // Greeting and account actions on top; every category below.
    return Column(
      children: [
        _AccountHeader(
          user: deps.authSession.user,
          onSettings: () {
            Scaffold.maybeOf(context)?.closeDrawer();
            context.push(AppRoutes.settings);
          },
          // Nothing to log out of without an account.
          onSignOut: deps.backend.deviceOnly
              ? null
              : deps.authRepository.signOut,
        ),
        const Divider(height: 1),
        Expanded(
          child: ListenableBuilder(
            listenable: deps.display,
            builder: (context, _) => buildViews(),
          ),
        ),
      ],
    );
  }
}

class _AccountHeader extends StatelessWidget {
  const _AccountHeader({
    required this.user,
    required this.onSettings,
    required this.onSignOut,
  });

  final AppUser? user;
  final VoidCallback onSettings;
  final VoidCallback? onSignOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final handle = userHandle(user);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Gap.lg, Gap.md, Gap.sm, Gap.sm),
      child: Row(
        children: [
          CircleAvatar(
            backgroundColor: theme.colorScheme.primaryContainer,
            foregroundColor: theme.colorScheme.onPrimaryContainer,
            child: Text(handle.isEmpty ? '?' : handle[0].toUpperCase()),
          ),
          const SizedBox(width: Gap.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  handle.isEmpty ? 'Hello' : 'Hello, @$handle',
                  style: theme.textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (onSignOut == null)
                  Text('On this device', style: theme.textTheme.bodySmall)
                else if (user?.email case final email?)
                  Text(
                    email,
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Settings',
            icon: const Icon(Icons.settings_outlined),
            onPressed: onSettings,
          ),
          if (onSignOut != null)
            IconButton(
              tooltip: 'Log out',
              icon: const Icon(Icons.logout),
              onPressed: onSignOut,
            ),
        ],
      ),
    );
  }
}

/// A short handle for greeting: the display name, or the part of the email
/// before "@".
String userHandle(AppUser? user) {
  final name = user?.displayName?.trim();
  if (name != null && name.isNotEmpty) return name;
  final email = user?.email;
  if (email == null) return '';
  final at = email.indexOf('@');
  return at > 0 ? email.substring(0, at) : email;
}

/// Display name of [view].
String viewTitle(BookmarkView view, Labels labels) => switch (view) {
  InboxView() => 'Unsorted',
  AllView() => 'All bookmarks',
  FavoritesView() => 'Favorites',
  RemindersView() => 'Reminders',
  ArchivedView() => 'Archived',
  TrashView() => 'Trash',
  SourceView(:final source) => source.label,
  TypeView(:final type) => type.label,
  LabelView(:final kind, :final labelId) =>
    labels.find(kind, labelId)?.name ?? kind.singular,
};
