import 'package:capsula/app/app.dart';
import 'package:capsula/config/app_config.dart';
import 'package:capsula_core/domain/auth/app_user.dart';
import 'package:capsula/features/bookmarks/library_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_auth_repository.dart';
import '../../fakes/fake_backend.dart';
import '../../fakes/fake_share_intake.dart';

Future<void> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    CapsulaApp(
      config: const AppConfig(
        environment: AppEnvironment.dev,
        useFirebaseEmulators: false,
        firebaseEmulatorHost: 'localhost',
      ),
      backend: await startedBackend(
        FakeAuthRepository(initialUser: const AppUser(id: 'u1')),
      ),
      shareIntake: FakeShareIntake(),
    ),
  );
  await tester.pumpAndSettle();
}

EditableText _searchField(WidgetTester tester) => tester.widget<EditableText>(
  find.descendant(
    of: find.byKey(LibraryScreen.searchFieldKey),
    matching: find.byType(EditableText),
  ),
);

void main() {
  testWidgets('"/" focuses search', (tester) async {
    await _pump(tester);
    expect(_searchField(tester).focusNode.hasFocus, isFalse);

    await tester.sendKeyEvent(LogicalKeyboardKey.slash);
    await tester.pump();

    expect(_searchField(tester).focusNode.hasFocus, isTrue);
  });

  testWidgets('"n" opens the add sheet', (tester) async {
    await _pump(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.pumpAndSettle();

    expect(find.text('Add bookmark'), findsOneWidget);
  });

  testWidgets('typing "n" in search types instead of opening the sheet', (
    tester,
  ) async {
    await _pump(tester);
    await tester.tap(find.byKey(LibraryScreen.searchFieldKey));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyN);
    await tester.pumpAndSettle();

    expect(find.text('Add bookmark'), findsNothing);
  });
}
