import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'package:capsula_core/domain/local/local_library.dart';

LocalStorage deviceStorage() => _FileStorage();

/// One JSON file per key in the app's private support folder.
class _FileStorage implements LocalStorage {
  Future<Directory>? _dir;

  Future<File> _file(String key) async {
    final dir = await (_dir ??= getApplicationSupportDirectory());
    return File('${dir.path}${Platform.pathSeparator}$key.json');
  }

  @override
  Future<String?> read(String key) async {
    final file = await _file(key);
    return await file.exists() ? file.readAsString() : null;
  }

  @override
  Future<void> write(String key, String value) async {
    final file = await _file(key);
    // Write a copy first so a crash mid-write can't corrupt the library.
    final temp = File('${file.path}.tmp');
    await temp.writeAsString(value, flush: true);
    await temp.rename(file.path);
  }
}
