import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../config/app_config.dart';
import '../domain/auth/auth_repository.dart';
import 'auth_session.dart';
import 'dependencies.dart';
import 'router.dart';
import 'theme.dart';

class CapsulaApp extends StatefulWidget {
  const CapsulaApp({
    super.key,
    required this.config,
    required this.authRepository,
  });

  final AppConfig config;
  final AuthRepository authRepository;

  @override
  State<CapsulaApp> createState() => _CapsulaAppState();
}

class _CapsulaAppState extends State<CapsulaApp> {
  late final AuthSession _session = AuthSession(widget.authRepository);
  late final GoRouter _router = createRouter(_session);

  @override
  void dispose() {
    _router.dispose();
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppDependencies(
      config: widget.config,
      authRepository: widget.authRepository,
      authSession: _session,
      child: MaterialApp.router(
        title: 'Capsula',
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        routerConfig: _router,
      ),
    );
  }
}
