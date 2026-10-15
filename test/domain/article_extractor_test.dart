import 'package:capsula_core/domain/reader/article_extractor.dart';
import 'package:capsula_core/domain/reader/reader_content.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:html/parser.dart' as html_parser;

final _base = Uri.parse('https://blog.example.com/posts/cooking-rice');

String _text(List<InlineRun> runs) => runs.map((r) => r.text).join();

String _paragraph(int i) =>
    'This is paragraph number $i of the article, with enough words to look '
    'like real prose, including commas, clauses, and a reasonable length.';

const _articleHtml = '''
<html>
<head>
  <title>How to Cook Rice | Example Blog</title>
  <meta property="og:title" content="How to Cook Perfect Rice">
  <meta property="og:description" content="A short guide to fluffy rice.">
  <meta property="og:image" content="/images/rice.jpg">
  <meta property="og:site_name" content="Example Blog">
  <meta name="author" content="Sam Cook">
  <script>trackEverything();</script>
  <style>body { color: red; }</style>
</head>
<body>
  <header class="site-header"><a href="/">Home</a> <a href="/about">About</a></header>
  <nav class="menu"><a href="/a">A</a><a href="/b">B</a></nav>
  <div class="cookie-banner">We use cookies. Accept?</div>
  <div class="layout">
    <aside class="sidebar"><p>Popular posts you might like to read today</p></aside>
    <div class="post-content">
      <h1>How to Cook Perfect Rice</h1>
      <p>__P1__</p>
      <h2>What you need</h2>
      <ul><li>Rice, <strong>one cup</strong></li><li>Water</li></ul>
      <p>__P2__ See <a href="/posts/washing-rice">washing rice</a>.</p>
      <figure>
        <img data-src="/images/pot.jpg" src="data:image/gif;base64,AAAA" alt="A pot">
        <figcaption>Use a heavy pot.</figcaption>
      </figure>
      <blockquote><p>Patience makes good rice.</p></blockquote>
      <pre><code>water = rice * 1.5</code></pre>
      <p>__P3__</p>
      <img src="https://tracker.example.com/pixel.gif" width="1" height="1">
      <div class="share-buttons"><a href="#">Share</a> <a href="#">Tweet</a></div>
    </div>
  </div>
  <div class="comments"><p>Great post! I tried this and it worked, thanks a lot for sharing.</p></div>
  <footer>Copyright Example Blog, all rights reserved, forever and ever.</footer>
</body>
</html>
''';

