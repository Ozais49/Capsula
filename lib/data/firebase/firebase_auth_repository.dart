import 'package:firebase_auth/firebase_auth.dart';

import '../../domain/auth/app_user.dart';
import '../../domain/auth/auth_repository.dart';

class FirebaseAuthRepository implements AuthRepository {
  FirebaseAuthRepository(this._auth);

  final FirebaseAuth _auth;

  @override
  Stream<AppUser?> authStateChanges() =>
      _auth.authStateChanges().map(_toAppUser);

  @override
  AppUser? get currentUser => _toAppUser(_auth.currentUser);

  @override
  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) => _guard(
    () => _auth.signInWithEmailAndPassword(email: email, password: password),
  );

  @override
  Future<void> registerWithEmail({
    required String email,
    required String password,
  }) => _guard(
    () =>
        _auth.createUserWithEmailAndPassword(email: email, password: password),
  );

  @override
  Future<void> sendPasswordReset(String email) =>
      _guard(() => _auth.sendPasswordResetEmail(email: email));

  @override
  Future<void> signOut() => _guard(_auth.signOut);

  static AppUser? _toAppUser(User? user) => user == null
      ? null
      : AppUser(id: user.uid, email: user.email, displayName: user.displayName);

  static Future<void> _guard(Future<Object?> Function() action) async {
    try {
      await action();
    } on FirebaseAuthException catch (e) {
      throw AuthException(mapFirebaseAuthCode(e.code));
    }
  }
}

AuthErrorCode mapFirebaseAuthCode(String code) => switch (code) {
  'invalid-credential' ||
  'wrong-password' ||
  'user-not-found' ||
  'invalid-login-credentials' => AuthErrorCode.invalidCredentials,
  'email-already-in-use' => AuthErrorCode.emailAlreadyInUse,
  'weak-password' => AuthErrorCode.weakPassword,
  'invalid-email' => AuthErrorCode.invalidEmail,
  'user-disabled' => AuthErrorCode.userDisabled,
  'too-many-requests' => AuthErrorCode.tooManyRequests,
  'network-request-failed' => AuthErrorCode.network,
  _ => AuthErrorCode.unknown,
};
