import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Reads text the user copied, so Capsula can offer to save a copied link.
abstract interface class ClipboardReader {
  /// Null when there's no text or reading isn't possible.
  Future<String?> read();
}

class SystemClipboardReader implements ClipboardReader {
  const SystemClipboardReader();

  @override
  Future<String?> read() async {
    // Browsers ask for permission on every read; only offer this on Android.
    if (kIsWeb) return null;
    try {
      return (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    } on Object {
      return null;
    }
  }
}
