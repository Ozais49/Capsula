import 'dart:math' as math;

import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'reader_content.dart';

/// Reads title, description, image and site name from page metadata
/// (Open Graph, Twitter cards, standard tags).
PageMetadata extractMetadata(dom.Document doc, Uri base) {
  String? meta(List<String> keys) {
    for (final key in keys) {
      final el = doc.querySelector('meta[property="$key"], meta[name="$key"]');
      final content = el?.attributes['content']?.trim();
      if (content != null && content.isNotEmpty) return content;
    }
    return null;
  }

  final image = meta(['og:image', 'og:image:url', 'twitter:image']);
  return PageMetadata(
    title: meta(['og:title', 'twitter:title']) ?? _documentTitle(doc),
    description: meta(['og:description', 'twitter:description', 'description']),
    image: image == null ? null : _resolveHttp(base, image),
    siteName: meta(['og:site_name', 'application-name']),
  );
}

/// Extracts the main readable content of an HTML page. Returns null when
/// the page has less than [minTextLength] characters of article text.
ArticleContent? extractArticle(
  String html,
  Uri base, {
  int minTextLength = 400,
}) {
  final doc = html_parser.parse(html);
  final metadata = extractMetadata(doc, base);
  final body = doc.body;
  if (body == null) return null;

  _clean(body);
  final container = _pickContainer(body);
  var blocks = (_BlockBuilder(base, base)..visitChildren(container)).finish();

  final title = metadata.title ?? '';
  blocks = _dropLeadingTitle(blocks, title);

  final article = ArticleContent(
    title: title,
    byline: _byline(doc),
    siteName: metadata.siteName,
    leadImage: blocks.any((b) => b is ImageBlock) ? null : metadata.image,
    excerpt: metadata.description,
    blocks: blocks,
  );
  return article.textLength >= minTextLength ? article : null;
}

/// Converts an HTML fragment (a Reddit post body, a README) into blocks.
/// Relative image URLs resolve against [imageBase] when given.
List<ReaderBlock> htmlToBlocks(String html, Uri base, {Uri? imageBase}) {
  final fragment = html_parser.parseFragment(html);
  final root = dom.Element.tag('div')..nodes.addAll(fragment.nodes.toList());
  _clean(root);
  return (_BlockBuilder(base, imageBase ?? base)..visitChildren(root)).finish();
}

// ---------------------------------------------------------------------------
// Cleaning

const _removeTags = {
  'script',
  'style',
  'noscript',
  'iframe',
  'form',
  'nav',
  'header',
  'footer',
  'aside',
  'svg',
  'button',
  'input',
  'select',
  'textarea',
  'template',
  'canvas',
  'object',
  'embed',
  'link',
  'meta',
  'dialog',
};

final _negative = RegExp(
  r'comment|share|social|sidebar|footer|masthead|\bnav|menu|subscribe|'
  r'newsletter|promo|related|sponsor|advert|\bads?\b|ad-|banner|cookie|'
  r'popup|modal|breadcrumb|pagination|widget|outbrain|taboola|signup',
  caseSensitive: false,
);

final _positive = RegExp(
  r'article|content|post|entry|main|body|text|story|blog|prose|markdown',
  caseSensitive: false,
);

const _keepAlways = {'html', 'body', 'article', 'main'};

void _clean(dom.Element root) {
  for (final el in root.querySelectorAll('*').toList()) {
    if (el.parent == null && el != root) continue; // Already removed.
    final tag = el.localName ?? '';
    if (_removeTags.contains(tag) || _isHidden(el)) {
      el.remove();
      continue;
    }
    if (_keepAlways.contains(tag)) continue;
    final role = el.attributes['role'];
    if (role == 'navigation' ||
        role == 'banner' ||
        role == 'complementary' ||
        role == 'contentinfo' ||
        role == 'dialog') {
      el.remove();
      continue;
    }
    final marker = '${el.className} ${el.id}';
    if (marker.trim().isNotEmpty &&
        _negative.hasMatch(marker) &&
        !_positive.hasMatch(marker)) {
      el.remove();
    }
  }
}

