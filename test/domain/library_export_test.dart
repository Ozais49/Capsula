import 'dart:convert';

import 'package:capsula_core/domain/bookmarks/bookmark.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_source.dart';
import 'package:capsula_core/domain/export/library_export.dart';
import 'package:capsula_core/domain/import/bookmark_html_parser.dart';
import 'package:capsula_core/domain/organization/label.dart';
import 'package:flutter_test/flutter_test.dart';

final _now = DateTime.utc(2026, 10, 14, 12);

const _labels = [
  Label(id: 't1', kind: LabelKind.tag, name: 'AI'),
  Label(id: 't2', kind: LabelKind.tag, name: 'Read "soon"'),
  Label(id: 'c1', kind: LabelKind.collection, name: 'Research & Papers'),
];

final _bookmarks = [
  Bookmark(
    id: 'a',
    url: 'https://arxiv.org/abs/1706.03762?x=1&y=2',
    canonicalUrl: 'https://arxiv.org/abs/1706.03762?x=1&y=2',
    title: 'Attention <Is> All You Need',
    description: 'Transformers',
    source: BookmarkSource.website,
    sourceDomain: 'arxiv.org',
    readingStatus: ReadingStatus.read,
    tagIds: const ['t1', 't2', 'deleted-tag'],
    collectionIds: const ['c1'],
    createdAt: DateTime.utc(2017, 6, 12),
    updatedAt: _now,
    importedFrom: 'Chrome',
    importedAt: _now,
  ),
  Bookmark(
    id: 'b',
    url: 'https://flutter.dev/',
    canonicalUrl: 'https://flutter.dev',
    title: 'Flutter',
    source: BookmarkSource.website,
    sourceDomain: 'flutter.dev',
    archived: true,
    inInbox: false,
    createdAt: DateTime.utc(2024, 1, 1),
    updatedAt: _now,
  ),
];

void main() {
  test('file names include the date and extension', () {
    expect(exportFileName(ExportFormat.json, _now), 'capsula-2026-10-14.json');
    expect(exportFileName(ExportFormat.html, _now), 'capsula-2026-10-14.html');
  });

  test('JSON backup keeps everything, with label names', () {
    final json = jsonDecode(
      exportLibrary(ExportFormat.json, _bookmarks, _labels, now: _now),
    ) as Map<String, Object?>;

    expect(json['format'], 'capsula');
    expect(json['version'], 1);
    final items = json['bookmarks'] as List;
    final first = items.first as Map;
    expect(first['url'], 'https://arxiv.org/abs/1706.03762?x=1&y=2');
    expect(first['readingStatus'], 'read');
    expect(first['tags'], ['AI', 'Read "soon"'], reason: 'unknown IDs dropped');
    expect(first['collections'], ['Research & Papers']);
    expect(first['createdAt'], '2017-06-12T00:00:00.000Z');
    expect(first['importedFrom'], 'Chrome');

    final second = items.last as Map;
    expect(second['archived'], isTrue);
    expect(second['inInbox'], isFalse);
    expect(second.containsKey('importedFrom'), isFalse);
  });

  test('HTML export re-imports with folders, tags and dates intact', () {
    final html = exportLibrary(
      ExportFormat.html,
      _bookmarks,
      _labels,
      now: _now,
    );
    expect(looksLikeBookmarkHtml(html), isTrue);

    final items = parseBookmarkHtml(html, now: _now);
    expect(items, hasLength(2));

    final paper = items.firstWhere((i) => i.url.contains('arxiv'));
    expect(paper.url, 'https://arxiv.org/abs/1706.03762?x=1&y=2');
    expect(paper.title, 'Attention <Is> All You Need');
    expect(paper.folder, 'Research & Papers');
    expect(paper.tags, ['AI', 'Read "soon"']);
    expect(paper.description, 'Transformers');
    expect(paper.createdAt, DateTime.utc(2017, 6, 12));

    final flutter = items.firstWhere((i) => i.url.contains('flutter'));
    expect(flutter.folder, isNull);
  });

  test('HTML escapes markup in titles and URLs', () {
    final html = exportLibrary(
      ExportFormat.html,
      _bookmarks,
      _labels,
      now: _now,
    );
    expect(html, contains('Attention &lt;Is&gt; All You Need'));
    expect(
      html,
      contains('HREF="https://arxiv.org/abs/1706.03762?x=1&amp;y=2"'),
    );
    expect(html, isNot(contains('<Is>')));
  });
}
