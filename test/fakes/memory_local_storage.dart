import 'package:capsula_core/domain/local/local_library.dart';

/// [LocalStorage] in a map, standing in for the device's storage.
class MemoryLocalStorage implements LocalStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}
