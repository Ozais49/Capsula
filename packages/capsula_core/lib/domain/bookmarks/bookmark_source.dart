/// Where content comes from, detected from the URL. This is metadata used
/// for filtering, never a folder.
///
/// These are the built-in sources, each with its own handling (title
/// lookup, reader). Users add their own sources on top (`CustomSource`);
/// links from anywhere else are [website] ("Webpage").
enum BookmarkSource {
  reddit('Reddit', ['reddit.com', 'redd.it']),
  youtube('YouTube', ['youtube.com', 'youtu.be']),
  instagram('Instagram', ['instagram.com', 'instagr.am']),
  facebook('Facebook', ['facebook.com', 'fb.com', 'fb.watch']),
  x('X', ['x.com', 'twitter.com', 't.co']),
  tiktok('TikTok', ['tiktok.com']),
  telegram('Telegram', ['t.me', 'telegram.me']),
  github('GitHub', ['github.com']),
  website('Webpage', []);

  const BookmarkSource(this.label, this._domains);

  final String label;
  final List<String> _domains;

  /// Stable identifier stored with bookmarks. Webpage keeps the ID
  /// `website` it was stored under before it was renamed.
  String get id => name;

  /// Unknown IDs (including `amazon`, once built in) read as [website].
  static BookmarkSource fromId(String? id) => BookmarkSource.values.firstWhere(
    (s) => s.id == id,
    orElse: () => BookmarkSource.website,
  );

  static BookmarkSource fromHost(String host) {
    final h = host.toLowerCase();
    for (final source in values) {
      for (final domain in source._domains) {
        if (h == domain || h.endsWith('.$domain')) return source;
      }
    }
    return website;
  }
}

/// Amazon stores and their short links. Not a built-in source any more,
/// but their pages still get product handling.
bool isAmazonHost(String host) {
  final h = host.toLowerCase();
  return RegExp(r'(^|\.)amazon\.[a-z.]+$').hasMatch(h) ||
      const {'amzn.to', 'amzn.eu', 'a.co'}.contains(h);
}
