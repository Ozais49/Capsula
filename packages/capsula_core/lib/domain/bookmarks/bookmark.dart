import '../organization/label.dart';
import 'bookmark_source.dart';

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

  String get displayTitle => title.trim().isEmpty ? sourceDomain : title;

  /// Text that search matches against.
  List<String> get searchableText => [
    title,
    sourceDomain,
    source.label,
    ?description,
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
    tagIds: tagIds ?? this.tagIds,
    collectionIds: collectionIds ?? this.collectionIds,
    importedFrom: importedFrom,
    importedAt: importedAt,
    createdAt: createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
