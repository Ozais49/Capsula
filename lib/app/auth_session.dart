import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:capsula_core/domain/auth/app_user.dart';
import 'package:capsula_core/domain/auth/auth_repository.dart';

enum AuthStatus { unknown, signedIn, signedOut }

/// Tracks the signed-in user so the router can react to auth changes.
/// Stays [AuthStatus.unknown] until a repository is attached.
class AuthSession extends ChangeNotifier {
  StreamSubscription<AppUser?>? _subscription;
  AuthStatus _status = AuthStatus.unknown;
  AppUser? _user;

  AuthRepository? _repository;

  AuthStatus get status => _status;
  AppUser? get user => _user;
  bool get isAttached => _subscription != null;

  /// The repository being followed.
  AuthRepository? get repository => _repository;

  /// Follows [repository], replacing any earlier one (switching between an
  /// account and the on-device library).
  void attach(AuthRepository repository) {
    _subscription?.cancel();
    _repository = repository;
    _subscription = repository.authStateChanges().listen(_onUserChanged);
  }

  void _onUserChanged(AppUser? user) {
    _user = user;
    _status = user == null ? AuthStatus.signedOut : AuthStatus.signedIn;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }
}
