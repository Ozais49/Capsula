import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import 'package:capsula_core/domain/bookmarks/bookmark_view.dart';

import '../features/auth/sign_in_screen.dart';
import '../features/connection/connection_screen.dart';
import '../features/bookmarks/bookmark_detail_screen.dart';
import '../features/bookmarks/library_screen.dart';
import '../features/import/import_screen.dart';
import '../features/loading/loading_screen.dart';
import '../features/reader/reader_screen.dart';
import '../features/share/share_screen.dart';
import 'auth_session.dart';
import 'backend_controller.dart';

abstract final class AppRoutes {
  static const home = '/';
  static const signIn = '/sign-in';
  static const loading = '/loading';
  static const connection = '/connection';
  static const share = '/share';
  static const import = '/import';

  static String bookmark(String id) => '/bookmarks/$id';

  static String reader(String id) => '/bookmarks/$id/read';

  static String library(BookmarkView view) => view is InboxView
      ? home
      : '$home?view=${Uri.encodeQueryComponent(view.key)}';
}

GoRouter createRouter(BackendController backend, AuthSession session) =>
    GoRouter(
      refreshListenable: Listenable.merge([backend, session]),
      redirect: (context, state) =>
          appRedirect(backend.status, session.status, state.uri),
      routes: [
        GoRoute(
          path: AppRoutes.connection,
          builder: (context, state) => const ConnectionScreen(),
        ),
        ..._authRoutes,
      ],
    );

final _authRoutes = [
  GoRoute(
    path: AppRoutes.home,
    builder: (context, state) => LibraryScreen(
      view: BookmarkView.parse(state.uri.queryParameters['view']),
    ),
    routes: [
      GoRoute(
        path: 'bookmarks/:id',
        builder: (context, state) =>
            BookmarkDetailScreen(bookmarkId: state.pathParameters['id']!),
        routes: [
          GoRoute(
            path: 'read',
            builder: (context, state) =>
                ReaderScreen(bookmarkId: state.pathParameters['id']!),
          ),
        ],
      ),
    ],
  ),
  GoRoute(
    path: AppRoutes.signIn,
    builder: (context, state) => const SignInScreen(),
  ),
  GoRoute(
    path: AppRoutes.loading,
    builder: (context, state) => const LoadingScreen(),
  ),
  GoRoute(
    path: AppRoutes.import,
    builder: (context, state) => const ImportScreen(),
  ),
  GoRoute(
    path: AppRoutes.share,
    builder: (context, state) => const ShareScreen(),
  ),
];

/// Sends the user to the connection screen until a backend is connected,
/// then applies [authRedirect]. The connection screen stays reachable
/// at all times so settings can be corrected.
String? appRedirect(BackendStatus backend, AuthStatus auth, Uri uri) {
  final path = uri.path;
  if (path == AppRoutes.connection) return null;

  switch (backend) {
    case BackendStatus.loading:
    case BackendStatus.connecting:
      return path == AppRoutes.loading
          ? null
          : _withFrom(AppRoutes.loading, _safeDestination(uri.toString()));
    case BackendStatus.notConfigured:
    case BackendStatus.failed:
      return AppRoutes.connection;
    case BackendStatus.connected:
      return authRedirect(auth, uri);
  }
}

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
