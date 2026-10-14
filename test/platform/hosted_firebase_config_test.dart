import 'dart:convert';

import 'package:capsula/platform/hosted_firebase_config.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

final _site = Uri.parse('https://capsula-ygtech.web.app/bookmarks/abc');

const _initJson = {
  'apiKey': 'AIza-web',
  'appId': '1:243779316527:web:fd7f89fa',
  'projectId': 'capsula-ygtech',
  'messagingSenderId': '243779316527',
  'authDomain': 'capsula-ygtech.firebaseapp.com',
  'storageBucket': 'capsula-ygtech.firebasestorage.app',
  'locationId': 'nam5',
};

void main() {
  test('reads the config Firebase Hosting serves', () async {
    late Uri requested;
    final connection = await loadHostedFirebaseConfig(
      _site,
      client: MockClient((request) async {
        requested = request.url;
        return http.Response(jsonEncode(_initJson), 200);
      }),
    );

    expect(
      requested.toString(),
      'https://capsula-ygtech.web.app/__/firebase/init.json',
    );
    expect(connection?.projectId, 'capsula-ygtech');
    expect(connection?.authDomain, 'capsula-ygtech.firebaseapp.com');
  });

  test('returns null when not on Firebase Hosting', () async {
    final connection = await loadHostedFirebaseConfig(
      _site,
      client: MockClient((_) async => http.Response('Not found', 404)),
    );
    expect(connection, isNull);
  });

  test('returns null for unusable or non-web configs', () async {
    for (final body in [
      'not json',
      '[]',
      jsonEncode({..._initJson, 'appId': '1:2:android:abc'}),
      jsonEncode({'projectId': 'only-this'}),
    ]) {
      final connection = await loadHostedFirebaseConfig(
        _site,
        client: MockClient((_) async => http.Response(body, 200)),
      );
      expect(connection, isNull, reason: body);
    }
  });

  test('returns null when offline', () async {
    final connection = await loadHostedFirebaseConfig(
      _site,
      client: MockClient((_) async => throw http.ClientException('offline')),
    );
    expect(connection, isNull);
  });
}
