import 'package:capsula/domain/bookmarks/search_tokens.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('splits text into lowercase words, including non-Latin letters', () {
    expect(searchWords('Flutter: Tips & Tricks!'), [
      'flutter',
      'tips',
      'tricks',
    ]);
    expect(searchWords('नेपाल यात्रा 2026'), ['नेपाल', 'यात्रा', '2026']);
    expect(searchWords('  '), isEmpty);
  });

  test('builds prefix tokens for every word', () {
    final tokens = buildSearchTokens(['Dart tips']);
    expect(
      tokens,
      containsAll(['d', 'da', 'dar', 'dart', 't', 'ti', 'tip', 'tips']),
    );
    expect(tokens.toSet().length, tokens.length, reason: 'no duplicates');
  });

  test('caps prefix length and token count', () {
    final long = 'a' * 50;
    expect(buildSearchTokens([long]).every((t) => t.length <= 20), isTrue);

    final many = List.generate(200, (i) => 'word$i').join(' ');
    expect(buildSearchTokens([many]).length, lessThanOrEqualTo(400));
  });

  test('uses the longest query word for the lookup', () {
    expect(primarySearchToken('ai Research papers'), 'research');
    expect(primarySearchToken('  '), isNull);
    expect(primarySearchToken('x' * 30), 'x' * 20);
  });

  test('matches when every query word prefixes a word', () {
    const texts = ['Flutter state management', 'medium.com'];
    expect(matchesSearch(texts, 'flut'), isTrue);
    expect(matchesSearch(texts, 'state flu'), isTrue);
    expect(matchesSearch(texts, 'MEDIUM'), isTrue);
    expect(matchesSearch(texts, 'flutter react'), isFalse);
    expect(matchesSearch(texts, 'utter'), isFalse);
    expect(matchesSearch(texts, ''), isTrue);
  });
}
