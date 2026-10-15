import 'package:capsula_core/domain/bookmarks/bookmark.dart';
import 'package:flutter/material.dart';

import '../../app/theme.dart';
import 'bookmark_display.dart';

/// Cover image, or a tinted panel with the source icon when there is none.
class BookmarkCover extends StatelessWidget {
  const BookmarkCover({super.key, required this.bookmark});

  final Bookmark bookmark;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(
      color: scheme.secondaryContainer,
      child: Center(
        child: Icon(
          sourceIcon(bookmark.source),
          size: 36,
          color: scheme.onSecondaryContainer,
          semanticLabel: bookmark.source.label,
        ),
      ),
    );
    final image = bookmark.imageUrl;
    if (image == null) return placeholder;
    return Image.network(
      image,
      fit: BoxFit.cover,
      excludeFromSemantics: true,
      webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
      errorBuilder: (_, _, _) => placeholder,
    );
  }
}

/// Raindrop-style card: cover, title, excerpt, source and date.
class BookmarkCard extends StatelessWidget {
  const BookmarkCard({
    super.key,
    required this.bookmark,
    required this.onTap,
    required this.onLongPress,
    this.selected = false,
    this.compact = false,
  });

  final Bookmark bookmark;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final bool selected;

  /// Grid cells: shorter text, cover fills the remaining space.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final meta = [
      bookmark.sourceDomain,
      formatSavedDate(bookmark.createdAt),
    ].join(' · ');

    final cover = Stack(
      fit: StackFit.expand,
      children: [
        BookmarkCover(bookmark: bookmark),
        if (bookmark.favorite)
          const Positioned(
            top: Gap.sm,
            right: Gap.sm,
            child: _Badge(icon: Icons.star, label: 'Favorite'),
          ),
        if (selected)
          ColoredBox(
            color: scheme.primary.withValues(alpha: 0.35),
            child: Center(
              child: Icon(
                Icons.check_circle,
                color: scheme.onPrimary,
                size: 40,
                semanticLabel: 'Selected',
              ),
            ),
          ),
      ],
    );

    final text = Padding(
      padding: const EdgeInsets.all(Gap.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            bookmark.displayTitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall,
          ),
          if (!compact && bookmark.description != null) ...[
            const SizedBox(height: Gap.xs),
            Text(
              bookmark.description!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: Gap.xs),
          Text(
            meta,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );

    return Card(
      clipBehavior: Clip.antiAlias,
      shape: selected
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: scheme.primary, width: 2),
            )
          : null,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: cover),
                  text,
                ],
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (bookmark.imageUrl != null)
                    AspectRatio(aspectRatio: 16 / 9, child: cover)
                  else if (selected || bookmark.favorite)
                    SizedBox(height: 56, child: cover),
                  text,
                ],
              ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: const BoxDecoration(
      color: Colors.black54,
      shape: BoxShape.circle,
    ),
    child: Padding(
      padding: const EdgeInsets.all(Gap.xs),
      child: Icon(icon, size: 16, color: Colors.amber, semanticLabel: label),
    ),
  );
}
