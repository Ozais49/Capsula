/// A passage the user marked while reading, optionally with a note.
enum HighlightColor {
  yellow,
  green,
  blue,
  pink;

  static HighlightColor fromName(String? name) => HighlightColor.values
      .firstWhere((c) => c.name == name, orElse: () => HighlightColor.yellow);
}

class Highlight {
  const Highlight({
    required this.id,
    required this.bookmarkId,
    required this.text,
    required this.createdAt,
    this.note,
    this.color = HighlightColor.yellow,
  });

  final String id;
  final String bookmarkId;

  /// The marked passage, as it appeared in the reader.
  final String text;
  final String? note;
  final HighlightColor color;
  final DateTime createdAt;

  Highlight copyWith({
    String? note,
    HighlightColor? color,
    bool clearNote = false,
  }) => Highlight(
    id: id,
    bookmarkId: bookmarkId,
    text: text,
    createdAt: createdAt,
    note: clearNote ? null : note ?? this.note,
    color: color ?? this.color,
  );
}

const maxHighlightLength = 5000;
const maxNoteLength = 10000;

/// Collapses whitespace in a selected passage; null when nothing is left.
String? normalizeHighlightText(String text) {
  final t = text.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (t.isEmpty) return null;
  return t.length > maxHighlightLength ? t.substring(0, maxHighlightLength) : t;
}

abstract interface class HighlightRepository {
  String newId();

  /// Highlights of one bookmark, in reading order of creation.
  Stream<List<Highlight>> watchForBookmark(String bookmarkId);

  /// All highlights, newest first.
  Stream<List<Highlight>> watchAll({required int limit});

  Future<void> save(Highlight highlight);

  Future<void> delete(String id);

  Future<void> deleteForBookmark(String bookmarkId);
}

/// Character ranges of [highlights] within [text], merged and sorted.
/// Matching ignores differences in whitespace.
List<(int, int)> highlightRanges(String text, Iterable<String> highlights) {
  final ranges = <(int, int)>[];
  // Map positions in whitespace-collapsed text back to the original.
  final collapsed = StringBuffer();
  final origin = <int>[];
  var lastWasSpace = false;
  for (var i = 0; i < text.length; i++) {
    final isSpace = text[i].trim().isEmpty;
    if (isSpace && lastWasSpace) continue;
    collapsed.write(isSpace ? ' ' : text[i]);
    origin.add(i);
    lastWasSpace = isSpace;
  }
  final haystack = collapsed.toString().toLowerCase();
  for (final h in highlights) {
    final needle = h.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
    if (needle.isEmpty) continue;
    var from = 0;
    while (true) {
      final at = haystack.indexOf(needle, from);
      if (at == -1) break;
      final end = at + needle.length - 1;
      ranges.add((origin[at], origin[end] + 1));
      from = at + needle.length;
    }
  }
  ranges.sort((a, b) => a.$1.compareTo(b.$1));
  final merged = <(int, int)>[];
  for (final r in ranges) {
    if (merged.isNotEmpty && r.$1 <= merged.last.$2) {
      final last = merged.removeLast();
      merged.add((last.$1, r.$2 > last.$2 ? r.$2 : last.$2));
    } else {
      merged.add(r);
    }
  }
  return merged;
}
