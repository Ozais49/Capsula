import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'package:capsula_core/domain/bookmarks/shared_content.dart';

/// Content shared into the app from other apps.
abstract interface class ShareIntake {
  /// Returns the pending share and clears it, or null if there is none.
  Future<SharedContent?> take();

  /// Hides the share window and returns to the app that shared, while the
  /// app keeps running to finish work in the background. Call [finish]
  /// when it is done.
  Future<void> moveToBackground();

  /// Closes the share window and returns to the app that shared.
  Future<void> finish();
}

/// Reads shares received by the Android `ShareActivity`.
class MethodChannelShareIntake implements ShareIntake {
  const MethodChannelShareIntake();

  static const _channel = MethodChannel('capsula/share');

  @override
  Future<SharedContent?> take() async {
    if (kIsWeb) return null;
    try {
      final data = await _channel.invokeMapMethod<String, String?>('takeShare');
      if (data == null) return null;
      return SharedContent(text: data['text'], subject: data['subject']);
    } on MissingPluginException {
      // Not launched from a share (e.g. the main activity).
      return null;
    }
  }

  @override
  Future<void> moveToBackground() async {
    try {
      await _channel.invokeMethod<void>('moveToBackground');
    } on MissingPluginException {
      await finish();
    }
  }

  @override
  Future<void> finish() => SystemNavigator.pop();
}
