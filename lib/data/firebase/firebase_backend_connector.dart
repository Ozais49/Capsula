import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../config/app_config.dart';

import 'package:capsula_core/domain/connection/backend.dart';
import 'package:capsula_core/domain/connection/firebase_connection.dart';

import 'firebase_auth_repository.dart';
import 'firestore_bookmark_repository.dart';
import 'firestore_highlight_repository.dart';
import 'firestore_label_repository.dart';

class FirebaseBackendConnector implements BackendConnector {
  FirebaseBackendConnector(this._config);

  final AppConfig _config;

  @override
  Future<BackendServices> connect(FirebaseConnection connection) async {
    final options = FirebaseOptions(
      apiKey: connection.apiKey,
      appId: connection.appId,
      messagingSenderId: connection.messagingSenderId,
      projectId: connection.projectId,
      authDomain: connection.authDomain,
      storageBucket: connection.storageBucket,
    );

    // The default Firebase app can only be initialized once per run.
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: options);
    } else if (Firebase.app().options != options) {
      throw StateError('Restart the app to use the new connection settings.');
    }

    final auth = FirebaseAuth.instance;
    final firestore = FirebaseFirestore.instance;
    // Keep a local copy so saved bookmarks survive being offline.
    firestore.settings = const Settings(
      persistenceEnabled: true,
      // Lets several browser tabs share the offline cache.
      webPersistentTabManager: WebPersistentMultipleTabManager(),
    );
    if (_config.useFirebaseEmulators) {
      await auth.useAuthEmulator(_config.firebaseEmulatorHost, 9099);
      firestore.useFirestoreEmulator(_config.firebaseEmulatorHost, 8080);
    }

    return BackendServices(
      authRepository: FirebaseAuthRepository(auth),
      bookmarkRepository: FirestoreBookmarkRepository(
        firestore,
        () => auth.currentUser?.uid,
      ),
      labelRepository: FirestoreLabelRepository(
        firestore,
        () => auth.currentUser?.uid,
      ),
      highlightRepository: FirestoreHighlightRepository(
        firestore,
        () => auth.currentUser?.uid,
      ),
    );
  }
}
