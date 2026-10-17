import 'package:capsula_core/domain/bookmarks/bookmark.dart';
import 'package:capsula_core/domain/highlights/highlight.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/dependencies.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import 'highlight_widgets.dart';

/// Every highlight, newest first, grouped by the bookmark it's from.
class HighlightsScreen extends StatefulWidget {
  const HighlightsScreen({super.key});

  static const limit = 200;

  @override
  State<HighlightsScreen> createState() => _HighlightsScreenState();
}

class _HighlightsScreenState extends State<HighlightsScreen> {
  Stream<List<Highlight>>? _stream;
  final _titles = <String, Future<Bookmark?>>{};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stream ??= AppDependencies.of(context).bookmarks.highlights
        .watchAll(limit: HighlightsScreen.limit);
  }

  Future<Bookmark?> _bookmark(String id) => _titles.putIfAbsent(
    id,
    () => AppDependencies.of(context).bookmarks.repository.watch(id).first,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Highlights')),
      body: StreamBuilder<List<Highlight>>(
        stream: _stream,
        builder: (context, snapshot) {
          final highlights = snapshot.data;
          if (highlights == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (highlights.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(Gap.lg),
                child: Text(
                  'No highlights yet.\nOpen a bookmark in the reader, select '
                  'text and choose Highlight.',
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          // Group consecutive highlights from the same bookmark.
          final groups = <(String, List<Highlight>)>[];
          for (final h in highlights) {
            if (groups.isNotEmpty && groups.last.$1 == h.bookmarkId) {
              groups.last.$2.add(h);
            } else {
              groups.add((h.bookmarkId, [h]));
            }
          }
          return ListView(
            padding: const EdgeInsets.all(Gap.md),
            children: [
              for (final (bookmarkId, items) in groups) ...[
                FutureBuilder<Bookmark?>(
                  future: _bookmark(bookmarkId),
                  builder: (context, b) => Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Gap.xs,
                      Gap.md,
                      Gap.xs,
                      Gap.sm,
                    ),
                    child: Text(
                      b.data?.displayTitle ?? '',
                      style: theme.textTheme.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                for (final h in items)
                  HighlightCard(
                    highlight: h,
                    onOpen: () => context.push(AppRoutes.reader(bookmarkId)),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}
