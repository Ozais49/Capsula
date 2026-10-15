import '../bookmarks/bookmark.dart';
import '../reader/content_fetcher.dart';

enum LinkHealth {
  ok,
  broken,

  /// Couldn't tell: the site blocks checks, needs sign-in, or rate-limits.
  unknown,
}

class LinkCheck {
  const LinkCheck(this.health, {this.statusCode, this.reason});

  final LinkHealth health;
  final int? statusCode;
  final String? reason;
}

abstract interface class LinkChecker {
  /// Never throws.
  Future<LinkCheck> check(Uri url);
}

/// Checks a link by requesting it.
class FetcherLinkChecker implements LinkChecker {
  FetcherLinkChecker(this._fetcher);

  final ContentFetcher _fetcher;

  @override
  Future<LinkCheck> check(Uri url) async {
    try {
      final page = await _fetcher.fetch(url);
      return linkCheckFor(page.statusCode);
    } on FetchException catch (e) {
      return e.failure == FetchFailure.blocked
          ? const LinkCheck(
              LinkHealth.unknown,
              reason: 'The browser blocked the check',
            )
          : const LinkCheck(LinkHealth.broken, reason: 'Unreachable');
    } on Object {
      return const LinkCheck(LinkHealth.unknown, reason: 'Check failed');
    }
  }
}

LinkCheck linkCheckFor(int status) => switch (status) {
  >= 200 && < 400 => LinkCheck(LinkHealth.ok, statusCode: status),
  404 || 410 => LinkCheck(
    LinkHealth.broken,
    statusCode: status,
    reason: 'Page not found',
  ),
  401 || 403 || 429 => LinkCheck(
    LinkHealth.unknown,
    statusCode: status,
    reason: 'The site didn\'t allow the check',
  ),
  >= 500 => LinkCheck(
    LinkHealth.broken,
    statusCode: status,
    reason: 'Server error',
  ),
  _ => LinkCheck(
    LinkHealth.unknown,
    statusCode: status,
    reason: 'Unexpected response',
  ),
};

/// Groups of bookmarks that point to the same page, oldest first in each
/// group. Groups are sorted by their newest member, newest first.
List<List<Bookmark>> findDuplicates(Iterable<Bookmark> bookmarks) {
  final byUrl = <String, List<Bookmark>>{};
  for (final b in bookmarks) {
    byUrl.putIfAbsent(b.canonicalUrl, () => []).add(b);
  }
  final groups = [
    for (final g in byUrl.values)
      if (g.length > 1) g..sort((a, b) => a.createdAt.compareTo(b.createdAt)),
  ];
  groups.sort((a, b) => b.last.createdAt.compareTo(a.last.createdAt));
  return groups;
}
