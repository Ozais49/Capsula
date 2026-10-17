import 'dart:async';

import 'package:capsula_core/domain/bookmarks/bookmark.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_repository.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_filters.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_view.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_service.dart';
import 'package:capsula_core/domain/bookmarks/search_tokens.dart';
import 'package:capsula_core/domain/bookmarks/shared_content.dart';
import 'package:capsula_core/domain/bookmarks/url_normalizer.dart';
import 'package:capsula_core/domain/organization/label.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../app/dependencies.dart';
import '../../app/display_preferences.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../common/sync_indicator.dart';
import 'filter_bar.dart';
import 'trash_actions.dart';
import '../common/keyboard_shortcuts.dart';
import '../organization/label_picker_sheet.dart';
import '../organization/labels_builder.dart';
import 'add_bookmark_sheet.dart';
import 'bookmark_cards.dart';
import 'bookmark_display.dart';
import 'bookmark_tile.dart';
import 'library_navigation.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({
    super.key,
    this.view = BookmarkView.inbox,
    this.filters = BookmarkFilters.none,
  });

  final BookmarkView view;

  /// Narrows the view by source, tags, kind and status.
  final BookmarkFilters filters;

  static const pageSize = 30;

  static const searchFieldKey = Key('library-search');

  /// The last copied link offered for saving, so each is offered once per
  /// app run even as the library screen is rebuilt.
  static String? lastOfferedLink;

  /// Width from which navigation is shown beside the list.
  static const wideLayout = 1000.0;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with WidgetsBindingObserver {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _debounce;
  String _search = '';
  int _limit = LibraryScreen.pageSize;
  BookmarkSort? _sort;
  Stream<List<Bookmark>>? _stream;

  /// Searching the text of saved pages instead of titles and links.
  bool _fullText = false;
  Future<List<Bookmark>>? _fullTextResults;

  /// Bookmarks selected for a bulk action, by ID. Empty when not selecting.
  final Map<String, Bookmark> _selected = {};

  DisplayPreferences get _display => AppDependencies.of(context).display;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sort ??= _display.sort;
    _stream ??= _subscribe();
    if (!_observing) {
      _observing = true;
      WidgetsBinding.instance.addObserver(this);
      _offerCopiedLink();
    }
  }

  bool _observing = false;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _offerCopiedLink();
  }

  /// Offers to save a link the user copied in another app.
  Future<void> _offerCopiedLink() async {
    final deps = AppDependencies.of(context);
    if (!deps.display.offerCopiedLinks) return;
    final text = await deps.clipboard.read();
    if (text == null || text.trim().isEmpty || !mounted) return;
    final links = extractSharedLinks(SharedContent(text: text));
    if (links.urls.isEmpty) return;
    final url = links.urls.first;
    final canonical = canonicalizeUrl(url);
    if (canonical == LibraryScreen.lastOfferedLink) return;
    LibraryScreen.lastOfferedLink = canonical;
    try {
      final existing = await deps.bookmarks.repository.findByCanonicalUrl(
        canonical,
      );
      if (existing != null || !mounted) return;
    } on Object {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 8),
        content: Text('Save the link you copied? ${url.host}'),
        action: SnackBarAction(
          label: 'Save',
          onPressed: () async {
            try {
              final result = await deps.bookmarks.save(
                url.toString(),
                title: links.title,
              );
              if (result case Saved(:final bookmark)) {
                deps.bookmarks
                    .fetchDetails(
                      bookmark,
                      deps.pageInfo,
                      fallbackTitle: links.title,
                    )
                    .ignore();
                messenger.showSnackBar(
                  const SnackBar(content: Text('Saved to Inbox')),
                );
              }
            } on Object catch (e) {
              messenger.showSnackBar(
                SnackBar(content: Text('Could not save: $e')),
              );
            }
          },
        ),
      ),
    );
  }

  @override
  void didUpdateWidget(LibraryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view != widget.view || oldWidget.filters != widget.filters) {
      _limit = LibraryScreen.pageSize;
      _selected.clear();
      _stream = _subscribe();
      _fullTextResults = _searchPages();
    }
  }

  @override
  void dispose() {
    if (_observing) WidgetsBinding.instance.removeObserver(this);
    _debounce?.cancel();
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Stream<List<Bookmark>> _subscribe() =>
      AppDependencies.of(context).bookmarks.repository.watchList(
        BookmarkQuery(
          view: widget.view,
          search: _search,
          sort: _sort ?? BookmarkSort.newest,
          filters: widget.filters,
        ),
        limit: _limit,
      );

  void _onSearchChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted || text == _search) return;
      setState(() {
        _search = text;
        _limit = LibraryScreen.pageSize;
        _stream = _subscribe();
        _fullTextResults = _searchPages();
      });
    });
  }

  Future<List<Bookmark>>? _searchPages() =>
      _fullText && _search.trim().isNotEmpty
      ? AppDependencies.of(context).bookmarks
            .searchContent(_search, view: widget.view)
            .then((found) => found.where(widget.filters.matches).toList())
      : null;

  void _setFullText(bool on) => setState(() {
    _fullText = on;
    _fullTextResults = _searchPages();
  });

  void _loadMore() => setState(() {
    _limit += LibraryScreen.pageSize;
    _stream = _subscribe();
  });

  void _setSort(BookmarkSort sort) {
    _display.setSort(sort);
    setState(() {
      _sort = sort;
      _limit = LibraryScreen.pageSize;
      _stream = _subscribe();
    });
  }

  // Filters stay on when moving between views.
  void _select(BookmarkView view) =>
      context.go(AppRoutes.library(view, widget.filters));

  void _setFilters(BookmarkFilters filters) =>
      context.go(AppRoutes.library(widget.view, filters));

  void _open(Bookmark b) =>
      _selected.isEmpty ? context.push(AppRoutes.bookmark(b.id)) : _toggle(b);

  void _toggle(Bookmark b) => setState(() {
    if (_selected.remove(b.id) == null) _selected[b.id] = b;
  });

  Future<void> _removeFromInbox(Bookmark bookmark) async {
    final service = AppDependencies.of(context).bookmarks;
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Removed from Inbox'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => service.setInInbox(bookmark, true).ignore(),
        ),
      ),
    );
    service.setInInbox(bookmark, false).catchError((Object e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not update: $e')));
    });
  }

  // ---------------------------------------------------------------------------
  // Bulk actions

  Future<void> _bulk(
    String done,
    Future<void> Function() action, {
    Future<void> Function()? undo,
  }) async {
    final messenger = ScaffoldMessenger.of(context);
    final count = _selected.length;
    setState(_selected.clear);
    try {
      await action();
      messenger.showSnackBar(
        SnackBar(
          content: Text('$done $count bookmark${count == 1 ? '' : 's'}'),
          action: undo == null
              ? null
              : SnackBarAction(label: 'Undo', onPressed: () => undo().ignore()),
        ),
      );
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not update: $e')));
    }
  }

  Future<void> _bulkLabel(LabelKind kind, Labels labels) async {
    final service = AppDependencies.of(context).bookmarks;
    final chosen = await showLabelPicker(
      context,
      kind: kind,
      available: labels.of(kind),
      selected: const [],
    );
    if (chosen == null || chosen.isEmpty || !mounted) return;
    final items = _selected.values.toList();
    await _bulk(
      kind == LabelKind.tag ? 'Tagged' : 'Added to collection:',
      () async {
        // Each change applies to the stored copy, so labels add up.
        for (final id in chosen) {
          await service.addLabelToMany(items, kind, id);
        }
      },
    );
  }

  Future<void> _bulkTrash() {
    final service = AppDependencies.of(context).bookmarks;
    final items = _selected.values.toList();
    return _bulk(
      'Moved to Trash:',
      () => service.moveToTrash(items),
      undo: () => service.restore(items),
    );
  }

  Future<void> _bulkDeleteForever() async {
    final count = _selected.length;
    final service = AppDependencies.of(context).bookmarks;
    final confirmed = await confirmDeleteForever(context, count);
    if (!confirmed || !mounted) return;
    final items = _selected.values.toList();
    await _bulk('Deleted', () => service.deleteMany(items));
  }

  Future<void> _emptyTrash() async {
    final service = AppDependencies.of(context).bookmarks;
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Empty Trash?'),
        content: const Text(
          'Everything in the Trash is deleted for good, with its highlights.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(88, 40)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Empty Trash'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      final count = await service.emptyTrash();
      messenger.showSnackBar(
        SnackBar(
          content: Text('Deleted $count bookmark${count == 1 ? '' : 's'}'),
        ),
      );
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not delete: $e')));
    }
  }

  AppBar _selectionBar(Labels labels) {
    final service = AppDependencies.of(context).bookmarks;
    final items = _selected.values.toList();
    final allFavorite = items.every((b) => b.favorite);
    final leading = IconButton(
      tooltip: 'Cancel selection',
      icon: const Icon(Icons.close),
      onPressed: () => setState(_selected.clear),
    );
    final title = Text('${_selected.length} selected');
    if (widget.view is TrashView) {
      return AppBar(
        leading: leading,
        title: title,
        actions: [
          IconButton(
            tooltip: 'Restore',
            icon: const Icon(Icons.restore_from_trash_outlined),
            onPressed: () => _bulk('Restored', () => service.restore(items)),
          ),
          IconButton(
            tooltip: 'Delete forever',
            icon: const Icon(Icons.delete_forever_outlined),
            onPressed: _bulkDeleteForever,
          ),
        ],
      );
    }
    return AppBar(
      leading: leading,
      title: title,
      actions: [
        IconButton(
          tooltip: allFavorite ? 'Remove from favorites' : 'Add to favorites',
          icon: Icon(allFavorite ? Icons.star : Icons.star_outline),
          onPressed: () => _bulk(
            allFavorite ? 'Unfavorited' : 'Favorited',
            () => service.updateMany(
              items,
              (b) => b.copyWith(favorite: !allFavorite),
            ),
          ),
        ),
        IconButton(
          tooltip: 'Add to collection',
          icon: const Icon(Icons.create_new_folder_outlined),
          onPressed: () => _bulkLabel(LabelKind.collection, labels),
        ),
        IconButton(
          tooltip: 'Add tags',
          icon: const Icon(Icons.new_label_outlined),
          onPressed: () => _bulkLabel(LabelKind.tag, labels),
        ),
        PopupMenuButton<String>(
          tooltip: 'More actions',
          onSelected: (action) => switch (action) {
            'done' => _bulk(
              'Removed from Inbox:',
              () =>
                  service.updateMany(items, (b) => b.copyWith(inInbox: false)),
            ),
            'archive' => _bulk(
              'Archived',
              () => service.updateMany(
                items,
                (b) => b.copyWith(archived: true, inInbox: false),
              ),
            ),
            'unarchive' => _bulk(
              'Unarchived',
              () =>
                  service.updateMany(items, (b) => b.copyWith(archived: false)),
            ),
            'trash' => _bulkTrash(),
            _ => null,
          },
          itemBuilder: (_) => [
            const PopupMenuItem(
              value: 'done',
              child: Text('Remove from Inbox'),
            ),
            if (widget.view is ArchivedView)
              const PopupMenuItem(value: 'unarchive', child: Text('Unarchive'))
            else
              const PopupMenuItem(value: 'archive', child: Text('Archive')),
            const PopupMenuItem(value: 'trash', child: Text('Move to Trash')),
          ],
        ),
      ],
    );
  }

  AppBar _normalBar(Labels labels) => AppBar(
    title: Text(viewTitle(widget.view, labels)),
    actions: [
      const SyncIndicator(),
      if (widget.view is TrashView)
        IconButton(
          tooltip: 'Empty Trash',
          icon: const Icon(Icons.delete_sweep_outlined),
          onPressed: _emptyTrash,
        ),
      ListenableBuilder(
        listenable: _display,
        builder: (context, _) => PopupMenuButton<Object>(
          tooltip: 'Display',
          icon: Icon(switch (_display.layout) {
            LibraryLayout.list => Icons.view_list_outlined,
            LibraryLayout.cards => Icons.view_agenda_outlined,
            LibraryLayout.grid => Icons.grid_view,
          }),
          onSelected: (choice) => switch (choice) {
            final LibraryLayout l => _display.setLayout(l),
            final BookmarkSort s => _setSort(s),
            _ => null,
          },
          itemBuilder: (_) => [
            for (final l in LibraryLayout.values)
              CheckedPopupMenuItem(
                value: l,
                checked: _display.layout == l,
                child: Text(l.label),
              ),
            const PopupMenuDivider(),
            for (final s in BookmarkSort.values)
              CheckedPopupMenuItem(
                value: s,
                checked: _sort == s,
                child: Text(s.label),
              ),
          ],
        ),
      ),
    ],
  );

  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    // "/" searches and "n" adds a bookmark, for keyboard users on the web.
    return SingleKeyShortcuts(
      bindings: {
        LogicalKeyboardKey.slash: _searchFocus.requestFocus,
        LogicalKeyboardKey.keyN: () => showAddBookmarkSheet(context),
      },
      child: _build(context),
    );
  }

  Widget _build(BuildContext context) {
    return LabelsBuilder(
      builder: (context, labels) => LayoutBuilder(
        builder: (context, constraints) {
          final wide = constraints.maxWidth >= LibraryScreen.wideLayout;
          final navigation = LibraryNavigation(
            selected: widget.view,
            labels: labels,
            onSelect: _select,
          );
          final scaffold = Scaffold(
            appBar: _selected.isEmpty
                ? _normalBar(labels)
                : _selectionBar(labels),
            drawer: wide ? null : Drawer(child: SafeArea(child: navigation)),
            floatingActionButton: _selected.isNotEmpty
                ? null
                : FloatingActionButton.extended(
                    onPressed: () => showAddBookmarkSheet(context),
                    icon: const Icon(Icons.add),
                    label: const Text('Add'),
                  ),
            body: _body(labels),
          );
          if (!wide) return scaffold;
          return Row(
            children: [
              SizedBox(
                width: 300,
                child: Material(child: SafeArea(child: navigation)),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: scaffold),
            ],
          );
        },
      ),
    );
  }

  Widget _body(Labels labels) {
    final matchingLabels = searchWords(_search).isEmpty
        ? const <Label>[]
        : [
            ...labels.collections,
            ...labels.tags,
          ].where((l) => matchesSearch([l.name], _search)).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, Gap.sm),
          // A TextField rather than SearchBar: its tap target covers the
          // whole box, not just the line of text.
          child: TextField(
            key: LibraryScreen.searchFieldKey,
            controller: _searchController,
            focusNode: _searchFocus,
            onChanged: _onSearchChanged,
            textInputAction: TextInputAction.search,
            decoration: InputDecoration(
              hintText:
                  'Search ${viewTitle(widget.view, labels).toLowerCase()}',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(28),
                borderSide: BorderSide.none,
              ),
              suffixIcon: ListenableBuilder(
                listenable: _searchController,
                builder: (context, _) => _searchController.text.isEmpty
                    ? const SizedBox.shrink()
                    : IconButton(
                        tooltip: 'Clear search',
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          _searchController.clear();
                          _onSearchChanged('');
                        },
                      ),
              ),
            ),
          ),
        ),
        FilterBar(
          filters: widget.filters,
          tags: labels.of(LabelKind.tag),
          sources: labels.sources,
          onChanged: _setFilters,
        ),
        if (_search.trim().isNotEmpty &&
            AppDependencies.of(context).bookmarks.hasContentIndex)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gap.md),
            child: Align(
              alignment: Alignment.centerLeft,
              child: FilterChip(
                avatar: const Icon(Icons.find_in_page_outlined, size: 18),
                label: const Text('Page text'),
                tooltip: 'Search inside saved pages',
                selected: _fullText,
                onSelected: _setFullText,
              ),
            ),
          ),
        if (matchingLabels.isNotEmpty)
          SizedBox(
            height: 48,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: Gap.md),
              children: [
                for (final label in matchingLabels)
                  Padding(
                    padding: const EdgeInsets.only(right: Gap.sm),
                    child: ActionChip(
                      avatar: Icon(
                        label.kind == LabelKind.tag
                            ? Icons.label_outline
                            : Icons.folder_outlined,
                        size: 18,
                      ),
                      label: Text(label.name),
                      onPressed: () {
                        _searchController.clear();
                        _onSearchChanged('');
                        _select(LabelView(label.kind, label.id));
                      },
                    ),
                  ),
              ],
            ),
          ),
        if (_fullTextResults case final pages?)
          Expanded(
            child: FutureBuilder<List<Bookmark>>(
              future: pages,
              builder: (context, snapshot) {
                final items = snapshot.data;
                if (snapshot.hasError) {
                  return _Message(
                    icon: Icons.error_outline,
                    text: 'Could not search pages.\n${snapshot.error}',
                  );
                }
                if (items == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (items.isEmpty) {
                  return _Message(
                    icon: Icons.find_in_page_outlined,
                    text:
                        'No saved page mentions "$_search".\n'
                        "Pages are searchable after they've been opened in "
                        'the reader or indexed under Maintenance.',
                  );
                }
                return ListenableBuilder(
                  listenable: _display,
                  builder: (context, _) =>
                      _items(items, labels, allowMore: false),
                );
              },
            ),
          )
        else
          Expanded(
            child: StreamBuilder<List<Bookmark>>(
              stream: _stream,
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _Message(
                    icon: Icons.error_outline,
                    text: 'Could not load bookmarks.\n${snapshot.error}',
                  );
                }
                final items = snapshot.data;
                if (items == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (items.isEmpty) return _empty();
                // Keep selected bookmarks current as they change.
                for (final b in items) {
                  if (_selected.containsKey(b.id)) _selected[b.id] = b;
                }
                return ListenableBuilder(
                  listenable: _display,
                  builder: (context, _) => _items(items, labels),
                );
              },
            ),
          ),
      ],
    );
  }

  Widget _items(List<Bookmark> items, Labels labels, {bool allowMore = true}) {
    final hasMore = allowMore && items.length >= _limit;
    final footer = SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Gap.md, Gap.md, Gap.md, 88),
        child: hasMore
            ? Center(
                child: OutlinedButton(
                  onPressed: _loadMore,
                  child: const Text('Load more'),
                ),
              )
            : const SizedBox.shrink(),
      ),
    );

    final Widget content = switch (_display.layout) {
      LibraryLayout.list => SliverList.builder(
        itemCount: items.length,
        itemBuilder: (context, i) => _listItem(items[i], labels),
      ),
      LibraryLayout.cards => SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.md),
        sliver: SliverList.builder(
          itemCount: items.length,
          itemBuilder: (context, i) => Padding(
            padding: const EdgeInsets.only(bottom: Gap.sm),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 720),
                child: BookmarkCard(
                  bookmark: items[i],
                  selected: _selected.containsKey(items[i].id),
                  onTap: () => _open(items[i]),
                  onLongPress: () => _toggle(items[i]),
                ),
              ),
            ),
          ),
        ),
      ),
      LibraryLayout.grid => SliverPadding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.md),
        sliver: SliverGrid.builder(
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 240,
            mainAxisSpacing: Gap.sm,
            crossAxisSpacing: Gap.sm,
            childAspectRatio: 0.78,
          ),
          itemCount: items.length,
          itemBuilder: (context, i) => BookmarkCard(
            bookmark: items[i],
            compact: true,
            selected: _selected.containsKey(items[i].id),
            onTap: () => _open(items[i]),
            onLongPress: () => _toggle(items[i]),
          ),
        ),
      ),
    };
    return CustomScrollView(slivers: [content, footer]);
  }

  Widget _listItem(Bookmark bookmark, Labels labels) {
    final selected = _selected.containsKey(bookmark.id);
    final tile = BookmarkTile(
      bookmark: bookmark,
      labels: labels,
      selected: selected,
      onTap: () => _open(bookmark),
      onLongPress: () => _toggle(bookmark),
    );
    if (widget.view is! InboxView || _selected.isNotEmpty) return tile;
    return Dismissible(
      key: ValueKey(bookmark.id),
      background: const _SwipeBackground(),
      onDismissed: (_) => _removeFromInbox(bookmark),
      // Swiping isn't available to screen reader users.
      child: Semantics(
        customSemanticsActions: {
          const CustomSemanticsAction(label: 'Remove from Inbox'): () =>
              _removeFromInbox(bookmark),
        },
        child: tile,
      ),
    );
  }

  Widget _empty() {
    if (_search.isNotEmpty) {
      return _Message(
        icon: Icons.search_off,
        text: 'No bookmarks match "$_search".',
      );
    }
    if (!widget.filters.isEmpty) {
      return const _Message(
        icon: Icons.filter_alt_off_outlined,
        text: 'No bookmarks match these filters.',
      );
    }
    return switch (widget.view) {
      InboxView() => const _Message(
        icon: Icons.inbox_outlined,
        text: 'Inbox is empty.\nShare a link to Capsula or tap Add.',
      ),
      AllView() => const _Message(
        icon: Icons.bookmark_border,
        text: 'No bookmarks yet. Tap Add to save a link.',
      ),
      FavoritesView() => const _Message(
        icon: Icons.star_outline,
        text: 'No favorites yet.\nTap the star on a bookmark to add it here.',
      ),
      RemindersView() => const _Message(
        icon: Icons.alarm,
        text: 'No reminders.\nOpen a bookmark and tap Remind me.',
      ),
      ArchivedView() => const _Message(
        icon: Icons.archive_outlined,
        text: 'Nothing archived yet.',
      ),
      TrashView() => const _Message(
        icon: Icons.delete_outline,
        text:
            'Trash is empty.\nDeleted bookmarks stay here for '
            '${BookmarkService.trashDays} days.',
      ),
      TypeView(:final type) => _Message(
        icon: typeIcon(type),
        text: 'No ${type.label.toLowerCase()} yet.',
      ),
      SourceView(:final source) => _Message(
        icon: Icons.public,
        text: 'No ${source.label} bookmarks.',
      ),
      LabelView(:final kind) => _Message(
        icon: kind == LabelKind.tag
            ? Icons.label_outline
            : Icons.folder_outlined,
        text: 'Nothing here yet.\nAdd bookmarks from their detail page.',
      ),
    };
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
        child: Row(
          children: [
            Icon(Icons.done, color: scheme.onPrimaryContainer),
            const SizedBox(width: Gap.sm),
            Text('Done', style: TextStyle(color: scheme.onPrimaryContainer)),
          ],
        ),
      ),
    );
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Gap.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: theme.colorScheme.outline),
            const SizedBox(height: Gap.md),
            Text(text, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
