import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/dependencies.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../domain/bookmarks/bookmark.dart';
import '../../domain/bookmarks/bookmark_repository.dart';
import '../../domain/bookmarks/bookmark_view.dart';
import '../../domain/bookmarks/search_tokens.dart';
import '../../domain/organization/label.dart';
import '../organization/labels_builder.dart';
import 'add_bookmark_sheet.dart';
import 'bookmark_tile.dart';
import 'library_navigation.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key, this.view = BookmarkView.inbox});

  final BookmarkView view;

  static const pageSize = 30;

  /// Width from which navigation is shown beside the list.
  static const wideLayout = 1000.0;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  String _search = '';
  int _limit = LibraryScreen.pageSize;
  Stream<List<Bookmark>>? _stream;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stream ??= _subscribe();
  }

  @override
  void didUpdateWidget(LibraryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view != widget.view) {
      _limit = LibraryScreen.pageSize;
      _stream = _subscribe();
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Stream<List<Bookmark>> _subscribe() =>
      AppDependencies.of(context).bookmarks.repository.watchList(
        BookmarkQuery(view: widget.view, search: _search),
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

  void _select(BookmarkView view) => context.go(AppRoutes.library(view));

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

  @override
  Widget build(BuildContext context) {
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
            appBar: AppBar(title: Text(viewTitle(widget.view, labels))),
            drawer: wide ? null : Drawer(child: SafeArea(child: navigation)),
            floatingActionButton: FloatingActionButton.extended(
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
          child: SearchBar(
            controller: _searchController,
            hintText: 'Search ${viewTitle(widget.view, labels).toLowerCase()}',
            leading: const Icon(Icons.search),
            onChanged: _onSearchChanged,
            trailing: [
              ListenableBuilder(
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
            ],
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

              final inInbox = widget.view is InboxView;
              final hasMore = items.length >= _limit;
              return ListView.builder(
                padding: const EdgeInsets.only(bottom: 88),
                itemCount: items.length + (hasMore ? 1 : 0),
                itemBuilder: (context, i) {
                  if (i == items.length) {
                    return Padding(
                      padding: const EdgeInsets.all(Gap.md),
                      child: Center(
                        child: OutlinedButton(
                          onPressed: _loadMore,
                          child: const Text('Load more'),
                        ),
                      ),
                    );
                  }
                  final bookmark = items[i];
                  final tile = BookmarkTile(
                    bookmark: bookmark,
                    labels: labels,
                    onTap: () => context.push(AppRoutes.bookmark(bookmark.id)),
                  );
                  if (!inInbox) return tile;
                  return Dismissible(
                    key: ValueKey(bookmark.id),
                    background: const _SwipeBackground(),
                    onDismissed: (_) => _removeFromInbox(bookmark),
                    child: tile,
                  );
                },
              );
            },
          ),
        ),
      ],
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
      ArchivedView() => const _Message(
        icon: Icons.archive_outlined,
        text: 'Nothing archived yet.',
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
