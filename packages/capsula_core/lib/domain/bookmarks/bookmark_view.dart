import '../organization/label.dart';
import 'bookmark_source.dart';
import 'content_type.dart';

/// A filtered view of the library. Views are queries over bookmark
/// metadata, never folders: one bookmark can appear in many views.
sealed class BookmarkView {
  const BookmarkView();

  static const inbox = InboxView();
  static const all = AllView();
  static const archived = ArchivedView();
  static const favorites = FavoritesView();
  static const reminders = RemindersView();
  static const trash = TrashView();

  /// Stable string used in URLs, e.g. `inbox`, `source:reddit`, `tag:abc`.
  String get key;

  /// Parses [key]; unknown values fall back to the Inbox.
  static BookmarkView parse(String? key) {
    if (key == null) return inbox;
    final separator = key.indexOf(':');
    if (separator == -1) {
      return switch (key) {
        'all' => all,
        'archived' => archived,
        'favorites' => favorites,
        'reminders' => reminders,
        'trash' => trash,
        _ => inbox,
      };
    }
    final type = key.substring(0, separator);
    final value = key.substring(separator + 1);
    if (value.isEmpty) return inbox;
    return switch (type) {
      'source' => SourceView(BookmarkSource.fromId(value)),
      'type' => TypeView(ContentType.fromName(value)),
      'tag' => LabelView(LabelKind.tag, value),
      'collection' => LabelView(LabelKind.collection, value),
      _ => inbox,
    };
  }

  @override
  bool operator ==(Object other) => other is BookmarkView && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// Unsorted: bookmarks with no tags and no collections. (Once called the
/// Inbox, and still under the key `inbox` so old links keep working.)
class InboxView extends BookmarkView {
  const InboxView();

  @override
  String get key => 'inbox';
}

class AllView extends BookmarkView {
  const AllView();

  @override
  String get key => 'all';
}

class FavoritesView extends BookmarkView {
  const FavoritesView();

  @override
  String get key => 'favorites';
}

/// Bookmarks with a reminder, soonest first.
class RemindersView extends BookmarkView {
  const RemindersView();

  @override
  String get key => 'reminders';
}

class ArchivedView extends BookmarkView {
  const ArchivedView();

  @override
  String get key => 'archived';
}

class SourceView extends BookmarkView {
  const SourceView(this.source);

  final BookmarkSource source;

  @override
  String get key => 'source:${source.id}';
}

class TypeView extends BookmarkView {
  const TypeView(this.type);

  final ContentType type;

  @override
  String get key => 'type:${type.name}';
}

class LabelView extends BookmarkView {
  const LabelView(this.kind, this.labelId);

  final LabelKind kind;
  final String labelId;

  @override
  String get key => '${kind.name}:$labelId';
}

/// Bookmarks moved to the Trash, most recently trashed first.
class TrashView extends BookmarkView {
  const TrashView();

  @override
  String get key => 'trash';
}
