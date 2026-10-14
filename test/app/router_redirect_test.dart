import 'package:capsula/app/auth_session.dart';
import 'package:capsula/app/router.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  String? redirect(AuthStatus status, String location) =>
      authRedirect(status, Uri.parse(location));

  group('while auth state is unknown', () {
    test('shows loading and remembers the destination', () {
      expect(redirect(AuthStatus.unknown, '/'), '/loading');
      expect(
        redirect(AuthStatus.unknown, '/settings'),
        '/loading?from=%2Fsettings',
      );
    });

    test('stays on loading', () {
      expect(redirect(AuthStatus.unknown, '/loading'), isNull);
    });
  });

  group('when signed out', () {
    test('sends protected routes to sign-in', () {
      expect(redirect(AuthStatus.signedOut, '/'), '/sign-in');
      expect(
        redirect(AuthStatus.signedOut, '/settings'),
        '/sign-in?from=%2Fsettings',
      );
    });

    test('carries the destination from loading to sign-in', () {
      expect(
        redirect(AuthStatus.signedOut, '/loading?from=%2Fsettings'),
        '/sign-in?from=%2Fsettings',
      );
    });

    test('stays on sign-in', () {
      expect(redirect(AuthStatus.signedOut, '/sign-in'), isNull);
    });
  });

  group('when signed in', () {
    test('leaves sign-in and loading for home', () {
      expect(redirect(AuthStatus.signedIn, '/sign-in'), '/');
      expect(redirect(AuthStatus.signedIn, '/loading'), '/');
    });

    test('returns to the original destination', () {
      expect(
        redirect(AuthStatus.signedIn, '/sign-in?from=%2Fsettings'),
        '/settings',
      );
    });

    test('ignores off-site destinations', () {
      expect(
        redirect(
          AuthStatus.signedIn,
          '/sign-in?from=https%3A%2F%2Fevil.example',
        ),
        '/',
      );
      expect(
        redirect(AuthStatus.signedIn, '/sign-in?from=%2F%2Fevil.example'),
        '/',
      );
    });

    test('does not redirect normal routes', () {
      expect(redirect(AuthStatus.signedIn, '/'), isNull);
    });
  });
}
