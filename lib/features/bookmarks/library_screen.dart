import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/dependencies.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../domain/bookmarks/bookmark.dart';
import '../../domain/bookmarks/bookmark_repository.dart';
import 'add_bookmark_sheet.dart';
import 'bookmark_tile.dart';

class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  static const pageSize = 30;

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  BookmarkQuery _query = const BookmarkQuery();
  int _limit = LibraryScreen.pageSize;
  Stream<List<Bookmark>>? _stream;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stream ??= _subscribe();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Stream<List<Bookmark>> _subscribe() =>
      AppDependencies.of(context).bookmarks.repository
          .watchList(_query, limit: _limit);

  void _setQuery(BookmarkQuery query) {
    if (query == _query) return;
    setState(() {
      _query = query;
      _limit = LibraryScreen.pageSize;
      _stream = _subscribe();
    });
  }

  void _onSearchChanged(String text) {
    _debounce?.cancel();
    _debounce = Timer(
      const Duration(milliseconds: 300),
      () => _setQuery(BookmarkQuery(archived: _query.archived, search: text)),
    );
  }

  void _loadMore() => setState(() {
    _limit += LibraryScreen.pageSize;
    _stream = _subscribe();
  });

  @override
  Widget build(BuildContext context) {
    final deps = AppDependencies.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Capsula'),
        actions: [
          PopupMenuButton<String>(
            tooltip: 'Menu',
            onSelected: (value) => switch (value) {
              'connection' => context.push(AppRoutes.connection),
              'sign-out' => deps.authRepository.signOut(),
              _ => null,
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'connection',
                child: Text('Connection settings'),
              ),
              PopupMenuItem(value: 'sign-out', child: Text('Sign out')),
            ],
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showAddBookmarkSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('Add'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Gap.md, Gap.sm, Gap.md, 0),
            child: SearchBar(
              controller: _searchController,
              hintText: 'Search bookmarks',
              leading: const Icon(Icons.search),
              onChanged: _onSearchChanged,
              trailing: [
                if (_searchController.text.isNotEmpty)
                  IconButton(
                    tooltip: 'Clear search',
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      _searchController.clear();
                      _onSearchChanged('');
                    },
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(Gap.md),
            child: SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('Library')),
                ButtonSegment(value: true, label: Text('Archived')),
              ],
              selected: {_query.archived},
              onSelectionChanged: (s) => _setQuery(
                BookmarkQuery(archived: s.single, search: _query.search),
              ),
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
                if (items.isEmpty) {
                  return _Message(
                    icon: _query.search.isNotEmpty
                        ? Icons.search_off
                        : Icons.bookmark_border,
                    text: _query.search.isNotEmpty
                        ? 'No bookmarks match "${_query.search}".'
                        : _query.archived
                        ? 'Nothing archived yet.'
                        : 'No bookmarks yet. Tap Add to save a link.',
                  );
                }
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
                    return BookmarkTile(
                      bookmark: bookmark,
                      onTap: () =>
                          context.push(AppRoutes.bookmark(bookmark.id)),
                    );
                  },
                );
              },
            ),
          ),
        ],
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
