import 'dart:async';

import 'package:capsula_core/domain/auth/app_user.dart';
import 'package:capsula_core/domain/auth/auth_repository.dart';

/// In-memory [AuthRepository] for tests.
class FakeAuthRepository implements AuthRepository {
  FakeAuthRepository({AppUser? initialUser}) : _user = initialUser;

  final _changes = StreamController<AppUser?>.broadcast();
  final Map<String, String> accounts = {};
  final List<String> passwordResets = [];
  AppUser? _user;

  /// When set, the next call throws this instead of succeeding.
  AuthException? nextError;

  @override
  AppUser? get currentUser => _user;

  @override
  Stream<AppUser?> authStateChanges() async* {
    yield _user;
    yield* _changes.stream;
  }

  @override
  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) async {
    _throwIfQueued();
    if (accounts[email] != password) {
      throw const AuthException(AuthErrorCode.invalidCredentials);
    }
    _setUser(AppUser(id: 'uid-$email', email: email));
  }

  @override
  Future<void> registerWithEmail({
    required String email,
    required String password,
  }) async {
    _throwIfQueued();
    if (accounts.containsKey(email)) {
      throw const AuthException(AuthErrorCode.emailAlreadyInUse);
    }
    accounts[email] = password;
    _setUser(AppUser(id: 'uid-$email', email: email));
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    _throwIfQueued();
    passwordResets.add(email);
  }

  @override
  Future<void> signOut() async {
    _throwIfQueued();
    _setUser(null);
  }

  void _setUser(AppUser? user) {
    _user = user;
    _changes.add(user);
  }

  void _throwIfQueued() {
    final error = nextError;
    nextError = null;
    if (error != null) throw error;
  }
}
