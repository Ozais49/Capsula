/// One bookmark read from an import file, before validation.
class ImportedItem {
  const ImportedItem({
    required this.url,
    this.title,
    this.description,
    this.folder,
    this.tags = const [],
    this.createdAt,
  });

  /// As found in the file; may be invalid.
  final String url;
  final String? title;
  final String? description;

  /// Folder or category in the source, imported as a collection.
  final String? folder;
  final List<String> tags;

  /// When it was originally saved, if the file says.
  final DateTime? createdAt;
}

/// Where an import came from, recorded on each imported bookmark.
enum ImportOrigin {
  chrome('Chrome'),
  firefox('Firefox'),
  edge('Edge'),
  safari('Safari'),
  raindrop('Raindrop'),
  pocket('Pocket'),
  file('File');

  const ImportOrigin(this.label);

  final String label;
}

/// Parses dates found in bookmark exports: Unix seconds, milliseconds or
/// microseconds, and ISO-like strings. Future dates are clamped to [now].
DateTime? parseImportDate(String? raw, {DateTime? now}) {
  final text = raw?.trim();
  if (text == null || text.isEmpty) return null;

  DateTime? date;
  final number = int.tryParse(text);
  if (number != null) {
    if (number <= 0) return null;
    date = switch (text.length) {
      <= 10 => DateTime.fromMillisecondsSinceEpoch(number * 1000, isUtc: true),
      <= 13 => DateTime.fromMillisecondsSinceEpoch(number, isUtc: true),
      _ => DateTime.fromMicrosecondsSinceEpoch(number, isUtc: true),
    };
  } else {
    date = DateTime.tryParse(text);
  }
  if (date == null || date.year < 1990) return null;
  final limit = now ?? DateTime.now();
  return date.isAfter(limit) ? limit : date;
}

/// Splits a tag field like `ai, research` or `ai|research`.
List<String> splitTags(String? raw) {
  if (raw == null) return const [];
  return raw
      .split(RegExp(r'[,;|]'))
      .map((t) => t.trim())
      .where((t) => t.isNotEmpty)
      .toSet()
      .toList();
}
