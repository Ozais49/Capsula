import 'package:capsula/domain/connection/firebase_connection.dart';
import 'package:flutter_test/flutter_test.dart';

const _package = 'com.ygtech.capsula';

FirebaseConnection _parse(String text) =>
    parseFirebaseConfig(text, androidPackageName: _package);

const _googleServices = '''
{
  "project_info": {
    "project_number": "243779316527",
    "project_id": "capsula-ygtech",
    "storage_bucket": "capsula-ygtech.firebasestorage.app"
  },
  "client": [
    {
      "client_info": {
        "mobilesdk_app_id": "1:243779316527:android:0000aaaa",
        "android_client_info": { "package_name": "com.other.app" }
      },
      "api_key": [ { "current_key": "other-key" } ]
    },
    {
      "client_info": {
        "mobilesdk_app_id": "1:243779316527:android:9de6e6a7",
        "android_client_info": { "package_name": "com.ygtech.capsula" }
      },
      "oauth_client": [],
      "api_key": [ { "current_key": "AIza-android-key" } ]
    }
  ],
  "configuration_version": "1"
}
''';

void main() {
  group('parseFirebaseConfig', () {
    test('reads google-services.json for the app package', () {
      final c = _parse(_googleServices);

      expect(c.apiKey, 'AIza-android-key');
      expect(c.appId, '1:243779316527:android:9de6e6a7');
      expect(c.projectId, 'capsula-ygtech');
      expect(c.messagingSenderId, '243779316527');
      expect(c.storageBucket, 'capsula-ygtech.firebasestorage.app');
      expect(c.authDomain, isNull);
    });

    test('rejects google-services.json without the app package', () {
      final other = _googleServices.replaceAll('com.ygtech.capsula', 'com.x');
      expect(
        () => _parse(other),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains(_package),
          ),
        ),
      );
    });

    test('rejects malformed google-services.json', () {
      expect(
        () => _parse('{ "project_info": '),
        throwsA(isA<FormatException>()),
      );
    });

    test('reads the web config JSON printed by the Firebase CLI', () {
      final c = _parse('''
{
  "projectId": "capsula-ygtech",
  "appId": "1:243779316527:web:fd7f89fa",
  "storageBucket": "capsula-ygtech.firebasestorage.app",
  "apiKey": "AIza-web-key",
  "authDomain": "capsula-ygtech.firebaseapp.com",
  "messagingSenderId": "243779316527",
  "projectNumber": "243779316527",
  "version": "2"
}''');

      expect(c.apiKey, 'AIza-web-key');
      expect(c.appId, '1:243779316527:web:fd7f89fa');
      expect(c.authDomain, 'capsula-ygtech.firebaseapp.com');
    });

    test('reads the JavaScript snippet from the Firebase console', () {
      final c = _parse('''
const firebaseConfig = {
  apiKey: "AIza-web-key",
  authDomain: 'capsula-ygtech.firebaseapp.com',
  projectId: "capsula-ygtech",
  storageBucket: "capsula-ygtech.firebasestorage.app",
  messagingSenderId: "243779316527",
  appId: "1:243779316527:web:fd7f89fa"
};''');

      expect(c.apiKey, 'AIza-web-key');
      expect(c.authDomain, 'capsula-ygtech.firebaseapp.com');
      expect(c.projectId, 'capsula-ygtech');
      expect(c.appId, '1:243779316527:web:fd7f89fa');
    });

    test('rejects text without Firebase settings', () {
      expect(() => _parse('hello'), throwsA(isA<FormatException>()));
      expect(() => _parse('   '), throwsA(isA<FormatException>()));
    });
  });

  group('validate', () {
    const android = FirebaseConnection(
      apiKey: 'key',
      appId: '1:243779316527:android:9de6e6a7',
      projectId: 'p',
      messagingSenderId: '243779316527',
    );

    test('accepts complete settings for the matching platform', () {
      expect(android.validate(ConnectionPlatform.android), isEmpty);
    });

    test('rejects an app ID from another platform', () {
      expect(
        android.validate(ConnectionPlatform.web).single,
        contains('This App ID is for android'),
      );
    });

    test('reports missing required fields', () {
      const empty = FirebaseConnection(
        apiKey: '',
        appId: '',
        projectId: '',
        messagingSenderId: '',
      );
      expect(empty.validate(ConnectionPlatform.android), hasLength(4));
    });

    test('rejects a malformed app ID', () {
      const bad = FirebaseConnection(
        apiKey: 'key',
        appId: 'not-an-app-id',
        projectId: 'p',
        messagingSenderId: '1',
      );
      expect(
        bad.validate(ConnectionPlatform.android).single,
        contains('App ID should look like'),
      );
    });
  });

  test('round-trips through JSON', () {
    const c = FirebaseConnection(
      apiKey: 'key',
      appId: '1:1:web:a',
      projectId: 'p',
      messagingSenderId: '1',
      authDomain: 'p.firebaseapp.com',
    );
    expect(FirebaseConnection.fromJson(c.toJson()), c);
    expect(c.toJson().containsKey('storageBucket'), isFalse);
  });
}
