import '../domain/connection/firebase_connection.dart';

/// Build-time configuration, supplied with `--dart-define-from-file=config/<env>.json`.
enum AppEnvironment { dev, prod }

class AppConfig {
  const AppConfig({
    required this.environment,
    required this.useFirebaseEmulators,
    required this.firebaseEmulatorHost,
    this.defaultAndroidConnection,
  });

  factory AppConfig.fromEnvironment() {
    const env = String.fromEnvironment('APP_ENV', defaultValue: 'dev');
    return AppConfig(
      environment: env == 'prod' ? AppEnvironment.prod : AppEnvironment.dev,
      useFirebaseEmulators: const bool.fromEnvironment(
        'USE_FIREBASE_EMULATORS',
      ),
      firebaseEmulatorHost: const String.fromEnvironment(
        'FIREBASE_EMULATOR_HOST',
        defaultValue: 'localhost',
      ),
      defaultAndroidConnection: _androidConnection(),
    );
  }

  /// The project's Android Firebase settings from `FIREBASE_ANDROID_*`
  /// defines, or null when the build doesn't include them.
  static FirebaseConnection? _androidConnection() {
    const appId = String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
    if (appId.isEmpty) return null;
    return FirebaseConnection.fromJson({
      'apiKey': const String.fromEnvironment('FIREBASE_ANDROID_API_KEY'),
      'appId': appId,
      'projectId': const String.fromEnvironment('FIREBASE_PROJECT_ID'),
      'messagingSenderId': const String.fromEnvironment(
        'FIREBASE_MESSAGING_SENDER_ID',
      ),
      'storageBucket': const String.fromEnvironment('FIREBASE_STORAGE_BUCKET'),
    });
  }

  /// Must match `applicationId` in android/app/build.gradle.kts.
  static const androidPackageName = 'com.ygtech.capsula';

  final AppEnvironment environment;

  /// When true, Firebase services connect to the local emulator suite
  /// instead of the real project.
  final bool useFirebaseEmulators;

  /// Host running the emulators. Use `10.0.2.2` from an Android emulator,
  /// or the computer's LAN IP from a physical device.
  final String firebaseEmulatorHost;

  /// Firebase settings built into Android builds, used when none are saved
  /// on the device. The connection screen can still override them.
  final FirebaseConnection? defaultAndroidConnection;

  bool get isProduction => environment == AppEnvironment.prod;
}
