import 'package:flutter/widgets.dart';

import '../config/app_config.dart';
import '../domain/auth/auth_repository.dart';
import '../domain/bookmarks/bookmark_service.dart';
import '../domain/import/import_service.dart';
import '../domain/reader/page_info_service.dart';
import '../domain/reader/reader_service.dart';
import '../platform/file_saver.dart';
import '../platform/import_file_picker.dart';
import '../platform/share_intake.dart';
import 'auth_session.dart';
import 'backend_controller.dart';

/// Makes app-wide services available to widgets without a DI package.
class AppDependencies extends InheritedWidget {
  const AppDependencies({
    super.key,
    required this.config,
    required this.backend,
    required this.authSession,
    required this.shareIntake,
    required this.reader,
    required this.pageInfo,
    this.importFilePicker = const FileSelectorImportPicker(),
    this.fileSaver = const PlatformFileSaver(),
    required super.child,
  });

  final AppConfig config;
  final BackendController backend;
  final AuthSession authSession;
  final ShareIntake shareIntake;
  final ReaderService reader;
  final PageInfoService pageInfo;
  final ImportFilePicker importFilePicker;
  final FileSaver fileSaver;

  /// Only available once the backend is connected; the router keeps
  /// screens that need it unreachable until then.
  AuthRepository get authRepository => backend.services!.authRepository;

  BookmarkService get bookmarks => backend.services!.bookmarks;

  ImportService get importer => backend.services!.importer;

  static AppDependencies of(BuildContext context) {
    final deps = context.dependOnInheritedWidgetOfExactType<AppDependencies>();
    assert(deps != null, 'No AppDependencies found in context');
    return deps!;
  }

  @override
  bool updateShouldNotify(AppDependencies oldWidget) =>
      config != oldWidget.config ||
      backend != oldWidget.backend ||
      authSession != oldWidget.authSession ||
      shareIntake != oldWidget.shareIntake ||
      reader != oldWidget.reader ||
      pageInfo != oldWidget.pageInfo ||
      importFilePicker != oldWidget.importFilePicker ||
      fileSaver != oldWidget.fileSaver;
}
