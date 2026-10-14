import 'bookmark.dart';
import 'bookmark_repository.dart';
import 'bookmark_source.dart';
import 'url_normalizer.dart';

sealed class SaveResult {
  const SaveResult();
}

class Saved extends SaveResult {
  const Saved(this.bookmark, this.committed);

  final Bookmark bookmark;

  /// Completes when the backend accepts the bookmark; fails if it rejects it.
  /// The bookmark is already visible locally before this completes.
  final Future<void> committed;
}

class AlreadySaved extends SaveResult {
  const AlreadySaved(this.existing);

  final Bookmark existing;
}

class InvalidUrl extends SaveResult {
  const InvalidUrl();
}

/// Bookmark use cases. Saving never waits on metadata or the network.
class BookmarkService {
  BookmarkService(this._repository, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final BookmarkRepository _repository;
  final DateTime Function() _now;

  BookmarkRepository get repository => _repository;

  Future<SaveResult> save(String input, {String? title}) async {
    final uri = parseWebUrl(input);
    if (uri == null) return const InvalidUrl();

    final canonicalUrl = canonicalizeUrl(uri);
    final existing = await _repository.findByCanonicalUrl(canonicalUrl);
    if (existing != null) return AlreadySaved(existing);

    final now = _now();
    final host = displayHost(uri);
    final bookmark = Bookmark(
      id: _repository.newId(),
      url: uri.toString(),
      canonicalUrl: canonicalUrl,
      title: (title?.trim().isNotEmpty ?? false)
          ? title!.trim()
          : titleFromUrl(uri),
      source: BookmarkSource.fromHost(host),
      sourceDomain: host,
      createdAt: now,
      updatedAt: now,
    );
    // Callers may not wait for the backend; ignore() keeps an unobserved
    // failure from surfacing as an unhandled error.
    return Saved(bookmark, _repository.create(bookmark)..ignore());
  }

  Future<void> setReadingStatus(Bookmark bookmark, ReadingStatus status) =>
      _repository.update(
        bookmark.copyWith(readingStatus: status, updatedAt: _now()),
      );

  /// Archiving also takes the bookmark out of the Inbox.
  Future<void> setArchived(Bookmark bookmark, bool archived) =>
      _repository.update(
        bookmark.copyWith(
          archived: archived,
          inInbox: archived ? false : bookmark.inInbox,
          updatedAt: _now(),
        ),
      );

  Future<void> rename(Bookmark bookmark, String title) => _repository.update(
    bookmark.copyWith(title: title.trim(), updatedAt: _now()),
  );

  Future<void> delete(Bookmark bookmark) => _repository.delete(bookmark.id);
}
