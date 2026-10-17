import 'package:flutter/foundation.dart';

import 'package:capsula_core/domain/import/bookmark_html_parser.dart';
import 'package:capsula_core/domain/import/import_service.dart';
import 'package:capsula_core/domain/import/imported_item.dart';
import 'package:capsula_core/domain/import/tabular_import.dart';
import 'package:capsula_core/domain/organization/label.dart';

import '../../platform/import_file_picker.dart';

sealed class ImportStep {
  const ImportStep();
}

class ChooseSource extends ImportStep {
  const ChooseSource({this.error});

  /// Why the last attempt failed, if it did.
  final String? error;
}

class Working extends ImportStep {
  const Working(this.message);

  final String message;
}

class MapFields extends ImportStep {
  const MapFields(this.table, this.mapping);

  final ImportTable table;
  final FieldMapping mapping;
}

class Preview extends ImportStep {
  const Preview(this.plan);

  final ImportPlan plan;
}

class Importing extends ImportStep {
  const Importing(this.done, this.total);

  final int done;
  final int total;
}

class Finished extends ImportStep {
  const Finished(this.result);

  final ImportResult result;
}

/// Drives the import flow: pick → (map fields) → preview → import → result.
class ImportController extends ChangeNotifier {
  ImportController(this._service, this._picker);

  final ImportService _service;
  final ImportFilePicker _picker;

  ImportStep _step = const ChooseSource();
  ImportOrigin _origin = ImportOrigin.file;
  String? _fileName;

  ImportStep get step => _step;
  ImportOrigin get origin => _origin;
  String? get fileName => _fileName;

  void _go(ImportStep step) {
    _step = step;
    notifyListeners();
  }

  void restart() => _go(const ChooseSource());

  Future<void> pickFile(ImportOrigin origin) async {
    _origin = origin;
    final PickedImportFile? file;
    try {
      file = await _picker.pick();
    } on Object catch (e) {
      return _go(ChooseSource(error: 'Could not open the file: $e'));
    }
    if (file == null) return;
    _fileName = file.name;
    await loadText(file.text);
  }

  /// Reads an export's contents. Public for tests and drag-and-drop.
  Future<void> loadText(String text) async {
    _go(const Working('Reading file…'));
    try {
      if (looksLikeBookmarkHtml(text)) {
        return await _plan(parseBookmarkHtml(text));
      }
      final trimmed = text.trimLeft();
      final table = trimmed.startsWith('[') || trimmed.startsWith('{')
          ? parseJsonTable(text)
          : parseCsv(text);
      if (table.rows.isEmpty) {
        return _go(
          const ChooseSource(error: 'No bookmarks found in this file.'),
        );
      }
      final mapping = suggestMapping(table.columns);
      final knownFormat =
          _origin == ImportOrigin.raindrop || _origin == ImportOrigin.pocket;
      if (knownFormat && mapping.isUsable) {
        return await _plan(applyMapping(table, mapping));
      }
      _go(MapFields(table, mapping));
    } on FormatException catch (e) {
      _go(ChooseSource(error: 'This file couldn\'t be read: ${e.message}'));
    }
  }

  void updateMapping(FieldMapping mapping) {
    if (_step case MapFields(:final table)) _go(MapFields(table, mapping));
  }

  Future<void> confirmMapping() async {
    if (_step case MapFields(:final table, :final mapping)
        when mapping.isUsable) {
      await _plan(applyMapping(table, mapping));
    }
  }

  Future<void> _plan(List<ImportedItem> items) async {
    if (items.isEmpty) {
      return _go(const ChooseSource(error: 'No links found in this file.'));
    }
    _go(Working('Checking ${items.length} links…'));
    try {
      _go(Preview(await _service.plan(items)));
    } on Object catch (e) {
      _go(ChooseSource(error: 'Could not check for duplicates: $e'));
    }
  }

  Future<void> startImport({
    required ImportOptions options,
    required List<Label> existingLabels,
  }) async {
    if (_step case Preview(:final plan)) {
      _go(Importing(0, plan.newItems.length));
      try {
        final result = await _service.run(
          plan,
          origin: _origin,
          options: options,
          existingLabels: existingLabels,
          onProgress: (done, total) => _go(Importing(done, total)),
        );
        _go(Finished(result));
      } on Object catch (e) {
        _go(ChooseSource(error: 'Import failed: $e'));
      }
    }
  }
}
