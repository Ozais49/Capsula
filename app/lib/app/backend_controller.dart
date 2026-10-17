import 'package:flutter/foundation.dart';

import 'package:capsula_core/domain/connection/backend.dart';
import 'package:capsula_core/domain/connection/firebase_connection.dart';

enum BackendStatus { loading, notConfigured, connecting, connected, failed }

/// Loads the saved connection settings and connects to the backend.
class BackendController extends ChangeNotifier {
  BackendController({
    required this._store,
    required this._connector,
    this._fallbackSettings,
    this._deviceLibrary,
  });

  /// Opens the library kept on this device, for use without a backend.
  final Future<BackendServices> Function()? _deviceLibrary;

  /// Settings to use when none are saved, such as the config Firebase
  /// Hosting serves for the site. Never saved to the device.
  final Future<FirebaseConnection?> Function()? _fallbackSettings;

  final ConnectionSettingsStore _store;
  final BackendConnector _connector;

  BackendStatus _status = BackendStatus.loading;
  FirebaseConnection? _saved;
  FirebaseConnection? _active;

  /// What was saved when the current connection was made.
  FirebaseConnection? _savedAtConnect;
  BackendServices? _services;
  String? _error;
  bool _deviceOnly = false;

  BackendStatus get status => _status;
  BackendServices? get services => _services;
  String? get error => _error;

  /// Settings saved on this device, which may differ from [activeSettings]
  /// until the app restarts.
  FirebaseConnection? get savedSettings => _saved;

  /// Settings of the current connection.
  FirebaseConnection? get activeSettings => _active;

  /// The library is kept on this device only, without an account.
  bool get deviceOnly => _deviceOnly;

  /// Whether this build can keep a library on the device.
  bool get canUseDevice => _deviceLibrary != null;

  bool get restartRequired =>
      !_deviceOnly && _active != null && _saved != _savedAtConnect;

  /// Connected with settings that aren't saved on this device (from the
  /// hosting site).
  bool get usingFallbackSettings => _active != null && _savedAtConnect == null;

  Future<void> start() async {
    _saved = await _store.load();
    if (canUseDevice && await _store.loadDeviceOnly()) {
      return _openDeviceLibrary();
    }
    final settings = _saved ?? await _loadFallback();
    if (settings == null) {
      _setStatus(BackendStatus.notConfigured);
    } else {
      await _connect(settings);
    }
  }

  Future<FirebaseConnection?> _loadFallback() async {
    try {
      return await _fallbackSettings?.call();
    } on Object {
      return null;
    }
  }

  /// Saves [settings] and connects if not already connected. Once connected,
  /// new settings take effect after a restart.
  Future<void> save(FirebaseConnection settings) async {
    await _store.save(settings);
    _saved = settings;
    if (_deviceOnly) {
      await _store.saveDeviceOnly(false);
      _deviceOnly = false;
      await _connect(settings);
    } else if (_status == BackendStatus.connected) {
      notifyListeners();
    } else {
      await _connect(settings);
    }
  }

  Future<void> clearSaved() async {
    await _store.clear();
    _saved = null;
    if (_status != BackendStatus.connected) {
      _status = BackendStatus.notConfigured;
    }
    _error = null;
    notifyListeners();
  }

  Future<void> _connect(FirebaseConnection settings) async {
    _error = null;
    _setStatus(BackendStatus.connecting);
    try {
      _services = await _connector.connect(settings);
      _active = settings;
      _savedAtConnect = _saved;
      _setStatus(BackendStatus.connected);
    } on Object catch (e) {
      _error = 'Could not connect: $e';
      _setStatus(BackendStatus.failed);
    }
  }

  /// Keeps the library on this device only, with no account. Takes effect
  /// right away.
  Future<void> useDevice() async {
    await _store.saveDeviceOnly(true);
    await _openDeviceLibrary();
  }

  /// Stops using the on-device library and connects with the saved (or
  /// built-in) settings, or asks for them when there are none. The
  /// on-device library stays on the device.
  Future<void> useAccount() async {
    await _store.saveDeviceOnly(false);
    _deviceOnly = false;
    _services = null;
    _active = null;
    final settings = _saved ?? await _loadFallback();
    if (settings == null) {
      _setStatus(BackendStatus.notConfigured);
    } else {
      await _connect(settings);
    }
  }

  Future<void> _openDeviceLibrary() async {
    _error = null;
    _setStatus(BackendStatus.connecting);
    try {
      _services = await _deviceLibrary!();
      _deviceOnly = true;
      _active = null;
      _setStatus(BackendStatus.connected);
    } on Object catch (e) {
      _error = 'Could not open the library on this device: $e';
      _setStatus(BackendStatus.failed);
    }
  }

  void _setStatus(BackendStatus status) {
    _status = status;
    notifyListeners();
  }
}
