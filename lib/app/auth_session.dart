import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/auth/app_user.dart';
import '../domain/auth/auth_repository.dart';

enum AuthStatus { unknown, signedIn, signedOut }

/// Tracks the signed-in user so the router can react to auth changes.
class AuthSession extends ChangeNotifier {
  AuthSession(AuthRepository repository) {
    _subscription = repository.authStateChanges().listen(_onUserChanged);
  }

  late final StreamSubscription<AppUser?> _subscription;
  AuthStatus _status = AuthStatus.unknown;
  AppUser? _user;

  AuthStatus get status => _status;
  AppUser? get user => _user;

  void _onUserChanged(AppUser? user) {
    _user = user;
    _status = user == null ? AuthStatus.signedOut : AuthStatus.signedIn;
    notifyListeners();
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
