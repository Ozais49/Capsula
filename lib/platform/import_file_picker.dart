import 'dart:convert';

import 'package:file_selector/file_selector.dart';

class PickedImportFile {
  const PickedImportFile(this.name, this.text);

  final String name;
  final String text;
}

/// Lets the user choose a bookmark export file.
abstract interface class ImportFilePicker {
  /// Null when the user cancels.
  Future<PickedImportFile?> pick();
}

class FileSelectorImportPicker implements ImportFilePicker {
  const FileSelectorImportPicker();

  static const _types = XTypeGroup(
    label: 'Bookmark exports',
    extensions: ['html', 'htm', 'csv', 'json', 'txt'],
    mimeTypes: [
      'text/html',
      'text/csv',
      'text/comma-separated-values',
      'application/json',
      'text/plain',
    ],
  );

  @override
  Future<PickedImportFile?> pick() async {
    final file = await openFile(acceptedTypeGroups: const [_types]);
    if (file == null) return null;
    final bytes = await file.readAsBytes();
    return PickedImportFile(
      file.name,
      utf8.decode(bytes, allowMalformed: true),
    );
  }
}