void main() {
  final html = _articleHtml
      .replaceFirst('__P1__', _paragraph(1))
      .replaceFirst('__P2__', _paragraph(2))
      .replaceFirst('__P3__', _paragraph(3));

  group('extractArticle', () {
    late ArticleContent article;

    setUp(() => article = extractArticle(html, _base)!);

    test('uses metadata for title, byline and site', () {
      expect(article.title, 'How to Cook Perfect Rice');
      expect(article.byline, 'Sam Cook');
      expect(article.siteName, 'Example Blog');
      expect(article.excerpt, 'A short guide to fluffy rice.');
    });

    test('keeps the article body in order', () {
      final kinds = article.blocks.map((b) => b.runtimeType).toList();
      expect(kinds, [
        ParagraphBlock,
        HeadingBlock,
        ListBlock,
        ParagraphBlock,
        ImageBlock,
        QuoteBlock,
        CodeBlock,
        ParagraphBlock,
      ]);
    });

    test('drops the heading that repeats the title', () {
      expect(
        article.blocks.whereType<HeadingBlock>().map((h) => _text(h.runs)),
        ['What you need'],
      );
    });

    test('removes navigation, sidebars, comments, banners and scripts', () {
      final all = article.blocks
          .map(
            (b) => switch (b) {
              ParagraphBlock(:final runs) => _text(runs),
              HeadingBlock(:final runs) => _text(runs),
              _ => '',
            },
          )
          .join('\n');
      for (final unwanted in [
        'Home',
        'Popular posts',
        'cookies',
        'Great post',
        'Copyright',
        'trackEverything',
        'Share',
      ]) {
        expect(all, isNot(contains(unwanted)), reason: unwanted);
      }
    });

    test('keeps inline formatting and resolves links', () {
      final list = article.blocks.whereType<ListBlock>().single;
      expect(list.ordered, isFalse);
      expect(list.items.map(_text), ['Rice, one cup', 'Water']);
      expect(
        list.items.first.any((r) => r.bold && r.text == 'one cup'),
        isTrue,
      );

      final linked = article.blocks
          .whereType<ParagraphBlock>()
          .expand((p) => p.runs)
          .firstWhere((r) => r.link != null);
      expect(linked.text, 'washing rice');
      expect(
        linked.link.toString(),
        'https://blog.example.com/posts/washing-rice',
      );
    });

    test('resolves lazy images, keeps captions, skips tracking pixels', () {
      final images = article.blocks.whereType<ImageBlock>().toList();
      expect(images, hasLength(1));
      expect(
        images.single.url.toString(),
        'https://blog.example.com/images/pot.jpg',
      );
      expect(images.single.caption, 'Use a heavy pot.');
      expect(article.leadImage, isNull, reason: 'body already has an image');
    });

    test('keeps code text as-is', () {
      expect(
        article.blocks.whereType<CodeBlock>().single.text,
        'water = rice * 1.5',
      );
    });
  });

  test('returns null for pages without enough text', () {
    expect(
      extractArticle(
        '<html><body><p>Just a short note.</p></body></html>',
        _base,
      ),
      isNull,
    );
  });

  test('finds content without semantic containers by scoring paragraphs', () {
    final paragraphs = List.generate(
      5,
      (i) => '<p>${_paragraph(i)}</p>',
    ).join();
    final page =
        '''
      <html><body>
        <div id="top"><a href="/1">Link one</a> <a href="/2">Link two</a></div>
        <div id="x1"><div id="x2">$paragraphs</div></div>
        <div id="bottom"><p>Small print.</p></div>
      </body></html>''';
    final article = extractArticle(page, _base)!;
    expect(article.blocks, hasLength(5));
    expect(article.blocks.every((b) => b is ParagraphBlock), isTrue);
  });

  test('prefers the largest <article> element', () {
    final page =
        '''
      <html><body>
        <article><p>Teaser for another story, short.</p></article>
        <article>${List.generate(4, (i) => '<p>${_paragraph(i)}</p>').join()}</article>
      </body></html>''';
    final article = extractArticle(page, _base)!;
    expect(article.blocks, hasLength(4));
  });

  group('extractMetadata', () {
    test('falls back to the <title> without the site suffix', () {
      final doc = html_parser.parse(
        '<html><head><title>Great Article Title - Some Site</title>'
        '<meta name="description" content="Desc"></head></html>',
      );
      final meta = extractMetadata(doc, _base);
      expect(meta.title, 'Great Article Title');
      expect(meta.description, 'Desc');
      expect(meta.image, isNull);
    });

    test('resolves the image and ignores non-web schemes', () {
      final doc = html_parser.parse(
        '<meta property="og:image" content="//cdn.example.com/a.png">',
      );
      expect(
        extractMetadata(doc, _base).image.toString(),
        'https://cdn.example.com/a.png',
      );

      final bad = html_parser.parse(
        '<meta property="og:image" content="javascript:alert(1)">',
      );
      expect(extractMetadata(bad, _base).image, isNull);
    });
  });

  test('htmlToBlocks converts fragments with a separate image base', () {
    final blocks = htmlToBlocks(
      '<h1>Project</h1><p>Read <a href="docs/guide.md">the guide</a>.</p>'
      '<p><img src="docs/logo.png" alt="Logo"></p>',
      Uri.parse('https://github.com/o/r/blob/HEAD/'),
      imageBase: Uri.parse('https://raw.githubusercontent.com/o/r/HEAD/'),
    );
    expect(blocks.first, isA<HeadingBlock>());
    final link = (blocks[1] as ParagraphBlock).runs.firstWhere(
      (r) => r.link != null,
    );
    expect(
      link.link.toString(),
      'https://github.com/o/r/blob/HEAD/docs/guide.md',
    );
    final image = blocks.whereType<ImageBlock>().single;
    expect(
      image.url.toString(),
      'https://raw.githubusercontent.com/o/r/HEAD/docs/logo.png',
    );
  });
}
