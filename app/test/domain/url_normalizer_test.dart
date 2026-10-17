import 'package:capsula_core/domain/bookmarks/url_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';

String canon(String url) => canonicalizeUrl(parseWebUrl(url)!);

void main() {
  group('parseWebUrl', () {
    test('accepts http and https URLs', () {
      expect(parseWebUrl('https://example.com/a')?.host, 'example.com');
      expect(parseWebUrl('http://example.com')?.scheme, 'http');
    });

    test('adds https when the scheme is missing', () {
      expect(
        parseWebUrl('example.com/article').toString(),
        'https://example.com/article',
      );
      expect(parseWebUrl('  www.reddit.com  ')?.host, 'www.reddit.com');
      expect(parseWebUrl('localhost:8080/x')?.port, 8080);
      expect(parseWebUrl('example.com:3000')?.host, 'example.com');
    });

    test('rejects non-web input', () {
      for (final input in [
        '',
        '   ',
        'hello world',
        'not a url',
        'ftp://example.com/file',
        'javascript:alert(1)',
        'mailto:someone@example.com',
        'https://',
        'justtext',
      ]) {
        expect(parseWebUrl(input), isNull, reason: input);
      }
    });
  });

  group('canonicalizeUrl', () {
    test('treats trailing slash, www, scheme and case as equal', () {
      const expected = 'https://example.com/article';
      expect(canon('https://example.com/article'), expected);
      expect(canon('https://example.com/article/'), expected);
      expect(canon('http://www.example.com/article'), expected);
      expect(canon('HTTPS://EXAMPLE.com/article'), expected);
      expect(canon('https://example.com:443/article'), expected);
    });

    test('keeps path case', () {
      expect(
        canon('https://example.com/Article'),
        'https://example.com/Article',
      );
    });

    test('root URL has no trailing slash', () {
      expect(canon('https://example.com/'), 'https://example.com');
      expect(canon('https://example.com'), 'https://example.com');
    });

    test('removes tracking parameters and sorts the rest', () {
      expect(
        canon('https://example.com/p?utm_source=x&b=2&fbclid=abc&a=1'),
        'https://example.com/p?a=1&b=2',
      );
    });

    test('drops in-page anchors but keeps hash routes', () {
      expect(
        canon('https://example.com/doc#section'),
        'https://example.com/doc',
      );
      expect(
        canon('https://example.com/app#/settings'),
        'https://example.com/app#/settings',
      );
    });

    test('keeps non-default ports', () {
      expect(canon('http://localhost:3000/x'), 'https://localhost:3000/x');
    });

    test('YouTube short links and share params match the watch URL', () {
      const expected = 'https://youtube.com/watch?v=dQw4w9WgXcQ';
      expect(canon('https://youtu.be/dQw4w9WgXcQ?si=abc123'), expected);
      expect(
        canon('https://www.youtube.com/watch?v=dQw4w9WgXcQ&t=42s&si=zz'),
        expected,
      );
      expect(canon('https://m.youtube.com/watch?v=dQw4w9WgXcQ'), expected);
    });

    test('Reddit host variants and share params match', () {
      const expected = 'https://reddit.com/r/flutterdev/comments/abc/title';
      expect(
        canon(
          'https://www.reddit.com/r/flutterdev/comments/abc/title/'
          '?utm_source=share&utm_medium=android_app&share_id=xyz',
        ),
        expected,
      );
      expect(
        canon('https://old.reddit.com/r/flutterdev/comments/abc/title'),
        expected,
      );
    });

    test('X and Twitter share links match', () {
      const expected = 'https://x.com/user/status/123';
      expect(canon('https://twitter.com/user/status/123?s=20&t=abc'), expected);
      expect(canon('https://x.com/user/status/123'), expected);
    });

    test('Instagram share params are removed', () {
      expect(
        canon('https://www.instagram.com/p/Cabc123/?igsh=MWQ1ZGUxMzBkMA=='),
        'https://instagram.com/p/Cabc123',
      );
    });

    test('Amazon product links reduce to the ASIN', () {
      const expected = 'https://amazon.com/dp/B08N5WRWNW';
      expect(
        canon(
          'https://www.amazon.com/Some-Product-Name/dp/B08N5WRWNW/ref=sr_1_1?keywords=x',
        ),
        expected,
      );
      expect(
        canon('https://www.amazon.com/gp/product/B08N5WRWNW?psc=1'),
        expected,
      );
    });

    test('different content stays different', () {
      expect(
        canon('https://example.com/a'),
        isNot(canon('https://example.com/b')),
      );
      expect(
        canon('https://example.com/search?q=dart'),
        isNot(canon('https://example.com/search?q=flutter')),
      );
    });
  });

  group('titleFromUrl', () {
    String title(String url) => titleFromUrl(parseWebUrl(url)!);

    test('uses a readable slug', () {
      expect(
        title('https://reddit.com/r/flutter/comments/abc123/my_first_app/'),
        'my first app',
      );
      expect(
        title('https://blog.example.com/how-to-cook-rice.html'),
        'how to cook rice',
      );
    });

    test('falls back to the host for opaque or generic paths', () {
      expect(title('https://youtube.com/watch?v=abc'), 'youtube.com');
      expect(title('https://www.example.com/'), 'example.com');
      expect(title('https://x.com/i/status/1234567890'), 'x.com');
    });
  });
}
