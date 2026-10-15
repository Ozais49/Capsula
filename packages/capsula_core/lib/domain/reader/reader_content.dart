/// What the reader shows for a bookmark, chosen by content type.
sealed class ReaderContent {
  const ReaderContent();
}

/// Extracted readable text (articles, blogs, docs, Reddit posts, READMEs).
class ArticleContent extends ReaderContent {
  const ArticleContent({
    required this.title,
    required this.blocks,
    this.byline,
    this.siteName,
    this.leadImage,
    this.excerpt,
  });

  final String title;
  final String? byline;
  final String? siteName;
  final Uri? leadImage;

  /// Short summary from page metadata, if any.
  final String? excerpt;
  final List<ReaderBlock> blocks;

  /// Plain text length, used to decide if extraction found real content.
  int get textLength => blocks.fold(0, (sum, b) => sum + b.textLength);
}

/// A video, shown as a card that opens the video app or site.
class VideoContent extends ReaderContent {
  const VideoContent({
    required this.title,
    required this.videoUrl,
    this.thumbnail,
    this.channel,
  });

  final String title;
  final Uri videoUrl;
  final Uri? thumbnail;
  final String? channel;
}

/// Only metadata is available (social posts, products, short pages).
class PreviewContent extends ReaderContent {
  const PreviewContent({required this.metadata, this.note});

  final PageMetadata metadata;

  /// Why only a preview is shown, e.g. the site requires signing in.
  final String? note;
}

enum UnavailableReason {
  loginRequired('This page requires signing in.'),
  notFound('This page no longer exists.'),
  notHtml('This link is not a web page Capsula can read.'),
  blocked('This site can\'t be read inside Capsula on the web.'),
  network('Couldn\'t reach this page. Check your connection.'),
  noContent('Couldn\'t find readable content on this page.'),
  failed('Something went wrong reading this page.');

  const UnavailableReason(this.message);

  final String message;
}

/// The reader can't show this page; the user can still open it in the browser.
class Unavailable extends ReaderContent {
  const Unavailable(this.reason, {this.metadata});

  final UnavailableReason reason;

  /// Whatever metadata could still be read.
  final PageMetadata? metadata;
}

class PageMetadata {
  const PageMetadata({this.title, this.description, this.image, this.siteName});

  final String? title;
  final String? description;
  final Uri? image;
  final String? siteName;

  bool get isEmpty => title == null && description == null && image == null;
}

/// A run of inline text with simple formatting.
class InlineRun {
  const InlineRun(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.code = false,
    this.link,
  });

  final String text;
  final bool bold;
  final bool italic;
  final bool code;
  final Uri? link;
}

sealed class ReaderBlock {
  const ReaderBlock();

  int get textLength;
}

int _runsLength(List<InlineRun> runs) =>
    runs.fold(0, (sum, r) => sum + r.text.trim().length);

class HeadingBlock extends ReaderBlock {
  const HeadingBlock(this.level, this.runs);

  final int level;
  final List<InlineRun> runs;

  @override
  int get textLength => _runsLength(runs);
}

class ParagraphBlock extends ReaderBlock {
  const ParagraphBlock(this.runs);

  final List<InlineRun> runs;

  @override
  int get textLength => _runsLength(runs);
}

class ListBlock extends ReaderBlock {
  const ListBlock({required this.ordered, required this.items});

  final bool ordered;
  final List<List<InlineRun>> items;

  @override
  int get textLength => items.fold(0, (sum, i) => sum + _runsLength(i));
}

class QuoteBlock extends ReaderBlock {
  const QuoteBlock(this.blocks);

  final List<ReaderBlock> blocks;

  @override
  int get textLength => blocks.fold(0, (sum, b) => sum + b.textLength);
}

class CodeBlock extends ReaderBlock {
  const CodeBlock(this.text);

  final String text;

  @override
  int get textLength => text.length;
}

class ImageBlock extends ReaderBlock {
  const ImageBlock(this.url, {this.caption});

  final Uri url;
  final String? caption;

  @override
  int get textLength => 0;
}
