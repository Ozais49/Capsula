import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';

/// Who is calling, and how they proved it.
class Principal {
  const Principal(this.uid, {required this.viaApiToken});

  final String uid;

  /// True for personal API tokens, false for Firebase sign-in tokens.
  final bool viaApiToken;
}

/// Verifies Firebase ID tokens issued to the app's signed-in users.
abstract interface class IdTokenVerifier {
  /// The user ID, or null when the token is invalid or expired.
  Future<String?> verify(String idToken);
}

class ApiToken {
  const ApiToken({
    required this.id,
    required this.uid,
    required this.name,
    required this.createdAt,
    this.lastUsedAt,
  });

  /// SHA-256 of the secret; the secret itself is never stored.
  final String id;
  final String uid;
  final String name;
  final DateTime createdAt;
  final DateTime? lastUsedAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toUtc().toIso8601String(),
    if (lastUsedAt case final t?) 'lastUsedAt': t.toUtc().toIso8601String(),
  };
}

/// Personal API tokens, stored only as hashes.
abstract interface class TokenStore {
  Future<void> save(ApiToken token);
  Future<ApiToken?> find(String id);
  Future<List<ApiToken>> forUser(String uid);
  Future<void> delete(String id);
  Future<void> touch(String id, DateTime when);
}

const apiTokenPrefix = 'cap_';

/// A new random token secret, e.g. `cap_3q2…`. Shown to the user once.
String generateTokenSecret([Random? random]) {
  final r = random ?? Random.secure();
  final bytes = List<int>.generate(32, (_) => r.nextInt(256));
  return '$apiTokenPrefix${base64Url.encode(bytes).replaceAll('=', '')}';
}

String hashToken(String secret) =>
    sha256.convert(utf8.encode(secret)).toString();

/// Resolves `Authorization: Bearer …` to a [Principal].
class Authenticator {
  Authenticator(this._idTokens, this._tokens, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final IdTokenVerifier _idTokens;
  final TokenStore _tokens;
  final DateTime Function() _now;

  Future<Principal?> authenticate(String? authorization) async {
    if (authorization == null) return null;
    final match = RegExp(
      r'^Bearer\s+(\S+)$',
      caseSensitive: false,
    ).firstMatch(authorization.trim());
    final credential = match?.group(1);
    if (credential == null) return null;

    if (credential.startsWith(apiTokenPrefix)) {
      final token = await _tokens.find(hashToken(credential));
      if (token == null) return null;
      // Best effort; a failed timestamp update doesn't block the request.
      _tokens.touch(token.id, _now()).ignore();
      return Principal(token.uid, viaApiToken: true);
    }

    final uid = await _idTokens.verify(credential);
    return uid == null ? null : Principal(uid, viaApiToken: false);
  }
}
