import 'dart:convert';

import 'package:html/parser.dart' as html_parser;

import '../bookmarks/bookmark.dart';
import '../bookmarks/bookmark_source.dart';
import 'article_extractor.dart';
import 'content_fetcher.dart';
import 'reader_content.dart';

/// Decides how to present a bookmark in the reader, by content type.
/// Never throws: failures become [Unavailable], and the bookmark itself is
/// never touched.
class ReaderService {
  ReaderService(this._fetcher);

  final ContentFetcher _fetcher;

  static const _socialNote =
      'Full content is only available on the site or in its app.';

  Future<ReaderContent> load(Bookmark bookmark) async {
    final uri = Uri.tryParse(bookmark.url);
    if (uri == null) return const Unavailable(UnavailableReason.failed);

    try {
      return switch (bookmark.source) {
        BookmarkSource.youtube => await _youtube(uri, bookmark),
        BookmarkSource.reddit when _isRedditPost(uri) => await _reddit(uri),
        BookmarkSource.github when _githubRepo(uri) != null => await _github(
          uri,
        ),
        BookmarkSource.instagram ||
        BookmarkSource.facebook ||
        BookmarkSource.tiktok ||
        BookmarkSource.x ||
        BookmarkSource.amazon => await _preview(uri, note: _socialNote),
        _ => await _article(uri),
      };
    } on FetchException catch (e) {
      return Unavailable(
        e.failure == FetchFailure.blocked
            ? UnavailableReason.blocked
            : UnavailableReason.network,
      );
    } on Object {
      return const Unavailable(UnavailableReason.failed);
    }
  }

  // -------------------------------------------------------------------------
  // Generic pages

  Future<ReaderContent> _article(Uri uri) async {
    final page = await _fetcher.fetch(uri);
    final problem = _checkResponse(uri, page);
    if (problem != null) return problem;

    final article = extractArticle(page.body, page.finalUrl);
    if (article != null) return article;

    final metadata = extractMetadata(
      html_parser.parse(page.body),
      page.finalUrl,
    );
    return metadata.isEmpty
        ? const Unavailable(UnavailableReason.noContent)
        : PreviewContent(metadata: metadata);
  }

  Future<ReaderContent> _preview(Uri uri, {String? note}) async {
    final page = await _fetcher.fetch(uri);
    final problem = _checkResponse(uri, page);
    if (problem != null) return problem;

    final metadata = extractMetadata(
      html_parser.parse(page.body),
      page.finalUrl,
    );
    return metadata.isEmpty
        ? const Unavailable(UnavailableReason.noContent)
        : PreviewContent(metadata: metadata, note: note);
  }

  /// Maps HTTP problems to [Unavailable]; null when the page is usable.
  Unavailable? _checkResponse(Uri requested, FetchedPage page) {
    final status = page.statusCode;
    if (status == 401 || status == 403) {
      return const Unavailable(UnavailableReason.loginRequired);
    }
    if (status == 404 || status == 410) {
      return const Unavailable(UnavailableReason.notFound);
    }
    if (status >= 400) return const Unavailable(UnavailableReason.failed);
    if (_redirectedToLogin(requested, page.finalUrl)) {
      return const Unavailable(UnavailableReason.loginRequired);
    }
    if (!page.isHtml) return const Unavailable(UnavailableReason.notHtml);
    return null;
  }

  static final _loginPath = RegExp(
    r'/(login|signin|sign-in|log-in|accounts/login|auth)\b',
    caseSensitive: false,
  );

  static bool _redirectedToLogin(Uri requested, Uri finalUrl) =>
      finalUrl != requested &&
      _loginPath.hasMatch(finalUrl.path) &&
      !_loginPath.hasMatch(requested.path);

  // -------------------------------------------------------------------------
  // YouTube

  Future<ReaderContent> _youtube(Uri uri, Bookmark bookmark) async {
    final id = youtubeVideoId(uri);
    if (id == null) return _preview(uri);

    var title = bookmark.displayTitle;
    String? channel;
    try {
      final page = await _fetcher.fetch(
        Uri.https('www.youtube.com', '/oembed', {
          'format': 'json',
          'url': uri.toString(),
        }),
      );
      if (page.statusCode == 200) {
        final json = jsonDecode(page.body) as Map<String, Object?>;
        title = json['title'] as String? ?? title;
        channel = json['author_name'] as String?;
      }
    } on Object {
      // The video card works without oEmbed details.
    }
    return VideoContent(
      title: title,
      videoUrl: uri,
      thumbnail: Uri.https('i.ytimg.com', '/vi/$id/hqdefault.jpg'),
      channel: channel,
    );
  }

