import '../auth/auth_repository.dart';
import '../bookmarks/bookmark_repository.dart';
import '../bookmarks/bookmark_service.dart';
import 'firebase_connection.dart';

/// Repositories provided by a connected backend.
class BackendServices {
  BackendServices({
    required this.authRepository,
    required this.bookmarkRepository,
  });

  final AuthRepository authRepository;
  final BookmarkRepository bookmarkRepository;

  late final BookmarkService bookmarks = BookmarkService(bookmarkRepository);
}

/// Connects to the backend described by the user's connection settings.
abstract interface class BackendConnector {
  Future<BackendServices> connect(FirebaseConnection connection);
}

/// Persists connection settings on this device.
abstract interface class ConnectionSettingsStore {
  /// Returns null when nothing is saved or the saved value is unreadable.
  Future<FirebaseConnection?> load();

  Future<void> save(FirebaseConnection connection);

  Future<void> clear();
}
