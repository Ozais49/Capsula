import 'package:flutter/widgets.dart';

import '../config/app_config.dart';
import '../domain/auth/auth_repository.dart';
import 'auth_session.dart';
import 'backend_controller.dart';

/// Makes app-wide services available to widgets without a DI package.
class AppDependencies extends InheritedWidget {
  const AppDependencies({
    super.key,
    required this.config,
    required this.backend,
    required this.authSession,
    required super.child,
  });

  final AppConfig config;
  final BackendController backend;
  final AuthSession authSession;

  /// Only available once the backend is connected; the router keeps
  /// screens that need it unreachable until then.
  AuthRepository get authRepository => backend.services!.authRepository;

  static AppDependencies of(BuildContext context) {
    final deps = context.dependOnInheritedWidgetOfExactType<AppDependencies>();
    assert(deps != null, 'No AppDependencies found in context');
    return deps!;
  }

  @override
  bool updateShouldNotify(AppDependencies oldWidget) =>
      config != oldWidget.config ||
      backend != oldWidget.backend ||
      authSession != oldWidget.authSession;
}
