import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/backend_controller.dart';
import '../../app/dependencies.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../config/app_config.dart';
import 'use_device_button.dart';

import 'package:capsula_core/domain/connection/firebase_connection.dart';

/// Lets the user connect the app to their Firebase project.
class ConnectionScreen extends StatefulWidget {
  const ConnectionScreen({super.key, this.platform});

  /// Overrides platform detection in tests.
  final ConnectionPlatform? platform;

  @override
  State<ConnectionScreen> createState() => _ConnectionScreenState();
}

class _ConnectionScreenState extends State<ConnectionScreen> {
  final _paste = TextEditingController();
  final _apiKey = TextEditingController();
  final _appId = TextEditingController();
  final _projectId = TextEditingController();
  final _senderId = TextEditingController();
  final _authDomain = TextEditingController();
  final _storageBucket = TextEditingController();

  bool _initialized = false;
  bool _saving = false;
  String? _pasteError;
  List<String> _problems = const [];

  ConnectionPlatform get _platform =>
      widget.platform ??
      (kIsWeb ? ConnectionPlatform.web : ConnectionPlatform.android);

  BackendController get _backend => AppDependencies.of(context).backend;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final saved = _backend.savedSettings;
    if (saved != null) _fill(saved);
  }

  @override
  void dispose() {
    for (final c in [
      _paste,
      _apiKey,
      _appId,
      _projectId,
      _senderId,
      _authDomain,
      _storageBucket,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _fill(FirebaseConnection c) {
    _apiKey.text = c.apiKey;
    _appId.text = c.appId;
    _projectId.text = c.projectId;
    _senderId.text = c.messagingSenderId;
    _authDomain.text = c.authDomain ?? '';
    _storageBucket.text = c.storageBucket ?? '';
  }

  FirebaseConnection _read() => FirebaseConnection.fromJson({
    'apiKey': _apiKey.text.trim(),
    'appId': _appId.text.trim(),
    'projectId': _projectId.text.trim(),
    'messagingSenderId': _senderId.text.trim(),
    'authDomain': _authDomain.text.trim(),
    'storageBucket': _storageBucket.text.trim(),
  });

  void _applyPaste() {
    try {
      final parsed = parseFirebaseConfig(
        _paste.text,
        androidPackageName: AppConfig.androidPackageName,
      );
      setState(() {
        _fill(parsed);
        _paste.clear();
        _pasteError = null;
        _problems = parsed.validate(_platform);
      });
    } on FormatException catch (e) {
      setState(() => _pasteError = e.message);
    }
  }

  Future<void> _save() async {
    final settings = _read();
    final problems = settings.validate(_platform);
    setState(() => _problems = problems);
    if (problems.isNotEmpty) return;

    final wasConnected = _backend.status == BackendStatus.connected;
    setState(() => _saving = true);
    await _backend.save(settings);
    if (!mounted) return;
    setState(() => _saving = false);

    if (!wasConnected && _backend.status == BackendStatus.connected) {
      context.go(AppRoutes.home);
    }
  }

  Future<void> _remove() async {
    await _backend.clearSaved();
    if (!mounted) return;
    setState(() {
      _fill(
        const FirebaseConnection(
          apiKey: '',
          appId: '',
          projectId: '',
          messagingSenderId: '',
        ),
      );
      _problems = const [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isWeb = _platform == ConnectionPlatform.web;

    return Scaffold(
      appBar: AppBar(title: const Text('Firebase connection')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Gap.lg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListenableBuilder(
                    listenable: _backend,
                    builder: (context, _) => _StatusPanel(backend: _backend),
                  ),
                  if (!_backend.deviceOnly) ...[
                    const SizedBox(height: Gap.md),
                    const UseDeviceButton(),
                  ],
                  const SizedBox(height: Gap.lg),
                  Text(
                    'Paste configuration',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: Gap.xs),
                  Text(
                    isWeb
                        ? 'Paste the firebaseConfig object of the Web app '
                              '(Firebase console → Project settings → Your apps).'
                        : 'Paste the contents of google-services.json for '
                              '${AppConfig.androidPackageName}.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: Gap.sm),
                  TextField(
                    controller: _paste,
                    minLines: 3,
                    maxLines: 8,
                    decoration: InputDecoration(
                      hintText: isWeb
                          ? '{ apiKey: "...", appId: "1:...:web:...", ... }'
                          : '{ "project_info": { ... }, "client": [ ... ] }',
                      errorText: _pasteError,
                      errorMaxLines: 3,
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                    ),
                  ),
                  const SizedBox(height: Gap.sm),
                  Align(
                    alignment: Alignment.centerRight,
                    child: OutlinedButton.icon(
                      onPressed: _applyPaste,
                      icon: const Icon(Icons.content_paste_go),
                      label: const Text('Fill in fields'),
                    ),
                  ),
                  const SizedBox(height: Gap.lg),
                  Text('Settings', style: theme.textTheme.titleMedium),
                  const SizedBox(height: Gap.md),
                  _field(_apiKey, 'API key'),
                  _field(
                    _appId,
                    'App ID',
                    hint: isWeb ? '1:123:web:abc' : '1:123:android:abc',
                  ),
                  _field(_projectId, 'Project ID'),
                  _field(_senderId, 'Messaging sender ID'),
                  _field(_authDomain, 'Auth domain (optional)'),
                  _field(_storageBucket, 'Storage bucket (optional)'),
                  for (final problem in _problems)
                    Padding(
                      padding: const EdgeInsets.only(bottom: Gap.xs),
                      child: Text(
                        problem,
                        style: TextStyle(color: theme.colorScheme.error),
                      ),
                    ),
                  const SizedBox(height: Gap.md),
                  FilledButton(
                    onPressed: _saving ? null : _save,
                    child: _saving
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Save and connect'),
                  ),
                  ListenableBuilder(
                    listenable: _backend,
                    builder: (context, _) => _backend.savedSettings == null
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(top: Gap.sm),
                            child: TextButton(
                              onPressed: _saving ? null : _remove,
                              child: const Text('Remove saved connection'),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _field(
    TextEditingController controller,
    String label, {
    String? hint,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: Gap.md),
    child: TextField(
      controller: controller,
      enabled: !_saving,
      autocorrect: false,
      enableSuggestions: false,
      decoration: InputDecoration(labelText: label, hintText: hint),
    ),
  );
}

class _StatusPanel extends StatelessWidget {
  const _StatusPanel({required this.backend});

  final BackendController backend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color, message) = switch (backend.status) {
      BackendStatus.connected when backend.deviceOnly => (
        Icons.phone_android,
        scheme.primary,
        'Using the library on this device, without an account. Saving '
            'settings below connects to Firebase instead.',
      ),
      BackendStatus.connected when backend.restartRequired => (
        Icons.restart_alt,
        scheme.tertiary,
        backend.savedSettings == null
            ? 'Saved connection removed. Restart the app to disconnect.'
            : 'New settings saved. Restart the app to use them.',
      ),
      BackendStatus.connected => (
        Icons.cloud_done_outlined,
        scheme.primary,
        backend.usingFallbackSettings
            ? 'Connected to ${backend.activeSettings?.projectId}, '
                  "this site's Firebase project."
            : 'Connected to ${backend.activeSettings?.projectId}.',
      ),
      BackendStatus.failed => (
        Icons.error_outline,
        scheme.error,
        backend.error ?? 'Could not connect.',
      ),
      BackendStatus.connecting || BackendStatus.loading => (
        Icons.sync,
        scheme.onSurfaceVariant,
        'Connecting…',
      ),
      BackendStatus.notConfigured => (
        Icons.cloud_off_outlined,
        scheme.onSurfaceVariant,
        'Not connected. Enter your Firebase project settings, or use '
            'Capsula without an account.',
      ),
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(Gap.md),
        child: Row(
          children: [
            Icon(icon, color: color),
            const SizedBox(width: Gap.md),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
  }
}
