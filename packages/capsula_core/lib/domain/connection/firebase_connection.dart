import 'dart:convert';

enum ConnectionPlatform { android, web }

/// Settings needed to connect to a Firebase project, entered in the app
/// rather than compiled in. These are identifiers, not secrets; access is
/// protected by Firebase Auth and security rules.
class FirebaseConnection {
  const FirebaseConnection({
    required this.apiKey,
    required this.appId,
    required this.projectId,
    required this.messagingSenderId,
    this.authDomain,
    this.storageBucket,
  });

  factory FirebaseConnection.fromJson(Map<String, Object?> json) =>
      FirebaseConnection(
        apiKey: json['apiKey'] as String? ?? '',
        appId: json['appId'] as String? ?? '',
        projectId: json['projectId'] as String? ?? '',
        messagingSenderId: json['messagingSenderId'] as String? ?? '',
        authDomain: _nonEmpty(json['authDomain'] as String?),
        storageBucket: _nonEmpty(json['storageBucket'] as String?),
      );

  final String apiKey;
  final String appId;
  final String projectId;
  final String messagingSenderId;
  final String? authDomain;
  final String? storageBucket;

  Map<String, String> toJson() => {
    'apiKey': apiKey,
    'appId': appId,
    'projectId': projectId,
    'messagingSenderId': messagingSenderId,
    'authDomain': ?authDomain,
    'storageBucket': ?storageBucket,
  };

  /// Returns a list of problems, empty when the settings look usable
  /// on [platform].
  List<String> validate(ConnectionPlatform platform) {
    final problems = <String>[
      if (apiKey.isEmpty) 'API key is required.',
      if (projectId.isEmpty) 'Project ID is required.',
      if (messagingSenderId.isEmpty) 'Messaging sender ID is required.',
      if (appId.isEmpty) 'App ID is required.',
    ];
    if (appId.isNotEmpty) {
      final match = _appIdPattern.firstMatch(appId);
      if (match == null) {
        problems.add('App ID should look like 1:1234567890:android:abc123.');
      } else if (match.group(1) != platform.name) {
        problems.add(
          'This App ID is for ${match.group(1)}. '
          'Use the ${platform.name} app ID from the same Firebase project.',
        );
      }
    }
    return problems;
  }

  static final _appIdPattern = RegExp(r'^\d+:\d+:(android|web|ios):[0-9a-f]+$');

  @override
  bool operator ==(Object other) =>
      other is FirebaseConnection &&
      other.apiKey == apiKey &&
      other.appId == appId &&
      other.projectId == projectId &&
      other.messagingSenderId == messagingSenderId &&
      other.authDomain == authDomain &&
      other.storageBucket == storageBucket;

  @override
  int get hashCode => Object.hash(
    apiKey,
    appId,
    projectId,
    messagingSenderId,
    authDomain,
    storageBucket,
  );
}

/// Reads Firebase settings from text pasted by the user: an Android
/// `google-services.json`, or a web `firebaseConfig` object (JSON or the
/// JavaScript snippet shown in the Firebase console).
FirebaseConnection parseFirebaseConfig(
  String text, {
  required String androidPackageName,
}) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) throw const FormatException('Nothing to read.');

  if (trimmed.contains('project_info')) {
    return _parseGoogleServices(trimmed, androidPackageName);
  }

  final values = <String, String>{
    for (final m in _keyValuePattern.allMatches(trimmed))
      m.group(1)!: m.group(2)!,
  };
  final connection = FirebaseConnection.fromJson(values);
  if (connection.apiKey.isEmpty && connection.projectId.isEmpty) {
    throw const FormatException(
      'Could not find Firebase settings. Paste google-services.json '
      'or the firebaseConfig object from the Firebase console.',
    );
  }
  return connection;
}

/// Matches `key: "value"`, `"key": "value"` and single-quoted variants.
final _keyValuePattern = RegExp(
  r'''["']?(apiKey|appId|projectId|messagingSenderId|authDomain|storageBucket)["']?\s*:\s*["']([^"']*)["']''',
);

FirebaseConnection _parseGoogleServices(String text, String packageName) {
  final Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    throw const FormatException('google-services.json is not valid JSON.');
  }
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('google-services.json is not valid JSON.');
  }

  final project = decoded['project_info'] as Map<String, Object?>? ?? {};
  final clients = (decoded['client'] as List<Object?>? ?? [])
      .whereType<Map<String, Object?>>();
  final client = clients.where((c) {
    final info = c['client_info'] as Map<String, Object?>?;
    final android = info?['android_client_info'] as Map<String, Object?>?;
    return android?['package_name'] == packageName;
  }).firstOrNull;

  if (client == null) {
    throw FormatException(
      'This google-services.json has no Android app with package '
      '$packageName. Register that package in the Firebase project.',
    );
  }

  final info = client['client_info'] as Map<String, Object?>;
  final keys = (client['api_key'] as List<Object?>? ?? [])
      .whereType<Map<String, Object?>>();

  return FirebaseConnection(
    apiKey: keys.firstOrNull?['current_key'] as String? ?? '',
    appId: info['mobilesdk_app_id'] as String? ?? '',
    projectId: project['project_id'] as String? ?? '',
    messagingSenderId: project['project_number'] as String? ?? '',
    storageBucket: _nonEmpty(project['storage_bucket'] as String?),
  );
}

String? _nonEmpty(String? value) =>
    value == null || value.trim().isEmpty ? null : value.trim();
