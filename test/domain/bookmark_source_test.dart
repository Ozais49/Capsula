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
      'amazon.com': BookmarkSource.amazon,
      'amazon.co.uk': BookmarkSource.amazon,
      'smile.amazon.de': BookmarkSource.amazon,
      'amzn.to': BookmarkSource.amazon,
      'example.com': BookmarkSource.website,
      'notreddit.com': BookmarkSource.website,
      'amazonaws.com': BookmarkSource.website,
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
  });
}
