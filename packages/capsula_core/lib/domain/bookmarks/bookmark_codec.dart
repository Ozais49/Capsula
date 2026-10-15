import '../highlights/highlight.dart';
import '../organization/label.dart';
import 'bookmark.dart';
import 'bookmark_source.dart';
import 'search_tokens.dart';

/// Document fields for a bookmark, shared by every Firestore client (the
/// app's SDK and the server's admin SDK). [timestamp] converts a date to the
/// client's timestamp type.
Map<String, Object?> encodeBookmark(
  Bookmark b,
  Object Function(DateTime) timestamp,
) => {
  'url': b.url,
  'canonicalUrl': b.canonicalUrl,
  'title': b.title,
  'description': ?b.description,
  'imageUrl': ?b.imageUrl,
  'source': b.source.id,
  'sourceDomain': b.sourceDomain,
  'readingStatus': b.readingStatus.name,
  'archived': b.archived,
  'inInbox': b.inInbox,
  if (b.favorite) 'favorite': true,
  'note': ?b.note,
  'tagIds': b.tagIds,
  'collectionIds': b.collectionIds,
  'importedFrom': ?b.importedFrom,
  if (b.importedAt case final at?) 'importedAt': timestamp(at),
  'createdAt': timestamp(b.createdAt),
  'updatedAt': timestamp(b.updatedAt),
  'searchTokens': buildSearchTokens(b.searchableText),
};

/// Reads a bookmark document. [readTime] converts the client's timestamp
/// type back to a date.
Bookmark decodeBookmark(
  String id,
  Map<String, Object?> data,
  DateTime? Function(Object?) readTime,
) => Bookmark(
  id: id,
  url: data['url'] as String? ?? '',
  canonicalUrl: data['canonicalUrl'] as String? ?? '',
  title: data['title'] as String? ?? '',
  description: data['description'] as String?,
  imageUrl: data['imageUrl'] as String?,
  source: BookmarkSource.fromId(data['source'] as String?),
  sourceDomain: data['sourceDomain'] as String? ?? '',
  readingStatus: ReadingStatus.fromName(data['readingStatus'] as String?),
  archived: data['archived'] as bool? ?? false,
  inInbox: data['inInbox'] as bool? ?? false,
  favorite: data['favorite'] as bool? ?? false,
  note: data['note'] as String?,
  tagIds: _strings(data['tagIds']),
  collectionIds: _strings(data['collectionIds']),
  importedFrom: data['importedFrom'] as String?,
  importedAt: readTime(data['importedAt']),
  createdAt:
      readTime(data['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
  updatedAt:
      readTime(data['updatedAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
);

List<String> _strings(Object? value) =>
    value is List ? value.whereType<String>().toList() : const [];

/// Bookmark field holding the IDs of labels of [kind].
String labelField(LabelKind kind) => switch (kind) {
  LabelKind.tag => 'tagIds',
  LabelKind.collection => 'collectionIds',
};

/// Firestore collection holding labels of [kind] under a user.
String labelCollection(LabelKind kind) => switch (kind) {
  LabelKind.tag => 'tags',
  LabelKind.collection => 'collections',
};

Map<String, Object?> encodeHighlight(
  Highlight h,
  Object Function(DateTime) timestamp,
) => {
  'bookmarkId': h.bookmarkId,
  'text': h.text,
  'note': ?h.note,
  'color': h.color.name,
  'createdAt': timestamp(h.createdAt),
};

Highlight decodeHighlight(
  String id,
  Map<String, Object?> data,
  DateTime? Function(Object?) readTime,
) => Highlight(
  id: id,
  bookmarkId: data['bookmarkId'] as String? ?? '',
  text: data['text'] as String? ?? '',
  note: data['note'] as String?,
  color: HighlightColor.fromName(data['color'] as String?),
  createdAt:
      readTime(data['createdAt']) ?? DateTime.fromMillisecondsSinceEpoch(0),
);
