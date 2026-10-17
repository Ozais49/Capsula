import 'package:flutter/material.dart';

import 'package:capsula_core/domain/bookmarks/bookmark.dart';
import 'package:capsula_core/domain/organization/label.dart';

import '../organization/labels_builder.dart';
import 'bookmark_display.dart';

class BookmarkTile extends StatelessWidget {
  const BookmarkTile({
    super.key,
    required this.bookmark,
    required this.onTap,
    this.onLongPress,
    this.selected = false,
    this.labels = const Labels(),
  });

  final Bookmark bookmark;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// Shown with a check mark during bulk selection.
  final bool selected;
  final Labels labels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = bookmark.readingStatus;
    final tags = labels.resolve(LabelKind.tag, bookmark.tagIds);

    return ListTile(
      onTap: onTap,
      onLongPress: onLongPress,
      selected: selected,
      leading: selected
          ? CircleAvatar(
              backgroundColor: theme.colorScheme.primary,
              foregroundColor: theme.colorScheme.onPrimary,
              child: const Icon(Icons.check, semanticLabel: 'Selected'),
            )
          : _Leading(bookmarkSource(bookmark, labels.sources), bookmark),
      trailing: bookmark.favorite
          ? const Icon(
              Icons.star,
              color: Colors.amber,
              semanticLabel: 'Favorite',
            )
          : null,
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
          if (bookmark.remindAt case final at?)
            '${bookmark.isDue(DateTime.now()) ? 'Due' : 'Remind'} ${formatReminder(at)}',
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
  const _Leading(this.source, this.bookmark);

  final ({String name, IconData icon}) source;
  final Bookmark bookmark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final icon = CircleAvatar(
      backgroundColor: scheme.secondaryContainer,
      foregroundColor: scheme.onSecondaryContainer,
      child: Icon(
        source.icon,
        size: 20,
        semanticLabel: source.name,
      ),
    );
    final image = bookmark.imageUrl;
    if (image == null) return icon;

    return Semantics(
      label: source.name,
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
