import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../../testing/in_memory_bookmark_repository.dart';
import '../../testing/in_memory_content_index.dart';
import '../../testing/in_memory_highlight_repository.dart';
import '../../testing/in_memory_label_repository.dart';
import '../auth/app_user.dart';
import '../auth/auth_repository.dart';
import '../bookmarks/bookmark.dart';
import '../bookmarks/bookmark_codec.dart';
import '../bookmarks/bookmark_repository.dart';
import '../connection/backend.dart';
import '../highlights/highlight.dart';
import '../organization/label.dart';
import '../search/full_text.dart';

/// Where an on-device library is kept: a file on Android, browser storage
/// on the web.
abstract interface class LocalStorage {
  /// Null when nothing is stored under [key].
  Future<String?> read(String key);

  Future<void> write(String key, String value);
}

/// A library kept only on this device, used without a Firebase project or
/// an account. Held in memory and written to [LocalStorage] after every
/// change.
class LocalLibrary {
  LocalLibrary._(this._storage);

  static const libraryKey = 'capsula_library';
  static const contentKey = 'capsula_content_index';

  /// Loads the library saved in [storage], or starts an empty one.
  static Future<LocalLibrary> open(LocalStorage storage) async {
    final library = LocalLibrary._(storage);
    await library._load();
    return library;
  }

  final LocalStorage _storage;
  final _bookmarks = InMemoryBookmarkRepository();
  late final _labels = InMemoryLabelRepository(_bookmarks);
  final _highlights = InMemoryHighlightRepository();
  final _content = InMemoryContentIndex();

  /// The user of an on-device library: always signed in, no account.
  static const user = AppUser(id: 'local');

  int get bookmarkCount => _bookmarks.items.length;

  /// Repositories for the app, always signed in as [user].
  BackendServices services() => BackendServices(
    authRepository: LocalAuthRepository(),
    bookmarkRepository: _LocalBookmarks(this),
    labelRepository: _LocalLabels(this),
    highlightRepository: _LocalHighlights(this),
    contentIndex: _LocalContent(this),
  );

  // ---------------------------------------------------------------------------
  // Saving

  Future<void> _saved = Future.value();
  bool _dirtyLibrary = false;
  bool _dirtyContent = false;

  /// Saves after a change. Completes once a save that includes it is done,
  /// so callers that await a write know it's stored. Saves run one at a
  /// time; changes made while one runs share the next.
  Future<void> _changed({bool content = false}) {
    if (content) {
      _dirtyContent = true;
    } else {
      _dirtyLibrary = true;
    }
    return _saved = _saved.catchError((Object _) {}).then((_) => _save());
  }

  Future<void> _save() async {
    if (_dirtyLibrary) {
      _dirtyLibrary = false;
      try {
        await _storage.write(libraryKey, jsonEncode(_libraryJson()));
      } on Object {
        _dirtyLibrary = true;
        rethrow;
      }
    }
    if (_dirtyContent) {
      _dirtyContent = false;
      try {
        await _storage.write(contentKey, jsonEncode(_content.items));
      } on Object {
        _dirtyContent = true;
        rethrow;
      }
    }
  }

  static String _time(DateTime d) => d.toUtc().toIso8601String();

  static DateTime? _readTime(Object? v) =>
      v is String ? DateTime.tryParse(v)?.toLocal() : null;

  Map<String, Object?> _libraryJson() => {
    'version': 1,
    'bookmarks': {
      for (final b in _bookmarks.items.values)
        b.id: encodeBookmark(b, _time)..remove('searchTokens'),
    },
    'labels': {
      for (final l in _labels.items.values)
        l.id: {'kind': l.kind.name, 'name': l.name, 'parentId': ?l.parentId},
    },
    'highlights': {
      for (final h in _highlights.items.values) h.id: encodeHighlight(h, _time),
    },
  };

  Future<void> _load() async {
    final raw = await _storage.read(libraryKey);
    if (raw != null) {
      final json = jsonDecode(raw) as Map<String, Object?>;
      _bookmarks.addAll([
        for (final MapEntry(:key, :value) in _entries(json['bookmarks']))
          decodeBookmark(key, value, _readTime),
      ]);
      _labels.addAll([
        for (final MapEntry(:key, :value) in _entries(json['labels']))
          Label(
            id: key,
            kind: LabelKind.values.asNameMap()[value['kind']] ?? LabelKind.tag,
            name: value['name'] as String? ?? '',
            parentId: value['parentId'] as String?,
          ),
      ]);
      _highlights.addAll([
        for (final MapEntry(:key, :value) in _entries(json['highlights']))
          decodeHighlight(key, value, _readTime),
      ]);
    }
    final content = await _storage.read(contentKey);
    if (content != null) {
      for (final MapEntry(:key, :value)
          in (jsonDecode(content) as Map<String, Object?>).entries) {
        if (value is List) _content.items[key] = value.cast<String>();
      }
    }
  }

