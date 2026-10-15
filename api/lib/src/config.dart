import 'dart:io';

/// Server settings, read from environment variables.
class ApiConfig {
  const ApiConfig({
    required this.port,
    required this.projectId,
    this.serviceAccountFile,
    this.useEmulators = false,
    this.corsOrigins = const ['*'],
    this.requestsPerMinute = 120,
  });

  factory ApiConfig.fromEnvironment([Map<String, String>? env]) {
    final e = env ?? Platform.environment;
    final projectId = e['FIREBASE_PROJECT_ID'];
    if (projectId == null || projectId.isEmpty) {
      throw StateError('FIREBASE_PROJECT_ID is required');
    }
    return ApiConfig(
      port: int.tryParse(e['PORT'] ?? '') ?? 8787,
      projectId: projectId,
      serviceAccountFile: e['GOOGLE_APPLICATION_CREDENTIALS'],
      useEmulators: e['USE_FIREBASE_EMULATORS'] == 'true',
      corsOrigins: (e['CORS_ORIGINS'] ?? '*')
          .split(',')
          .map((o) => o.trim())
          .where((o) => o.isNotEmpty)
          .toList(),
      requestsPerMinute: int.tryParse(e['RATE_LIMIT_PER_MINUTE'] ?? '') ?? 120,
    );
  }

  final int port;
  final String projectId;

  /// Path to a Firebase service account key (JSON). Required unless using
  /// the emulators or Google application default credentials.
  final String? serviceAccountFile;
  final bool useEmulators;

  /// Origins allowed to call the API from a browser; `*` allows any.
  final List<String> corsOrigins;
  final int requestsPerMinute;
}
