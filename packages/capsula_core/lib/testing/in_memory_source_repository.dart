import 'dart:async';

import '../domain/sources/custom_source.dart';

/// In-memory [SourceRepository], used by tests and to hold the on-device
/// library.
class InMemorySourceRepository implements SourceRepository {
  final Map<String, CustomSource> items = {};
  final _changes = StreamController<void>.broadcast();
  int _nextId = 0;

  void addAll(Iterable<CustomSource> sources) {
    for (final s in sources) {
      items[s.id] = s;
    }
    _changes.add(null);
  }

  @override
  String newId() => 's${_nextId++}';

  @override
  Stream<List<CustomSource>> watch() async* {
    yield sortSources(items.values);
    await for (final _ in _changes.stream) {
      yield sortSources(items.values);
    }
  }

  @override
  Future<void> create(CustomSource source) async => addAll([source]);

  @override
  Future<void> update(CustomSource source) async => addAll([source]);

  @override
  Future<void> delete(String id) async {
    items.remove(id);
    _changes.add(null);
  }
}
