import 'package:flutter/foundation.dart';
import 'package:go_router/go_router.dart';

import 'package:capsula_core/domain/bookmarks/bookmark_filters.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_view.dart';

import '../features/auth/sign_in_screen.dart';
import '../features/connection/connection_screen.dart';
import '../features/bookmarks/bookmark_detail_screen.dart';
import '../features/bookmarks/library_screen.dart';
import '../features/highlights/highlights_screen.dart';
import '../features/import/import_screen.dart';
import '../features/integrations/integrations_screen.dart';
import '../features/loading/loading_screen.dart';
import '../features/maintenance/maintenance_screen.dart';
import '../features/settings/rules_screen.dart';
import '../features/settings/sources_screen.dart';
import '../features/reader/reader_screen.dart';
import '../features/settings/settings_screen.dart';
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
  static const integrations = '/integrations';
  static const highlights = '/highlights';
  static const maintenance = '/maintenance';
  static const sources = '/sources';
  static const rules = '/rules';
  static const settings = '/settings';

  static String bookmark(String id) => '/bookmarks/$id';

  static String reader(String id) => '/bookmarks/$id/read';

  static String library(
    BookmarkView view, [
    BookmarkFilters filters = BookmarkFilters.none,
  ]) {
    final query = {
      if (view is! AllView) 'view': view.key,
      ...filters.toQuery(),
    };
    return query.isEmpty
        ? home
        : Uri(path: home, queryParameters: query).toString();
  }
}

/// The view and filters in a library URL. Sources and types used to be
/// views (`?view=source:reddit`); such links now open All bookmarks with
/// the matching filter.
(BookmarkView, BookmarkFilters) libraryLocation(Map<String, String> query) {
  final view = BookmarkView.parse(query['view']);
  final filters = BookmarkFilters.fromQuery(query);
  return switch (view) {
    SourceView(:final source) => (
      BookmarkView.all,
      filters.copyWith(sources: {...filters.sources, source.id}),
    ),
    TypeView(:final type) => (
      BookmarkView.all,
      filters.copyWith(kinds: {...filters.kinds, type}),
    ),
    _ => (view, filters),
  };
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
    builder: (context, state) {
      final (view, filters) = libraryLocation(state.uri.queryParameters);
      return LibraryScreen(view: view, filters: filters);
    },
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
    path: AppRoutes.settings,
    builder: (context, state) => const SettingsScreen(),
  ),
  GoRoute(
    path: AppRoutes.maintenance,
    builder: (context, state) => const MaintenanceScreen(),
  ),
  GoRoute(
    path: AppRoutes.sources,
    builder: (context, state) => const SourcesScreen(),
  ),
  GoRoute(
    path: AppRoutes.rules,
    builder: (context, state) => const RulesScreen(),
  ),
  GoRoute(
    path: AppRoutes.highlights,
    builder: (context, state) => const HighlightsScreen(),
  ),
  GoRoute(
    path: AppRoutes.integrations,
    builder: (context, state) => const IntegrationsScreen(),
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
