import 'package:capsula/app/backend_controller.dart';
import 'package:capsula/domain/connection/firebase_connection.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_auth_repository.dart';
import '../fakes/fake_backend.dart';

void main() {
  late FakeConnectionStore store;
  late FakeBackendConnector connector;
  late BackendController backend;

  setUp(() {
    store = FakeConnectionStore();
    connector = FakeBackendConnector(FakeAuthRepository());
    backend = BackendController(store: store, connector: connector);
  });

  test('starts in loading state', () {
    expect(backend.status, BackendStatus.loading);
  });

  test('is not configured when nothing is saved', () async {
    await backend.start();

    expect(backend.status, BackendStatus.notConfigured);
    expect(connector.attempts, isEmpty);
  });

  test('connects with saved settings on start', () async {
    store.saved = testConnection;
    await backend.start();

    expect(backend.status, BackendStatus.connected);
    expect(backend.activeSettings, testConnection);
    expect(backend.services, isNotNull);
    expect(backend.restartRequired, isFalse);
  });

  test('saving settings persists them and connects', () async {
    await backend.start();
    await backend.save(testConnection);

    expect(store.saved, testConnection);
    expect(backend.status, BackendStatus.connected);
    expect(connector.attempts, [testConnection]);
  });

  test('reports a failed connection and allows retrying', () async {
    await backend.start();
    connector.nextError = Exception('bad options');
    await backend.save(testConnection);

    expect(backend.status, BackendStatus.failed);
    expect(backend.error, contains('bad options'));
    expect(store.saved, testConnection, reason: 'settings are kept to edit');

    await backend.save(testConnection);
    expect(backend.status, BackendStatus.connected);
    expect(backend.error, isNull);
  });

  test('changing settings while connected requires a restart', () async {
    store.saved = testConnection;
    await backend.start();

    const changed = FirebaseConnection(
      apiKey: 'other',
      appId: '1:222:android:def456',
      projectId: 'other-project',
      messagingSenderId: '222',
    );
    await backend.save(changed);

    expect(store.saved, changed);
    expect(backend.activeSettings, testConnection);
    expect(backend.restartRequired, isTrue);
    expect(connector.attempts, [testConnection]);
  });

  test('clearing while connected keeps the connection until restart', () async {
    store.saved = testConnection;
    await backend.start();
    await backend.clearSaved();

    expect(store.saved, isNull);
    expect(backend.status, BackendStatus.connected);
    expect(backend.restartRequired, isTrue);
  });

  test('clearing after a failure returns to not configured', () async {
    await backend.start();
    connector.nextError = Exception('bad options');
    await backend.save(testConnection);
    await backend.clearSaved();

    expect(backend.status, BackendStatus.notConfigured);
    expect(backend.error, isNull);
  });
}
