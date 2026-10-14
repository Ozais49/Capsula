import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/dependencies.dart';
import '../../app/theme.dart';
import '../../domain/bookmarks/bookmark.dart';
import '../../domain/bookmarks/bookmark_service.dart';
import 'bookmark_display.dart';

class BookmarkDetailScreen extends StatefulWidget {
  const BookmarkDetailScreen({super.key, required this.bookmarkId});

  final String bookmarkId;

  @override
  State<BookmarkDetailScreen> createState() => _BookmarkDetailScreenState();
}

class _BookmarkDetailScreenState extends State<BookmarkDetailScreen> {
  Stream<Bookmark?>? _stream;

  BookmarkService get _service => AppDependencies.of(context).bookmarks;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stream ??= _service.repository.watch(widget.bookmarkId);
  }

  Future<void> _run(Future<void> Function() action) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not update: $e')));
    }
  }

  Future<void> _openInBrowser(Bookmark bookmark) async {
    final messenger = ScaffoldMessenger.of(context);
    final opened = await launchUrl(
      Uri.parse(bookmark.url),
      mode: LaunchMode.externalApplication,
    );
    if (!opened) {
      messenger.showSnackBar(
        const SnackBar(content: Text('No app found to open this link.')),
      );
    }
  }

  Future<void> _confirmDelete(Bookmark bookmark) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete bookmark?'),
        content: Text(bookmark.displayTitle),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    // Leave immediately; the deletion syncs in the background.
    final messenger = ScaffoldMessenger.of(context);
    final service = _service;
    Navigator.of(context).maybePop();
    service.delete(bookmark).catchError((Object e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not delete: $e')));
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Bookmark?>(
      stream: _stream,
      builder: (context, snapshot) {
        final bookmark = snapshot.data;
        final Widget body;
        if (snapshot.hasError) {
          body = Center(child: Text('Could not load: ${snapshot.error}'));
        } else if (snapshot.connectionState == ConnectionState.waiting) {
          body = const Center(child: CircularProgressIndicator());
        } else if (bookmark == null) {
          body = const Center(child: Text('This bookmark no longer exists.'));
        } else {
          body = _Details(
            bookmark: bookmark,
            onOpen: () => _openInBrowser(bookmark),
            onStatus: (s) => _run(() => _service.setReadingStatus(bookmark, s)),
          );
        }

        return Scaffold(
          appBar: AppBar(
            actions: [
              if (bookmark != null) ...[
                IconButton(
                  tooltip: bookmark.archived ? 'Unarchive' : 'Archive',
                  icon: Icon(
                    bookmark.archived
                        ? Icons.unarchive_outlined
                        : Icons.archive_outlined,
                  ),
                  onPressed: () => _run(
                    () => _service.setArchived(bookmark, !bookmark.archived),
                  ),
                ),
                IconButton(
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _confirmDelete(bookmark),
                ),
              ],
            ],
          ),
          body: body,
        );
      },
    );
  }
}

class _Details extends StatelessWidget {
  const _Details({
    required this.bookmark,
    required this.onOpen,
    required this.onStatus,
  });

  final Bookmark bookmark;
  final VoidCallback onOpen;
  final ValueChanged<ReadingStatus> onStatus;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.labelLarge?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    return ListView(
      padding: const EdgeInsets.all(Gap.lg),
      children: [
        Text(bookmark.displayTitle, style: theme.textTheme.headlineSmall),
        const SizedBox(height: Gap.md),
        Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.sm,
          children: [
            Chip(
              avatar: Icon(sourceIcon(bookmark.source), size: 18),
              label: Text(bookmark.source.label),
            ),
            Chip(label: Text(bookmark.sourceDomain)),
            if (bookmark.inInbox) const Chip(label: Text('Inbox')),
            if (bookmark.archived) const Chip(label: Text('Archived')),
          ],
        ),
        const SizedBox(height: Gap.sm),
        Text(
          'Saved ${formatSavedDate(bookmark.createdAt).toLowerCase()}',
          style: theme.textTheme.bodySmall,
        ),
        if (bookmark.description case final description?) ...[
          const SizedBox(height: Gap.md),
          Text(description),
        ],
        const SizedBox(height: Gap.lg),
        Text('Status', style: labelStyle),
        const SizedBox(height: Gap.sm),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SegmentedButton<ReadingStatus>(
            segments: [
              for (final s in ReadingStatus.values)
                ButtonSegment(value: s, label: Text(s.label)),
            ],
            selected: {bookmark.readingStatus},
            onSelectionChanged: (s) => onStatus(s.single),
          ),
        ),
        const SizedBox(height: Gap.lg),
        Text('Link', style: labelStyle),
        const SizedBox(height: Gap.xs),
        SelectableText(bookmark.url, style: theme.textTheme.bodySmall),
        const SizedBox(height: Gap.xl),
        FilledButton.icon(
          onPressed: onOpen,
          icon: const Icon(Icons.open_in_new),
          label: const Text('Open in browser'),
        ),
      ],
    );
  }
}
