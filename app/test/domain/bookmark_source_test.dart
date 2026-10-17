import 'package:capsula_core/domain/bookmarks/bookmark_source.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('detects sources from hosts', () {
    const cases = {
      'reddit.com': BookmarkSource.reddit,
      'old.reddit.com': BookmarkSource.reddit,
      'redd.it': BookmarkSource.reddit,
      'youtube.com': BookmarkSource.youtube,
      'm.youtube.com': BookmarkSource.youtube,
      'youtu.be': BookmarkSource.youtube,
      'instagram.com': BookmarkSource.instagram,
      'facebook.com': BookmarkSource.facebook,
      'fb.watch': BookmarkSource.facebook,
      'x.com': BookmarkSource.x,
      'twitter.com': BookmarkSource.x,
      'tiktok.com': BookmarkSource.tiktok,
      'vm.tiktok.com': BookmarkSource.tiktok,
      't.me': BookmarkSource.telegram,
      'github.com': BookmarkSource.github,
      'gist.github.com': BookmarkSource.github,
      'example.com': BookmarkSource.website,
      'notreddit.com': BookmarkSource.website,
      'amazonaws.com': BookmarkSource.website,
      // No longer built in; users can add Amazon as their own source.
      'amazon.com': BookmarkSource.website,
      'myyoutube.com.evil.net': BookmarkSource.website,
    };
    cases.forEach((host, expected) {
      expect(BookmarkSource.fromHost(host), expected, reason: host);
    });
  });

  test('round-trips through its id', () {
    for (final source in BookmarkSource.values) {
      expect(BookmarkSource.fromId(source.id), source);
    }
    expect(BookmarkSource.fromId('unknown'), BookmarkSource.website);
    expect(BookmarkSource.fromId(null), BookmarkSource.website);
    // Once built in; such bookmarks now show as Webpage.
    expect(BookmarkSource.fromId('amazon'), BookmarkSource.website);
    expect(BookmarkSource.website.label, 'Webpage');
  });

  test('Amazon pages are still recognized as shops', () {
    for (final host in ['amazon.com', 'smile.amazon.de', 'amzn.to']) {
      expect(isAmazonHost(host), isTrue, reason: host);
    }
    expect(isAmazonHost('amazonaws.com'), isFalse);
  });
}
