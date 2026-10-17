/// JSON shapes of the Capsula REST API, shared by the server and clients.
library;

import '../domain/bookmarks/bookmark.dart';
import '../domain/highlights/highlight.dart';
import '../domain/organization/label.dart';
import '../domain/reader/reader_content.dart';

Map<String, Object?> bookmarkToJson(Bookmark b) => {
  'id': b.id,
  'url': b.url,
  'canonicalUrl': b.canonicalUrl,
  'title': b.title,
  'description': ?b.description,
  'imageUrl': ?b.imageUrl,
  'source': b.source.id,
  'sourceDomain': b.sourceDomain,
  'customSourceId': ?b.customSourceId,
  'readingStatus': b.readingStatus.name,
  'archived': b.archived,
  'inInbox': b.inInbox,
  'unsorted': b.isUnsorted,
  'favorite': b.favorite,
  'note': ?b.note,
  if (b.remindAt case final at?) 'remindAt': _iso(at),
  'tagIds': b.tagIds,
  'collectionIds': b.collectionIds,
  'importedFrom': ?b.importedFrom,
  if (b.importedAt case final at?) 'importedAt': _iso(at),
  if (b.deletedAt case final at?) 'deletedAt': _iso(at),
  'createdAt': _iso(b.createdAt),
  'updatedAt': _iso(b.updatedAt),
};

Map<String, Object?> labelToJson(Label l) => {
  'id': l.id,
  'kind': l.kind.name,
  'name': l.name,
  'parentId': ?l.parentId,
  'shareId': ?l.shareId,
};

String _iso(DateTime d) => d.toUtc().toIso8601String();

Map<String, Object?> metadataToJson(PageMetadata m) => {
  'title': ?m.title,
  'description': ?m.description,
  if (m.image case final image?) 'image': image.toString(),
  'siteName': ?m.siteName,
};

PageMetadata metadataFromJson(Map<String, Object?> json) => PageMetadata(
  title: json['title'] as String?,
  description: json['description'] as String?,
  image: switch (json['image']) {
    final String s => Uri.tryParse(s),
    _ => null,
  },
  siteName: json['siteName'] as String?,
);

Map<String, Object?> readerContentToJson(ReaderContent c) => switch (c) {
  ArticleContent() => {
    'type': 'article',
    'title': c.title,
    'byline': ?c.byline,
    'siteName': ?c.siteName,
    if (c.leadImage case final i?) 'leadImage': i.toString(),
    'excerpt': ?c.excerpt,
    'blocks': c.blocks.map(_blockToJson).toList(),
  },
  VideoContent() => {
    'type': 'video',
    'title': c.title,
    'videoUrl': c.videoUrl.toString(),
    if (c.thumbnail case final t?) 'thumbnail': t.toString(),
    'channel': ?c.channel,
  },
  PreviewContent() => {
    'type': 'preview',
    'metadata': metadataToJson(c.metadata),
    'note': ?c.note,
  },
  Unavailable() => {
    'type': 'unavailable',
    'reason': c.reason.name,
    if (c.metadata case final m?) 'metadata': metadataToJson(m),
  },
};

ReaderContent readerContentFromJson(Map<String, Object?> json) {
  Uri? uri(Object? v) => v is String ? Uri.tryParse(v) : null;
  Map<String, Object?> map(Object? v) => (v as Map).cast<String, Object?>();

  return switch (json['type']) {
    'article' => ArticleContent(
      title: json['title'] as String? ?? '',
      byline: json['byline'] as String?,
      siteName: json['siteName'] as String?,
      leadImage: uri(json['leadImage']),
      excerpt: json['excerpt'] as String?,
      blocks: [
        for (final b in json['blocks'] as List? ?? const [])
          ?_blockFromJson(map(b)),
      ],
    ),
    'video' => VideoContent(
      title: json['title'] as String? ?? '',
      videoUrl: uri(json['videoUrl']) ?? Uri(),
      thumbnail: uri(json['thumbnail']),
      channel: json['channel'] as String?,
    ),
    'preview' => PreviewContent(
      metadata: metadataFromJson(map(json['metadata'])),
      note: json['note'] as String?,
    ),
    _ => Unavailable(
      UnavailableReason.values.firstWhere(
        (r) => r.name == json['reason'],
        orElse: () => UnavailableReason.failed,
      ),
      metadata: json['metadata'] == null
          ? null
          : metadataFromJson(map(json['metadata'])),
    ),
  };
}

Map<String, Object?> _runToJson(InlineRun r) => {
  't': r.text,
  if (r.bold) 'b': true,
  if (r.italic) 'i': true,
  if (r.code) 'c': true,
  if (r.link case final l?) 'a': l.toString(),
};

InlineRun _runFromJson(Map<String, Object?> j) => InlineRun(
  j['t'] as String? ?? '',
  bold: j['b'] == true,
  italic: j['i'] == true,
  code: j['c'] == true,
  link: j['a'] is String ? Uri.tryParse(j['a'] as String) : null,
);

List<Map<String, Object?>> _runs(List<InlineRun> runs) =>
    runs.map(_runToJson).toList();

List<InlineRun> _runsFrom(Object? v) => [
  for (final r in v as List? ?? const [])
    _runFromJson((r as Map).cast<String, Object?>()),
];

Map<String, Object?> _blockToJson(ReaderBlock b) => switch (b) {
  HeadingBlock() => {'k': 'h', 'level': b.level, 'runs': _runs(b.runs)},
  ParagraphBlock() => {'k': 'p', 'runs': _runs(b.runs)},
  ListBlock() => {
    'k': 'list',
    'ordered': b.ordered,
    'items': b.items.map(_runs).toList(),
  },
  QuoteBlock() => {'k': 'quote', 'blocks': b.blocks.map(_blockToJson).toList()},
  CodeBlock() => {'k': 'code', 'text': b.text},
  ImageBlock() => {'k': 'img', 'url': b.url.toString(), 'caption': ?b.caption},
};

ReaderBlock? _blockFromJson(Map<String, Object?> j) => switch (j['k']) {
  'h' => HeadingBlock(j['level'] as int? ?? 2, _runsFrom(j['runs'])),
  'p' => ParagraphBlock(_runsFrom(j['runs'])),
  'list' => ListBlock(
    ordered: j['ordered'] == true,
    items: [for (final i in j['items'] as List? ?? const []) _runsFrom(i)],
  ),
  'quote' => QuoteBlock([
    for (final b in j['blocks'] as List? ?? const [])
      ?_blockFromJson((b as Map).cast<String, Object?>()),
  ]),
  'code' => CodeBlock(j['text'] as String? ?? ''),
  'img' => switch (Uri.tryParse(j['url'] as String? ?? '')) {
    final url? when url.hasScheme => ImageBlock(
      url,
      caption: j['caption'] as String?,
    ),
    _ => null,
  },
  _ => null,
};

Map<String, Object?> highlightToJson(Highlight h) => {
  'id': h.id,
  'bookmarkId': h.bookmarkId,
  'text': h.text,
  'note': ?h.note,
  'color': h.color.name,
  'createdAt': _iso(h.createdAt),
};
