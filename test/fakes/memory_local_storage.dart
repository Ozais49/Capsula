import 'dart:async';

import 'package:capsula_core/domain/local/local_library.dart';

/// [LocalStorage] in a map, standing in for the device's storage. Several
/// instances can share one map, like browser tabs sharing local storage.
class MemoryLocalStorage implements LocalStorage {
  MemoryLocalStorage([Map<String, String>? values]) : values = values ?? {};

  final Map<String, String> values;

  /// Fails every write with this error while set (e.g. a full quota).
  Object? writeError;

  final _external = StreamController<String>.broadcast();

  /// Reports [key] as written by someone else, like a browser storage event.
  void notifyExternalChange(String key) => _external.add(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    if (writeError case final error?) throw error;
    values[key] = value;
  }

  @override
  Stream<String> watchExternalChanges() => _external.stream;
}
