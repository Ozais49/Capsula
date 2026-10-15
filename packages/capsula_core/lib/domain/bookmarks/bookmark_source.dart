/// Where content comes from, detected from the URL. This is metadata used
/// for filtering, never a folder.
enum BookmarkSource {
  reddit('Reddit', ['reddit.com', 'redd.it']),
  youtube('YouTube', ['youtube.com', 'youtu.be']),
  instagram('Instagram', ['instagram.com', 'instagr.am']),
  facebook('Facebook', ['facebook.com', 'fb.com', 'fb.watch']),
  x('X', ['x.com', 'twitter.com', 't.co']),
  tiktok('TikTok', ['tiktok.com']),
  telegram('Telegram', ['t.me', 'telegram.me']),
  github('GitHub', ['github.com']),
  amazon('Amazon', ['amzn.to', 'amzn.eu', 'a.co']),
  website('Website', []);

  const BookmarkSource(this.label, this._domains);

  final String label;
  final List<String> _domains;

  /// Stable identifier stored with bookmarks.
  String get id => name;

  static BookmarkSource fromId(String? id) => BookmarkSource.values.firstWhere(
    (s) => s.id == id,
    orElse: () => BookmarkSource.website,
  );

  static BookmarkSource fromHost(String host) {
    final h = host.toLowerCase();
    if (RegExp(r'(^|\.)amazon\.[a-z.]+$').hasMatch(h)) return amazon;
    for (final source in values) {
      for (final domain in source._domains) {
        if (h == domain || h.endsWith('.$domain')) return source;
      }
    }
    return website;
  }
}
