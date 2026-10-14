import 'package:flutter/widgets.dart';

import 'app/app.dart';
import 'app/backend_controller.dart';
import 'config/app_config.dart';
import 'data/firebase/firebase_backend_connector.dart';
import 'data/local/shared_prefs_connection_store.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.fromEnvironment();
  final backend = BackendController(
    store: SharedPrefsConnectionStore(),
    connector: FirebaseBackendConnector(config),
  );
  runApp(CapsulaApp(config: config, backend: backend));
  await backend.start();
}
