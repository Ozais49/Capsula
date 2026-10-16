import 'device_storage_web.dart'
    if (dart.library.io) 'device_storage_io.dart'
    as impl;

import 'package:capsula_core/domain/local/local_library.dart';

/// Storage for the on-device library: a file in the app's private folder
/// on Android, browser storage on the web.
LocalStorage deviceStorage() => impl.deviceStorage();
