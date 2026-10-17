import 'dart:convert';

import 'package:capsula_core/domain/reader/content_fetcher.dart';
import 'package:capsula_core/domain/reader/page_info_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_content_fetcher.dart';

void main() {
  late FakeContentFetcher fetcher;
  late PageInfoService pageInfo;

  setUp(() {
    fetcher = FakeContentFetcher();
    pageInfo = PageInfoService(fetcher);
  });

  test('YouTube titles come from oEmbed', () async {
    fetcher.json(
      'https://www.youtube.com/oembed',
      jsonEncode({
        'title': 'Flutter in 100 Seconds',
        'author_name': 'Fireship',
        'provider_name': 'YouTube',
        'thumbnail_url': 'https://i.ytimg.com/vi/abc/hqdefault.jpg',
      }),
    );
    final info = await pageInfo.lookup(Uri.parse('https://youtu.be/abc?si=x'));
    expect(info?.title, 'Flutter in 100 Seconds');
    expect(info?.image.toString(), 'https://i.ytimg.com/vi/abc/hqdefault.jpg');
    expect(
      fetcher.requests.single.queryParameters['url'],
      'https://youtu.be/abc?si=x',
    );
  });

  test('TikTok titles come from oEmbed, falling back to the author', () async {
    fetcher.json(
      'https://www.tiktok.com/oembed',
      jsonEncode({
        'title': '',
        'author_name': 'chef',
        'provider_name': 'TikTok',
      }),
    );
    final info = await pageInfo.lookup(
      Uri.parse('https://www.tiktok.com/@chef/video/123'),
    );
    expect(info?.title, 'chef on TikTok');
  });

  test('X posts become "author: text"', () async {
    fetcher.json(
      'https://publish.twitter.com/oembed',
      jsonEncode({
        'author_name': 'Flutter',
        'html':
            '<blockquote><p lang="en">Flutter 4 is out! <a href="#">link</a></p>'
            '&mdash; Flutter</blockquote>',
      }),
    );
    final info = await pageInfo.lookup(
      Uri.parse('https://x.com/FlutterDev/status/1'),
    );
    expect(info?.title, 'Flutter: Flutter 4 is out! link');
  });

  test('Reddit posts use the JSON title', () async {
    fetcher.json(
      'https://www.reddit.com/r/FlutterDev/comments/abc/x.json',
      jsonEncode([
        {
          'data': {
            'children': [
              {
                'data': {
                  'title': 'How does hot reload work?',
                  'subreddit_name_prefixed': 'r/FlutterDev',
                },
              },
            ],
          },
        },
      ]),
    );
    final info = await pageInfo.lookup(
      Uri.parse('https://www.reddit.com/r/FlutterDev/comments/abc/x/'),
    );
    expect(info?.title, 'How does hot reload work?');
    expect(info?.siteName, 'r/FlutterDev');
  });

  test('Reddit share links fall back to the page title', () async {
    fetcher.html(
      'https://www.reddit.com/r/FlutterDev/s/',
      '<meta property="og:title" content="A great thread">',
    );
    final info = await pageInfo.lookup(
      Uri.parse('https://www.reddit.com/r/FlutterDev/s/AbCdEf'),
    );
    expect(info?.title, 'A great thread');
  });

  test('Instagram is asked the way link previews ask', () async {
    fetcher.html(
      'https://www.instagram.com/',
      '<meta property="og:title" content="Chef Sam on Instagram: &quot;Perfect rice&quot;">'
          '<meta property="og:image" content="https://cdn.instagram.com/p.jpg">',
    );
    final info = await pageInfo.lookup(
      Uri.parse('https://www.instagram.com/reel/Cabc/?igsh=x'),
    );
    expect(info?.title, 'Chef Sam on Instagram: "Perfect rice"');
    expect(
      fetcher.requestHeaders.single['User-Agent'],
      contains('externalhit'),
    );
  });

  test('websites use page metadata', () async {
    fetcher.html(
      'https://blog.example.com/',
      '<title>Cooking Perfect Rice | Example Blog</title>',
    );
    final info = await pageInfo.lookup(
      Uri.parse('https://blog.example.com/p/123'),
    );
    expect(info?.title, 'Cooking Perfect Rice');
  });

  test('generic login-wall titles are ignored', () async {
    fetcher.html(
      'https://www.instagram.com/',
      '<meta property="og:title" content="Instagram">',
    );
    expect(
      await pageInfo.lookup(Uri.parse('https://www.instagram.com/p/x/')),
      isNull,
    );
    expect(isGenericTitle('Reddit - Dive into anything'), isTrue);
    expect(isGenericTitle('How to cook rice'), isFalse);
  });

  test('failures return null instead of throwing', () async {
    fetcher.failure = const FetchException(FetchFailure.network);
    expect(await pageInfo.lookup(Uri.parse('https://example.com/a')), isNull);

    fetcher.failure = null;
    fetcher.html('https://example.com/', 'denied', status: 403);
    expect(await pageInfo.lookup(Uri.parse('https://example.com/a')), isNull);

    fetcher.json('https://www.youtube.com/oembed', 'not json');
    expect(await pageInfo.lookup(Uri.parse('https://youtu.be/x')), isNull);
  });

  test('Reddit falls back to the post RSS when the API is blocked', () async {
    fetcher.json(
      'https://www.reddit.com/r/FlutterDev/comments/',
      'Blocked',
      status: 403,
    );
    fetcher.raw(
      'https://www.reddit.com/r/FlutterDev/comments/1x5xrvo/code_forge/.rss',
      FetchedPage(
        statusCode: 200,
        finalUrl: Uri.parse('https://www.reddit.com/x'),
        contentType: 'application/atom+xml',
        body:
            '<feed><title>code_forge : FlutterDev</title>'
            '<entry><title>code_forge migrated to pure Dart &amp; more</title></entry></feed>',
      ),
    );
    final info = await pageInfo.lookup(
      Uri.parse(
        'https://www.reddit.com/r/FlutterDev/comments/1x5xrvo/code_forge/',
      ),
    );
    expect(info?.title, 'code_forge migrated to pure Dart & more');
    expect(info?.siteName, 'r/FlutterDev');
  });

  test('Reddit app share links are followed to the post', () async {
    fetcher.raw(
      'https://www.reddit.com/r/FlutterDev/s/',
      FetchedPage(
        statusCode: 200,
        body: '<html></html>',
        finalUrl: Uri.parse(
          'https://www.reddit.com/r/FlutterDev/comments/abc/real_post/',
        ),
      ),
    );
    fetcher.json(
      'https://www.reddit.com/r/FlutterDev/comments/abc/real_post.json',
      jsonEncode([
        {
          'data': {
            'children': [
              {
                'data': {'title': 'The real post'},
              },
            ],
          },
        },
      ]),
    );
    final info = await pageInfo.lookup(
      Uri.parse('https://www.reddit.com/r/FlutterDev/s/AbCdEf'),
    );
    expect(info?.title, 'The real post');
  });
}
