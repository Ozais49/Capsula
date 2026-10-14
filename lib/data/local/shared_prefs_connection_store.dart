import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/connection/backend.dart';
import '../../domain/connection/firebase_connection.dart';

class SharedPrefsConnectionStore implements ConnectionSettingsStore {
  SharedPrefsConnectionStore([SharedPreferencesAsync? prefs])
    : _prefs = prefs ?? SharedPreferencesAsync();

  static const _key = 'firebase_connection';

  final SharedPreferencesAsync _prefs;

  @override
  Future<FirebaseConnection?> load() async {
    final raw = await _prefs.getString(_key);
    if (raw == null) return null;
    try {
      return FirebaseConnection.fromJson(
        jsonDecode(raw) as Map<String, Object?>,
      );
    } on Object {
      return null;
    }
  }

  @override
  Future<void> save(FirebaseConnection connection) =>
      _prefs.setString(_key, jsonEncode(connection.toJson()));

  @override
  Future<void> clear() => _prefs.remove(_key);
}
