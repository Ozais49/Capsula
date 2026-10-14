import 'package:capsula/app/app.dart';
import 'package:capsula/config/app_config.dart';
import 'package:capsula/domain/auth/app_user.dart';
import 'package:capsula/features/auth/sign_in_screen.dart';
import 'package:capsula/features/home/home_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_auth_repository.dart';

const _config = AppConfig(
  environment: AppEnvironment.dev,
  useFirebaseEmulators: false,
  firebaseEmulatorHost: 'localhost',
);

void main() {
  testWidgets('signed-out user lands on sign-in', (tester) async {
    await tester.pumpWidget(
      CapsulaApp(config: _config, authRepository: FakeAuthRepository()),
    );
    await tester.pumpAndSettle();

    expect(find.byType(SignInScreen), findsOneWidget);
    expect(find.byType(HomeScreen), findsNothing);
  });

  testWidgets('signed-in user lands on home', (tester) async {
    final auth = FakeAuthRepository(
      initialUser: const AppUser(id: 'u1', email: 'a@example.com'),
    );
    await tester.pumpWidget(CapsulaApp(config: _config, authRepository: auth));
    await tester.pumpAndSettle();

    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.text('Signed in as a@example.com'), findsOneWidget);
  });

  testWidgets('sign in, then sign out', (tester) async {
    final auth = FakeAuthRepository()..accounts['a@example.com'] = 'secret1';
    await tester.pumpWidget(CapsulaApp(config: _config, authRepository: auth));
    await tester.pumpAndSettle();

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

    expect(find.byType(HomeScreen), findsOneWidget);

    await tester.tap(find.byTooltip('Sign out'));
    await tester.pumpAndSettle();

    expect(find.byType(SignInScreen), findsOneWidget);
  });
}
