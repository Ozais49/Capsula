import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../app/dependencies.dart';
import '../../app/router.dart';
import '../../app/theme.dart';

import 'package:capsula_core/domain/bookmarks/bookmark.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_service.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_view.dart';
import 'package:capsula_core/domain/organization/label.dart';

import 'trash_actions.dart';
import '../common/open_link.dart';
import '../common/text_prompt.dart';
import '../highlights/highlight_widgets.dart';

import 'package:capsula_core/domain/highlights/highlight.dart';

import '../organization/label_picker_sheet.dart';
import '../organization/labels_builder.dart';
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

  Future<void> _editLabels(
    Bookmark bookmark,
    LabelKind kind,
    List<Label> available,
  ) async {
    final chosen = await showLabelPicker(
      context,
      kind: kind,
      available: available,
      selected: bookmark.labelIds(kind),
    );
    if (chosen == null || !mounted) return;
    await _run(() => _service.setLabels(bookmark, kind, chosen));
  }

  Future<void> _editTitle(Bookmark bookmark) async {
    final title = await promptText(
      context,
      title: 'Edit title',
      label: 'Title',
      initial: bookmark.title,
      maxLength: 1000,
    );
    if (title == null || title.trim().isEmpty || !mounted) return;
    await _run(() => _service.rename(bookmark, title));
  }

  /// Moves the bookmark to the Trash and leaves, offering Undo.
  void _moveToTrash(Bookmark bookmark) {
    final messenger = ScaffoldMessenger.of(context);
    final service = _service;
    Navigator.of(context).maybePop();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Moved to Trash'),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () => service.restore([bookmark]).ignore(),
        ),
      ),
    );
    service.moveToTrash([bookmark]).catchError((Object e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not delete: $e')));
    });
  }

  Future<void> _deleteForever(Bookmark bookmark) async {
    if (!await confirmDeleteForever(context, 1) || !mounted) return;
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
            onOpen: () => openExternal(context, Uri.parse(bookmark.url)),
            onRead: () => context.push(AppRoutes.reader(bookmark.id)),
            onStatus: (s) => _run(() => _service.setReadingStatus(bookmark, s)),
            onInbox: (inInbox) =>
                _run(() => _service.setInInbox(bookmark, inInbox)),
            onEditLabels: (kind, labels) => _editLabels(bookmark, kind, labels),
          );
        }

        return Scaffold(
          appBar: AppBar(
            actions: [
              if (bookmark != null && bookmark.isTrashed) ...[
                IconButton(
                  tooltip: 'Restore',
                  icon: const Icon(Icons.restore_from_trash_outlined),
                  onPressed: () => _run(() => _service.restore([bookmark])),
                ),
                IconButton(
                  tooltip: 'Delete forever',
                  icon: const Icon(Icons.delete_forever_outlined),
                  onPressed: () => _deleteForever(bookmark),
                ),
              ] else if (bookmark != null) ...[
                IconButton(
                  tooltip: bookmark.favorite
                      ? 'Remove from favorites'
                      : 'Add to favorites',
                  icon: Icon(
                    bookmark.favorite ? Icons.star : Icons.star_outline,
                    color: bookmark.favorite ? Colors.amber : null,
                  ),
                  onPressed: () => _run(
                    () => _service.setFavorite(bookmark, !bookmark.favorite),
                  ),
                ),
                IconButton(
                  tooltip: 'Edit title',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed: () => _editTitle(bookmark),
                ),
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
                  tooltip: 'Move to Trash',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => _moveToTrash(bookmark),
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
    required this.onRead,
    required this.onStatus,
    required this.onInbox,
    required this.onEditLabels,
  });

  final Bookmark bookmark;
  final VoidCallback onOpen;
  final VoidCallback onRead;
  final ValueChanged<ReadingStatus> onStatus;
  final ValueChanged<bool> onInbox;
  final void Function(LabelKind kind, List<Label> available) onEditLabels;

  @override
  Widget build(BuildContext context) =>
      LabelsBuilder(builder: (context, labels) => _build(context, labels));

  Widget _labelSection(
    BuildContext context,
    Labels labels,
    LabelKind kind,
    IconData icon,
    TextStyle? labelStyle,
  ) {
    final assigned = labels.resolve(kind, bookmark.labelIds(kind));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: Gap.lg),
        Text(kind.plural, style: labelStyle),
        const SizedBox(height: Gap.sm),
        Wrap(
          spacing: Gap.sm,
          runSpacing: Gap.sm,
          children: [
            for (final label in assigned)
              ActionChip(
                avatar: Icon(icon, size: 18),
                label: Text(label.name),
                onPressed: () =>
                    context.go(AppRoutes.library(LabelView(kind, label.id))),
              ),
            ActionChip(
              avatar: const Icon(Icons.edit_outlined, size: 18),
              label: Text(
                assigned.isEmpty
                    ? 'Add ${kind.singular.toLowerCase()}'
                    : 'Edit',
              ),
              onPressed: () => onEditLabels(kind, labels.of(kind)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _build(BuildContext context, Labels labels) {
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
              avatar: Icon(
                bookmarkSource(bookmark, labels.sources).icon,
                size: 18,
              ),
              label: Text(bookmarkSource(bookmark, labels.sources).name),
            ),
            Chip(label: Text(bookmark.sourceDomain)),
            if (bookmark.archived) const Chip(label: Text('Archived')),
          ],
        ),
        if (!bookmark.archived) ...[
          const SizedBox(height: Gap.md),
          bookmark.inInbox
              ? OutlinedButton.icon(
                  onPressed: () => onInbox(false),
                  icon: const Icon(Icons.done),
                  label: const Text('Done, remove from Inbox'),
                )
              : TextButton.icon(
                  onPressed: () => onInbox(true),
                  icon: const Icon(Icons.move_to_inbox_outlined),
                  label: const Text('Move back to Inbox'),
                ),
        ],
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
        _labelSection(
          context,
          labels,
          LabelKind.collection,
          Icons.folder_outlined,
          labelStyle,
        ),
        _labelSection(
          context,
          labels,
          LabelKind.tag,
          Icons.label_outline,
          labelStyle,
        ),
        const SizedBox(height: Gap.lg),
        _ReminderSection(bookmark: bookmark, labelStyle: labelStyle),
        _NoteSection(bookmark: bookmark, labelStyle: labelStyle),
        _HighlightsSection(bookmarkId: bookmark.id, labelStyle: labelStyle),
        const SizedBox(height: Gap.lg),
        Text('Link', style: labelStyle),
        Row(
          children: [
            Expanded(
              child: Text(
                bookmark.url,
                style: theme.textTheme.bodySmall,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            IconButton(
              tooltip: 'Copy link',
              icon: const Icon(Icons.copy_outlined),
              onPressed: () {
                Clipboard.setData(ClipboardData(text: bookmark.url));
                ScaffoldMessenger.of(context)
                    .showSnackBar(const SnackBar(content: Text('Link copied')));
              },
            ),
          ],
        ),
        const SizedBox(height: Gap.xl),
        FilledButton.icon(
          onPressed: onRead,
          icon: const Icon(Icons.chrome_reader_mode_outlined),
          label: const Text('Read'),
        ),
        const SizedBox(height: Gap.sm),
        OutlinedButton.icon(
          onPressed: onOpen,
          icon: const Icon(Icons.open_in_new),
          label: const Text('Open in browser'),
        ),
      ],
    );
  }
}

class _NoteSection extends StatelessWidget {
  const _NoteSection({required this.bookmark, required this.labelStyle});

  final Bookmark bookmark;
  final TextStyle? labelStyle;

  Future<void> _edit(BuildContext context) async {
    final service = AppDependencies.of(context).bookmarks;
    final messenger = ScaffoldMessenger.of(context);
    final note = await promptText(
      context,
      title: bookmark.note == null ? 'Add note' : 'Edit note',
      label: 'Note',
      initial: bookmark.note ?? '',
      maxLength: maxNoteLength,
      maxLines: 8,
    );
    if (note == null) return;
    try {
      await service.setNote(bookmark, note);
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not save: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final note = bookmark.note;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Note', style: labelStyle),
        const SizedBox(height: Gap.xs),
        if (note == null)
          TextButton.icon(
            onPressed: () => _edit(context),
            icon: const Icon(Icons.sticky_note_2_outlined),
            label: const Text('Add a note'),
          )
        else
          Card(
            margin: EdgeInsets.zero,
            child: InkWell(
              onTap: () => _edit(context),
              child: Padding(
                padding: const EdgeInsets.all(Gap.md),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: Text(note)),
                    const Icon(
                      Icons.edit_outlined,
                      size: 18,
                      semanticLabel: 'Edit note',
                    ),
                  ],
                ),
              ),
            ),
          ),
        const SizedBox(height: Gap.lg),
      ],
    );
  }
}

