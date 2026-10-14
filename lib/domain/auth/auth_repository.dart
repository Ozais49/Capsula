import 'app_user.dart';

/// Authentication boundary. UI and application code depend on this,
/// never on a specific provider such as Firebase.
abstract interface class AuthRepository {
  /// Emits the current user immediately, then on every sign-in or sign-out.
  Stream<AppUser?> authStateChanges();

  AppUser? get currentUser;

  Future<void> signInWithEmail({
    required String email,
    required String password,
  });

  Future<void> registerWithEmail({
    required String email,
    required String password,
  });

  Future<void> sendPasswordReset(String email);

  Future<void> signOut();
}

enum AuthErrorCode {
  invalidCredentials,
  emailAlreadyInUse,
  weakPassword,
  invalidEmail,
  userDisabled,
  tooManyRequests,
  network,
  unknown,
}

class AuthException implements Exception {
  const AuthException(this.code);

  final AuthErrorCode code;

  String get message => switch (code) {
    AuthErrorCode.invalidCredentials => 'Incorrect email or password.',
    AuthErrorCode.emailAlreadyInUse =>
      'An account already exists for this email.',
    AuthErrorCode.weakPassword => 'Password must be at least 6 characters.',
    AuthErrorCode.invalidEmail => 'Enter a valid email address.',
    AuthErrorCode.userDisabled => 'This account has been disabled.',
    AuthErrorCode.tooManyRequests =>
      'Too many attempts. Please wait and try again.',
    AuthErrorCode.network => 'No connection. Check your network and retry.',
    AuthErrorCode.unknown => 'Something went wrong. Please try again.',
  };

  @override
  String toString() => 'AuthException($code)';
}
