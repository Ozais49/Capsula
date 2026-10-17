import 'dart:io';

import 'package:capsula_api/capsula_api.dart';
import 'package:capsula_core/domain/maintenance/maintenance.dart';
import 'package:capsula_core/domain/reader/page_info_service.dart';
import 'package:capsula_core/domain/reader/reader_service.dart';
import 'package:capsula_core/net/http_content_fetcher.dart';
import 'package:dart_firebase_admin/auth.dart';
import 'package:dart_firebase_admin/dart_firebase_admin.dart';
import 'package:dart_firebase_admin/firestore.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as io;

Future<void> main() async {
  final config = ApiConfig.fromEnvironment();

  final credentialFile = config.serviceAccountFile;
  final app = FirebaseAdminApp.initializeApp(
    config.projectId,
    credentialFile != null && !config.useEmulators
        ? Credential.fromServiceAccount(File(credentialFile))
        : Credential.fromApplicationDefaultCredentials(),
  );
  if (config.useEmulators) app.useEmulator();

  final firestore = Firestore(app);
  final fetcher = HttpContentFetcher();
  final api = CapsulaApi(
    authenticator: Authenticator(
      FirebaseIdTokenVerifier(Auth(app)),
      FirestoreTokenStore(firestore),
    ),
    userData: (uid) => UserData(
      AdminBookmarkRepository(firestore, uid),
      AdminLabelRepository(firestore, uid),
      AdminHighlightRepository(firestore, uid),
      AdminContentIndex(firestore, uid),
      AdminSourceRepository(firestore, uid),
    ),
    tokens: FirestoreTokenStore(firestore),
    shares: FirestoreShareStore(firestore),
    pageInfo: PageInfoService(fetcher),
    reader: ReaderService(fetcher),
    linkChecker: FetcherLinkChecker(fetcher),
    rateLimiter: RateLimiter(config.requestsPerMinute),
    corsOrigins: config.corsOrigins,
    log: (error, stack) => stderr.writeln('Unhandled error: $error\n$stack'),
  );

  final handler = const Pipeline()
      .addMiddleware(logRequests(logger: _logWithoutQuery))
      .addHandler(api.handler);
  final server = await io.serve(handler, InternetAddress.anyIPv4, config.port);
  stdout.writeln(
    'Capsula API listening on port ${server.port} '
    '(project ${config.projectId}${config.useEmulators ? ', emulators' : ''})',
  );

  // Cloud Run and Docker send SIGTERM before stopping an instance (when
  // scaling in or deploying). Stop taking new connections and let requests
  // in flight finish, so clients don't see dropped writes.
  var stopping = false;
  Future<void> shutDown(ProcessSignal signal) async {
    if (stopping) return;
    stopping = true;
    stdout.writeln('Received $signal, finishing requests in flight');
    await server.close().timeout(
      const Duration(seconds: 8),
      onTimeout: () => server.close(force: true),
    );
    await app.close();
    exit(0);
  }

  ProcessSignal.sigint.watch().listen(shutDown);
  if (!Platform.isWindows) ProcessSignal.sigterm.watch().listen(shutDown);
}

/// Logs method, path and status only. Query strings can hold private URLs.
void _logWithoutQuery(String message, bool isError) {
  final redacted = message.replaceAll(RegExp(r'\?\S*'), '?…');
  (isError ? stderr : stdout).writeln(redacted);
}
