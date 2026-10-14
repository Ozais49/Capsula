import 'dart:convert';

import '../bookmarks/bookmark.dart';
import '../organization/label.dart';

enum ExportFormat {
  /// Everything Capsula stores, for backup.
  json('JSON backup', 'json', 'application/json'),

  /// Netscape bookmark file that browsers and bookmark services import.
  html('Browser bookmarks (HTML)', 'html', 'text/html');

  const ExportFormat(this.label, this.extension, this.mimeType);

  final String label;
  final String extension;
  final String mimeType;
}

String exportFileName(ExportFormat format, DateTime now) {
  String two(int n) => n.toString().padLeft(2, '0');
  return 'capsula-${now.year}-${two(now.month)}-${two(now.day)}.${format.extension}';
}

String exportLibrary(
  ExportFormat format,
  List<Bookmark> bookmarks,
  List<Label> labels, {
  required DateTime now,
}) => switch (format) {
  ExportFormat.json => _json(bookmarks, labels, now),
  ExportFormat.html => _html(bookmarks, labels),
};

Map<String, String> _names(List<Label> labels, LabelKind kind) => {
  for (final l in labels.where((l) => l.kind == kind)) l.id: l.name,
};

List<String> _resolve(Map<String, String> names, List<String> ids) =>
    ids.map((id) => names[id]).nonNulls.toList();

String _json(List<Bookmark> bookmarks, List<Label> labels, DateTime now) {
  final tags = _names(labels, LabelKind.tag);
  final collections = _names(labels, LabelKind.collection);
  return const JsonEncoder.withIndent('  ').convert({
    'format': 'capsula',
    'version': 1,
    'exportedAt': now.toUtc().toIso8601String(),
    'tags': tags.values.toList(),
    'collections': collections.values.toList(),
    'bookmarks': [
      for (final b in bookmarks)
        {
          'url': b.url,
          'title': b.title,
          'description': ?b.description,
          'imageUrl': ?b.imageUrl,
          'source': b.source.id,
          'readingStatus': b.readingStatus.name,
          'archived': b.archived,
          'inInbox': b.inInbox,
          'tags': _resolve(tags, b.tagIds),
          'collections': _resolve(collections, b.collectionIds),
          'createdAt': b.createdAt.toUtc().toIso8601String(),
          'updatedAt': b.updatedAt.toUtc().toIso8601String(),
          'importedFrom': ?b.importedFrom,
          if (b.importedAt case final at?)
            'importedAt': at.toUtc().toIso8601String(),
        },
    ],
  });
}

String _html(List<Bookmark> bookmarks, List<Label> labels) {
  final tags = _names(labels, LabelKind.tag);
  final collections = _names(labels, LabelKind.collection);
  final buffer = StringBuffer()
    ..writeln('<!DOCTYPE NETSCAPE-Bookmark-file-1>')
    ..writeln('<!-- Exported from Capsula -->')
    ..writeln(
      '<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">',
    )
    ..writeln('<TITLE>Bookmarks</TITLE>')
    ..writeln('<H1>Bookmarks</H1>')
    ..writeln('<DL><p>');

  void link(Bookmark b, String indent) {
    final tagNames = _resolve(tags, b.tagIds);
    final addDate = b.createdAt.millisecondsSinceEpoch ~/ 1000;
    buffer.write('$indent<DT><A HREF="${_escape(b.url)}" ADD_DATE="$addDate"');
    if (tagNames.isNotEmpty) {
      buffer.write(' TAGS="${_escape(tagNames.join(','))}"');
    }
    buffer.writeln('>${_escape(b.displayTitle)}</A>');
    if (b.description case final d? when d.isNotEmpty) {
      buffer.writeln('$indent<DD>${_escape(d)}');
    }
  }

  // A bookmark in several collections appears in each folder.
  for (final entry in collections.entries) {
    final members = bookmarks.where((b) => b.collectionIds.contains(entry.key));
    if (members.isEmpty) continue;
    buffer
      ..writeln('    <DT><H3>${_escape(entry.value)}</H3>')
      ..writeln('    <DL><p>');
    for (final b in members) {
      link(b, '        ');
    }
    buffer.writeln('    </DL><p>');
  }
  for (final b in bookmarks.where(
    (b) => _resolve(collections, b.collectionIds).isEmpty,
  )) {
    link(b, '    ');
  }
  buffer.writeln('</DL><p>');
  return buffer.toString();
}

String _escape(String text) => text
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;');
