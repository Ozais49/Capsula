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
    final status = bookmark.readingStatus;
    final tags = labels.resolve(LabelKind.tag, bookmark.tagIds);

    return ListTile(
      onTap: onTap,
      leading: _Leading(bookmark),
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

/// The page's image when known, otherwise the source icon. Screen readers
/// hear the source name either way.
class _Leading extends StatelessWidget {
  const _Leading(this.bookmark);

  final Bookmark bookmark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final icon = CircleAvatar(
      backgroundColor: scheme.secondaryContainer,
      foregroundColor: scheme.onSecondaryContainer,
      child: Icon(
        sourceIcon(bookmark.source),
        size: 20,
        semanticLabel: bookmark.source.label,
      ),
    );
    final image = bookmark.imageUrl;
    if (image == null) return icon;

    return Semantics(
      label: bookmark.source.label,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: SizedBox.square(
          dimension: 40,
          child: Image.network(
            image,
            fit: BoxFit.cover,
            excludeFromSemantics: true,
            webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
            errorBuilder: (_, _, _) => icon,
          ),
        ),
      ),
    );
  }
}
