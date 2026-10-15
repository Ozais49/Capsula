import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract interface class ApiSettingsStore {
  Future<String?> load();
  Future<void> save(String? url);
}

class SharedPrefsApiSettingsStore implements ApiSettingsStore {
  SharedPrefsApiSettingsStore([this._override]);

  static const _key = 'api_base_url';
  final SharedPreferencesAsync? _override;

  // Created on first use, so constructing the store never touches the
  // platform plugin.
  late final SharedPreferencesAsync _prefs =
      _override ?? SharedPreferencesAsync();

  @override
  Future<String?> load() => _prefs.getString(_key);

  @override
  Future<void> save(String? url) =>
      url == null ? _prefs.remove(_key) : _prefs.setString(_key, url);
}

/// The Capsula API server this device uses, if any. Saved on the device;
/// [defaultUrl] (from the build) applies until the user sets one.
class ApiSettings extends ChangeNotifier {
  ApiSettings(this._store, {this.defaultUrl});

  final ApiSettingsStore _store;
  final Uri? defaultUrl;
  Uri? _url;
  bool _loaded = false;

  Uri? get baseUrl => _loaded ? _url : defaultUrl;

  Future<void> load() async {
    try {
      final saved = await _store.load();
      _url = saved == null ? defaultUrl : parseApiUrl(saved);
    } on Object {
      _url = defaultUrl;
    }
    _loaded = true;
    notifyListeners();
  }

  /// Saves [text], or clears the setting when it's blank. Returns false for
  /// an invalid address.
  Future<bool> save(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      await _store.save(null);
      _url = null;
    } else {
      final url = parseApiUrl(trimmed);
      if (url == null) return false;
      await _store.save(url.toString());
      _url = url;
    }
    _loaded = true;
    notifyListeners();
    return true;
  }
}

/// An `http(s)://host[:port][/path]` address without a trailing slash.
Uri? parseApiUrl(String text) {
  final url = Uri.tryParse(text.trim());
  if (url == null ||
      (url.scheme != 'https' && url.scheme != 'http') ||
      url.host.isEmpty) {
    return null;
  }
  return url.replace(
    path: url.path.replaceFirst(RegExp(r'/+$'), ''),
    query: null,
    fragment: null,
  );
}
