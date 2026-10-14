/// Build-time configuration, supplied with `--dart-define-from-file=config/<env>.json`.
enum AppEnvironment { dev, prod }

class AppConfig {
  const AppConfig({
    required this.environment,
    required this.useFirebaseEmulators,
    required this.firebaseEmulatorHost,
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
    );
  }

  final AppEnvironment environment;

  /// When true, Firebase services connect to the local emulator suite
  /// instead of the real project.
  final bool useFirebaseEmulators;

  /// Host running the emulators. Use `10.0.2.2` from an Android emulator,
  /// or the computer's LAN IP from a physical device.
  final String firebaseEmulatorHost;

  bool get isProduction => environment == AppEnvironment.prod;
}
