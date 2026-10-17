import 'package:flutter/material.dart';

import 'package:capsula_core/domain/bookmarks/bookmark.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_filters.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_source.dart';
import 'package:capsula_core/domain/bookmarks/content_type.dart';
import 'package:capsula_core/domain/organization/label.dart';

import '../../app/theme.dart';
import 'bookmark_display.dart';

typedef _Option = ({String key, String label, IconData icon});

/// Chips above the library list for narrowing it by source, tags, kind of
/// content and reading status. Each opens a list to pick from.
class FilterBar extends StatelessWidget {
  const FilterBar({
    super.key,
    required this.filters,
    required this.tags,
    required this.onChanged,
  });

  final BookmarkFilters filters;
  final List<Label> tags;
  final ValueChanged<BookmarkFilters> onChanged;

  static final List<_Option> _sources = [
    for (final s in BookmarkSource.values)
      (key: s.id, label: s.label, icon: sourceIcon(s)),
  ];

  static final List<_Option> _kinds = [
    for (final k in ContentType.values)
      (key: k.name, label: k.label, icon: typeIcon(k)),
  ];

  static const List<_Option> _statuses = [
    (key: 'saved', label: 'Saved', icon: Icons.bookmark_border),
    (key: 'readLater', label: 'Read later', icon: Icons.schedule),
    (key: 'reading', label: 'Reading', icon: Icons.chrome_reader_mode_outlined),
    (key: 'read', label: 'Read', icon: Icons.done_all),
  ];

  @override
  Widget build(BuildContext context) {
    final tagOptions = [
      for (final t in tags)
        (key: t.id, label: t.name, icon: Icons.label_outline),
    ];
    final statuses = ReadingStatus.values.asNameMap();
    final kinds = ContentType.values.asNameMap();
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Gap.md),
        children: [
          if (!filters.isEmpty)
            Padding(
              padding: const EdgeInsets.only(right: Gap.sm),
              child: ActionChip(
                avatar: const Icon(Icons.filter_alt_off_outlined, size: 18),
                label: const Text('Clear'),
                tooltip: 'Clear filters',
                onPressed: () => onChanged(BookmarkFilters.none),
              ),
            ),
          _FilterChip(
            name: 'Source',
            options: _sources,
            selected: filters.sources,
            onChanged: (s) => onChanged(filters.copyWith(sources: s)),
          ),
          _FilterChip(
            name: 'Tags',
            options: tagOptions,
            selected: filters.tagIds,
            emptyText: 'No tags yet.',
            onChanged: (s) => onChanged(filters.copyWith(tagIds: s)),
          ),
          _FilterChip(
            name: 'Kind',
            options: _kinds,
            selected: {for (final k in filters.kinds) k.name},
            onChanged: (s) => onChanged(
              filters.copyWith(kinds: {...s.map((k) => kinds[k]).nonNulls}),
            ),
          ),
          _FilterChip(
            name: 'Status',
            options: _statuses,
            selected: {for (final s in filters.statuses) s.name},
            onChanged: (s) => onChanged(
              filters.copyWith(
                statuses: {...s.map((k) => statuses[k]).nonNulls},
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.name,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.emptyText,
  });

  final String name;
  final List<_Option> options;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;
  final String? emptyText;

  String get _label {
    // Choices that no longer exist (a deleted tag) don't count.
    final chosen = options.where((o) => selected.contains(o.key)).toList();
    if (chosen.isEmpty) return name;
    if (chosen.length == 1) return chosen.single.label;
    return '$name · ${chosen.length}';
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(right: Gap.sm),
    child: FilterChip(
      label: Text(_label),
      selected: selected.isNotEmpty,
      showCheckmark: false,
      avatar: const Icon(Icons.arrow_drop_down, size: 18),
      tooltip: 'Filter by ${name.toLowerCase()}',
      onSelected: (_) async {
        final chosen = await showModalBottomSheet<Set<String>>(
          context: context,
          isScrollControlled: true,
          showDragHandle: true,
          builder: (context) => _OptionsSheet(
            title: name,
            options: options,
            selected: selected,
            emptyText: emptyText,
          ),
        );
        if (chosen != null) onChanged(chosen);
      },
    ),
  );
}

class _OptionsSheet extends StatefulWidget {
  const _OptionsSheet({
    required this.title,
    required this.options,
    required this.selected,
    this.emptyText,
  });

  final String title;
  final List<_Option> options;
  final Set<String> selected;
  final String? emptyText;

  @override
  State<_OptionsSheet> createState() => _OptionsSheetState();
}

class _OptionsSheetState extends State<_OptionsSheet> {
  late final Set<String> _chosen = {...widget.selected};

  @override
  Widget build(BuildContext context) => ConstrainedBox(
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * 0.7,
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(Gap.lg, 0, Gap.lg, Gap.sm),
          child: Text(
            'Filter by ${widget.title.toLowerCase()}',
            style: Theme.of(context).textTheme.titleMedium,
          ),
        ),
        if (widget.options.isEmpty)
          Padding(
            padding: const EdgeInsets.all(Gap.lg),
            child: Text(widget.emptyText ?? 'Nothing to choose from.'),
          ),
        Flexible(
          child: ListView(
            shrinkWrap: true,
            children: [
              for (final o in widget.options)
                CheckboxListTile(
                  secondary: Icon(o.icon),
                  title: Text(o.label),
                  value: _chosen.contains(o.key),
                  onChanged: (on) => setState(
                    () => on! ? _chosen.add(o.key) : _chosen.remove(o.key),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.all(Gap.md),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.pop(context, <String>{}),
                child: const Text('Clear'),
              ),
              const SizedBox(width: Gap.sm),
              FilledButton(
                style: FilledButton.styleFrom(minimumSize: const Size(88, 40)),
                onPressed: () => Navigator.pop(context, _chosen),
                child: const Text('Apply'),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
