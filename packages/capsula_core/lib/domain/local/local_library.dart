import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../../testing/in_memory_bookmark_repository.dart';
import '../../testing/in_memory_content_index.dart';
import '../../testing/in_memory_highlight_repository.dart';
import '../../testing/in_memory_label_repository.dart';
import '../../testing/in_memory_source_repository.dart';
import '../../testing/in_memory_rule_repository.dart';
import '../auth/app_user.dart';
import '../auth/auth_repository.dart';
import '../bookmarks/bookmark.dart';
import '../bookmarks/bookmark_codec.dart';
import '../bookmarks/bookmark_repository.dart';
import '../connection/backend.dart';
import '../highlights/highlight.dart';
import '../organization/label.dart';
import '../search/full_text.dart';
import '../sources/custom_source.dart';
import '../meta/library_meta.dart';
import '../rules/rule.dart';

/// Where an on-device library is kept: a file on Android, browser storage
/// on the web.
abstract interface class LocalStorage {
  /// Null when nothing is stored under [key].
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  /// Keys written by someone else sharing this storage, such as another
  /// browser tab. Empty where nothing else can write.
  Stream<String> watchExternalChanges();
}

/// A library kept only on this device, used without a Firebase project or
/// an account. Held in memory and written to [LocalStorage] after every
/// change.
class LocalLibrary {
  LocalLibrary._(this._storage);

  static const libraryKey = 'capsula_library';
  static const contentKey = 'capsula_content_index';

  /// The previous good copy of the library, kept in case the current one
  /// can't be read.
  static const backupKey = 'capsula_library_backup';

  /// A library that couldn't be read, kept rather than overwritten.
  static const unreadableKey = 'capsula_library_unreadable';

  /// Loads the library saved in [storage], or starts an empty one.
  static Future<LocalLibrary> open(LocalStorage storage) async {
    final library = LocalLibrary._(storage);
    await library._load();
    library._external = storage.watchExternalChanges().listen((key) {
      if (key == libraryKey || key == contentKey) library._refresh();
    });
    return library;
  }

  StreamSubscription<String>? _external;

  /// Whether the saved library couldn't be read and its backup copy was
  /// loaded instead.
  bool get restoredFromBackup => _restoredFromBackup;
  bool _restoredFromBackup = false;

  /// Stops following changes made by other tabs.
  Future<void> close() async => _external?.cancel();

