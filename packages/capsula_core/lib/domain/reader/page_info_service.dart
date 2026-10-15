import 'dart:convert';

import 'package:html/parser.dart' as html_parser;

import '../bookmarks/bookmark_source.dart';
import '../bookmarks/url_normalizer.dart';
import 'article_extractor.dart';
import 'content_fetcher.dart';
import 'reader_content.dart';

/// Looks up a link's title and details: locally ([PageInfoService]) or
/// through the Capsula API.
abstract interface class PageInfoSource {
  /// Returns null when nothing useful could be found. Never throws.
  Future<PageMetadata?> lookup(Uri url);
}

/// Looks up a link's real title, description and image from the source:
/// official oEmbed endpoints where they exist, otherwise the page metadata.
class PageInfoService implements PageInfoSource {
  PageInfoService(this._fetcher);

  final ContentFetcher _fetcher;

  /// Instagram and Facebook only serve page metadata to link-preview
  /// crawlers, so ask the way link previews in messaging apps do.
  static const _previewAgent =
      'facebookexternalhit/1.1 (+http://www.facebook.com/externalhit_uatext.php)';

  @override
  Future<PageMetadata?> lookup(Uri url) async {
    final source = BookmarkSource.fromHost(displayHost(url));
    try {
      final metadata = switch (source) {
        BookmarkSource.youtube => await _oembed(
          Uri.https('www.youtube.com', '/oembed', {
            'format': 'json',
            'url': url.toString(),
          }),
        ),
        BookmarkSource.tiktok => await _oembed(
          Uri.https('www.tiktok.com', '/oembed', {'url': url.toString()}),
        ),
        BookmarkSource.x => await _xPost(url),
        BookmarkSource.reddit => await _redditPost(url) ?? await _page(url),
        BookmarkSource.instagram ||
        BookmarkSource.facebook => await _page(url, userAgent: _previewAgent),
        _ => await _page(url),
      };
      return metadata == null ? null : _clean(metadata);
    } on Object {
      return null;
    }
  }

  Future<PageMetadata?> _page(Uri url, {String? userAgent}) async {
    final page = await _fetcher.fetch(url, headers: {'User-Agent': ?userAgent});
    if (page.statusCode != 200 || !page.isHtml) return null;
    return extractMetadata(html_parser.parse(page.body), page.finalUrl);
  }

  Future<PageMetadata?> _oembed(Uri endpoint) async {
    final json = await _json(endpoint);
    if (json is! Map) return null;
    final author = json['author_name'] as String?;
    var title = (json['title'] as String?)?.trim();
    if ((title == null || title.isEmpty) && author != null) {
      title = '$author on ${json['provider_name'] ?? 'video'}';
    }
    final thumbnail = json['thumbnail_url'] as String?;
    return PageMetadata(
      title: title,
      siteName: json['provider_name'] as String?,
      image: thumbnail == null ? null : Uri.tryParse(thumbnail),
    );
  }

  /// X posts: "Author: post text" from the oEmbed HTML.
  Future<PageMetadata?> _xPost(Uri url) async {
    final json = await _json(
      Uri.https('publish.twitter.com', '/oembed', {
        'url': url.toString(),
        'omit_script': '1',
      }),
    );
    if (json is! Map) return null;
    final author = json['author_name'] as String?;
    final html = json['html'] as String?;
    final text = html == null
        ? null
        : html_parser.parseFragment(html).querySelector('p')?.text.trim();
    final title = [
      ?author,
      if (text != null && text.isNotEmpty) text,
    ].join(': ');
    return PageMetadata(title: title.isEmpty ? null : title, siteName: 'X');
  }

  /// Reddit posts: share links (`/r/<sub>/s/<code>`) are followed to the
  /// post first. The JSON API is tried, then the post's RSS feed, which
  /// Reddit serves even where it blocks the API.
  Future<PageMetadata?> _redditPost(Uri url) async {
    var post = url;
    if (_segments(post) case [_, _, 's', _, ...]) {
      post = (await _fetcher.fetch(post)).finalUrl;
    }
    final s = _segments(post);
    if (s.length < 4 || s[0] != 'r' || s[2] != 'comments') return null;
    final path = post.path.replaceFirst(RegExp(r'/+$'), '');

    try {
      final json = await _json(
        Uri.https('www.reddit.com', '$path.json', {'raw_json': '1'}),
      );
      if (json is List && json.isNotEmpty) {
        final data =
            ((((json.first as Map)['data'] as Map)['children'] as List).first
                    as Map)['data']
                as Map;
        final image =
            ((((data['preview'] as Map?)?['images'] as List?)?.firstOrNull
                        as Map?)?['source']
                    as Map?)?['url']
                as String?;
        return PageMetadata(
          title: data['title'] as String?,
          siteName: data['subreddit_name_prefixed'] as String? ?? 'Reddit',
          image: image == null ? null : Uri.tryParse(image),
        );
      }
    } on Object {
      // Fall through to RSS.
    }

    final feed = await _fetcher.fetch(
      Uri.https('www.reddit.com', '$path/.rss'),
    );
    if (feed.statusCode != 200) return null;
    final entry = feed.body.indexOf('<entry');
    if (entry == -1) return null;
    final title = RegExp(r'<title[^>]*>([^<]*)</title>')
        .firstMatch(feed.body.substring(entry))
        ?.group(1);
    return PageMetadata(
      title: title == null ? null : _decodeEntities(title),
      siteName: 'r/${s[1]}',
    );
  }

  static List<String> _segments(Uri url) =>
      url.pathSegments.where((p) => p.isNotEmpty).toList();

  static String _decodeEntities(String text) =>
      html_parser.parseFragment(text).text ?? text;
  Future<Object?> _json(Uri endpoint) async {
    final page = await _fetcher.fetch(
      endpoint,
      headers: {'Accept': 'application/json'},
    );
    if (page.statusCode != 200) return null;
    return jsonDecode(page.body);
  }

  /// Drops titles that only name the site (login walls, error pages).
  static PageMetadata? _clean(PageMetadata m) {
    final title = m.title?.trim().replaceAll(RegExp(r'\s+'), ' ');
    final usable = title != null && title.isNotEmpty && !isGenericTitle(title);
    final cleaned = PageMetadata(
      title: usable ? title : null,
      description: m.description,
      image: m.image,
      siteName: m.siteName,
    );
    return cleaned.isEmpty ? null : cleaned;
  }
}

const _genericTitles = {
  'instagram',
  'login • instagram',
  'instagram login',
  'facebook',
  'log in or sign up to view',
  'log into facebook',
  'youtube',
  'reddit',
  'reddit - dive into anything',
  'reddit - the heart of the internet',
  'x',
  'twitter',
  'tiktok',
  'tiktok - make your day',
  'amazon.com',
  'just a moment...',
  'access denied',
  'page not found',
  '404 not found',
  'sign in',
  'log in',
  'attention required! | cloudflare',
};

/// True for titles that name a site or an error rather than the content.
bool isGenericTitle(String title) =>
    _genericTitles.contains(title.trim().toLowerCase());
