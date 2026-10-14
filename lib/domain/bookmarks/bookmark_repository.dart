import 'bookmark.dart';
import 'bookmark_view.dart';

class BookmarkQuery {
  const BookmarkQuery({this.view = BookmarkView.inbox, this.search = ''});

  final BookmarkView view;
  final String search;

  @override
  bool operator ==(Object other) =>
      other is BookmarkQuery && other.view == view && other.search == search;

  @override
  int get hashCode => Object.hash(view, search);
}

/// Persistence for the signed-in user's bookmarks. Implementations scope
/// every call to the current user; callers never pass a user ID.
abstract interface class BookmarkRepository {
  /// A new unique bookmark ID.
  String newId();

  /// Completes when the backend has accepted the write. The bookmark is
  /// visible to [watch] and [watchList] immediately, even while offline.
  Future<void> create(Bookmark bookmark);

  Future<void> update(Bookmark bookmark);

  Future<void> delete(String id);

  Stream<Bookmark?> watch(String id);

  /// Newest first, at most [limit] results.
  Stream<List<Bookmark>> watchList(BookmarkQuery query, {required int limit});

  Future<Bookmark?> findByCanonicalUrl(String canonicalUrl);

  /// Number of bookmarks in the Inbox, or null when it can't be counted
  /// (for example while offline).
  Future<int?> countInbox();
}

/// Whether [bookmark] belongs in [view]. Shared by implementations that
/// filter in memory.
bool bookmarkInView(Bookmark bookmark, BookmarkView view) => switch (view) {
  InboxView() => !bookmark.archived && bookmark.inInbox,
  AllView() => !bookmark.archived,
  ArchivedView() => bookmark.archived,
  SourceView(:final source) => !bookmark.archived && bookmark.source == source,
  LabelView(:final kind, :final labelId) =>
    !bookmark.archived && bookmark.labelIds(kind).contains(labelId),
};