bool _isHidden(dom.Element el) {
  if (el.attributes.containsKey('hidden')) return true;
  if (el.attributes['aria-hidden'] == 'true') return true;
  final style = el.attributes['style']?.replaceAll(' ', '').toLowerCase();
  return style != null &&
      (style.contains('display:none') || style.contains('visibility:hidden'));
}

// ---------------------------------------------------------------------------
// Choosing the content container

dom.Element _pickContainer(dom.Element body) {
  final semantic = [
    ...body.querySelectorAll('article'),
    ...body.querySelectorAll('main, [role="main"]'),
  ];
  dom.Element? bestSemantic;
  var bestLength = 0;
  for (final el in semantic) {
    final length = _paragraphTextLength(el);
    if (length > bestLength) {
      bestLength = length;
      bestSemantic = el;
    }
  }
  if (bestSemantic != null && bestLength >= 250) return bestSemantic;

  final scores = <dom.Element, double>{};
  for (final p in body.querySelectorAll('p, pre, td, blockquote')) {
    final text = p.text.trim();
    if (text.length < 25) continue;
    final score =
        1 + ','.allMatches(text).length + math.min(text.length / 100, 3);
    final parent = p.parent;
    if (parent == null) continue;
    scores[parent] = (scores[parent] ?? 0) + score;
    final grand = parent.parent;
    if (grand != null) scores[grand] = (scores[grand] ?? 0) + score / 2;
  }

  dom.Element? best;
  var bestScore = 0.0;
  scores.forEach((el, score) {
    final adjusted = score * (1 - _linkDensity(el));
    if (adjusted > bestScore) {
      bestScore = adjusted;
      best = el;
    }
  });
  return best ?? body;
}

int _paragraphTextLength(dom.Element el) =>
    el.querySelectorAll('p').fold(0, (sum, p) => sum + p.text.trim().length);

double _linkDensity(dom.Element el) {
  final total = el.text.trim().length;
  if (total == 0) return 0;
  final links = el
      .querySelectorAll('a')
      .fold(0, (sum, a) => sum + a.text.trim().length);
  return links / total;
}

// ---------------------------------------------------------------------------
// Converting to blocks

const _inlineTags = {
  'a',
  'strong',
  'b',
  'em',
  'i',
  'code',
  'kbd',
  'samp',
  'span',
  'small',
  'sup',
  'sub',
  'mark',
  'abbr',
  'time',
  'cite',
  'u',
  's',
  'del',
  'ins',
  'q',
  'var',
  'label',
  'font',
};

class _BlockBuilder {
  _BlockBuilder(this.base, this.imageBase);

  final Uri base;
  final Uri imageBase;
  final _blocks = <ReaderBlock>[];
  var _pending = <InlineRun>[];

  static const _maxBlocks = 3000;

  List<ReaderBlock> finish() {
    _flush();
    return _blocks;
  }

  void visitChildren(dom.Node node) {
    for (final child in node.nodes) {
      if (_blocks.length >= _maxBlocks) return;
      _visit(child);
    }
  }