class _HighlightsSection extends StatefulWidget {
  const _HighlightsSection({
    required this.bookmarkId,
    required this.labelStyle,
  });

  final String bookmarkId;
  final TextStyle? labelStyle;

  @override
  State<_HighlightsSection> createState() => _HighlightsSectionState();
}

class _HighlightsSectionState extends State<_HighlightsSection> {
  Stream<List<Highlight>>? _stream;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _stream ??= AppDependencies.of(context).bookmarks.highlights
        .watchForBookmark(widget.bookmarkId);
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Highlight>>(
    stream: _stream,
    builder: (context, snapshot) {
      final highlights = snapshot.data ?? const <Highlight>[];
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            highlights.isEmpty
                ? 'Highlights'
                : 'Highlights (${highlights.length})',
            style: widget.labelStyle,
          ),
          const SizedBox(height: Gap.xs),
          if (highlights.isEmpty)
            Text(
              'Select text in the reader and choose Highlight.',
              style: Theme.of(context).textTheme.bodySmall,
            )
          else
            for (final h in highlights) HighlightCard(highlight: h),
        ],
      );
    },
  );
}

class _ReminderSection extends StatelessWidget {
  const _ReminderSection({required this.bookmark, required this.labelStyle});

  final Bookmark bookmark;
  final TextStyle? labelStyle;