  final LocalStorage _storage;
  final _bookmarks = InMemoryBookmarkRepository();
  late final _labels = InMemoryLabelRepository(_bookmarks);
  final _highlights = InMemoryHighlightRepository();
  final _sources = InMemorySourceRepository();
  final _rules = InMemoryRuleRepository();
  int _schemaVersion = 1;
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
    sourceRepository: _LocalSources(this),
    ruleRepository: _LocalRules(this),
    libraryMeta: _LocalMeta(this),
  );

  // ---------------------------------------------------------------------------
  // Saving

  // Several tabs (or the share window and the app) can use one stored
  // library. Each keeps its own copy in memory, so every save first checks
  // the stored revision: if someone else saved in between, their version is
  // merged in, keeping this copy's own changes, before writing.

  Future<void> _saved = Future.value();

  /// IDs of items changed (or deleted) here since the last save, per part
  /// of the library.
  final _touched = <String, Set<String>>{
    for (final part in _parts) part: <String>{},
  };
  static const _parts = [
    'bookmarks',
    'labels',
    'highlights',
    'sources',
    'rules',
    'meta',
    'content',
  ];
  static const _libraryParts = [
    'bookmarks',
    'labels',
    'highlights',
    'sources',
    'rules',
    'meta',
  ];

  /// Revision of the stored library this copy last read or wrote.
  int _revision = 0;
  int _contentRevision = 0;

  /// Saves after a change to items [ids] of [part]. Completes once a save
  /// that includes it is done, so callers that await a write know it's
  /// stored. Saves run one at a time; changes made while one runs share
  /// the next. A failed save keeps the changes and retries with the next.
  Future<void> _changed(String part, Iterable<String> ids) {
    _touched[part]!.addAll(ids);
    return _saved = _saved.catchError((Object _) {}).then((_) => _save());
  }

  Future<void> _save() async {
    if (_libraryParts.any((part) => _touched[part]!.isNotEmpty)) {
      final raw = await _storage.read(libraryKey);
      final stored = raw == null ? null : _decode(raw);
      final storedRevision = _revisionOf(stored);
      if (stored != null && storedRevision != _revision) _mergeLibrary(stored);
      final saving = {
        for (final part in _libraryParts) part: {..._touched[part]!},
      };
      for (final part in saving.keys) {
        _touched[part]!.clear();
      }
      try {
        if (stored != null) await _storage.write(backupKey, raw!);
        await _storage.write(
          libraryKey,
          jsonEncode(_libraryJson(storedRevision + 1)),
        );
        _revision = storedRevision + 1;
      } on Object {
        saving.forEach((part, ids) => _touched[part]!.addAll(ids));
        rethrow;
      }
    }
    if (_touched['content']!.isNotEmpty) {
      final raw = await _storage.read(contentKey);
      final stored = raw == null ? null : _decode(raw);
      final storedRevision = _revisionOf(stored);
      if (stored != null && storedRevision != _contentRevision) {
        _mergeContent(stored);
      }
      final saving = {..._touched['content']!};
      _touched['content']!.clear();
      try {
        await _storage.write(
          contentKey,
          jsonEncode({'revision': storedRevision + 1, 'pages': _content.items}),
        );
        _contentRevision = storedRevision + 1;
      } on Object {
        _touched['content']!.addAll(saving);
        rethrow;
      }
    }
  }

  /// Picks up a save made elsewhere (another tab), keeping changes made
  /// here that aren't saved yet.
  void _refresh() {
    _saved = _saved.catchError((Object _) {}).then((_) async {
      final raw = await _storage.read(libraryKey);
      final stored = raw == null ? null : _decode(raw);
      if (stored != null && _revisionOf(stored) != _revision) {
        _mergeLibrary(stored);
        _revision = _revisionOf(stored);
      }
      final content = await _storage.read(contentKey);
      final storedContent = content == null ? null : _decode(content);
      if (storedContent != null &&
          _revisionOf(storedContent) != _contentRevision) {
        _mergeContent(storedContent);
        _contentRevision = _revisionOf(storedContent);
      }
    });
  }

  static Map<String, Object?>? _decode(String raw) {
    try {
      return jsonDecode(raw) as Map<String, Object?>;
    } on Object {
      return null;
    }
  }

  static int _revisionOf(Map<String, Object?>? json) =>
      json?['revision'] as int? ?? 0;

  /// Takes everything from [stored] except items changed here, which keep
  /// this copy's version (or stay deleted).
  void _mergeLibrary(Map<String, Object?> stored) {
    void merge<T>(Map<String, T> mine, Map<String, T> theirs, String part) {
      final touched = _touched[part]!;
      final kept = {for (final id in touched) id: ?mine[id]};
      mine
        ..clear()
        ..addAll({
          for (final MapEntry(:key, :value) in theirs.entries)
            if (!touched.contains(key)) key: value,
        })
        ..addAll(kept);
    }

    final theirs = _LibraryData.fromJson(stored);
    merge(_bookmarks.items, theirs.bookmarks, 'bookmarks');
    merge(_labels.items, theirs.labels, 'labels');
    merge(_highlights.items, theirs.highlights, 'highlights');
    merge(_sources.items, theirs.sources, 'sources');
    merge(_rules.items, theirs.rules, 'rules');
    if (theirs.schemaVersion > _schemaVersion) {
      _schemaVersion = theirs.schemaVersion;
    }
    _bookmarks.addAll(const []);
    _labels.addAll(const []);
    _highlights.addAll(const []);
    _sources.addAll(const []);
    _rules.addAll(const []);
  }

  void _mergeContent(Map<String, Object?> stored) {
    final touched = _touched['content']!;
    final theirs = _contentFromJson(stored);
    final kept = {for (final id in touched) id: ?_content.items[id]};
    _content.items
      ..clear()
      ..addAll({
        for (final MapEntry(:key, :value) in theirs.entries)
          if (!touched.contains(key)) key: value,
      })
      ..addAll(kept);
  }

  static String _time(DateTime d) => d.toUtc().toIso8601String();

  static DateTime? _readTime(Object? v) =>
      v is String ? DateTime.tryParse(v)?.toLocal() : null;

  Map<String, Object?> _libraryJson(int revision) => {
    'version': 1,
    'revision': revision,
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
    'sources': {for (final s in _sources.items.values) s.id: encodeSource(s)},
    'rules': {for (final r in _rules.items.values) r.id: r.toJson()},
    'schemaVersion': _schemaVersion,
  };

  Future<void> _load() async {
    final raw = await _storage.read(libraryKey);
    if (raw != null) {
      var json = _decode(raw);
      if (json == null) {
        // Keep the unreadable copy, then fall back to the last good one.
        await _storage.write(unreadableKey, raw);
        final backup = await _storage.read(backupKey);
        json = backup == null ? null : _decode(backup);
        _restoredFromBackup = json != null;
      }
      if (json != null) {
        final data = _LibraryData.fromJson(json);
        _bookmarks.addAll(data.bookmarks.values);
        _labels.addAll(data.labels.values);
        _highlights.addAll(data.highlights.values);
        _sources.addAll(data.sources.values);
        _rules.addAll(data.rules.values);
        _schemaVersion = data.schemaVersion;
        _revision = _revisionOf(json);
      }
    }
    final content = await _storage.read(contentKey);
    final contentJson = content == null ? null : _decode(content);
    if (contentJson != null) {
      _content.items.addAll(_contentFromJson(contentJson));
      _contentRevision = _revisionOf(contentJson);
    }
  }

  /// Page words by bookmark ID. Older saves stored the map at the top
  /// level, without a revision.
  static Map<String, List<String>> _contentFromJson(Map<String, Object?> json) {
    final pages = json['pages'] is Map<String, Object?>
        ? json['pages']! as Map<String, Object?>
        : json;
    return {
      for (final MapEntry(:key, :value) in pages.entries)
        if (value is List) key: value.cast<String>(),
    };
  }
}

