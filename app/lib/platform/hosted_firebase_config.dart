import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'package:capsula_core/domain/connection/firebase_connection.dart';

/// Firebase Hosting serves the project's web config at this path, so a
/// copy of the app hosted there can connect without manual setup.
const hostedConfigPath = '/__/firebase/init.json';

/// Reads the hosting site's Firebase config relative to [siteUrl]. Returns
/// null when the site isn't on Firebase Hosting or the config is unusable.
Future<FirebaseConnection?> loadHostedFirebaseConfig(
  Uri siteUrl, {
  http.Client? client,
}) async {
  final httpClient = client ?? http.Client();
  try {
    final response = await httpClient
        .get(siteUrl.resolve(hostedConfigPath))
        .timeout(const Duration(seconds: 5));
    if (response.statusCode != 200) return null;
    final json = jsonDecode(response.body);
    if (json is! Map<String, Object?>) return null;
    final connection = FirebaseConnection.fromJson(json);
    return connection.validate(ConnectionPlatform.web).isEmpty
        ? connection
        : null;
  } on Object {
    return null;
  } finally {
    if (client == null) httpClient.close();
  }
}
