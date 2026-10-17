import 'dart:convert';

import 'package:capsula/app/api_settings.dart';
import 'package:capsula/app/app.dart';
import 'package:capsula/data/api/api_client.dart';
import 'package:capsula_core/domain/auth/app_user.dart';
import 'package:capsula_core/domain/organization/label.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import '../fakes/fake_auth_repository.dart';
import '../fakes/fake_backend.dart';
import '../fakes/fake_share_intake.dart';
import '../fakes/memory_api_settings_store.dart';
import '../fakes/navigation.dart';
import '../fakes/test_dependencies.dart';

const _work = Label(id: 'c1', kind: LabelKind.collection, name: 'Work');

Future<List<http.Request>> _open(WidgetTester tester, {String? apiUrl}) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final requests = <http.Request>[];
  final connector = FakeBackendConnector(
    FakeAuthRepository(initialUser: const AppUser(id: 'u1')),
  );
  connector.labels.addAll([_work]);
  final settings = ApiSettings(MemoryApiSettingsStore(apiUrl));
  await settings.load();

  await tester.pumpWidget(
    CapsulaApp(
      config: testConfig,
      backend: await startedBackendWith(connector),
      shareIntake: FakeShareIntake(),
      apiSettings: settings,
      apiClientFactory: (url, idToken) => CapsulaApiClient(
        url,
        idToken,
        client: MockClient((r) async {
          requests.add(r);
          return r.method == 'DELETE'
              ? http.Response('', 204)
              : http.Response(
                  jsonEncode({
                    'shareId': 'abcdefghijklmnop',
                    'url': 'https://api.example.com/p/abcdefghijklmnop',
                  }),
                  200,
                );
        }),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await openNavigation(tester);
  await tester.tap(find.byTooltip('Work options'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Share…'));
  await tester.pumpAndSettle();
  return requests;
}

void main() {
  testWidgets('explains that sharing needs the API server', (tester) async {
    await _open(tester);
    expect(find.textContaining('served by your Capsula API'), findsOneWidget);
    expect(find.text('Set up API'), findsOneWidget);
  });

  testWidgets('turn the public link on, see it, then turn it off', (
    tester,
  ) async {
    final requests = await _open(tester, apiUrl: 'https://api.example.com');

    await tester.tap(find.widgetWithText(SwitchListTile, 'Public link'));
    await tester.pumpAndSettle();
    expect(requests.last.method, 'POST');
    expect(requests.last.url.path, '/v1/collections/c1/share');
    expect(
      find.text('https://api.example.com/p/abcdefghijklmnop'),
      findsOneWidget,
    );
    expect(find.text('Copy link'), findsOneWidget);

    await tester.tap(find.widgetWithText(SwitchListTile, 'Public link'));
    await tester.pumpAndSettle();
    expect(requests.last.method, 'DELETE');
    expect(find.text('Copy link'), findsNothing);
  });
}
