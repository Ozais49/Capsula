import 'package:capsula_core/domain/import/bookmark_html_parser.dart';
import 'package:capsula_core/domain/import/imported_item.dart';
import 'package:capsula_core/domain/import/tabular_import.dart';
import 'package:flutter_test/flutter_test.dart';

/// Shape of a Chrome / Edge export.
const chromeExport = '''
<!DOCTYPE NETSCAPE-Bookmark-file-1>
<!-- This is an automatically generated file. -->
<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
<TITLE>Bookmarks</TITLE>
<H1>Bookmarks</H1>
<DL><p>
    <DT><H3 ADD_DATE="1700000000" PERSONAL_TOOLBAR_FOLDER="true">Bookmarks bar</H3>
    <DL><p>
        <DT><A HREF="https://flutter.dev/" ADD_DATE="1700000100">Flutter</A>
        <DT><H3 ADD_DATE="1700000200">AI Research</H3>
        <DL><p>
            <DT><A HREF="https://arxiv.org/abs/1706.03762" ADD_DATE="1700000300">Attention Is All You Need</A>
            <DT><H3>Papers to read</H3>
            <DL><p>
                <DT><A HREF="https://arxiv.org/abs/2005.14165">GPT-3</A>
            </DL><p>
        </DL><p>
    </DL><p>
    <DT><H3>Other bookmarks</H3>
    <DL><p>
        <DT><A HREF="https://example.com/x">Loose link</A>
        <DT><A HREF="javascript:void(0)">Bookmarklet</A>
    </DL><p>
</DL><p>
''';

/// Shape of a Firefox / Raindrop / Pinboard export with tags and notes.
const firefoxExport = '''
<!DOCTYPE NETSCAPE-Bookmark-file-1>
<DL><p>
  <DT><H3>Bookmarks Menu</H3>
  <DL><p>
    <DT><H3>Travel</H3>
    <DL><p>
      <DT><A HREF="https://japan-guide.com/" ADD_DATE="1650000000" TAGS="japan,trip">Japan Guide</A>
      <DD>Planning notes for the spring trip
    </DL><p>
  </DL><p>
</DL>
''';

