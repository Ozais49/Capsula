import '../organization/label.dart';
import 'bookmark_source.dart';
import 'content_type.dart';

/// Reading progress, independent of source, tags and collections.
enum ReadingStatus {
  saved('Saved'),
  readLater('Read later'),
  reading('Reading'),
  read('Read');

  const ReadingStatus(this.label);

  final String label;

  static ReadingStatus fromName(String? name) => ReadingStatus.values
      .firstWhere((s) => s.name == name, orElse: () => ReadingStatus.saved);
}

class Bookmark {
  const Bookmark({
    required this.id,
    required this.url,
    required this.canonicalUrl,
    required this.title,
    required this.source,
    required this.sourceDomain,
    required this.createdAt,
    required this.updatedAt,
    this.description,
    this.imageUrl,
    this.readingStatus = ReadingStatus.saved,
    this.archived = false,
    this.inInbox = true,
    this.favorite = false,
    this.note,
    this.remindAt,
    this.contentIndexedAt,
    this.deletedAt,
    this.customSourceId,
    this.tagIds = const [],
    this.collectionIds = const [],
    this.importedFrom,
    this.importedAt,
  });

  final String id;

  /// The URL as saved, opened when the user leaves the app.
  final String url;

  /// Normalized form used only for duplicate detection.
  final String canonicalUrl;
  final String title;
  final String? description;
  final String? imageUrl;
  final BookmarkSource source;

  /// Host without `www.`, e.g. `reddit.com`.
  final String sourceDomain;
  final ReadingStatus readingStatus;
  final bool archived;

  /// Newly captured items awaiting organization.
  final bool inInbox;
  final bool favorite;

  /// The user's own note about the bookmark.
  final String? note;

  /// When to bring the bookmark back to the user's attention.
  final DateTime? remindAt;

  /// When the page's text was last indexed for full-text search.
  final DateTime? contentIndexedAt;

  /// When the bookmark was moved to the Trash; null when it is not there.
  /// Trashed bookmarks are also archived, so the library's views (which
  /// all show unarchived bookmarks) leave them out.
  final DateTime? deletedAt;

  bool get isTrashed => deletedAt != null;

  /// The user's own source this link matched (see `CustomSource`), or
  /// null for a built-in source. [source] still decides how it is read.
  final String? customSourceId;

  /// Not in any collection and without tags: no rule recognized it and
  /// nobody has organized it yet. Shown in Unsorted.
  bool get isUnsorted => tagIds.isEmpty && collectionIds.isEmpty;

  /// The source shown and filtered on: the custom one, else the built-in.
  String get sourceKey => customSourceId ?? source.id;

  bool isDue(DateTime now) => remindAt != null && !remindAt!.isAfter(now);
  final List<String> tagIds;
  final List<String> collectionIds;

  /// Where an imported bookmark came from (e.g. `Chrome`, `Raindrop`);
  /// null for bookmarks saved in Capsula. Separate from [source].
  final String? importedFrom;
  final DateTime? importedAt;
  final DateTime createdAt;
  final DateTime updatedAt;

  List<String> labelIds(LabelKind kind) => switch (kind) {
    LabelKind.tag => tagIds,
    LabelKind.collection => collectionIds,
  };

  /// Detected from the URL; stored for type filters.
  ContentType get type => detectContentType(Uri.tryParse(url) ?? Uri(), source);

  String get displayTitle => title.trim().isEmpty ? sourceDomain : title;

  /// Text that search matches against.
  List<String> get searchableText => [
    title,
    sourceDomain,
    source.label,
    ?description,
    ?note,
    ...?Uri.tryParse(url)?.pathSegments.take(6),
  ];

  Bookmark copyWith({
    String? title,
    String? description,
    String? imageUrl,
    ReadingStatus? readingStatus,
    bool? archived,
    bool? inInbox,
    bool? favorite,
    String? note,
    bool clearNote = false,
    DateTime? remindAt,
    bool clearReminder = false,
    DateTime? contentIndexedAt,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
    String? customSourceId,
    bool clearCustomSource = false,
    List<String>? tagIds,
    List<String>? collectionIds,
    DateTime? updatedAt,
  }) => Bookmark(
    id: id,
    url: url,
    canonicalUrl: canonicalUrl,
    title: title ?? this.title,
    description: description ?? this.description,
    imageUrl: imageUrl ?? this.imageUrl,
    source: source,
    sourceDomain: sourceDomain,
    readingStatus: readingStatus ?? this.readingStatus,
    archived: archived ?? this.archived,
    inInbox: inInbox ?? this.inInbox,
    favorite: favorite ?? this.favorite,
    note: clearNote ? null : note ?? this.note,
    remindAt: clearReminder ? null : remindAt ?? this.remindAt,
    contentIndexedAt: contentIndexedAt ?? this.contentIndexedAt,
    deletedAt: clearDeletedAt ? null : deletedAt ?? this.deletedAt,
    customSourceId: clearCustomSource
        ? null
        : customSourceId ?? this.customSourceId,
    tagIds: tagIds ?? this.tagIds,
    collectionIds: collectionIds ?? this.collectionIds,
    importedFrom: importedFrom,
    importedAt: importedAt,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
