import 'bookmark.dart';
import 'bookmark_view.dart';

enum BookmarkSort {
  newest('Newest first'),
  oldest('Oldest first');

  const BookmarkSort(this.label);

  final String label;
}

class BookmarkQuery {
  const BookmarkQuery({
    this.view = BookmarkView.inbox,
    this.search = '',
    this.sort = BookmarkSort.newest,
  });

  final BookmarkView view;
  final String search;
  final BookmarkSort sort;

  @override
  bool operator ==(Object other) =>
      other is BookmarkQuery &&
      other.view == view &&
      other.search == search &&
      other.sort == sort;

  @override
  int get hashCode => Object.hash(view, search, sort);
}

/// Most writes sent together in one batch (Firestore allows 500).
const writeBatchSize = 450;

/// Persistence for the signed-in user's bookmarks. Implementations scope
/// every call to the current user; callers never pass a user ID.
abstract interface class BookmarkRepository {
  /// A new unique bookmark ID.
  String newId();

  /// Completes when the backend has accepted the write. The bookmark is
  /// visible to [watch] and [watchList] immediately, even while offline.
  Future<void> create(Bookmark bookmark);

  /// Writes [bookmark] whole, replacing what is stored. Only for writes
  /// that own every field (restores, re-indexing); edits use [modify].
  Future<void> update(Bookmark bookmark);

  /// Applies [change] to the latest stored copy of bookmark [id] and writes
  /// only the fields it changed, so changes made meanwhile by another
  /// device, tab or task to other fields are kept. Does nothing when the
  /// bookmark doesn't exist. Completes when the backend has accepted it.
  Future<void> modify(String id, Bookmark Function(Bookmark current) change);

  /// [modify] for many bookmarks, written in batches one after another.
  /// [change] should be idempotent, so a run that failed part way can
  /// simply be repeated.
  Future<void> modifyMany(
    Iterable<String> ids,
    Bookmark Function(Bookmark current) change, {
    void Function(int done, int total)? onProgress,
  });

  Future<void> delete(String id);

  /// Deletes many bookmarks, in batches.
  Future<void> deleteMany(Iterable<String> ids);

  /// Whether changes made on this device are still waiting for the
  /// backend to accept them (for example while offline).
  Stream<bool> watchPendingWrites();

  Stream<Bookmark?> watch(String id);

  /// Newest first, at most [limit] results.
  Stream<List<Bookmark>> watchList(BookmarkQuery query, {required int limit});

  Future<Bookmark?> findByCanonicalUrl(String canonicalUrl);

  /// Which of [canonicalUrls] are already in the library.
  Future<Set<String>> existingCanonicalUrls(Iterable<String> canonicalUrls);

  /// Writes many bookmarks at once (at most 500). Completes when the
  /// backend has accepted all of them; fails as a whole otherwise.
  Future<void> createMany(List<Bookmark> bookmarks);

  /// Every bookmark, newest first, read in pages (for export).
  Future<List<Bookmark>> fetchAll();

  /// Number of bookmarks in the Inbox, or null when it can't be counted
  /// (for example while offline).
  Future<int?> countInbox();
}

/// Whether [bookmark] belongs in [view]. Shared by implementations that
/// filter in memory.
bool bookmarkInView(Bookmark bookmark, BookmarkView view) => switch (view) {
  InboxView() => !bookmark.archived && bookmark.inInbox,
  AllView() => !bookmark.archived,
  FavoritesView() => !bookmark.archived && bookmark.favorite,
  RemindersView() => !bookmark.archived && bookmark.remindAt != null,
  ArchivedView() => bookmark.archived,
  SourceView(:final source) => !bookmark.archived && bookmark.source == source,
  TypeView(:final type) => !bookmark.archived && bookmark.type == type,
  LabelView(:final kind, :final labelId) =>
    !bookmark.archived && bookmark.labelIds(kind).contains(labelId),
};