  /// Quick choices, or a date and time from the pickers.
  Future<DateTime?> _choose(BuildContext context) async {
    final now = DateTime.now();
    final today = DateUtils.dateOnly(now);
    final evening = today.add(const Duration(hours: 18));
    final options = <(String, DateTime)>[
      if (now.isBefore(evening.subtract(const Duration(hours: 1))))
        ('Later today (18:00)', evening),
      (
        'Tomorrow morning (09:00)',
        today.add(const Duration(days: 1, hours: 9)),
      ),
      (
        'Next week (Mon 09:00)',
        _nextMonday(today).add(const Duration(hours: 9)),
      ),
    ];
    final picked = await showModalBottomSheet<Object>(
      context: context,
      showDragHandle: true,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (label, at) in options)
              ListTile(
                leading: const Icon(Icons.alarm),
                title: Text(label),
                onTap: () => Navigator.pop(context, at),
              ),
            ListTile(
              leading: const Icon(Icons.edit_calendar_outlined),
              title: const Text('Pick date and time…'),
              onTap: () => Navigator.pop(context, 'custom'),
            ),
          ],
        ),
      ),
    );
    if (picked is DateTime || picked == null || !context.mounted) {
      return picked as DateTime?;
    }
    final date = await showDatePicker(
      context: context,
      initialDate: today.add(const Duration(days: 1)),
      firstDate: today,
      lastDate: today.add(const Duration(days: 365 * 5)),
    );
    if (date == null || !context.mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: const TimeOfDay(hour: 9, minute: 0),
    );
    if (time == null) return null;
    return date.add(Duration(hours: time.hour, minutes: time.minute));
  }

  /// The coming Monday (a week ahead if today is Monday).
  static DateTime _nextMonday(DateTime day) {
    final days = (DateTime.monday - day.weekday + 7) % 7;
    return day.add(Duration(days: days == 0 ? 7 : days));
  }

  Future<void> _set(BuildContext context) async {
    final service = AppDependencies.of(context).bookmarks;
    final when = await _choose(context);
    if (when != null) await service.setReminder(bookmark, when);
  }

  @override
  Widget build(BuildContext context) {
    final service = AppDependencies.of(context).bookmarks;
    final remindAt = bookmark.remindAt;
    final due = bookmark.isDue(DateTime.now());
    final scheme = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Reminder', style: labelStyle),
        const SizedBox(height: Gap.xs),
        if (remindAt == null)
          ActionChip(
            avatar: const Icon(Icons.alarm_add_outlined, size: 18),
            label: const Text('Remind me'),
            onPressed: () => _set(context),
          )
        else
          InputChip(
            avatar: Icon(
              due ? Icons.alarm_on : Icons.alarm,
              size: 18,
              color: due ? scheme.error : null,
            ),
            label: Text(
              '${due ? 'Due' : 'Remind'} ${formatReminder(remindAt)}',
            ),
            onPressed: () => _set(context),
            deleteButtonTooltipMessage: 'Clear reminder',
            onDeleted: () => service.setReminder(bookmark, null),
          ),
        const SizedBox(height: Gap.lg),
      ],
    );
  }
}