  static Iterable<MapEntry<String, Map<String, Object?>>> _entries(
    Object? map,
  ) => map is Map<String, Object?>
      ? map.entries
            .where((e) => e.value is Map<String, Object?>)
            .map((e) => MapEntry(e.key, e.value! as Map<String, Object?>))
      : const [];
}

final _random = Random.secure();

/// IDs that stay unique across app runs (unlike the in-memory counters).
String _newId() {
  final time = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final suffix = List.generate(
    6,
    (_) => _random.nextInt(36).toRadixString(36),
  ).join();
  return '$time$suffix';
}

class _LocalBookmarks implements BookmarkRepository {
  _LocalBookmarks(this._library);

  final LocalLibrary _library;
  InMemoryBookmarkRepository get _inner => _library._bookmarks;

  @override
  String newId() => _newId();

  @override
  Future<void> create(Bookmark bookmark) async {
    await _inner.create(bookmark);
    await _library._changed();
  }

  @override
  Future<void> update(Bookmark bookmark) async {
    await _inner.update(bookmark);
    await _library._changed();
  }

  @override
  Future<void> delete(String id) async {
    await _inner.delete(id);
    await _library._changed();
  }

  @override
  Future<void> createMany(List<Bookmark> bookmarks) async {
    _inner.addAll(bookmarks);
    await _library._changed();
  }

  @override
  Stream<Bookmark?> watch(String id) => _inner.watch(id);

  @override
  Stream<List<Bookmark>> watchList(BookmarkQuery query, {required int limit}) =>
      _inner.watchList(query, limit: limit);

  @override
  Future<Bookmark?> findByCanonicalUrl(String canonicalUrl) =>
      _inner.findByCanonicalUrl(canonicalUrl);

  @override
  Future<Set<String>> existingCanonicalUrls(Iterable<String> canonicalUrls) =>
      _inner.existingCanonicalUrls(canonicalUrls);

  @override
  Future<List<Bookmark>> fetchAll() => _inner.fetchAll();

  @override
  Future<int?> countInbox() => _inner.countInbox();
}

class _LocalLabels implements LabelRepository {
  _LocalLabels(this._library);

  final LocalLibrary _library;
  InMemoryLabelRepository get _inner => _library._labels;

  @override
  String newId(LabelKind kind) => _newId();

  @override
  Stream<List<Label>> watch(LabelKind kind) => _inner.watch(kind);

  @override
  Future<void> create(Label label) async {
    await _inner.create(label);
    await _library._changed();
  }

  @override
  Future<void> rename(Label label, String name) async {
    await _inner.rename(label, name);
    await _library._changed();
  }

  @override
  Future<void> setParent(Label label, String? parentId) async {
    await _inner.setParent(label, parentId);
    await _library._changed();
  }

  @override
  Future<void> delete(Label label) async {
    await _inner.delete(label);
    await _library._changed();
  }
}

class _LocalHighlights implements HighlightRepository {
  _LocalHighlights(this._library);

  final LocalLibrary _library;
  InMemoryHighlightRepository get _inner => _library._highlights;

  @override
  String newId() => _newId();

  @override
  Stream<List<Highlight>> watchForBookmark(String bookmarkId) =>
      _inner.watchForBookmark(bookmarkId);

  @override
  Stream<List<Highlight>> watchAll({required int limit}) =>
      _inner.watchAll(limit: limit);

  @override
  Future<void> save(Highlight highlight) async {
    await _inner.save(highlight);
    await _library._changed();
  }

  @override
  Future<void> delete(String id) async {
    await _inner.delete(id);
    await _library._changed();
  }

  @override
  Future<void> deleteForBookmark(String bookmarkId) async {
    await _inner.deleteForBookmark(bookmarkId);
    await _library._changed();
  }
}

class _LocalContent implements ContentIndex {
  _LocalContent(this._library);

  final LocalLibrary _library;
  InMemoryContentIndex get _inner => _library._content;

  @override
  Future<void> save(String bookmarkId, List<String> words) async {
    await _inner.save(bookmarkId, words);
    await _library._changed(content: true);
  }

  @override
  Future<List<String>> search(String query, {int limit = 50}) =>
      _inner.search(query, limit: limit);

  @override
  Future<void> delete(String bookmarkId) async {
    await _inner.delete(bookmarkId);
    await _library._changed(content: true);
  }
}

/// Auth for an on-device library: always signed in as [LocalLibrary.user],
/// with no account to sign in to.
class LocalAuthRepository implements AuthRepository {
  @override
  Stream<AppUser?> authStateChanges() => Stream.value(LocalLibrary.user);

  @override
  AppUser? get currentUser => LocalLibrary.user;

  @override
  Future<void> signInWithEmail({
    required String email,
    required String password,
  }) => throw const AuthException(AuthErrorCode.unknown);

  @override
  Future<void> registerWithEmail({
    required String email,
    required String password,
  }) => throw const AuthException(AuthErrorCode.unknown);

  @override
  Future<void> sendPasswordReset(String email) =>
      throw const AuthException(AuthErrorCode.unknown);

  @override
  Future<void> signOut() async {}

  @override
  Future<String?> idToken() async => null;
}
