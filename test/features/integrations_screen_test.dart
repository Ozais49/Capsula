import 'dart:convert';

import 'package:capsula/app/api_settings.dart';
import 'package:capsula/app/app.dart';
import 'package:capsula/config/app_config.dart';
import 'package:capsula/data/api/api_client.dart';
import 'package:capsula/features/integrations/integrations_screen.dart';
import 'package:capsula_core/domain/auth/app_user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../fakes/fake_auth_repository.dart';
import '../fakes/fake_backend.dart';
import '../fakes/fake_share_intake.dart';
import '../fakes/memory_api_settings_store.dart';
import '../fakes/navigation.dart';

/// A tiny in-memory stand-in for the API server's token endpoints.
class _FakeServer {
  final tokens = <Map<String, Object?>>[];
  String? lastAuth;

  Future<http.Response> handle(http.Request r) async {
    lastAuth = r.headers['Authorization'];
    final path = r.url.path;
    if (path.endsWith('/v1/health')) {
      return http.Response('{"status":"ok"}', 200);
    }
    if (path.endsWith('/v1/tokens') && r.method == 'GET') {
      return http.Response(jsonEncode({'tokens': tokens}), 200);
    }
    if (path.endsWith('/v1/tokens') && r.method == 'POST') {
      final token = {
        'id': 'id${tokens.length}',
        'name': jsonDecode(r.body)['name'],
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      };
      tokens.add(token);
      return http.Response(
        jsonEncode({...token, 'token': 'cap_shown_once'}),
        201,
      );
    }
    if (r.method == 'DELETE') {
      tokens.removeWhere((t) => path.endsWith('/${t['id']}'));
      return http.Response('', 204);
    }
    return http.Response('{}', 404);
  }
}

Future<(_FakeServer, MemoryApiSettingsStore)> _open(
  WidgetTester tester, {
  String? savedUrl,
}) async {
  tester.view.physicalSize = const Size(700, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final server = _FakeServer();
  final store = MemoryApiSettingsStore(savedUrl);
  final settings = ApiSettings(store);
  await settings.load();

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
      apiSettings: settings,
      apiClientFactory: (url, idToken) =>
          CapsulaApiClient(url, idToken, client: MockClient(server.handle)),
    ),
  );
  await tester.pumpAndSettle();
  await openNavigation(tester);
  await tester.tap(find.text('API & integrations'));
  await tester.pumpAndSettle();
  return (server, store);
}

void main() {
  testWidgets('saving a server address connects and shows tokens', (
    tester,
  ) async {
    final (_, store) = await _open(tester);
    expect(find.byType(IntegrationsScreen), findsOneWidget);
    expect(find.text('API tokens'), findsNothing);

    await tester.enterText(
      find.widgetWithText(TextField, 'Server address'),
      'https://api.example.com/',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(store.saved, 'https://api.example.com');
    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('No tokens yet.'), findsOneWidget);
  });

  testWidgets('rejects an invalid address', (tester) async {
    await _open(tester);
    await tester.enterText(
      find.widgetWithText(TextField, 'Server address'),
      'not an address',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Enter an address like'), findsOneWidget);
  });

  testWidgets('create a token, see it once, then revoke it', (tester) async {
    final (server, _) = await _open(
      tester,
      savedUrl: 'https://api.example.com',
    );

    await tester.tap(find.text('New token'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Browser extension');
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();

    expect(find.text('cap_shown_once'), findsOneWidget);
    expect(server.lastAuth, 'Bearer id-token-u1');
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    expect(find.text('cap_shown_once'), findsNothing);
    expect(find.text('Browser extension'), findsOneWidget);

    await tester.tap(find.byTooltip('Revoke Browser extension'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Revoke'));
    await tester.pumpAndSettle();
    expect(server.tokens, isEmpty);
    expect(find.text('No tokens yet.'), findsOneWidget);
  });
}
