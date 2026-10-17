import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:web/web.dart' as web;

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

  /// The browser reports writes made by other tabs of this site (never this
  /// tab's own). Stored keys may carry a prefix, so match by ending.
  @override
  Stream<String> watchExternalChanges() => web.EventStreamProviders.storageEvent
      .forTarget(web.window)
      .map((event) => event.key)
      .where((key) => key != null)
      .map(
        (key) => [
          LocalLibrary.libraryKey,
          LocalLibrary.contentKey,
        ].firstWhere(key!.endsWith, orElse: () => key),
      );
}
