import 'dart:convert';

import 'imported_item.dart';

/// Rows from a CSV or JSON file, keyed by column name.
class ImportTable {
  const ImportTable(this.columns, this.rows);

  final List<String> columns;
  final List<Map<String, String>> rows;
}

/// Parses CSV (RFC 4180: quoted fields, escaped quotes, newlines in quotes).
/// The first row is the header.
ImportTable parseCsv(String text) {
  final records = <List<String>>[];
  var record = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  final input = text.startsWith('﻿') ? text.substring(1) : text;

  for (var i = 0; i < input.length; i++) {
    final c = input[i];
    if (inQuotes) {
      if (c == '"') {
        if (i + 1 < input.length && input[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(c);
      }
    } else if (c == '"') {
      inQuotes = true;
    } else if (c == ',') {
      record.add(field.toString());
      field.clear();
    } else if (c == '\n' || c == '\r') {
      if (c == '\r' && i + 1 < input.length && input[i + 1] == '\n') i++;
      record.add(field.toString());
      field.clear();
      if (record.any((f) => f.isNotEmpty)) records.add(record);
      record = <String>[];
    } else {
      field.write(c);
    }
  }
  record.add(field.toString());
  if (record.any((f) => f.isNotEmpty)) records.add(record);

  if (records.isEmpty) return const ImportTable([], []);
  final columns = records.first.map((c) => c.trim()).toList();
  final rows = [
    for (final r in records.skip(1))
      {
        for (var c = 0; c < columns.length; c++)
          columns[c]: c < r.length ? r[c] : '',
      },
  ];
  return ImportTable(columns, rows);
}

/// Parses a JSON array of objects, or an object holding one (for example
/// `{"bookmarks": [...]}`). Nested values are flattened to strings.
ImportTable parseJsonTable(String text) {
  final decoded = jsonDecode(text);
  final list = switch (decoded) {
    List() => decoded,
    Map() => decoded.values.whereType<List>().firstOrNull ?? const <Object?>[],
    _ => const <Object?>[],
  };
  final rows = <Map<String, String>>[];
  final columns = <String>{};
  for (final entry in list.whereType<Map>()) {
    final row = <String, String>{};
    entry.forEach((key, value) {
      if (value == null) return;
      row['$key'] = value is List
          ? value.map((v) => '$v').join(', ')
          : value is Map
          ? jsonEncode(value)
          : '$value';
    });
    columns.addAll(row.keys);
    rows.add(row);
  }
  return ImportTable(columns.toList(), rows);
}

/// Which column feeds each bookmark field. Only [url] is required.
class FieldMapping {
  const FieldMapping({
    this.url,
    this.title,
    this.description,
    this.folder,
    this.tags,
    this.createdAt,
  });

  final String? url;
  final String? title;
  final String? description;
  final String? folder;
  final String? tags;
  final String? createdAt;

  bool get isUsable => url != null;

  FieldMapping copyWith({
    String? Function()? url,
    String? Function()? title,
    String? Function()? description,
    String? Function()? folder,
    String? Function()? tags,
    String? Function()? createdAt,
  }) => FieldMapping(
    url: url == null ? this.url : url(),
    title: title == null ? this.title : title(),
    description: description == null ? this.description : description(),
    folder: folder == null ? this.folder : folder(),
    tags: tags == null ? this.tags : tags(),
    createdAt: createdAt == null ? this.createdAt : createdAt(),
  );
}

const _candidates = {
  'url': ['url', 'link', 'href', 'uri', 'address', 'given_url', 'resolved_url'],
  'title': ['title', 'name', 'given_title', 'resolved_title'],
  'description': [
    'description',
    'note',
    'notes',
    'excerpt',
    'summary',
    'comment',
  ],
  'folder': ['folder', 'collection', 'category', 'list', 'group', 'path'],
  'tags': ['tags', 'tag', 'labels', 'keywords'],
  'createdAt': [
    'created',
    'created_at',
    'createdat',
    'date',
    'date_added',
    'add_date',
    'added',
    'time_added',
    'timestamp',
    'saved_at',
  ],
};

/// Guesses the mapping from column names (case-insensitive).
FieldMapping suggestMapping(List<String> columns) {
  String? find(String field) {
    for (final candidate in _candidates[field]!) {
      for (final column in columns) {
        if (column.trim().toLowerCase() == candidate) return column;
      }
    }
    return null;
  }

  return FieldMapping(
    url: find('url'),
    title: find('title'),
    description: find('description'),
    folder: find('folder'),
    tags: find('tags'),
    createdAt: find('createdAt'),
  );
}

/// The folder values that mean "no folder" in common exports.
const _noFolder = {'', 'unsorted', 'root', '/', 'none', 'default'};

List<ImportedItem> applyMapping(
  ImportTable table,
  FieldMapping mapping, {
  DateTime? now,
}) {
  String? value(Map<String, String> row, String? column) {
    if (column == null) return null;
    final v = row[column]?.trim();
    return v == null || v.isEmpty ? null : v;
  }

  return [
    for (final row in table.rows)
      if (value(row, mapping.url) case final url?)
        ImportedItem(
          url: url,
          title: value(row, mapping.title),
          description: value(row, mapping.description),
          folder: switch (value(row, mapping.folder)) {
            // "Parent/Child" paths keep the innermost folder.
            final f? when !_noFolder.contains(f.toLowerCase()) =>
              f.split('/').where((p) => p.trim().isNotEmpty).lastOrNull?.trim(),
            _ => null,
          },
          tags: splitTags(value(row, mapping.tags)),
          createdAt: parseImportDate(value(row, mapping.createdAt), now: now),
        ),
  ];
}
