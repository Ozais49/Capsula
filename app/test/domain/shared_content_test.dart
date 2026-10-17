import 'package:capsula_core/domain/bookmarks/shared_content.dart';
import 'package:flutter_test/flutter_test.dart';

SharedLinks _extract(String? text, [String? subject]) =>
    extractSharedLinks(SharedContent(text: text, subject: subject));

List<String> _urls(SharedLinks links) =>
    links.urls.map((u) => u.toString()).toList();

void main() {
  test('a bare URL', () {
    final links = _extract('https://www.reddit.com/r/flutter/comments/abc/x/');
    expect(_urls(links), ['https://www.reddit.com/r/flutter/comments/abc/x/']);
    expect(links.title, isNull);
  });

  test('Chrome: URL in text, page title in subject', () {
    final links = _extract('https://example.com/post', 'A great post');
    expect(_urls(links), ['https://example.com/post']);
    expect(links.title, 'A great post');
  });

  test('text around the URL becomes the title', () {
    final links = _extract('Check this out - https://youtu.be/abc123');
    expect(_urls(links), ['https://youtu.be/abc123']);
    expect(links.title, 'Check this out');
  });

  test('ignores a subject that is just the URL', () {
    final links = _extract('https://example.com/a', 'https://example.com/a');
    expect(links.title, isNull);
  });

  test('trims trailing sentence punctuation', () {
    expect(_urls(_extract('See https://example.com/a.')), [
      'https://example.com/a',
    ]);
    expect(_urls(_extract('(link: https://example.com/a)')), [
      'https://example.com/a',
    ]);
    expect(_urls(_extract('"https://example.com/a",')), [
      'https://example.com/a',
    ]);
  });

  test('keeps balanced parentheses in URLs', () {
    expect(_urls(_extract('https://en.wikipedia.org/wiki/Dart_(language)')), [
      'https://en.wikipedia.org/wiki/Dart_(language)',
    ]);
  });

  test('finds several links, without duplicates, and no title', () {
    final links = _extract(
      'One https://a.example.com/x and two https://b.example.com/y '
      'and again https://a.example.com/x/',
    );
    expect(_urls(links), [
      'https://a.example.com/x',
      'https://b.example.com/y',
    ]);
    expect(links.title, isNull);
  });

  test('falls back to www. links without a scheme', () {
    expect(_urls(_extract('go to www.example.com/page now')), [
      'https://www.example.com/page',
    ]);
  });

  test('nothing usable', () {
    expect(_extract('just some words').urls, isEmpty);
    expect(_extract(null).urls, isEmpty);
    expect(_extract('mailto:a@b.com javascript:alert(1)').urls, isEmpty);
  });
}