/// The parts of a stored library, read from its JSON.
class _LibraryData {
  _LibraryData.fromJson(Map<String, Object?> json)
    : bookmarks = {
        for (final MapEntry(:key, :value) in _entries(json['bookmarks']))
          key: decodeBookmark(key, value, LocalLibrary._readTime),
      },
      labels = {
        for (final MapEntry(:key, :value) in _entries(json['labels']))
          key: Label(
            id: key,
            kind: LabelKind.values.asNameMap()[value['kind']] ?? LabelKind.tag,
            name: value['name'] as String? ?? '',
            parentId: value['parentId'] as String?,
          ),
      },
      highlights = {
        for (final MapEntry(:key, :value) in _entries(json['highlights']))
          key: decodeHighlight(key, value, LocalLibrary._readTime),
      },
      sources = {
        for (final MapEntry(:key, :value) in _entries(json['sources']))
          key: decodeSource(key, value),
      },
      rules = {
        for (final MapEntry(:key, :value) in _entries(json['rules']))
          key: Rule.fromJson(key, value),
      },
      schemaVersion = json['schemaVersion'] as int? ?? 1;

  final Map<String, Bookmark> bookmarks;
  final Map<String, Label> labels;
  final Map<String, Highlight> highlights;
  final Map<String, CustomSource> sources;
  final Map<String, Rule> rules;
  final int schemaVersion;

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

  Future<void> _changed(Iterable<String> ids) =>
      _library._changed('bookmarks', ids);

  @override
  String newId() => _newId();

  @override
  Future<void> create(Bookmark bookmark) async {
    await _inner.create(bookmark);
    await _changed([bookmark.id]);
  }

  @override
  Future<void> update(Bookmark bookmark) async {
    await _inner.update(bookmark);
    await _changed([bookmark.id]);
  }

  @override
  Future<void> modify(
    String id,
    Bookmark Function(Bookmark current) change,
  ) async {
    await _inner.modify(id, change);
    await _changed([id]);
  }

  @override
  Future<void> modifyMany(
    Iterable<String> ids,
    Bookmark Function(Bookmark current) change, {
    void Function(int done, int total)? onProgress,
  }) async {
    final all = ids.toList();
    await _inner.modifyMany(all, change, onProgress: onProgress);
    await _changed(all);
  }

  @override
  Future<void> delete(String id) async {
    await _inner.delete(id);
    await _changed([id]);
  }

  @override
  Future<void> deleteMany(Iterable<String> ids) async {
    final all = ids.toList();
    await _inner.deleteMany(all);
    await _changed(all);
  }

  @override
  Future<void> createMany(List<Bookmark> bookmarks) async {
    _inner.addAll(bookmarks);
    await _changed(bookmarks.map((b) => b.id));
  }