  void _visit(dom.Node node) {
    if (node is dom.Text) {
      _pending.addAll(_inline(node));
      return;
    }
    if (node is! dom.Element) return;
    final tag = node.localName ?? '';

    switch (tag) {
      case 'h1' || 'h2' || 'h3' || 'h4' || 'h5' || 'h6':
        _flush();
        final runs = _trimRuns(_inline(node));
        if (runs.isNotEmpty) {
          _blocks.add(HeadingBlock(int.parse(tag.substring(1)), runs));
        }
      case 'p':
        _flush();
        _paragraph(_inline(node));
        _images(node);
      case 'ul' || 'ol':
        _flush();
        _list(node, ordered: tag == 'ol');
      case 'blockquote':
        _flush();
        final inner = (_BlockBuilder(
          base,
          imageBase,
        )..visitChildren(node)).finish();
        if (inner.isNotEmpty) _blocks.add(QuoteBlock(inner));
      case 'pre':
        _flush();
        final text = node.text.replaceAll(RegExp(r'^\n+|\s+$'), '');
        if (text.isNotEmpty) _blocks.add(CodeBlock(text));
      case 'img':
        _flush();
        _image(node);
      case 'figure' || 'picture':
        _flush();
        final img = node.localName == 'img' ? node : node.querySelector('img');
        if (img != null) {
          final caption = node.querySelector('figcaption')?.text.trim();
          _image(
            img,
            caption: caption == null || caption.isEmpty ? null : caption,
          );
        }
      case 'br':
        _pending.add(const InlineRun('\n'));
      case 'hr':
        _flush();
      case 'table':
        _flush();
        for (final row in node.querySelectorAll('tr')) {
          final cells = row.children
              .where((c) => c.localName == 'td' || c.localName == 'th')
              .map((c) => c.text.trim().replaceAll(RegExp(r'\s+'), ' '))
              .where((t) => t.isNotEmpty);
          if (cells.isNotEmpty) {
            _blocks.add(ParagraphBlock([InlineRun(cells.join('  ·  '))]));
          }
        }
      default:
        if (_inlineTags.contains(tag)) {
          _pending.addAll(_inline(node));
        } else {
          // div, section, article, li outside lists, etc.
          _flush();
          visitChildren(node);
          _flush();
        }
    }
  }

  void _flush() {
    _paragraph(_pending);
    _pending = [];
  }

  void _paragraph(List<InlineRun> runs) {
    final trimmed = _trimRuns(runs);
    if (trimmed.isEmpty) return;
    // Skip short link lists that survived cleaning (e.g. "Share · Tweet").
    final text = trimmed.fold(0, (n, r) => n + r.text.length);
    final linked = trimmed
        .where((r) => r.link != null)
        .fold(0, (n, r) => n + r.text.length);
    if (text < 80 && linked / text > 0.6 && trimmed.length > 1) return;
    _blocks.add(ParagraphBlock(trimmed));
  }

  void _list(dom.Element list, {required bool ordered}) {
    final items = <List<InlineRun>>[];
    for (final li in list.children.where((c) => c.localName == 'li')) {
      final runs = _trimRuns(_inline(li));
      if (runs.isNotEmpty) items.add(runs);
    }
    if (items.isNotEmpty) {
      _blocks.add(ListBlock(ordered: ordered, items: items));
    }
  }

  void _images(dom.Element el) {
    for (final img in el.querySelectorAll('img')) {
      _image(img);
    }
  }

  void _image(dom.Element img, {String? caption}) {
    final width = int.tryParse(img.attributes['width'] ?? '');
    final height = int.tryParse(img.attributes['height'] ?? '');
    if ((width != null && width <= 2) || (height != null && height <= 2)) {
      return; // Tracking pixel.
    }
    final src = _imageSource(img);
    if (src == null) return;
    final url = _resolveHttp(imageBase, src);
    if (url == null) return;
    final alt = img.attributes['alt']?.trim();
    _blocks.add(
      ImageBlock(
        url,
        caption: caption ?? (alt == null || alt.isEmpty ? null : alt),
      ),
    );
  }