void main() {
  group('bookmark HTML', () {
    test('is recognized', () {
      expect(looksLikeBookmarkHtml(chromeExport), isTrue);
      expect(looksLikeBookmarkHtml('url,title\nhttps://a.com,A'), isFalse);
    });

    test('reads links with nearest real folder and dates', () {
      final items = parseBookmarkHtml(chromeExport);
      expect(items.map((i) => i.url), [
        'https://flutter.dev/',
        'https://arxiv.org/abs/1706.03762',
        'https://arxiv.org/abs/2005.14165',
        'https://example.com/x',
        'javascript:void(0)',
      ]);

      final byTitle = {for (final i in items) i.title: i};
      expect(byTitle['Flutter']!.folder, isNull, reason: 'browser root folder');
      expect(byTitle['Attention Is All You Need']!.folder, 'AI Research');
      expect(byTitle['GPT-3']!.folder, 'Papers to read');
      expect(byTitle['Loose link']!.folder, isNull);
      expect(
        byTitle['Flutter']!.createdAt,
        DateTime.fromMillisecondsSinceEpoch(1700000100 * 1000, isUtc: true),
      );
    });

    test('reads tags and descriptions', () {
      final item = parseBookmarkHtml(firefoxExport).single;
      expect(item.title, 'Japan Guide');
      expect(item.folder, 'Travel');
      expect(item.tags, ['japan', 'trip']);
      expect(item.description, 'Planning notes for the spring trip');
    });
  });

  group('CSV', () {
    test('handles quotes, escaped quotes, commas, newlines and a BOM', () {
      final table = parseCsv(
        '﻿url,title,note\r\n'
        'https://a.com,"Hello, world","He said ""hi"""\r\n'
        'https://b.com,"Two\nlines",\r\n'
        '\r\n',
      );
      expect(table.columns, ['url', 'title', 'note']);
      expect(table.rows, hasLength(2));
      expect(table.rows[0]['title'], 'Hello, world');
      expect(table.rows[0]['note'], 'He said "hi"');
      expect(table.rows[1]['title'], 'Two\nlines');
      expect(table.rows[1]['note'], '');
    });

    test('Raindrop export maps automatically', () {
      final table = parseCsv(
        'id,title,note,excerpt,url,folder,tags,created,cover,highlights,favorite\n'
        '1,Flutter,My note,,https://flutter.dev,Programming,"dart, mobile",2024-03-01T10:00:00.000Z,,,false\n'
        '2,Unsorted thing,,,https://x.com/a,Unsorted,,2024-03-02T10:00:00.000Z,,,false\n',
      );
      final mapping = suggestMapping(table.columns);
      expect(mapping.url, 'url');
      expect(mapping.title, 'title');
      expect(mapping.description, 'note');
      expect(mapping.folder, 'folder');
      expect(mapping.tags, 'tags');
      expect(mapping.createdAt, 'created');

      final items = applyMapping(table, mapping);
      expect(items.first.folder, 'Programming');
      expect(items.first.tags, ['dart', 'mobile']);
      expect(items.first.createdAt, DateTime.utc(2024, 3, 1, 10));
      expect(items.last.folder, isNull, reason: '"Unsorted" is no folder');
    });

    test('Pocket export maps automatically', () {
      final table = parseCsv(
        'title,url,time_added,tags,status\n'
        'Article,https://example.com/a,1700000000,read|later,unread\n',
      );
      final item = applyMapping(table, suggestMapping(table.columns)).single;
      expect(item.tags, ['read', 'later']);
      expect(item.createdAt!.year, 2023);
    });

    test('rows without a URL are skipped', () {
      final table = parseCsv('link,name\n,No link\nhttps://a.com,A\n');
      final items = applyMapping(table, suggestMapping(table.columns));
      expect(items.map((i) => i.title), ['A']);
    });
  });

  group('JSON', () {
    test('reads an array or a wrapped array, flattening lists', () {
      final direct = parseJsonTable(
        '[{"link": "https://a.com", "name": "A", "labels": ["x", "y"]}]',
      );
      expect(direct.rows.single['labels'], 'x, y');

      final wrapped = parseJsonTable(
        '{"version": 2, "bookmarks": [{"url": "https://b.com"}]}',
      );
      expect(wrapped.rows.single['url'], 'https://b.com');

      final item = applyMapping(direct, suggestMapping(direct.columns)).single;
      expect(item.url, 'https://a.com');
      expect(item.title, 'A');
      expect(item.tags, ['x', 'y']);
    });
  });

  test('folder paths keep the innermost folder', () {
    final table = parseCsv('url,folder\nhttps://a.com,Work/Projects/Capsula\n');
    expect(
      applyMapping(table, suggestMapping(table.columns)).single.folder,
      'Capsula',
    );
  });

  group('parseImportDate', () {
    final now = DateTime.utc(2026, 10, 14);

    test('reads seconds, milliseconds, microseconds and ISO', () {
      final expected = DateTime.utc(2023, 11, 14, 22, 13, 20);
      expect(parseImportDate('1700000000', now: now), expected);
      expect(parseImportDate('1700000000000', now: now), expected);
      expect(parseImportDate('1700000000000000', now: now), expected);
      expect(parseImportDate('2023-11-14T22:13:20Z', now: now), expected);
    });

    test('rejects nonsense and clamps future dates', () {
      expect(parseImportDate('', now: now), isNull);
      expect(parseImportDate('yesterday', now: now), isNull);
      expect(parseImportDate('0', now: now), isNull);
      expect(parseImportDate('1980-01-01', now: now), isNull);
      expect(parseImportDate('2099-01-01', now: now), now);
    });
  });

  test('splitTags handles separators and duplicates', () {
    expect(splitTags('a, b;c|a'), ['a', 'b', 'c']);
    expect(splitTags(null), isEmpty);
  });
}
