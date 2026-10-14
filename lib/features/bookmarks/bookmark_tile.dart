import 'package:flutter/material.dart';

import '../../domain/bookmarks/bookmark.dart';
import '../../domain/organization/label.dart';
import '../organization/labels_builder.dart';
import 'bookmark_display.dart';

class BookmarkTile extends StatelessWidget {
  const BookmarkTile({
    super.key,
    required this.bookmark,
    required this.onTap,
    this.labels = const Labels(),
  });

  final Bookmark bookmark;
  final VoidCallback onTap;
  final Labels labels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = bookmark.readingStatus;
    final tags = labels.resolve(LabelKind.tag, bookmark.tagIds);

    return ListTile(
      onTap: onTap,
      leading: CircleAvatar(
        backgroundColor: theme.colorScheme.secondaryContainer,
        foregroundColor: theme.colorScheme.onSecondaryContainer,
        child: Icon(sourceIcon(bookmark.source), size: 20),
      ),
      title: Text(
        bookmark.displayTitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        [
          bookmark.sourceDomain,
          formatSavedDate(bookmark.createdAt),
          if (status != ReadingStatus.saved) status.label,
          ...tags.map((t) => '#${t.name}'),
        ].join(' · '),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
