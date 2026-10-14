import 'package:capsula/app/auth_session.dart';
import 'package:capsula/app/dependencies.dart';
import 'package:capsula/config/app_config.dart';
import 'package:capsula/domain/auth/auth_repository.dart';
import 'package:capsula/features/auth/sign_in_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_auth_repository.dart';
import '../../fakes/fake_backend.dart';
import '../../fakes/fake_share_intake.dart';

Future<Widget> _wrap(FakeAuthRepository auth) async => AppDependencies(
  config: const AppConfig(
    environment: AppEnvironment.dev,
    useFirebaseEmulators: false,
    firebaseEmulatorHost: 'localhost',
  ),
  backend: await startedBackend(auth),
  authSession: AuthSession()..attach(auth),
  shareIntake: FakeShareIntake(),
  child: const MaterialApp(home: SignInScreen()),
);

Finder get _email => find.widgetWithText(TextFormField, 'Email');
Finder get _password => find.widgetWithText(TextFormField, 'Password');

void main() {
  testWidgets('requires email and password', (tester) async {
    await tester.pumpWidget(await _wrap(FakeAuthRepository()));

    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();

    expect(find.text('Email is required.'), findsOneWidget);
    expect(find.text('Password is required.'), findsOneWidget);
  });

  testWidgets('rejects a malformed email', (tester) async {
    await tester.pumpWidget(await _wrap(FakeAuthRepository()));

    await tester.enterText(_email, 'not-an-email');
    await tester.enterText(_password, 'secret1');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();

    expect(find.text('Enter a valid email address.'), findsOneWidget);
  });

  testWidgets('shows an error for wrong credentials', (tester) async {
    final auth = FakeAuthRepository()..accounts['a@example.com'] = 'secret1';
    await tester.pumpWidget(await _wrap(auth));

    await tester.enterText(_email, 'a@example.com');
    await tester.enterText(_password, 'wrong-password');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.text('Incorrect email or password.'), findsOneWidget);
    expect(auth.currentUser, isNull);
  });

  testWidgets('creates an account in register mode', (tester) async {
    final auth = FakeAuthRepository();
    await tester.pumpWidget(await _wrap(auth));

    await tester.tap(find.text("Don't have an account? Create one"));
    await tester.pump();
    await tester.enterText(_email, 'new@example.com');
    await tester.enterText(_password, 'secret1');
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pumpAndSettle();

    expect(auth.accounts, containsPair('new@example.com', 'secret1'));
    expect(auth.currentUser?.email, 'new@example.com');
  });

  testWidgets('register mode enforces minimum password length', (tester) async {
    await tester.pumpWidget(await _wrap(FakeAuthRepository()));

    await tester.tap(find.text("Don't have an account? Create one"));
    await tester.pump();
    await tester.enterText(_email, 'new@example.com');
    await tester.enterText(_password, '123');
    await tester.tap(find.widgetWithText(FilledButton, 'Create account'));
    await tester.pump();

    expect(
      find.text('Password must be at least 6 characters.'),
      findsOneWidget,
    );
  });

  testWidgets('shows network errors from the repository', (tester) async {
    final auth = FakeAuthRepository()
      ..accounts['a@example.com'] = 'secret1'
      ..nextError = const AuthException(AuthErrorCode.network);
    await tester.pumpWidget(await _wrap(auth));

    await tester.enterText(_email, 'a@example.com');
    await tester.enterText(_password, 'secret1');
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(
      find.text('No connection. Check your network and retry.'),
      findsOneWidget,
    );
  });

  testWidgets('sends a password reset for the entered email', (tester) async {
    final auth = FakeAuthRepository();
    await tester.pumpWidget(await _wrap(auth));

    await tester.enterText(_email, 'a@example.com');
    await tester.tap(find.text('Forgot password?'));
    await tester.pumpAndSettle();

    expect(auth.passwordResets, ['a@example.com']);
    expect(
      find.text('Password reset email sent to a@example.com.'),
      findsOneWidget,
    );
  });

  testWidgets('password reset asks for an email first', (tester) async {
    final auth = FakeAuthRepository();
    await tester.pumpWidget(await _wrap(auth));

    await tester.tap(find.text('Forgot password?'));
    await tester.pump();

    expect(auth.passwordResets, isEmpty);
    expect(
      find.text('Enter your email above to reset your password.'),
      findsOneWidget,
    );
  });
}
