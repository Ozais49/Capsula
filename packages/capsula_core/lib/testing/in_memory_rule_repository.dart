import 'dart:async';

import '../domain/meta/library_meta.dart';
import '../domain/rules/rule.dart';

/// In-memory [RuleRepository], used by tests and to hold the on-device
/// library.
class InMemoryRuleRepository implements RuleRepository {
  final Map<String, Rule> items = {};
  final _changes = StreamController<void>.broadcast();
  int _nextId = 0;

  void addAll(Iterable<Rule> rules) {
    for (final r in rules) {
      items[r.id] = r;
    }
    _changes.add(null);
  }

  @override
  String newId() => 'r${_nextId++}';

  @override
  Stream<List<Rule>> watch() async* {
    yield sortRules(items.values);
    await for (final _ in _changes.stream) {
      yield sortRules(items.values);
    }
  }

  @override
  Future<void> create(Rule rule) async => addAll([rule]);

  @override
  Future<void> update(Rule rule) async => addAll([rule]);

  @override
  Future<void> delete(String id) async {
    items.remove(id);
    _changes.add(null);
  }
}

/// In-memory [LibraryMetaRepository].
class InMemoryLibraryMeta implements LibraryMetaRepository {
  InMemoryLibraryMeta([this.version = 1]);

  int version;

  @override
  Future<int> schemaVersion() async => version;

  @override
  Future<void> setSchemaVersion(int version) async => this.version = version;
}
