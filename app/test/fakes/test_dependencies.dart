import 'package:capsula/app/api_settings.dart';
import 'package:capsula/app/auth_session.dart';
import 'package:capsula/app/backend_controller.dart';
import 'package:capsula/app/dependencies.dart';
import 'package:capsula/app/display_preferences.dart';
import 'package:capsula/config/app_config.dart';
import 'package:capsula_core/domain/maintenance/maintenance.dart';
import 'package:capsula_core/domain/reader/page_info_service.dart';
import 'package:capsula_core/domain/reader/reader_service.dart';
import 'package:flutter/widgets.dart';

import 'fake_content_fetcher.dart';
import 'fake_share_intake.dart';
import 'memory_api_settings_store.dart';

const testConfig = AppConfig(
  environment: AppEnvironment.dev,
  useFirebaseEmulators: false,
  firebaseEmulatorHost: 'localhost',
);

/// [AppDependencies] with test fakes, for screens tested outside the app.
AppDependencies testDependencies({
  required BackendController backend,
  required AuthSession session,
  required Widget child,
}) => AppDependencies(
  config: testConfig,
  backend: backend,
  authSession: session,
  shareIntake: FakeShareIntake(),
  reader: ReaderService(FakeContentFetcher()),
  pageInfo: PageInfoService(FakeContentFetcher()),
  apiSettings: ApiSettings(MemoryApiSettingsStore()),
  apiClient: () => null,
  display: DisplayPreferences(persist: false),
  linkChecker: FetcherLinkChecker(FakeContentFetcher()),
  child: child,
);
