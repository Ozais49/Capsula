import 'package:capsula/app/app.dart';
import 'package:capsula/app/backend_controller.dart';
import 'package:capsula/config/app_config.dart';
import 'package:capsula/domain/auth/app_user.dart';
import 'package:capsula/features/auth/sign_in_screen.dart';
import 'package:capsula/features/connection/connection_screen.dart';
import 'package:capsula/features/bookmarks/library_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_auth_repository.dart';
import '../fakes/fake_backend.dart';

const _config = AppConfig(
  environment: AppEnvironment.dev,
  useFirebaseEmulators: false,
  firebaseEmulatorHost: 'localhost',
);

Future<void> _pumpApp(WidgetTester tester, BackendController backend) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(CapsulaApp(config: _config, backend: backend));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('first run without settings opens the connection screen', (
    tester,
  ) async {
    final backend = await startedBackend(
      FakeAuthRepository(),
      connected: false,
    );
    await _pumpApp(tester, backend);

    expect(find.byType(ConnectionScreen), findsOneWidget);
    expect(find.textContaining('Not connected'), findsOneWidget);
  });

  testWidgets('connecting from the connection screen leads to sign-in', (
    tester,
  ) async {
    final backend = await startedBackend(
      FakeAuthRepository(),
      connected: false,
    );
    await _pumpApp(tester, backend);

    Future<void> enter(String label, String value) =>
        tester.enterText(find.widgetWithText(TextField, label), value);
    await enter('API key', testConnection.apiKey);
    await enter('App ID', testConnection.appId);
    await enter('Project ID', testConnection.projectId);
    await enter('Messaging sender ID', testConnection.messagingSenderId);
    await tester.tap(find.widgetWithText(FilledButton, 'Save and connect'));
    await tester.pumpAndSettle();

    expect(backend.status, BackendStatus.connected);
    expect(find.byType(SignInScreen), findsOneWidget);
  });

  testWidgets('signed-out user lands on sign-in', (tester) async {
    await _pumpApp(tester, await startedBackend(FakeAuthRepository()));

    expect(find.byType(SignInScreen), findsOneWidget);
    expect(find.byType(LibraryScreen), findsNothing);
  });

  testWidgets('signed-in user lands on the library', (tester) async {
    final auth = FakeAuthRepository(
      initialUser: const AppUser(id: 'u1', email: 'a@example.com'),
    );
    await _pumpApp(tester, await startedBackend(auth));

    expect(find.byType(LibraryScreen), findsOneWidget);
  });

  testWidgets('sign in, then sign out', (tester) async {
    final auth = FakeAuthRepository()..accounts['a@example.com'] = 'secret1';
    await _pumpApp(tester, await startedBackend(auth));

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'a@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'secret1',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.byType(LibraryScreen), findsOneWidget);

    await tester.tap(find.byTooltip('Menu'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign out'));
    await tester.pumpAndSettle();

    expect(find.byType(SignInScreen), findsOneWidget);
  });

  testWidgets('connection settings are reachable from sign-in and go back', (
    tester,
  ) async {
    await _pumpApp(tester, await startedBackend(FakeAuthRepository()));

    await tester.tap(find.text('Connection settings'));
    await tester.pumpAndSettle();

    expect(find.byType(ConnectionScreen), findsOneWidget);
    expect(find.text('Connected to capsula-test.'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    expect(find.byType(SignInScreen), findsOneWidget);
  });
}
