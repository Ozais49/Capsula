import 'bookmark.dart';

class BookmarkQuery {
  const BookmarkQuery({this.archived = false, this.search = ''});

  final bool archived;
  final String search;

  @override
  bool operator ==(Object other) =>
      other is BookmarkQuery &&
      other.archived == archived &&
      other.search == search;

  @override
  int get hashCode => Object.hash(archived, search);
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
}
