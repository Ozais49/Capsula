import '../auth/auth_repository.dart';
import '../bookmarks/bookmark_repository.dart';
import '../bookmarks/bookmark_service.dart';
import '../import/import_service.dart';
import '../highlights/highlight.dart';
import '../organization/label.dart';
import 'firebase_connection.dart';

/// Repositories provided by a connected backend.
class BackendServices {
  BackendServices({
    required this.authRepository,
    required this.bookmarkRepository,
    required this.labelRepository,
    required this.highlightRepository,
  });

  final AuthRepository authRepository;
  final BookmarkRepository bookmarkRepository;
  final LabelRepository labelRepository;
  final HighlightRepository highlightRepository;

  late final BookmarkService bookmarks = BookmarkService(
    bookmarkRepository,
    labelRepository,
    highlights: highlightRepository,
  );

  late final ImportService importer = ImportService(
    bookmarkRepository,
    labelRepository,
  );
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
