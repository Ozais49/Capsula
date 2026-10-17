/// Facts about a library as a whole, such as which data migrations it has
/// had.
abstract interface class LibraryMetaRepository {
  /// Version of the stored data's shape; 1 for libraries that predate
  /// migrations.
  Future<int> schemaVersion();

  Future<void> setSchemaVersion(int version);
}
