import 'dart:convert';
import 'dart:math';

import 'package:capsula_core/domain/bookmarks/bookmark.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_source.dart';

/// Where a public link points.
class ShareTarget {
  const ShareTarget(this.uid, this.collectionId);

  final String uid;
  final String collectionId;
}

/// Public read-only links to collections. Stored at `publicShares/{id}`,
/// which clients can't read or write; only the server resolves them.
abstract interface class ShareStore {
  Future<ShareTarget?> find(String shareId);

  /// Records the link and marks the collection with [shareId].
  Future<void> create(String shareId, ShareTarget target);

  /// Removes the link and the collection's mark.
  Future<void> delete(String shareId, ShareTarget target);
}

/// 128 random bits, URL-safe: unguessable, so only people given the link
/// can find the collection.
String generateShareId([Random? random]) {
  final r = random ?? Random.secure();
  return base64Url
      .encode(List<int>.generate(16, (_) => r.nextInt(256)))
      .replaceAll('=', '');
}

bool isValidShareId(String id) =>
    RegExp(r'^[A-Za-z0-9_-]{16,64}$').hasMatch(id);

/// Only what a public visitor should see: no notes, tags, highlights,
/// reading status or provenance.
Map<String, Object?> publicBookmarkJson(Bookmark b) => {
  'title': b.displayTitle,
  'url': b.url,
  'description': ?b.description,
  'imageUrl': ?b.imageUrl,
  'source': b.source.id,
  'sourceDomain': b.sourceDomain,
  'savedAt': b.createdAt.toUtc().toIso8601String(),
};

// Escapes & < > " ' (safe in text and quoted attributes) but not "/",
// so URLs stay readable.
String _escape(String s) =>
    const HtmlEscape(HtmlEscapeMode.attribute).convert(s);

/// A small, dependency-free page for a shared collection.
String publicCollectionHtml(String name, List<Bookmark> bookmarks) {
  final items = bookmarks
      .map((b) {
        final description = b.description == null
            ? ''
            : '<p class="d">${_escape(b.description!)}</p>';
        final image = b.imageUrl == null
            ? ''
            : '<img src="${_escape(b.imageUrl!)}" alt="" loading="lazy">';
        return '''
<li><a href="${_escape(b.url)}" rel="noopener nofollow" target="_blank">$image
<div><h2>${_escape(b.displayTitle)}</h2>$description
<p class="m">${_escape(b.source == BookmarkSource.website ? b.sourceDomain : '${b.source.label} · ${b.sourceDomain}')}</p></div></a></li>''';
      })
      .join('\n');

  return '''<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="robots" content="noindex">
<title>${_escape(name)} · Capsula</title>
<style>
:root{color-scheme:light dark;--bg:#fafafa;--card:#fff;--fg:#1b1c1c;--muted:#5f6368;--accent:#2f6f73}
@media (prefers-color-scheme:dark){:root{--bg:#121414;--card:#1e2121;--fg:#e3e3e3;--muted:#a0a4a8;--accent:#8fd0d4}}
body{margin:0;font:16px/1.5 system-ui,-apple-system,Segoe UI,Roboto,sans-serif;background:var(--bg);color:var(--fg)}
main{max-width:760px;margin:0 auto;padding:24px 16px}
h1{margin:0 0 4px;font-size:28px}.sub{color:var(--muted);margin:0 0 24px}
ul{list-style:none;margin:0;padding:0;display:grid;gap:12px}
a{display:flex;gap:16px;padding:16px;border-radius:12px;background:var(--card);color:inherit;text-decoration:none;box-shadow:0 1px 2px #0002}
a:hover h2{color:var(--accent)}
img{width:120px;height:80px;object-fit:cover;border-radius:8px;flex:none}
h2{margin:0;font-size:17px;line-height:1.3}.d{margin:6px 0 0;color:var(--muted);font-size:14px;display:-webkit-box;-webkit-line-clamp:2;-webkit-box-orient:vertical;overflow:hidden}
.m{margin:6px 0 0;color:var(--muted);font-size:13px}
@media (max-width:480px){img{width:80px;height:64px}}
</style></head>
<body><main>
<h1>${_escape(name)}</h1>
<p class="sub">${bookmarks.length} link${bookmarks.length == 1 ? '' : 's'} · shared from Capsula</p>
<ul>
$items
</ul>
</main></body></html>''';
}
