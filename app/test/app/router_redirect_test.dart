import 'package:capsula/app/auth_session.dart';
import 'package:capsula/app/backend_controller.dart';
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

  group('backend connection gate', () {
    String? app(BackendStatus backend, String location) =>
        appRedirect(backend, AuthStatus.signedIn, Uri.parse(location));

    test('waits on loading while the backend starts or connects', () {
      expect(app(BackendStatus.loading, '/'), '/loading');
      expect(app(BackendStatus.connecting, '/loading'), isNull);
      expect(
        app(BackendStatus.loading, '/settings'),
        '/loading?from=%2Fsettings',
      );
    });

    test('sends everything to the connection screen until configured', () {
      expect(app(BackendStatus.notConfigured, '/'), '/connection');
      expect(app(BackendStatus.notConfigured, '/sign-in'), '/connection');
      expect(app(BackendStatus.failed, '/loading'), '/connection');
    });

    test('the connection screen is always reachable', () {
      for (final status in BackendStatus.values) {
        expect(app(status, '/connection'), isNull, reason: '$status');
      }
    });

    test('applies auth rules once connected', () {
      expect(
        appRedirect(
          BackendStatus.connected,
          AuthStatus.signedOut,
          Uri.parse('/'),
        ),
        '/sign-in',
      );
      expect(app(BackendStatus.connected, '/'), isNull);
    });
  });
}
