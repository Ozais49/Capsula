import 'bookmark.dart';
import 'bookmark_codec.dart';

/// The fields that differ between two versions of a bookmark, so a backend
/// can write only those. Writing whole documents loses changes made in the
/// meantime by another device, tab or background task; a patch only
/// overwrites what this change touched.
///
/// Values are as [encodeBookmark] produces them, with dates as [DateTime].
class BookmarkPatch {
  const BookmarkPatch({
    this.set = const {},
    this.removed = const {},
    this.added = const {},
    this.pulled = const {},
  });

  /// Computes the patch from [before] to [after].
  ///
  /// ID lists (tags, collections) are expressed as items [added] and
  /// [pulled], so label changes made elsewhere at the same time merge
  /// instead of being replaced. When a list both gains and loses items, it
  /// is written whole, because a backend can't apply both to one field in
  /// a single write.
  factory BookmarkPatch.between(Bookmark before, Bookmark after) =>
      BookmarkPatch.fromDocuments(
        encodeBookmark(before, _keepDate),
        encodeBookmark(after, _keepDate),
      );

  /// The patch from stored document fields [a] to [b] (both with dates as
  /// [DateTime]). Fields of [a] that [b] doesn't have are [removed].
  factory BookmarkPatch.fromDocuments(
    Map<String, Object?> a,
    Map<String, Object?> b,
  ) {
    final set = <String, Object?>{};
    final added = <String, List<String>>{};
    final pulled = <String, List<String>>{};
    for (final MapEntry(:key, :value) in b.entries) {
      final old = a[key];
      if (_equal(old, value)) continue;
      if (mergedListFields.contains(key)) {
        final oldItems = {...?(old as List?)?.cast<String>()};
        final newItems = {...(value! as List).cast<String>()};
        final plus = newItems.difference(oldItems).toList();
        final minus = oldItems.difference(newItems).toList();
        if (plus.isNotEmpty && minus.isNotEmpty) {
          set[key] = value;
        } else if (plus.isNotEmpty) {
          added[key] = plus;
        } else if (minus.isNotEmpty) {
          pulled[key] = minus;
        }
        continue;
      }
      set[key] = value;
    }
    return BookmarkPatch(
      set: set,
      removed: {
        // Only fields this version knows: fields added by a newer version
        // of the app are left alone.
        for (final key in a.keys)
          if (!b.containsKey(key) && optionalFields.contains(key)) key,
      },
      added: added,
      pulled: pulled,
    );
  }

  /// Bookmark fields written as set changes rather than whole values.
  static const mergedListFields = {'tagIds', 'collectionIds'};

  /// Fields [encodeBookmark] leaves out when they have no value.
  static const optionalFields = {
    'description',
    'imageUrl',
    'favorite',
    'note',
    'remindAt',
    'contentIndexedAt',
    'deletedAt',
    'customSourceId',
    'importedFrom',
    'importedAt',
  };

  /// Fields to write with their new value.
  final Map<String, Object?> set;

  /// Optional fields to delete.
  final Set<String> removed;

  /// Items to add to an ID list, keeping items added elsewhere.
  final Map<String, List<String>> added;

  /// Items to take out of an ID list, keeping the rest.
  final Map<String, List<String>> pulled;

  bool get isEmpty =>
      set.isEmpty && removed.isEmpty && added.isEmpty && pulled.isEmpty;

  /// Applies the patch to a document's fields, as a backend would.
  Map<String, Object?> applyTo(Map<String, Object?> document) {
    final result = {...document, ...set};
    removed.forEach(result.remove);
    added.forEach((key, items) {
      final list = [...?(result[key] as List?)?.cast<String>()];
      for (final item in items) {
        if (!list.contains(item)) list.add(item);
      }
      result[key] = list;
    });
    pulled.forEach((key, items) {
      result[key] = [
        for (final item in (result[key] as List?)?.cast<String>() ?? const [])
          if (!items.contains(item)) item,
      ];
    });
    return result;
  }

  static Object _keepDate(DateTime d) => d;

  static bool _equal(Object? a, Object? b) {
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (a[i] != b[i]) return false;
      }
      return true;
    }
    return a == b;
  }
}

/// The document ID for a bookmark of [canonicalUrl]. Every device derives
/// the same ID for the same link, so saving it on two devices at once
/// writes one bookmark instead of two.
///
/// Two 32-bit FNV-1a hashes with different seeds, computed with 32-bit
/// arithmetic so the result is the same on the web.
String bookmarkIdFor(String canonicalUrl) {
  final h1 = _fnv1a(canonicalUrl, 0x811c9dc5);
  final h2 = _fnv1a(canonicalUrl, 0x050c5d1f);
  String part(int h) => h.toRadixString(36).padLeft(7, '0');
  return 'u${part(h1)}${part(h2)}';
}

int _fnv1a(String text, int seed) {
  var hash = seed;
  for (final unit in text.codeUnits) {
    hash = (hash ^ unit) & 0xffffffff;
    // hash * 16777619 (2^24 + 403), keeping the low 32 bits.
    hash = (((hash & 0xff) << 24) + hash * 403) & 0xffffffff;
  }
  return hash;
}
