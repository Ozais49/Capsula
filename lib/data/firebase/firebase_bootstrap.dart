import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../config/app_config.dart';
import '../../domain/auth/auth_repository.dart';
import 'firebase_auth_repository.dart';
import 'firebase_options.dart';

/// Repositories backed by Firebase. Swapping backends means providing
/// a different set of implementations here, not changing the UI.
class FirebaseServices {
  const FirebaseServices({required this.authRepository});

  final AuthRepository authRepository;
}

Future<FirebaseServices> initializeFirebase(AppConfig config) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  final auth = FirebaseAuth.instance;

  if (config.useFirebaseEmulators) {
    await auth.useAuthEmulator(config.firebaseEmulatorHost, 9099);
  }

  return FirebaseServices(authRepository: FirebaseAuthRepository(auth));
}
