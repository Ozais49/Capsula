import 'package:shared_preferences/shared_preferences.dart';

import 'package:capsula_core/domain/local/local_library.dart';

LocalStorage deviceStorage() => _PrefsStorage(SharedPreferencesAsync());

/// The browser's local storage for this site.
class _PrefsStorage implements LocalStorage {
  _PrefsStorage(this._prefs);

  final SharedPreferencesAsync _prefs;

  @override
  Future<String?> read(String key) => _prefs.getString(key);

  @override
  Future<void> write(String key, String value) => _prefs.setString(key, value);
}
