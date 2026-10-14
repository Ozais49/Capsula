import 'dart:convert';

import 'package:capsula/domain/bookmarks/bookmark.dart';
import 'package:capsula/domain/bookmarks/bookmark_source.dart';
import 'package:capsula/domain/bookmarks/url_normalizer.dart';
import 'package:capsula/domain/reader/content_fetcher.dart';
import 'package:capsula/domain/reader/reader_content.dart';
import 'package:capsula/domain/reader/reader_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_content_fetcher.dart';

Bookmark _bookmark(String url, {String? title}) {
  final uri = Uri.parse(url);
  final host = displayHost(uri);
  final t = DateTime(2026);
  return Bookmark(
    id: 'b1',
    url: url,
    canonicalUrl: canonicalizeUrl(uri),
    title: title ?? titleFromUrl(uri),
    source: BookmarkSource.fromHost(host),
    sourceDomain: host,
    createdAt: t,
    updatedAt: t,
  );
}

String _longArticle(String title) =>
    '<html><head><title>$title</title></head><body><article>'
    '${List.generate(5, (i) => '<p>Paragraph $i has enough words, commas, and length to count as real article text for extraction.</p>').join()}'
    '</article></body></html>';

void main() {
  late FakeContentFetcher fetcher;
  late ReaderService reader;

  setUp(() {
    fetcher = FakeContentFetcher();
    reader = ReaderService(fetcher);
  });

  group('websites', () {
    test('extracts an article', () async {
      fetcher.html('https://blog.example.com/', _longArticle('Rice guide'));
      final content = await reader.load(
        _bookmark('https://blog.example.com/rice'),
      );
      expect(content, isA<ArticleContent>());
      expect((content as ArticleContent).title, 'Rice guide');
    });

    test('short pages become a metadata preview', () async {
      fetcher.html(
        'https://example.com/',
        '<html><head><meta property="og:title" content="Landing">'
            '<meta name="description" content="Welcome"></head>'
            '<body><p>Hi</p></body></html>',
      );
      final content = await reader.load(_bookmark('https://example.com/'));
      expect(content, isA<PreviewContent>());
      expect((content as PreviewContent).metadata.title, 'Landing');
    });

    test('pages with nothing readable are unavailable', () async {
      fetcher.html('https://example.com/', '<html><body></body></html>');
      final content = await reader.load(_bookmark('https://example.com/x'));
      expect((content as Unavailable).reason, UnavailableReason.noContent);
    });

    test('maps HTTP problems to reasons', () async {
      for (final (status, reason) in [
        (401, UnavailableReason.loginRequired),
        (403, UnavailableReason.loginRequired),
        (404, UnavailableReason.notFound),
        (410, UnavailableReason.notFound),
        (500, UnavailableReason.failed),
      ]) {
        fetcher.html('https://example.com/', 'x', status: status);
        final content = await reader.load(_bookmark('https://example.com/p'));
        expect((content as Unavailable).reason, reason, reason: '$status');
      }
    });

    test('a redirect to a login page needs sign-in', () async {
      fetcher.html(
        'https://example.com/',
        _longArticle('Sign in'),
        finalUrl: Uri.parse('https://example.com/login?next=/private'),
      );
      final content = await reader.load(
        _bookmark('https://example.com/private'),
      );
      expect((content as Unavailable).reason, UnavailableReason.loginRequired);
    });

    test('non-HTML links are not read', () async {
      fetcher.raw(
        'https://example.com/',
        FetchedPage(
          statusCode: 200,
          body: '%PDF-1.7',
          finalUrl: Uri.parse('https://example.com/file.pdf'),
          contentType: 'application/pdf',
        ),
      );
      final content = await reader.load(
        _bookmark('https://example.com/file.pdf'),
      );
      expect((content as Unavailable).reason, UnavailableReason.notHtml);
    });

    test('network failures and blocked requests are reported', () async {
      fetcher.failure = const FetchException(FetchFailure.network);
      expect(
        ((await reader.load(
          _bookmark('https://example.com/a'),
        )) as Unavailable).reason,
        UnavailableReason.network,
      );

      fetcher.failure = const FetchException(FetchFailure.blocked);
      expect(
        ((await reader.load(
          _bookmark('https://example.com/a'),
        )) as Unavailable).reason,
        UnavailableReason.blocked,
      );
    });
  });

  group('YouTube', () {
    test('shows a video card with oEmbed details', () async {
      fetcher.json(
        'https://www.youtube.com/oembed',
        jsonEncode({
          'title': 'Flutter in 100 seconds',
          'author_name': 'Fireship',
        }),
      );
      final content = await reader.load(
        _bookmark('https://www.youtube.com/watch?v=abc123&t=10'),
      );
      final video = content as VideoContent;
      expect(video.title, 'Flutter in 100 seconds');
      expect(video.channel, 'Fireship');
      expect(
        video.thumbnail.toString(),
        'https://i.ytimg.com/vi/abc123/hqdefault.jpg',
      );
    });

    test('still shows the video card offline', () async {
      fetcher.failure = const FetchException(FetchFailure.network);
      final content = await reader.load(
        _bookmark('https://youtu.be/xyz789', title: 'Saved title'),
      );
      expect((content as VideoContent).title, 'Saved title');
    });

    test('finds video IDs in all URL forms', () {
      for (final (url, id) in [
        ('https://www.youtube.com/watch?v=a1', 'a1'),
        ('https://youtu.be/b2?si=x', 'b2'),
        ('https://youtube.com/shorts/c3', 'c3'),
        ('https://www.youtube.com/embed/d4', 'd4'),
        ('https://www.youtube.com/@channel', null),
      ]) {
        expect(youtubeVideoId(Uri.parse(url)), id, reason: url);
      }
    });
  });

  group('Reddit', () {
    const post = 'https://www.reddit.com/r/FlutterDev/comments/abc/hot_reload/';

    test('reads a post through the JSON API', () async {
      fetcher.json(
        'https://www.reddit.com/r/FlutterDev/comments/abc/hot_reload.json',
        jsonEncode([
          {
            'data': {
              'children': [
                {
                  'data': {
                    'title': 'How hot reload works',
                    'author': 'dash',
                    'subreddit_name_prefixed': 'r/FlutterDev',
                    'selftext_html': '<div class="md"><p>It injects <strong>new code</strong>.</p></div>',
                    'url_overridden_by_dest':
                        'https://docs.flutter.dev/hot-reload',
                    'preview': {
                      'images': [
                        {
                          'source': {'url': 'https://preview.redd.it/x.jpg'},
                        },
                      ],
                    },
                  },
                },
              ],
            },
          },
        ]),
      );

      final article = await reader.load(_bookmark(post)) as ArticleContent;
      expect(article.title, 'How hot reload works');
      expect(article.byline, 'u/dash · r/FlutterDev');
      expect(article.leadImage.toString(), 'https://preview.redd.it/x.jpg');
      expect(article.blocks.first, isA<ParagraphBlock>());
      final link = article.blocks.last as ParagraphBlock;
      expect(
        link.runs.last.link.toString(),
        'https://docs.flutter.dev/hot-reload',
      );
      expect(fetcher.requests.single.queryParameters['raw_json'], '1');
    });

    test('falls back to a preview when the API refuses', () async {
      fetcher.json('https://www.reddit.com/r/', '{}', status: 429);
      fetcher.html(
        'https://www.reddit.com/r/FlutterDev/comments/',
        '<meta property="og:title" content="Post title">',
      );
      final content = await reader.load(_bookmark(post));
      expect((content as PreviewContent).metadata.title, 'Post title');
    });
  });

  group('GitHub', () {
    test('shows a repository README', () async {
      fetcher.html(
        'https://api.github.com/repos/flutter/flutter/readme',
        '<h1>Flutter</h1><p>Flutter is Google\'s UI toolkit for building apps.</p>'
            '<img src="docs/logo.png">',
      );
      final article = await reader.load(
        _bookmark('https://github.com/flutter/flutter'),
      ) as ArticleContent;

      expect(article.title, 'flutter/flutter');
      expect(article.siteName, 'GitHub');
      expect(
        article.blocks.whereType<ImageBlock>().single.url.toString(),
        'https://raw.githubusercontent.com/flutter/flutter/HEAD/docs/logo.png',
      );
      expect(fetcher.requestHeaders.single['Accept'], contains('html'));
    });

    test('other GitHub pages are read as articles', () async {
      fetcher.html(
        'https://github.com/o/r/issues/1',
        _longArticle('Bug report'),
      );
      final content = await reader.load(
        _bookmark('https://github.com/o/r/issues/1'),
      );
      expect((content as ArticleContent).title, 'Bug report');
    });
  });

  test('social and shopping links show a preview with a note', () async {
    fetcher.html(
      'https://www.instagram.com/',
      '<meta property="og:title" content="A photo">'
          '<meta property="og:image" content="https://cdn.instagram.com/p.jpg">',
    );
    final content = await reader.load(
      _bookmark('https://www.instagram.com/p/Cabc/'),
    );
    final preview = content as PreviewContent;
    expect(preview.metadata.title, 'A photo');
    expect(preview.note, isNotNull);
  });

  test('metadataFrom picks what can enrich a bookmark', () {
    expect(
      metadataFrom(
        VideoContent(title: 'T', videoUrl: Uri.parse('https://youtu.be/x')),
      )?.title,
      'T',
    );
    expect(metadataFrom(const Unavailable(UnavailableReason.network)), isNull);
  });
}
