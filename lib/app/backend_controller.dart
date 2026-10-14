import 'package:flutter/foundation.dart';

import '../domain/connection/backend.dart';
import '../domain/connection/firebase_connection.dart';

enum BackendStatus { loading, notConfigured, connecting, connected, failed }

/// Loads the saved connection settings and connects to the backend.
class BackendController extends ChangeNotifier {
  BackendController({required this._store, required this._connector});

  final ConnectionSettingsStore _store;
  final BackendConnector _connector;

  BackendStatus _status = BackendStatus.loading;
  FirebaseConnection? _saved;
  FirebaseConnection? _active;
  BackendServices? _services;
  String? _error;

  BackendStatus get status => _status;
  BackendServices? get services => _services;
  String? get error => _error;

  /// Settings saved on this device, which may differ from [activeSettings]
  /// until the app restarts.
  FirebaseConnection? get savedSettings => _saved;

  /// Settings of the current connection.
  FirebaseConnection? get activeSettings => _active;

  bool get restartRequired => _active != null && _saved != _active;

  Future<void> start() async {
    _saved = await _store.load();
    final saved = _saved;
    if (saved == null) {
      _setStatus(BackendStatus.notConfigured);
    } else {
      await _connect(saved);
    }
  }

  /// Saves [settings] and connects if not already connected. Once connected,
  /// new settings take effect after a restart.
  Future<void> save(FirebaseConnection settings) async {
    await _store.save(settings);
    _saved = settings;
    if (_status == BackendStatus.connected) {
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
      _setStatus(BackendStatus.connected);
    } on Object catch (e) {
      _error = 'Could not connect: $e';
      _setStatus(BackendStatus.failed);
    }
  }

  void _setStatus(BackendStatus status) {
    _status = status;
    notifyListeners();
  }
}
