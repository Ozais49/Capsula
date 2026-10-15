import 'package:capsula_core/domain/reader/page_info_service.dart';
import 'package:capsula_core/domain/reader/reader_service.dart';
import 'package:capsula_core/net/http_content_fetcher.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../config/app_config.dart';
import '../data/api/api_client.dart';
import '../platform/file_saver.dart';
import '../platform/import_file_picker.dart';
import '../platform/share_intake.dart';
import 'api_settings.dart';
import 'auth_session.dart';
import 'backend_controller.dart';
import 'dependencies.dart';
import 'router.dart';
import 'theme.dart';

typedef ApiClientFactory = CapsulaApiClient Function(
  Uri baseUrl,
  Future<String?> Function() idToken,
);

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
    this.apiSettings,
    this.apiClientFactory,
  });

  final AppConfig config;
  final BackendController backend;
  final ShareIntake shareIntake;

  /// Defaults to reading pages over HTTP on the device.
  final ReaderSource? reader;

  /// Defaults to looking up titles over HTTP on the device.
  final PageInfoSource? pageInfo;
  final ImportFilePicker importFilePicker;
  final FileSaver fileSaver;

  /// Defaults to the address saved on the device.
  final ApiSettings? apiSettings;
  final ApiClientFactory? apiClientFactory;

  @override
  State<CapsulaApp> createState() => _CapsulaAppState();
}

class _CapsulaAppState extends State<CapsulaApp> {
  final _session = AuthSession();
  late final _fetcher = HttpContentFetcher(inBrowser: kIsWeb);
  late final ApiSettings _apiSettings =
      widget.apiSettings ??
      ApiSettings(
        SharedPrefsApiSettingsStore(),
        defaultUrl: widget.config.apiBaseUrl,
      );

  // When an API server is set, it reads pages and looks up titles (avoiding
  // browser cross-origin limits); otherwise, or if it can't be reached, the
  // device does.
  late final ReaderSource _reader = ApiOrLocalReader(
    _apiClient,
    widget.reader ?? ReaderService(_fetcher),
  );
  late final PageInfoSource _pageInfo = ApiOrLocalPageInfo(
    _apiClient,
    widget.pageInfo ?? PageInfoService(_fetcher),
  );
  late final GoRouter _router = createRouter(widget.backend, _session);
  bool _backfilled = false;
  (Uri, CapsulaApiClient)? _client;

  @override
  void initState() {
    super.initState();
    widget.backend.addListener(_attachSessionWhenConnected);
    _attachSessionWhenConnected();
    _session.addListener(_backfillOnceSignedIn);
    if (widget.apiSettings == null) _apiSettings.load();
  }

  CapsulaApiClient? _apiClient() {
    final url = _apiSettings.baseUrl;
    final auth = widget.backend.services?.authRepository;
    if (url == null || auth == null) return null;
    if (_client case (final cachedUrl, final client) when cachedUrl == url) {
      return client;
    }
    final client =
        widget.apiClientFactory?.call(url, auth.idToken) ??
        CapsulaApiClient(url, auth.idToken);
    _client = (url, client);
    return client;
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
    if (widget.apiSettings == null) _apiSettings.dispose();
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
      apiSettings: _apiSettings,
      apiClient: _apiClient,
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
