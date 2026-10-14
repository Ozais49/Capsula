import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../config/app_config.dart';
import 'auth_session.dart';
import 'backend_controller.dart';
import 'dependencies.dart';
import 'router.dart';
import 'theme.dart';

class CapsulaApp extends StatefulWidget {
  const CapsulaApp({super.key, required this.config, required this.backend});

  final AppConfig config;
  final BackendController backend;

  @override
  State<CapsulaApp> createState() => _CapsulaAppState();
}

class _CapsulaAppState extends State<CapsulaApp> {
  final _session = AuthSession();
  late final GoRouter _router = createRouter(widget.backend, _session);

  @override
  void initState() {
    super.initState();
    widget.backend.addListener(_attachSessionWhenConnected);
    _attachSessionWhenConnected();
  }

  void _attachSessionWhenConnected() {
    final services = widget.backend.services;
    if (services != null && !_session.isAttached) {
      _session.attach(services.authRepository);
    }
  }

  @override
  void dispose() {
    widget.backend.removeListener(_attachSessionWhenConnected);
    _router.dispose();
    _session.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AppDependencies(
      config: widget.config,
      backend: widget.backend,
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
