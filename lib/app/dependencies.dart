import 'package:flutter/widgets.dart';

import '../config/app_config.dart';
import '../domain/auth/auth_repository.dart';
import 'auth_session.dart';

/// Makes app-wide services available to widgets without a DI package.
class AppDependencies extends InheritedWidget {
  const AppDependencies({
    super.key,
    required this.config,
    required this.authRepository,
    required this.authSession,
    required super.child,
  });

  final AppConfig config;
  final AuthRepository authRepository;
  final AuthSession authSession;

  static AppDependencies of(BuildContext context) {
    final deps = context.dependOnInheritedWidgetOfExactType<AppDependencies>();
    assert(deps != null, 'No AppDependencies found in context');
    return deps!;
  }

  @override
  bool updateShouldNotify(AppDependencies oldWidget) =>
      config != oldWidget.config ||
      authRepository != oldWidget.authRepository ||
      authSession != oldWidget.authSession;
}
