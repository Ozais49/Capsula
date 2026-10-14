import 'package:go_router/go_router.dart';

import '../features/auth/sign_in_screen.dart';
import '../features/home/home_screen.dart';
import '../features/loading/loading_screen.dart';
import 'auth_session.dart';

abstract final class AppRoutes {
  static const home = '/';
  static const signIn = '/sign-in';
  static const loading = '/loading';
}

GoRouter createRouter(AuthSession session) => GoRouter(
  initialLocation: AppRoutes.home,
  refreshListenable: session,
  redirect: (context, state) => authRedirect(session.status, state.uri),
  routes: [
    GoRoute(
      path: AppRoutes.home,
      builder: (context, state) => const HomeScreen(),
    ),
    GoRoute(
      path: AppRoutes.signIn,
      builder: (context, state) => const SignInScreen(),
    ),
    GoRoute(
      path: AppRoutes.loading,
      builder: (context, state) => const LoadingScreen(),
    ),
  ],
);

/// Keeps signed-out users on the sign-in screen and returns them to the
/// page they originally requested (`?from=`) after signing in.
String? authRedirect(AuthStatus status, Uri uri) {
  final path = uri.path;
  final onGate = path == AppRoutes.signIn || path == AppRoutes.loading;
  final destination = onGate
      ? _safeDestination(uri.queryParameters['from'])
      : uri.toString();

  switch (status) {
    case AuthStatus.unknown:
      return path == AppRoutes.loading
          ? null
          : _withFrom(AppRoutes.loading, destination);
    case AuthStatus.signedOut:
      return path == AppRoutes.signIn
          ? null
          : _withFrom(AppRoutes.signIn, destination);
    case AuthStatus.signedIn:
      return onGate ? destination ?? AppRoutes.home : null;
  }
}

String _withFrom(String path, String? from) =>
    from == null || from == AppRoutes.home
    ? path
    : Uri(path: path, queryParameters: {'from': from}).toString();

/// Only allow in-app paths, so `?from=` cannot redirect off-site.
String? _safeDestination(String? from) =>
    from != null && from.startsWith('/') && !from.startsWith('//')
    ? from
    : null;