  // -------------------------------------------------------------------------
  // Reddit

  static bool _isRedditPost(Uri uri) {
    final s = uri.pathSegments.where((p) => p.isNotEmpty).toList();
    return s.length >= 4 && s[0] == 'r' && s[2] == 'comments';
  }

  Future<ReaderContent> _reddit(Uri uri) async {
    final path = uri.path.replaceFirst(RegExp(r'/+$'), '');
    final page = await _fetcher.fetch(
      Uri.https('www.reddit.com', '$path.json', {'raw_json': '1'}),
    );
    if (page.statusCode != 200) return _preview(uri);

    final Map<String, Object?> post;
    try {
      final listing = jsonDecode(page.body) as List<Object?>;
      final data = (listing.first as Map)['data'] as Map;
      post =
          ((data['children'] as List).first as Map)['data']
              as Map<String, Object?>;
    } on Object {
      return _preview(uri);
    }

    final base = Uri.https('www.reddit.com', path);
    final blocks = <ReaderBlock>[];
    final selfHtml = post['selftext_html'] as String?;
    if (selfHtml != null && selfHtml.isNotEmpty) {
      blocks.addAll(htmlToBlocks(selfHtml, base));
    }
    final linked = post['url_overridden_by_dest'] as String?;
    final linkedUri = linked == null ? null : Uri.tryParse(linked);
    if (linkedUri != null && linkedUri.hasScheme) {
      blocks.add(
        ParagraphBlock([
          const InlineRun('Link: ', bold: true),
          InlineRun(linked!, link: linkedUri),
        ]),
      );
    }

    final author = post['author'] as String?;
    final subreddit = post['subreddit_name_prefixed'] as String?;
    return ArticleContent(
      title: post['title'] as String? ?? '',
      byline: [?(author == null ? null : 'u/$author'), ?subreddit].join(' · '),
      siteName: 'Reddit',
      leadImage: _redditImage(post),
      blocks: blocks,
    );
  }

  static Uri? _redditImage(Map<String, Object?> post) {
    try {
      final images = (post['preview'] as Map?)?['images'] as List?;
      final source = (images?.first as Map?)?['source'] as Map?;
      final url = source?['url'] as String?;
      return url == null ? null : Uri.tryParse(url);
    } on Object {
      return null;
    }
  }

  // -------------------------------------------------------------------------
  // GitHub

  /// `(owner, repo)` for repository home pages.
  static (String, String)? _githubRepo(Uri uri) {
    final s = uri.pathSegments.where((p) => p.isNotEmpty).toList();
    return s.length == 2 ? (s[0], s[1]) : null;
  }

  Future<ReaderContent> _github(Uri uri) async {
    final (owner, repo) = _githubRepo(uri)!;
    final page = await _fetcher.fetch(
      Uri.https('api.github.com', '/repos/$owner/$repo/readme'),
      headers: {'Accept': 'application/vnd.github.html+json'},
    );
    if (page.statusCode != 200) return _article(uri);

    final blocks = htmlToBlocks(
      page.body,
      Uri.https('github.com', '/$owner/$repo/blob/HEAD/'),
      imageBase: Uri.https('raw.githubusercontent.com', '/$owner/$repo/HEAD/'),
    );
    return ArticleContent(
      title: '$owner/$repo',
      siteName: 'GitHub',
      blocks: blocks,
    );
  }
}

/// The video ID of a YouTube watch, shorts, embed or youtu.be URL.
String? youtubeVideoId(Uri uri) {
  final host = uri.host.toLowerCase();
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (host.endsWith('youtu.be')) {
    return segments.isEmpty ? null : segments.first;
  }
  if (uri.queryParameters['v'] case final v? when v.isNotEmpty) return v;
  if (segments.length >= 2 &&
      (segments[0] == 'shorts' ||
          segments[0] == 'embed' ||
          segments[0] == 'live')) {
    return segments[1];
  }
  return null;
}

/// Metadata worth saving back to the bookmark from what the reader loaded.
PageMetadata? metadataFrom(ReaderContent content) => switch (content) {
  ArticleContent(
    :final title,
    :final excerpt,
    :final leadImage,
    :final siteName,
  ) =>
    PageMetadata(
      title: title.isEmpty ? null : title,
      description: excerpt,
      image: leadImage,
      siteName: siteName,
    ),
  VideoContent(:final title, :final thumbnail) => PageMetadata(
    title: title,
    image: thumbnail,
  ),
  PreviewContent(:final metadata) => metadata,
  Unavailable(:final metadata) => metadata,
};
