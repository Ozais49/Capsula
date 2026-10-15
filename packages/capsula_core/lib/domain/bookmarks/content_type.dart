import 'bookmark_source.dart';

/// What kind of content a link points to, detected from its URL. Used for
/// type filters, independent of source, tags and collections.
enum ContentType {
  article('Articles'),
  video('Videos'),
  image('Images'),
  document('Documents'),
  post('Posts'),
  product('Products');

  const ContentType(this.label);

  final String label;

  static ContentType fromName(String? name) => ContentType.values.firstWhere(
    (t) => t.name == name,
    orElse: () => ContentType.article,
  );
}

const _videoHosts = {
  'vimeo.com',
  'dailymotion.com',
  'twitch.tv',
  'rumble.com',
  'loom.com',
};
const _postHosts = {
  'threads.net',
  'mastodon.social',
  'bsky.app',
  'linkedin.com',
  'quora.com',
  'medium.com',
};
const _shopHosts = {
  'ebay.com',
  'etsy.com',
  'aliexpress.com',
  'daraz.com.np',
  'flipkart.com',
  'walmart.com',
  'bestbuy.com',
};

ContentType detectContentType(Uri url, BookmarkSource source) {
  final path = url.path.toLowerCase();
  final ext = path.contains('.') ? path.split('.').last : '';
  final host = url.host.toLowerCase().replaceFirst('www.', '');
  bool onHost(Set<String> hosts) =>
      hosts.any((h) => host == h || host.endsWith('.$h'));

  if (const {
    'pdf',
    'doc',
    'docx',
    'ppt',
    'pptx',
    'xls',
    'xlsx',
    'epub',
    'odt',
  }.contains(ext)) {
    return ContentType.document;
  }
  if (const {
    'jpg',
    'jpeg',
    'png',
    'gif',
    'webp',
    'svg',
    'avif',
    'heic',
  }.contains(ext)) {
    return ContentType.image;
  }
  if (const {'mp4', 'webm', 'mov', 'm3u8'}.contains(ext)) {
    return ContentType.video;
  }

  switch (source) {
    case BookmarkSource.youtube || BookmarkSource.tiktok:
      return ContentType.video;
    case BookmarkSource.instagram:
      return path.startsWith('/reel') || path.startsWith('/tv/')
          ? ContentType.video
          : ContentType.post;
    case BookmarkSource.reddit ||
        BookmarkSource.x ||
        BookmarkSource.facebook ||
        BookmarkSource.telegram:
      return path.contains('/videos/') || host == 'fb.watch'
          ? ContentType.video
          : ContentType.post;
    case BookmarkSource.amazon:
      return ContentType.product;
    case BookmarkSource.github || BookmarkSource.website:
      break;
  }
  if (onHost(_videoHosts)) return ContentType.video;
  if (onHost(_shopHosts)) return ContentType.product;
  if (onHost(_postHosts) && !host.endsWith('medium.com')) {
    return ContentType.post;
  }
  return ContentType.article;
}
