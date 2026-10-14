import 'package:capsula/app/auth_session.dart';
import 'package:capsula/app/backend_controller.dart';
import 'package:capsula/app/dependencies.dart';
import 'package:capsula/config/app_config.dart';
import 'package:capsula/domain/connection/firebase_connection.dart';
import 'package:capsula/features/connection/connection_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_auth_repository.dart';
import '../../fakes/fake_backend.dart';

Future<void> _pump(
  WidgetTester tester,
  BackendController backend, {
  ConnectionPlatform platform = ConnectionPlatform.android,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    AppDependencies(
      config: const AppConfig(
        environment: AppEnvironment.dev,
        useFirebaseEmulators: false,
        firebaseEmulatorHost: 'localhost',
      ),
      backend: backend,
      authSession: AuthSession(),
      child: MaterialApp(home: ConnectionScreen(platform: platform)),
    ),
  );
}

Finder _field(String label) => find.widgetWithText(TextField, label);

String _text(WidgetTester tester, String label) =>
    tester.widget<TextField>(_field(label)).controller!.text;

void main() {
  testWidgets('fills fields from pasted google-services.json', (tester) async {
    final backend = await startedBackend(
      FakeAuthRepository(),
      connected: false,
    );
    await _pump(tester, backend);

    await tester.enterText(find.byType(TextField).first, '''
{
  "project_info": {
    "project_number": "243779316527",
    "project_id": "capsula-ygtech"
  },
  "client": [{
    "client_info": {
      "mobilesdk_app_id": "1:243779316527:android:9de6e6a7",
      "android_client_info": { "package_name": "com.ygtech.capsula" }
    },
    "api_key": [{ "current_key": "AIza-key" }]
  }]
}''');
    await tester.tap(find.text('Fill in fields'));
    await tester.pump();

    expect(_text(tester, 'API key'), 'AIza-key');
    expect(_text(tester, 'App ID'), '1:243779316527:android:9de6e6a7');
    expect(_text(tester, 'Project ID'), 'capsula-ygtech');
    expect(_text(tester, 'Messaging sender ID'), '243779316527');
  });

  testWidgets('shows an error for unreadable pasted text', (tester) async {
    final backend = await startedBackend(
      FakeAuthRepository(),
      connected: false,
    );
    await _pump(tester, backend);

    await tester.enterText(find.byType(TextField).first, 'nonsense');
    await tester.tap(find.text('Fill in fields'));
    await tester.pump();

    expect(
      find.textContaining('Could not find Firebase settings'),
      findsOneWidget,
    );
  });

  testWidgets('does not save invalid settings', (tester) async {
    final store = FakeConnectionStore();
    final backend = BackendController(
      store: store,
      connector: FakeBackendConnector(FakeAuthRepository()),
    );
    await backend.start();
    await _pump(tester, backend, platform: ConnectionPlatform.web);

    await tester.enterText(_field('API key'), 'key');
    await tester.enterText(_field('App ID'), '1:111:android:abc');
    await tester.enterText(_field('Project ID'), 'p');
    await tester.enterText(_field('Messaging sender ID'), '111');
    await tester.tap(find.text('Save and connect'));
    await tester.pump();

    expect(find.textContaining('This App ID is for android'), findsOneWidget);
    expect(store.saved, isNull);
  });

  testWidgets('shows the connection error after a failed attempt', (
    tester,
  ) async {
    final connector = FakeBackendConnector(FakeAuthRepository())
      ..nextError = Exception('boom');
    final backend = BackendController(
      store: FakeConnectionStore(),
      connector: connector,
    );
    await backend.start();
    await _pump(tester, backend);

    await tester.enterText(_field('API key'), testConnection.apiKey);
    await tester.enterText(_field('App ID'), testConnection.appId);
    await tester.enterText(_field('Project ID'), testConnection.projectId);
    await tester.enterText(
      _field('Messaging sender ID'),
      testConnection.messagingSenderId,
    );
    await tester.tap(find.text('Save and connect'));
    await tester.pumpAndSettle();

    expect(find.textContaining('boom'), findsOneWidget);
    expect(backend.status, BackendStatus.failed);
  });

  testWidgets('prefills saved settings and asks for restart on change', (
    tester,
  ) async {
    final backend = await startedBackend(FakeAuthRepository());
    await _pump(tester, backend);

    expect(_text(tester, 'Project ID'), testConnection.projectId);
    expect(find.text('Connected to capsula-test.'), findsOneWidget);

    await tester.enterText(_field('Project ID'), 'another-project');
    await tester.tap(find.text('Save and connect'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Restart the app'), findsOneWidget);
  });

  testWidgets('removing the saved connection', (tester) async {
    final backend = await startedBackend(FakeAuthRepository());
    await _pump(tester, backend);

    await tester.tap(find.text('Remove saved connection'));
    await tester.pumpAndSettle();

    expect(backend.savedSettings, isNull);
    expect(find.text('Remove saved connection'), findsNothing);
    expect(
      find.textContaining('Restart the app to disconnect'),
      findsOneWidget,
    );
  });
}
