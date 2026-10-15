import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'app/app.dart';
import 'app/backend_controller.dart';
import 'config/app_config.dart';
import 'data/firebase/firebase_backend_connector.dart';
import 'data/local/shared_prefs_connection_store.dart';
import 'platform/hosted_firebase_config.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Web URLs like /bookmarks/abc instead of /#/bookmarks/abc.
  usePathUrlStrategy();

  final config = AppConfig.fromEnvironment();
  final backend = BackendController(
    store: SharedPrefsConnectionStore(),
    connector: FirebaseBackendConnector(config),
    // Web: the hosting site's project. Android: the project built in.
    fallbackSettings: kIsWeb
        ? () => loadHostedFirebaseConfig(Uri.base)
        : () async => config.defaultAndroidConnection,
  );
  runApp(CapsulaApp(config: config, backend: backend));
  await backend.start();
}
