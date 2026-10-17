import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Saves a file the user can keep: a download on the web, the system
/// "Save as" dialog on Android.
abstract interface class FileSaver {
  /// Returns false when the user cancels.
  Future<bool> save(String name, String mimeType, Uint8List bytes);
}

class PlatformFileSaver implements FileSaver {
  const PlatformFileSaver();

  static const _channel = MethodChannel('capsula/files');

  @override
  Future<bool> save(String name, String mimeType, Uint8List bytes) async {
    if (kIsWeb) {
      // On the web, saveTo starts a download named after the file.
      await XFile.fromData(bytes, mimeType: mimeType, name: name).saveTo(name);
      return true;
    }
    final saved = await _channel.invokeMethod<bool>('saveFile', {
      'name': name,
      'mimeType': mimeType,
      'bytes': bytes,
    });
    return saved ?? false;
  }
}
