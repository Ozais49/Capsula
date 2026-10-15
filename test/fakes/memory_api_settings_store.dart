import 'package:capsula/app/api_settings.dart';

class MemoryApiSettingsStore implements ApiSettingsStore {
  MemoryApiSettingsStore([this.saved]);

  String? saved;

  @override
  Future<String?> load() async => saved;

  @override
  Future<void> save(String? url) async => saved = url;
}
