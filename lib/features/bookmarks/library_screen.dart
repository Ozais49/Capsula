import 'dart:async';

import 'package:capsula_core/domain/bookmarks/bookmark.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_repository.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_view.dart';
import 'package:capsula_core/domain/bookmarks/search_tokens.dart';
import 'package:capsula_core/domain/organization/label.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../app/dependencies.dart';
import '../../app/display_preferences.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../common/keyboard_shortcuts.dart';
import '../organization/label_picker_sheet.dart';
import '../organization/labels_builder.dart';
import 'add_bookmark_sheet.dart';
import 'bookmark_cards.dart';
import 'bookmark_display.dart';
import 'bookmark_tile.dart';
import 'library_navigation.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, this.view = BookmarkView.inbox});

  final BookmarkView view;

  static const pageSize = 30;

  static const searchFieldKey = Key('library-search');

  /// Width from which navigation is shown beside the list.
  static const wideLayout = 1000.0;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  Timer? _debounce;
  String _search = '';
  int _limit = LibraryScreen.pageSize;
  BookmarkSort? _sort;
  Stream<List<Bookmark>>? _stream;

  /// Bookmarks selected for a bulk action, by ID. Empty when not selecting.
  final Map<String, Bookmark> _selected = {};

  DisplayPreferences get _display => AppDependencies.of(context).display;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sort ??= _display.sort;
    _stream ??= _subscribe();
  }

  @override
  void didUpdateWidget(LibraryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view != widget.view) {
      _limit = LibraryScreen.pageSize;
      _selected.clear();
      _stream = _subscribe();
    }
  }

  @override
  void dispose() {
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
      });
    });
  }

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

  void _select(BookmarkView view) => context.go(AppRoutes.library(view));

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

  Future<void> _bulk(String done, Future<void> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    final count = _selected.length;
    setState(_selected.clear);
    try {
      await action();
      messenger.showSnackBar(
        SnackBar(
          content: Text('$done $count bookmark${count == 1 ? '' : 's'}'),
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
        for (final id in chosen) {
          await service.addLabelToMany(items, kind, id);
          // Re-read so later labels build on the updated lists.
          for (var i = 0; i < items.length; i++) {
            items[i] =
                await service.repository.watch(items[i].id).first ?? items[i];
          }
        }
      },
    );
  }

  Future<void> _bulkDelete() async {
    final count = _selected.length;
    final service = AppDependencies.of(context).bookmarks;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete $count bookmark${count == 1 ? '' : 's'}?'),
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
    if (confirmed != true || !mounted) return;
    final items = _selected.values.toList();
    await _bulk('Deleted', () => service.deleteMany(items));
  }

  AppBar _selectionBar(Labels labels) {
    final service = AppDependencies.of(context).bookmarks;
    final items = _selected.values.toList();
    final allFavorite = items.every((b) => b.favorite);
    return AppBar(
      leading: IconButton(
        tooltip: 'Cancel selection',
        icon: const Icon(Icons.close),
        onPressed: () => setState(_selected.clear),
      ),
      title: Text('${_selected.length} selected'),
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
            'delete' => _bulkDelete(),
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
            const PopupMenuItem(value: 'delete', child: Text('Delete')),
          ],
        ),
      ],
    );
  }

  AppBar _normalBar(Labels labels) => AppBar(
    title: Text(viewTitle(widget.view, labels)),
    actions: [
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

  Widget _items(List<Bookmark> items, Labels labels) {
    final hasMore = items.length >= _limit;
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
      ArchivedView() => const _Message(
        icon: Icons.archive_outlined,
        text: 'Nothing archived yet.',
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
