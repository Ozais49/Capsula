import 'package:capsula/data/firebase/firebase_auth_repository.dart';
import 'package:capsula/domain/auth/auth_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('maps Firebase auth error codes to domain codes', () {
    const cases = {
      'invalid-credential': AuthErrorCode.invalidCredentials,
      'wrong-password': AuthErrorCode.invalidCredentials,
      'user-not-found': AuthErrorCode.invalidCredentials,
      'email-already-in-use': AuthErrorCode.emailAlreadyInUse,
      'weak-password': AuthErrorCode.weakPassword,
      'invalid-email': AuthErrorCode.invalidEmail,
      'user-disabled': AuthErrorCode.userDisabled,
      'too-many-requests': AuthErrorCode.tooManyRequests,
      'network-request-failed': AuthErrorCode.network,
      'operation-not-allowed': AuthErrorCode.signInMethodDisabled,
      'configuration-not-found': AuthErrorCode.signInMethodDisabled,
      'invalid-api-key': AuthErrorCode.invalidConnection,
      'api-key-not-valid.-please-pass-a-valid-api-key.':
          AuthErrorCode.invalidConnection,
      'something-new': AuthErrorCode.unknown,
    };
    cases.forEach((code, expected) {
      expect(mapFirebaseAuthCode(code), expected, reason: code);
    });
  });
}
