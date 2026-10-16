import 'package:capsula/app/app.dart';
import 'package:capsula/app/backend_controller.dart';
import 'package:capsula/features/auth/sign_in_screen.dart';
import 'package:capsula/features/bookmarks/library_screen.dart';
import 'package:capsula_core/domain/auth/app_user.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_service.dart';
import 'package:capsula_core/domain/local/local_library.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_auth_repository.dart';
import '../../fakes/fake_backend.dart';
import '../../fakes/fake_share_intake.dart';
import '../../fakes/memory_local_storage.dart';
import '../../fakes/navigation.dart';
import '../../fakes/test_dependencies.dart';

class _Setup {
  _Setup({AppUser? user})
    : connector = FakeBackendConnector(FakeAuthRepository(initialUser: user));

  final store = FakeConnectionStore(testConnection);
  final storage = MemoryLocalStorage();
  final FakeBackendConnector connector;

  BackendController controller() => BackendController(
    store: store,
    connector: connector,
    deviceLibrary: () async => (await LocalLibrary.open(storage)).services(),
  );

  Future<BackendController> pump(WidgetTester tester) async {
    final backend = controller();
    await backend.start();
    await tester.pumpWidget(
      CapsulaApp(
        config: testConfig,
        backend: backend,
        shareIntake: FakeShareIntake(),
      ),
    );
    await tester.pumpAndSettle();
    return backend;
  }
}

Future<void> _switch(WidgetTester tester, String item) async {
  await openSettingsItem(tester, item);
  await tester.tap(find.widgetWithText(FilledButton, 'Switch'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => LibraryScreen.lastOfferedLink = null);

  testWidgets('use without an account, and it stays that way', (tester) async {
    final setup = _Setup();
    await setup.pump(tester);
    expect(find.byType(SignInScreen), findsOneWidget);

    await tester.tap(find.text('Use without an account'));
    await tester.pumpAndSettle();
    expect(find.byType(LibraryScreen), findsOneWidget);
    expect(setup.store.deviceOnly, isTrue);

    await openNavigation(tester);
    expect(find.text('On this device'), findsOneWidget);
    expect(find.byTooltip('Log out'), findsNothing);

    // Next start opens the device library without connecting anywhere.
    setup.connector.attempts.clear();
    final restarted = setup.controller();
    await restarted.start();
    expect(restarted.deviceOnly, isTrue);
    expect(restarted.status, BackendStatus.connected);
    expect(setup.connector.attempts, isEmpty);
  });

  testWidgets('switch from the device library to an account', (tester) async {
    final setup = _Setup()..store.deviceOnly = true;
    final backend = await setup.pump(tester);
    expect(backend.deviceOnly, isTrue);
    expect(find.byType(LibraryScreen), findsOneWidget);

    await _switch(tester, 'Use an account instead');
    expect(backend.deviceOnly, isFalse);
    expect(setup.store.deviceOnly, isFalse);
    expect(find.byType(SignInScreen), findsOneWidget);
  });

  testWidgets('switch from an account to the device library', (tester) async {
    final setup = _Setup(
      user: const AppUser(id: 'u1', email: 'a@b.co'),
    );
    final backend = await setup.pump(tester);
    expect(find.byType(LibraryScreen), findsOneWidget);

    await _switch(tester, 'Use on this device only');
    expect(backend.deviceOnly, isTrue);
    expect(find.byType(LibraryScreen), findsOneWidget);
    await openNavigation(tester);
    expect(find.text('On this device'), findsOneWidget);

    // Saving goes to the device.
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();
    expect(find.text('API & integrations'), findsNothing);
    final services = backend.services!;
    final saved =
        await services.bookmarks.save('https://example.com/kept') as Saved;
    await saved.committed;
    expect(setup.storage.values[LocalLibrary.libraryKey], contains('kept'));
  });
}
