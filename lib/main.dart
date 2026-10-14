import 'package:flutter/widgets.dart';

import 'app/app.dart';
import 'config/app_config.dart';
import 'data/firebase/firebase_bootstrap.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final config = AppConfig.fromEnvironment();
  final services = await initializeFirebase(config);
  runApp(CapsulaApp(config: config, authRepository: services.authRepository));
}