  List<InlineRun> _inline(
    dom.Node node, {
    bool bold = false,
    bool italic = false,
    bool code = false,
    Uri? link,
  }) {
    if (node is dom.Text) {
      final text = node.text.replaceAll(RegExp(r'\s+'), ' ');
      if (text.isEmpty) return const [];
      return [
        InlineRun(text, bold: bold, italic: italic, code: code, link: link),
      ];
    }
    if (node is! dom.Element) return const [];
    final tag = node.localName ?? '';
    if (tag == 'br') return const [InlineRun('\n')];
    if (tag == 'img' || tag == 'figure' || tag == 'picture') return const [];

    var b = bold, i = italic, c = code;
    var href = link;
    switch (tag) {
      case 'strong' || 'b':
        b = true;
      case 'em' || 'i' || 'cite':
        i = true;
      case 'code' || 'kbd' || 'samp':
        c = true;
      case 'a':
        final raw = node.attributes['href'];
        if (raw != null && !raw.startsWith('#')) {
          href = _resolveHttp(base, raw) ?? href;
        }
    }
    return [
      for (final child in node.nodes)
        ..._inline(child, bold: b, italic: i, code: c, link: href),
    ];
  }
}

String? _imageSource(dom.Element img) {
  for (final attr in ['data-src', 'data-lazy-src', 'data-original', 'src']) {
    final value = img.attributes[attr]?.trim();
    if (value != null && value.isNotEmpty && !value.startsWith('data:')) {
      return value;
    }
  }
  final srcset = img.attributes['srcset'] ?? img.attributes['data-srcset'];
  if (srcset != null && srcset.trim().isNotEmpty) {
    // The last candidate is usually the largest.
    return srcset.split(',').last.trim().split(RegExp(r'\s+')).first;
  }
  return null;
}

/// Trims whitespace at the edges and drops empty runs.
List<InlineRun> _trimRuns(List<InlineRun> runs) {
  final result = runs.where((r) => r.text.isNotEmpty).toList();
  while (result.isNotEmpty && result.first.text.trim().isEmpty) {
    result.removeAt(0);
  }
  while (result.isNotEmpty && result.last.text.trim().isEmpty) {
    result.removeLast();
  }
  if (result.isEmpty) return result;
  result[0] = _withText(result[0], result[0].text.trimLeft());
  result[result.length - 1] = _withText(
    result.last,
    result.last.text.trimRight(),
  );
  return result;
}

InlineRun _withText(InlineRun r, String text) =>
    InlineRun(text, bold: r.bold, italic: r.italic, code: r.code, link: r.link);

List<ReaderBlock> _dropLeadingTitle(List<ReaderBlock> blocks, String title) {
  if (blocks.isEmpty || title.isEmpty) return blocks;
  final first = blocks.first;
  if (first is HeadingBlock) {
    final text = first.runs.map((r) => r.text).join().trim().toLowerCase();
    final t = title.trim().toLowerCase();
    if (text == t || t.startsWith(text) || text.startsWith(t)) {
      return blocks.sublist(1);
    }
  }
  return blocks;
}

String? _documentTitle(dom.Document doc) {
  final raw = doc.querySelector('title')?.text.trim();
  if (raw != null && raw.isNotEmpty) {
    // "Article title | Site name" → "Article title"
    final parts = raw.split(RegExp(r'\s+[|\-–—·]\s+'));
    if (parts.length > 1 && parts.first.split(' ').length >= 2) {
      return parts.first.trim();
    }
    return raw;
  }
  final h1 = doc.querySelector('h1')?.text.trim();
  return h1 == null || h1.isEmpty ? null : h1;
}

String? _byline(dom.Document doc) {
  final author = doc
      .querySelector('meta[name="author"], meta[property="article:author"]')
      ?.attributes['content']
      ?.trim();
  if (author != null && author.isNotEmpty && !author.startsWith('http')) {
    return author;
  }
  final rel = doc
      .querySelector('[rel="author"], .byline, .author')
      ?.text
      .trim();
  return rel == null || rel.isEmpty || rel.length > 100 ? null : rel;
}

Uri? _resolveHttp(Uri base, String ref) {
  try {
    final resolved = base.resolve(ref.trim());
    return resolved.scheme == 'http' || resolved.scheme == 'https'
        ? resolved
        : null;
  } on FormatException {
    return null;
  }
}
