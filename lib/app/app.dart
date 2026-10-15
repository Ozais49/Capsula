import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../config/app_config.dart';
import '../data/http/http_content_fetcher.dart';

import 'package:capsula_core/domain/reader/page_info_service.dart';
import 'package:capsula_core/domain/reader/reader_service.dart';

import '../platform/file_saver.dart';
import '../platform/import_file_picker.dart';
import '../platform/share_intake.dart';
import 'auth_session.dart';
import 'backend_controller.dart';
import 'dependencies.dart';
import 'router.dart';
import 'theme.dart';

class CapsulaApp extends StatefulWidget {
  const CapsulaApp({
    super.key,
    required this.config,
    required this.backend,
    this.shareIntake = const MethodChannelShareIntake(),
    this.reader,
    this.pageInfo,
    this.importFilePicker = const FileSelectorImportPicker(),
    this.fileSaver = const PlatformFileSaver(),
  });

  final AppConfig config;
  final BackendController backend;
  final ShareIntake shareIntake;

  /// Defaults to reading pages over HTTP.
  final ReaderService? reader;

  /// Defaults to looking up titles over HTTP.
  final PageInfoService? pageInfo;
  final ImportFilePicker importFilePicker;
  final FileSaver fileSaver;

  @override
  State<CapsulaApp> createState() => _CapsulaAppState();
}

class _CapsulaAppState extends State<CapsulaApp> {
  final _session = AuthSession();
  late final _fetcher = HttpContentFetcher();
  late final ReaderService _reader = widget.reader ?? ReaderService(_fetcher);
  late final PageInfoService _pageInfo =
      widget.pageInfo ?? PageInfoService(_fetcher);
  bool _backfilled = false;
  late final GoRouter _router = createRouter(widget.backend, _session);

  @override
  void initState() {
    super.initState();
    widget.backend.addListener(_attachSessionWhenConnected);
    _attachSessionWhenConnected();
    _session.addListener(_backfillOnceSignedIn);
  }

  /// Once per run, fetch real titles for links saved without them (for
  /// example shared while offline).
  void _backfillOnceSignedIn() {
    final services = widget.backend.services;
    if (_backfilled ||
        services == null ||
        _session.status != AuthStatus.signedIn) {
      return;
    }
    _backfilled = true;
    services.bookmarks.backfillDetails(_pageInfo).ignore();
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
    _session.removeListener(_backfillOnceSignedIn);
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
      shareIntake: widget.shareIntake,
      reader: _reader,
      pageInfo: _pageInfo,
      importFilePicker: widget.importFilePicker,
      fileSaver: widget.fileSaver,
      child: MaterialApp.router(
        title: 'Capsula',
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        routerConfig: _router,
      ),
    );
  }
}
