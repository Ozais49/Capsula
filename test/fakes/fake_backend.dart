import 'package:capsula/app/backend_controller.dart';
import 'package:capsula_core/domain/connection/backend.dart';
import 'package:capsula_core/domain/connection/firebase_connection.dart';

import 'fake_auth_repository.dart';

import 'package:capsula_core/testing/in_memory_bookmark_repository.dart';
import 'package:capsula_core/testing/in_memory_label_repository.dart';

const testConnection = FirebaseConnection(
  apiKey: 'test-api-key',
  appId: '1:111:android:abc123',
  projectId: 'capsula-test',
  messagingSenderId: '111',
);

class FakeConnectionStore implements ConnectionSettingsStore {
  FakeConnectionStore([this.saved]);

  FirebaseConnection? saved;

  @override
  Future<FirebaseConnection?> load() async => saved;

  @override
  Future<void> save(FirebaseConnection connection) async => saved = connection;

  @override
  Future<void> clear() async => saved = null;
}

class FakeBackendConnector implements BackendConnector {
  FakeBackendConnector(this.auth, {InMemoryBookmarkRepository? bookmarks})
    : bookmarks = bookmarks ?? InMemoryBookmarkRepository() {
    labels = InMemoryLabelRepository(this.bookmarks);
  }

  final FakeAuthRepository auth;
  final InMemoryBookmarkRepository bookmarks;
  late final InMemoryLabelRepository labels;
  final List<FirebaseConnection> attempts = [];

  /// When set, the next connect attempt throws this.
  Object? nextError;

  @override
  Future<BackendServices> connect(FirebaseConnection connection) async {
    attempts.add(connection);
    final error = nextError;
    nextError = null;
    if (error != null) throw error;
    return BackendServices(
      authRepository: auth,
      bookmarkRepository: bookmarks,
      labelRepository: labels,
    );
  }
}

/// A started controller, connected when [connected] is true.
Future<BackendController> startedBackend(
  FakeAuthRepository auth, {
  bool connected = true,
  InMemoryBookmarkRepository? bookmarks,
}) async {
  final backend = BackendController(
    store: FakeConnectionStore(connected ? testConnection : null),
    connector: FakeBackendConnector(auth, bookmarks: bookmarks),
  );
  await backend.start();
  return backend;
}

/// A controller started and connected through [connector].
Future<BackendController> startedBackendWith(
  FakeBackendConnector connector,
) async {
  final backend = BackendController(
    store: FakeConnectionStore(testConnection),
    connector: connector,
  );
  await backend.start();
  return backend;
}
