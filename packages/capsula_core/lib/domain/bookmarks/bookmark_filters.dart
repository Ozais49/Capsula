import 'bookmark.dart';
import 'content_type.dart';

/// Narrows a view of the library by metadata: where links come from, tags,
/// kind of content and reading status. Within one filter any value matches
/// (Reddit or YouTube); different filters must all match (Reddit and
/// tagged Recipes). Empty filters match everything.
class BookmarkFilters {
  const BookmarkFilters({
    this.sources = const {},
    this.tagIds = const {},
    this.kinds = const {},
    this.statuses = const {},
  });

  static const none = BookmarkFilters();

  /// Source IDs (`reddit`, `website`, …).
  final Set<String> sources;
  final Set<String> tagIds;
  final Set<ContentType> kinds;
  final Set<ReadingStatus> statuses;

  bool get isEmpty =>
      sources.isEmpty && tagIds.isEmpty && kinds.isEmpty && statuses.isEmpty;

  /// How many filters are in use.
  int get activeCount => [
    sources,
    tagIds,
    kinds,
    statuses,
  ].where((s) => s.isNotEmpty).length;

  bool matches(Bookmark b) =>
      (sources.isEmpty || sources.contains(b.source.id)) &&
      (tagIds.isEmpty || b.tagIds.any(tagIds.contains)) &&
      (kinds.isEmpty || kinds.contains(b.type)) &&
      (statuses.isEmpty || statuses.contains(b.readingStatus));

  BookmarkFilters copyWith({
    Set<String>? sources,
    Set<String>? tagIds,
    Set<ContentType>? kinds,
    Set<ReadingStatus>? statuses,
  }) => BookmarkFilters(
    sources: sources ?? this.sources,
    tagIds: tagIds ?? this.tagIds,
    kinds: kinds ?? this.kinds,
    statuses: statuses ?? this.statuses,
  );

  /// URL query parameters, e.g. `source=reddit,youtube&tag=abc`.
  Map<String, String> toQuery() => {
    if (sources.isNotEmpty) 'source': (sources.toList()..sort()).join(','),
    if (tagIds.isNotEmpty) 'tag': (tagIds.toList()..sort()).join(','),
    if (kinds.isNotEmpty) 'kind': (kinds.map((k) => k.name).toList()..sort())
        .join(','),
    if (statuses.isNotEmpty)
      'status': (statuses.map((s) => s.name).toList()..sort()).join(','),
  };

  /// Reads [toQuery]'s parameters; unknown values are ignored.
  factory BookmarkFilters.fromQuery(Map<String, String> query) {
    Set<String> values(String key) => {
      for (final v in (query[key] ?? '').split(','))
        if (v.trim().isNotEmpty) v.trim(),
    };
    final kinds = ContentType.values.asNameMap();
    final statuses = ReadingStatus.values.asNameMap();
    return BookmarkFilters(
      sources: values('source'),
      tagIds: values('tag'),
      kinds: {...values('kind').map((k) => kinds[k]).nonNulls},
      statuses: {...values('status').map((s) => statuses[s]).nonNulls},
    );
  }

  @override
  bool operator ==(Object other) =>
      other is BookmarkFilters &&
      _sameSet(other.sources, sources) &&
      _sameSet(other.tagIds, tagIds) &&
      _sameSet(other.kinds, kinds) &&
      _sameSet(other.statuses, statuses);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(sources),
    Object.hashAllUnordered(tagIds),
    Object.hashAllUnordered(kinds),
    Object.hashAllUnordered(statuses),
  );

  static bool _sameSet<T>(Set<T> a, Set<T> b) =>
      a.length == b.length && a.containsAll(b);
}
