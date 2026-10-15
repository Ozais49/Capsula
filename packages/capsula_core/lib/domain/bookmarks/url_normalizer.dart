/// Parses user input into an http(s) URL, adding `https://` when no scheme
/// is given. Returns null when the input is not a usable web address.
Uri? parseWebUrl(String input) {
  var text = input.trim();
  if (text.isEmpty || RegExp(r'\s').hasMatch(text)) return null;
  // Another scheme such as `mailto:` or `javascript:` (but not `host:port`).
  if (RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*:(?!\d)').hasMatch(text) &&
      !RegExp(r'^https?://', caseSensitive: false).hasMatch(text)) {
    return null;
  }
  if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9+.-]*://').hasMatch(text)) {
    text = 'https://$text';
  }
  final uri = Uri.tryParse(text);
  if (uri == null) return null;
  if (uri.scheme != 'http' && uri.scheme != 'https') return null;
  final host = uri.host;
  if (host.isEmpty || (!host.contains('.') && host != 'localhost')) return null;
  return uri;
}

/// The host without `www.`, lowercased, e.g. `reddit.com`.
String displayHost(Uri uri) {
  final host = uri.host.toLowerCase();
  return host.startsWith('www.') ? host.substring(4) : host;
}

/// Produces a stable form of [uri] for duplicate detection: two links to the
/// same content should produce the same string. The original URL is kept
/// separately; this value is only compared, never opened.
String canonicalizeUrl(Uri uri) {
  var host = _canonicalHost(displayHost(uri));
  var path = uri.path;
  var query = Map<String, String>.of(uri.queryParameters);
  var fragment = uri.fragment;

  // Site-specific forms of the same content.
  if (host == 'youtu.be' && path.length > 1) {
    query = {'v': path.substring(1).split('/').first};
    host = 'youtube.com';
    path = '/watch';
  } else if (host == 'youtube.com' && path == '/watch') {
    query = {'v': ?query['v']};
  } else if (_isAmazon(host)) {
    final asin = RegExp(r'/(?:dp|gp/product|gp/aw/d)/([A-Z0-9]{10})')
        .firstMatch(path)
        ?.group(1);
    if (asin != null) {
      path = '/dp/$asin';
      query = {};
    }
  } else if (_dropAllQueryHosts.contains(host)) {
    query = {};
  }

  query.removeWhere((key, _) => _isTrackingParam(key, host));

  if (path.length > 1 && path.endsWith('/')) {
    path = path.replaceFirst(RegExp(r'/+$'), '');
  }
  if (path == '/') path = '';

  // Keep hash-based app routes (#/page, #!/page); drop in-page anchors.
  if (!fragment.startsWith('/') && !fragment.startsWith('!')) fragment = '';

  final port = uri.hasPort && uri.port != 80 && uri.port != 443
      ? ':${uri.port}'
      : '';
  final sortedQuery = (query.keys.toList()..sort())
      .map(
        (k) =>
            '${Uri.encodeQueryComponent(k)}=${Uri.encodeQueryComponent(query[k]!)}',
      )
      .join('&');

  return [
    'https://$host$port$path',
    if (sortedQuery.isNotEmpty) '?$sortedQuery',
    if (fragment.isNotEmpty) '#$fragment',
  ].join();
}

/// A readable title for a link without one, from its last path segment,
/// e.g. `/r/flutter/comments/abc/my_first_app/` → `my first app`.
String titleFromUrl(Uri uri) {
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  for (final segment in segments.reversed) {
    final words = Uri.decodeComponent(segment)
        .replaceFirst(RegExp(r'\.(html?|php|aspx?)$'), '')
        .replaceAll(RegExp(r'[-_+]+'), ' ')
        .trim();
    if (_genericSegments.contains(words.toLowerCase())) continue;
    // Skip opaque IDs such as `abc123` or `1234567`.
    if (words.contains(' ') || RegExp(r'^[a-zA-Z]{4,}$').hasMatch(words)) {
      return words;
    }
  }
  return displayHost(uri);
}

/// Path segments that describe the page type rather than its content.
const _genericSegments = {
  'watch',
  'index',
  'home',
  'status',
  'comments',
  'reel',
  'reels',
  'shorts',
  'video',
  'videos',
  'post',
  'posts',
  'product',
  'article',
  'articles',
};

const _hostAliases = {
  'm.youtube.com': 'youtube.com',
  'music.youtube.com': 'youtube.com',
  'old.reddit.com': 'reddit.com',
  'new.reddit.com': 'reddit.com',
  'np.reddit.com': 'reddit.com',
  'm.reddit.com': 'reddit.com',
  'twitter.com': 'x.com',
  'mobile.twitter.com': 'x.com',
  'mobile.x.com': 'x.com',
  'm.facebook.com': 'facebook.com',
  'mbasic.facebook.com': 'facebook.com',
  'web.facebook.com': 'facebook.com',
  'en.m.wikipedia.org': 'en.wikipedia.org',
};

String _canonicalHost(String host) => _hostAliases[host] ?? host;

/// Hosts whose share links only add tracking to the query string.
const _dropAllQueryHosts = {'x.com', 'instagram.com', 'tiktok.com'};

const _trackingParams = {
  'fbclid',
  'gclid',
  'dclid',
  'gbraid',
  'wbraid',
  'msclkid',
  'mc_cid',
  'mc_eid',
  'igshid',
  'igsh',
  'ref_src',
  'ref_url',
  'share_id',
  'rdt',
  '_hsenc',
  '_hsmi',
  'yclid',
  'spm',
};

bool _isTrackingParam(String key, String host) {
  final k = key.toLowerCase();
  if (k.startsWith('utm_') || _trackingParams.contains(k)) return true;
  // YouTube and Spotify add `si` to share links.
  if (k == 'si' && (host == 'youtube.com' || host == 'open.spotify.com')) {
    return true;
  }
  return false;
}

bool _isAmazon(String host) => RegExp(r'(^|\.)amazon\.[a-z.]+$').hasMatch(host);