  @override
  Stream<bool> watchPendingWrites() => _inner.watchPendingWrites();

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

  Future<void> _changed(Iterable<String> ids) =>
      _library._changed('labels', ids);

  @override
  String newId(LabelKind kind) => _newId();

  @override
  Stream<List<Label>> watch(LabelKind kind) => _inner.watch(kind);

  @override
  Future<void> create(Label label) async {
    await _inner.create(label);
    await _changed([label.id]);
  }

  @override
  Future<void> rename(Label label, String name) async {
    await _inner.rename(label, name);
    await _changed([label.id]);
  }

  @override
  Future<void> setParent(Label label, String? parentId) async {
    await _inner.setParent(label, parentId);
    await _changed([label.id]);
  }

  @override
  Future<void> delete(Label label) async {
    // Deleting a label also moves its children and untags bookmarks.
    final children = [
      for (final l in _inner.items.values)
        if (l.parentId == label.id) l.id,
    ];
    final tagged = [
      for (final b in _library._bookmarks.items.values)
        if (b.labelIds(label.kind).contains(label.id)) b.id,
    ];
    await _inner.delete(label);
    _library._touched['bookmarks']!.addAll(tagged);
    await _changed([label.id, ...children]);
  }
}

class _LocalHighlights implements HighlightRepository {
  _LocalHighlights(this._library);

  final LocalLibrary _library;
  InMemoryHighlightRepository get _inner => _library._highlights;

  Future<void> _changed(Iterable<String> ids) =>
      _library._changed('highlights', ids);

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
    await _changed([highlight.id]);
  }

  @override
  Future<void> delete(String id) async {
    await _inner.delete(id);
    await _changed([id]);
  }

  @override
  Future<void> deleteForBookmark(String bookmarkId) async {
    final ids = [
      for (final h in _inner.items.values)
        if (h.bookmarkId == bookmarkId) h.id,
    ];
    await _inner.deleteForBookmark(bookmarkId);
    await _changed(ids);
  }
}

class _LocalContent implements ContentIndex {
  _LocalContent(this._library);

  final LocalLibrary _library;
  InMemoryContentIndex get _inner => _library._content;

  @override
  Future<void> save(String bookmarkId, List<String> words) async {
    await _inner.save(bookmarkId, words);
    await _library._changed('content', [bookmarkId]);
  }

  @override
  Future<List<String>> search(String query, {int limit = 50}) =>
      _inner.search(query, limit: limit);

  @override
  Future<void> delete(String bookmarkId) async {
    await _inner.delete(bookmarkId);
    await _library._changed('content', [bookmarkId]);
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

class _LocalSources implements SourceRepository {
  _LocalSources(this._library);

  final LocalLibrary _library;
  InMemorySourceRepository get _inner => _library._sources;

  @override
  String newId() => _newId();

  @override
  Stream<List<CustomSource>> watch() => _inner.watch();

  @override
  Future<void> create(CustomSource source) async {
    await _inner.create(source);
    await _library._changed('sources', [source.id]);
  }

  @override
  Future<void> update(CustomSource source) async {
    await _inner.update(source);
    await _library._changed('sources', [source.id]);
  }

  @override
  Future<void> delete(String id) async {
    await _inner.delete(id);
    await _library._changed('sources', [id]);
  }
}

class _LocalRules implements RuleRepository {
  _LocalRules(this._library);

  final LocalLibrary _library;
  InMemoryRuleRepository get _inner => _library._rules;

  @override
  String newId() => _newId();

  @override
  Stream<List<Rule>> watch() => _inner.watch();

  @override
  Future<void> create(Rule rule) async {
    await _inner.create(rule);
    await _library._changed('rules', [rule.id]);
  }

  @override
  Future<void> update(Rule rule) async {
    await _inner.update(rule);
    await _library._changed('rules', [rule.id]);
  }

  @override
  Future<void> delete(String id) async {
    await _inner.delete(id);
    await _library._changed('rules', [id]);
  }
}

class _LocalMeta implements LibraryMetaRepository {
  _LocalMeta(this._library);

  final LocalLibrary _library;

  @override
  Future<int> schemaVersion() async => _library._schemaVersion;

  @override
  Future<void> setSchemaVersion(int version) async {
    _library._schemaVersion = version;
    await _library._changed('meta', ['schema']);
  }
}
