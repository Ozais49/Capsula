import '../highlights/highlight.dart';
import '../organization/label.dart';
import '../reader/page_info_service.dart';
import '../search/full_text.dart';
import '../sources/custom_source.dart';
import '../meta/library_meta.dart';
import '../rules/rule.dart';
import 'content_type.dart';
import '../reader/reader_content.dart';
import 'bookmark.dart';
import 'bookmark_patch.dart';
import 'bookmark_repository.dart';
import 'bookmark_source.dart';
import 'bookmark_view.dart';
import 'url_normalizer.dart';

sealed class SaveResult {
  const SaveResult();
}

class Saved extends SaveResult {
  const Saved(this.bookmark, this.committed);

  final Bookmark bookmark;

  /// Completes when the backend accepts the bookmark; fails if it rejects it.
  /// The bookmark is already visible locally before this completes.
  final Future<void> committed;
}

class AlreadySaved extends SaveResult {
  const AlreadySaved(this.existing);

  final Bookmark existing;
}

class InvalidUrl extends SaveResult {
  const InvalidUrl();
}

/// Bookmark use cases. Saving never waits on metadata or the network.
class BookmarkService {
  BookmarkService(
    this._repository,
    this._labels, {
    this._highlights,
    this._contentIndex,
    this._sources,
    this._rules,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final RuleRepository? _rules;

  RuleRepository get rules =>
      _rules ?? (throw StateError('No rule repository'));

  final SourceRepository? _sources;

  SourceRepository get sources =>
      _sources ?? (throw StateError('No source repository'));

  final ContentIndex? _contentIndex;

  bool get hasContentIndex => _contentIndex != null;

  final HighlightRepository? _highlights;

  HighlightRepository get highlights =>
      _highlights ?? (throw StateError('No highlight repository'));

  final BookmarkRepository _repository;
  final LabelRepository _labels;
  final DateTime Function() _now;

  BookmarkRepository get repository => _repository;
  LabelRepository get labels => _labels;

  Future<SaveResult> save(String input, {String? title}) async {
    final uri = parseWebUrl(input);
    if (uri == null) return const InvalidUrl();

    final canonicalUrl = canonicalizeUrl(uri);
    final existing = await _repository.findByCanonicalUrl(canonicalUrl);
    if (existing != null && existing.isTrashed) {
      // Saving a link that is in the Trash brings it back.
      final restored = _restored(existing).copyWith(updatedAt: _now());
      return Saved(restored, restore([existing])..ignore());
    }
    if (existing != null) return AlreadySaved(existing);

    final now = _now();
    final host = displayHost(uri);
    final rules = await _activeRules();
    final bookmark = applyRules(
      Bookmark(
        id: bookmarkIdFor(canonicalUrl),
        url: uri.toString(),
        canonicalUrl: canonicalUrl,
        title: (title?.trim().isNotEmpty ?? false)
            ? title!.trim()
            : titleFromUrl(uri),
        source: BookmarkSource.fromHost(host),
        customSourceId: detectCustomSource(host, await _customSources()),
        sourceDomain: host,
        createdAt: now,
        updatedAt: now,
      ),
      rules,
    );
    // Callers may not wait for the backend; ignore() keeps an unobserved
    // failure from surfacing as an unhandled error.
    return Saved(bookmark, _repository.create(bookmark)..ignore());
  }

  /// Applies [change] to the stored bookmark, writing only what it changes
  /// and stamping the time of the change.
  Future<void> _modify(
    Bookmark bookmark,
    Bookmark Function(Bookmark b) change,
  ) => _repository.modify(
    bookmark.id,
    (b) => change(b).copyWith(updatedAt: _now()),
  );

  Future<void> setReadingStatus(Bookmark bookmark, ReadingStatus status) =>
      _modify(bookmark, (b) => b.copyWith(readingStatus: status));

  /// Archiving also takes the bookmark out of the Inbox.
  Future<void> setArchived(Bookmark bookmark, bool archived) => _modify(
    bookmark,
    (b) =>
        b.copyWith(archived: archived, inInbox: archived ? false : b.inInbox),
  );

  Future<void> rename(Bookmark bookmark, String title) =>
      _modify(bookmark, (b) => b.copyWith(title: title.trim()));

  /// Sets a reminder, or clears it when [when] is null.
  Future<void> setReminder(Bookmark bookmark, DateTime? when) => _modify(
    bookmark,
    (b) => b.copyWith(remindAt: when, clearReminder: when == null),
  );

  Future<void> setFavorite(Bookmark bookmark, bool favorite) =>
      _modify(bookmark, (b) => b.copyWith(favorite: favorite));

  /// Applies [change] to every bookmark in [bookmarks] (bulk edit), in
  /// batches. [change] receives the latest stored copy of each one.
  Future<void> updateMany(
    Iterable<Bookmark> bookmarks,
    Bookmark Function(Bookmark b) change, {
    void Function(int done, int total)? onProgress,
  }) => _repository.modifyMany(
    bookmarks.map((b) => b.id),
    (b) => change(b).copyWith(updatedAt: _now()),
    onProgress: onProgress,
  );

  /// Adds [labelId] to every bookmark that doesn't have it yet.
  Future<void> addLabelToMany(
    Iterable<Bookmark> bookmarks,
    LabelKind kind,
    String labelId,
  ) => _repository.modifyMany(
    bookmarks
        .where((b) => !b.labelIds(kind).contains(labelId))
        .map((b) => b.id),
    (b) => b.labelIds(kind).contains(labelId)
        ? b
        : _withLabels(b, kind, [...b.labelIds(kind), labelId]),
  );

  /// Rewrites stored fields derived from each bookmark (type, search
  /// words) where they are out of date. Returns how many were checked.
  Future<int> reindexAll({
    void Function(int done, int total)? onProgress,
  }) async {
    final all = await _repository.fetchAll();
    onProgress?.call(0, all.length);
    await _repository.modifyMany(
      all.map((b) => b.id),
      (b) => b,
      onProgress: onProgress,
    );
    return all.length;
  }

  /// Deletes the bookmarks, their highlights and their saved page text.
  Future<void> deleteMany(Iterable<Bookmark> bookmarks) async {
    final ids = bookmarks.map((b) => b.id).toList();
    await _repository.deleteMany(ids);
    for (final id in ids) {
      await _highlights?.deleteForBookmark(id);
      await _contentIndex?.delete(id);
    }
  }

  Future<void> setInInbox(Bookmark bookmark, bool inInbox) =>
      _modify(bookmark, (b) => b.copyWith(inInbox: inInbox));

  /// Gives [bookmark] exactly [labelIds] of [kind], as the user chose them
  /// starting from [bookmark]. Labels added or removed meanwhile elsewhere
  /// are kept that way: only the user's own additions and removals apply.
  Future<void> setLabels(
    Bookmark bookmark,
    LabelKind kind,
    Iterable<String> labelIds,
  ) {
    final chosen = labelIds.toSet();
    final before = bookmark.labelIds(kind).toSet();
    final added = chosen.difference(before);
    final removed = before.difference(chosen);
    return _modify(
      bookmark,
      (b) => _withLabels(b, kind, [
        for (final id in b.labelIds(kind))
          if (!removed.contains(id)) id,
        for (final id in added)
          if (!b.labelIds(kind).contains(id)) id,
      ]),
    );
  }

  static Bookmark _withLabels(Bookmark b, LabelKind kind, List<String> ids) =>
      switch (kind) {
        LabelKind.tag => b.copyWith(tagIds: ids),
        LabelKind.collection => b.copyWith(collectionIds: ids),
      };

  // ---------------------------------------------------------------------------
  // Rules

  /// The rules last read, for work that can't wait to read them.
  List<Rule> _cachedRules = const [];

  /// The user's enabled rules, or none when they can't be read quickly (so
  /// saving never waits on them).
  Future<List<Rule>> _activeRules() async {
    final rules = _rules;
    if (rules == null) return const [];
    try {
      final all = await rules.watch().first.timeout(const Duration(seconds: 2));
      return _cachedRules = [
        for (final r in all)
          if (r.enabled) r,
      ];
    } on Object {
      return _cachedRules;
    }
  }

  /// Checks a rule. Returns the cleaned-up rule, or a message saying
  /// what's wrong.
  (Rule?, String?) _validRule(Rule rule) {
    final name = normalizeLabelName(rule.name);
    if (name == null) return (null, 'Enter a name');
    final conditions = [
      for (final c in rule.conditions)
        if (c.value.trim().isNotEmpty)
          RuleCondition(c.field, c.op, c.value.trim()),
    ];
    if (conditions.isEmpty) return (null, 'Add a condition');
    if (conditions.length > maxRuleConditions) {
      return (null, 'At most $maxRuleConditions conditions');
    }
    for (final c in conditions) {
      if (c.value.length > maxRuleValueLength) {
        return (
          null,
          'Conditions are limited to $maxRuleValueLength characters',
        );
      }
      if (c.op == RuleOp.matches) {
        try {
          RegExp(c.value);
        } on FormatException {
          return (null, '"${c.value}" is not a valid pattern');
        }
      }
    }
    final valid = rule.copyWith(name: name, conditions: conditions);
    if (!valid.hasActions) {
      return (null, 'Choose tags, a collection or a star to add');
    }
    return (valid, null);
  }

  /// Creates or updates [rule]. Returns an error message, or null when it
  /// was saved. Saved bookmarks only get its actions with
  /// [applyRulesToAll].
  Future<String?> saveRule(Rule rule, {bool isNew = false}) async {
    final (valid, error) = _validRule(rule);
    if (valid == null) return error;
    await (isNew ? rules.create(valid) : rules.update(valid));
    return null;
  }

  Future<void> deleteRule(Rule rule) => rules.delete(rule.id);

  /// Runs the enabled rules over every bookmark not in the Trash. Rules
  /// only add, so running this again changes nothing more. Returns how many
  /// bookmarks changed.
  Future<int> applyRulesToAll({
    void Function(int done, int total)? onProgress,
  }) async {
    final active = await _activeRules();
    if (active.isEmpty) return 0;
    final changed = (await _repository.fetchAll())
        .where((b) => !b.isTrashed && !identical(applyRules(b, active), b))
        .toList();
    await _repository.modifyMany(changed.map((b) => b.id), (b) {
      final ruled = applyRules(b, active);
      return identical(ruled, b) ? b : ruled.copyWith(updatedAt: _now());
    }, onProgress: onProgress);
    return changed.length;
  }

  /// The shape of library data this version of the app writes.
  static const schemaVersion = 3;

  /// Brings a library up to [schemaVersion]:
  ///
  /// - 2: the fixed content types become tags: a tag and an editable rule
  ///   for each kind (Video, Image, Document, Post, Product), and existing
  ///   bookmarks tagged by their kind.
  /// - 3: every bookmark stores whether it is unsorted, so Unsorted can be
  ///   queried.
  ///
  /// Every step can run again harmlessly, so a migration interrupted by a
  /// crash or lost connection, or running on two devices at once, finishes
  /// correctly next time. Returns whether anything was done.
  Future<bool> upgradeLibrary(LibraryMetaRepository meta) async {
    final from = await meta.schemaVersion();
    if (from >= schemaVersion) return false;
    if (from < 2) await _typesToTags();
    if (from < 3) {
      // Rewrites stored fields derived from each bookmark, adding
      // `unsorted`.
      await _repository.modifyMany(
        (await _repository.fetchAll()).map((b) => b.id),
        (b) => b,
      );
    }
    await meta.setSchemaVersion(schemaVersion);
    return true;
  }

  Future<void> _typesToTags() async {
    final tags = await _labels.watch(LabelKind.tag).first;
    final existingRules = await rules.watch().first;
    final tagFor = <ContentType, String>{};
    for (final kind in kindsWithDefaultRules) {
      final name = kindTagName(kind);
      final existing = tags
          .where((t) => t.name.toLowerCase() == name.toLowerCase())
          .firstOrNull;
      // Fixed IDs, so two devices migrating at once create one tag.
      final tagId = existing?.id ?? defaultRuleId(kind);
      if (existing == null) {
        await _labels.create(Label(id: tagId, kind: LabelKind.tag, name: name));
      }
      tagFor[kind] = tagId;
      if (!existingRules.any((r) => r.id == defaultRuleId(kind))) {
        await rules.create(
          Rule(
            id: defaultRuleId(kind),
            name: '${name}s',
            conditions: [
              RuleCondition(RuleField.kind, RuleOp.isEqual, kind.name),
            ],
            tagIds: [tagId],
          ),
        );
      }
    }
    final toTag = (await _repository.fetchAll())
        .where((b) => tagFor.containsKey(b.type))
        .where((b) => !b.tagIds.contains(tagFor[b.type]))
        .map((b) => b.id);
    await _repository.modifyMany(toTag, (b) {
      final tag = tagFor[b.type];
      return tag == null || b.tagIds.contains(tag)
          ? b
          : b.copyWith(tagIds: [...b.tagIds, tag], updatedAt: _now());
    });
  }

  // ---------------------------------------------------------------------------
  // Sources

  /// The user's own sources, or none when they can't be read quickly (so
  /// saving never waits on them).
  Future<List<CustomSource>> _customSources() async {
    final sources = _sources;
    if (sources == null) return const [];
    try {
      return await sources.watch().first.timeout(const Duration(seconds: 2));
    } on Object {
      return const [];
    }
  }

  /// Checks a source's name and domains. Returns the cleaned-up source, or
  /// a message saying what's wrong.
  (CustomSource?, String?) _validSource(
    CustomSource source,
    List<CustomSource> existing,
  ) {
    final name = normalizeLabelName(source.name);
    if (name == null) return (null, 'Enter a name');
    final builtIn = BookmarkSource.values.any(
      (s) => s.label.toLowerCase() == name.toLowerCase(),
    );
    final taken = existing.any(
      (s) => s.id != source.id && s.name.toLowerCase() == name.toLowerCase(),
    );
    if (builtIn || taken) return (null, '"$name" is already a source');
    final domains = <String>{};
    for (final d in source.domains) {
      final domain = normalizeSourceDomain(d);
      if (domain == null) return (null, '"${d.trim()}" is not a domain');
      domains.add(domain);
    }
    if (domains.isEmpty) return (null, 'Enter at least one domain');
    if (domains.length > maxSourceDomains) {
      return (null, 'At most $maxSourceDomains domains');
    }
    return (source.copyWith(name: name, domains: domains.toList()), null);
  }

  /// Adds a source. Returns an error message, or null when it was added.
  /// Existing bookmarks only move to it with [redetectSources].
  Future<String?> addSource(
    String name,
    List<String> domains,
    List<CustomSource> existing,
  ) async {
    final (source, error) = _validSource(
      CustomSource(id: sources.newId(), name: name, domains: domains),
      existing,
    );
    if (source == null) return error;
    await sources.create(source);
    return null;
  }

  /// Saves a new name or domains. Returns an error message, or null.
  Future<String?> updateSource(
    CustomSource source,
    List<CustomSource> existing,
  ) async {
    final (valid, error) = _validSource(source, existing);
    if (valid == null) return error;
    await sources.update(valid);
    return null;
  }

  /// Deletes a source; its bookmarks show their built-in source again.
  Future<void> deleteSource(CustomSource source) async {
    final from = (await _repository.fetchAll()).where(
      (b) => b.customSourceId == source.id,
    );
    await _repository.modifyMany(
      from.map((b) => b.id),
      (b) => b.customSourceId == source.id
          ? b.copyWith(clearCustomSource: true, updatedAt: _now())
          : b,
    );
    await sources.delete(source.id);
  }

  /// Detects the source of every bookmark again, for example after adding
  /// a source or changing its domains. Only bookmarks whose source changes
  /// are written; running it twice changes nothing more. Returns how many
  /// bookmarks changed.
  Future<int> redetectSources({
    void Function(int done, int total)? onProgress,
  }) async {
    final custom = await _customSources();
    String? detect(Bookmark b) => detectCustomSource(b.sourceDomain, custom);
    final changed = (await _repository.fetchAll())
        .where((b) => b.customSourceId != detect(b))
        .toList();
    await _repository.modifyMany(changed.map((b) => b.id), (b) {
      final id = detect(b);
      if (id == b.customSourceId) return b;
      return id == null
          ? b.copyWith(clearCustomSource: true, updatedAt: _now())
          : b.copyWith(customSourceId: id, updatedAt: _now());
    }, onProgress: onProgress);
    return changed.length;
  }

  /// Days a bookmark stays in the Trash before it is deleted for good.
  static const trashDays = 30;

  /// Moves bookmarks to the Trash. They keep their tags, collections,
  /// highlights and page text until deleted for good.
  Future<void> moveToTrash(Iterable<Bookmark> bookmarks) {
    final now = _now();
    return updateMany(
      bookmarks,
      (b) => b.isTrashed
          ? b
          : b.copyWith(archived: true, inInbox: false, deletedAt: now),
    );
  }

  /// Takes bookmarks out of the Trash, back into the library. Given the
  /// copies from before they were trashed (to undo a move), they get back
  /// exactly where they were, archived or in the Inbox.
  Future<void> restore(Iterable<Bookmark> bookmarks) {
    final before = {for (final b in bookmarks) b.id: b};
    return updateMany(bookmarks, (current) {
      final was = before[current.id];
      if (!current.isTrashed || was == null || was.isTrashed) {
        return _restored(current);
      }
      return current.copyWith(
        archived: was.archived,
        inInbox: was.inInbox,
        clearDeletedAt: true,
      );
    });
  }

  static Bookmark _restored(Bookmark b) =>
      b.isTrashed ? b.copyWith(archived: false, clearDeletedAt: true) : b;

  /// Every bookmark in the Trash.
  Future<List<Bookmark>> _trashed() => _repository
      .watchList(const BookmarkQuery(view: BookmarkView.trash), limit: 100000)
      .first;

  /// Deletes everything in the Trash for good. Returns how many.
  Future<int> emptyTrash() async {
    final trashed = await _trashed();
    await deleteMany(trashed);
    return trashed.length;
  }

  /// Deletes for good bookmarks trashed more than [trashDays] ago. Safe to
  /// run on several devices at once. Returns how many were deleted.
  Future<int> purgeTrash() async {
    final cutoff = _now().subtract(const Duration(days: trashDays));
    final expired = (await _trashed())
        .where((b) => b.deletedAt!.isBefore(cutoff))
        .toList();
    if (expired.isNotEmpty) await deleteMany(expired);
    return expired.length;
  }

  /// Deletes the bookmark for good, with its highlights and page text.
  Future<void> delete(Bookmark bookmark) async {
    await _repository.delete(bookmark.id);
    await _highlights?.deleteForBookmark(bookmark.id);
    await _contentIndex?.delete(bookmark.id);
  }

  /// Stores the words of an article for full-text search. Returns false
  /// when there's nothing to index (not an article, or no index).
  Future<bool> indexContent(Bookmark bookmark, ReaderContent content) async {
    final index = _contentIndex;
    if (index == null || content is! ArticleContent) return false;
    final words = contentWords(articleTexts(content));
    if (words.isEmpty) return false;
    await index.save(bookmark.id, words);
    await _modify(bookmark, (b) => b.copyWith(contentIndexedAt: _now()));
    return true;
  }

  /// Bookmarks in [view] whose saved page contains every word of [query].
  Future<List<Bookmark>> searchContent(
    String query, {
    BookmarkView view = BookmarkView.all,
    int limit = 50,
  }) async {
    final index = _contentIndex;
    if (index == null) return const [];
    final ids = await index.search(query, limit: limit * 2);
    final found = await Future.wait(
      ids.map((id) => _repository.watch(id).first),
    );
    return found.nonNulls
        .where((b) => bookmarkInView(b, view))
        .take(limit)
        .toList();
  }

  /// Sets or, when blank, clears the bookmark's note.
  Future<void> setNote(Bookmark bookmark, String note) {
    final trimmed = note.trim();
    if (trimmed.length > maxNoteLength) {
      throw ArgumentError('Notes are limited to $maxNoteLength characters');
    }
    return _modify(
      bookmark,
      (b) => b.copyWith(
        note: trimmed.isEmpty ? null : trimmed,
        clearNote: trimmed.isEmpty,
      ),
    );
  }

  /// Highlights [text] in [bookmark]. Returns null for an empty selection.
  Highlight? addHighlight(
    Bookmark bookmark,
    String text, {
    HighlightColor color = HighlightColor.yellow,
  }) {
    final normalized = normalizeHighlightText(text);
    if (normalized == null) return null;
    final highlight = Highlight(
      id: highlights.newId(),
      bookmarkId: bookmark.id,
      text: normalized,
      color: color,
      createdAt: _now(),
    );
    highlights.save(highlight).ignore();
    return highlight;
  }

  Future<void> updateHighlight(
    Highlight highlight, {
    String? note,
    HighlightColor? color,
  }) {
    final trimmed = note?.trim();
    return highlights.save(
      highlight.copyWith(
        note: trimmed,
        clearNote: trimmed != null && trimmed.isEmpty,
        color: color,
      ),
    );
  }

  Future<void> deleteHighlight(Highlight highlight) =>
      highlights.delete(highlight.id);

  /// Whether the title was made up by Capsula from the URL, rather than
  /// found on the page or chosen by the user.
  static bool hasAutoTitle(Bookmark bookmark) {
    final uri = Uri.tryParse(bookmark.url);
    return bookmark.title.trim().isEmpty ||
        bookmark.title == bookmark.sourceDomain ||
        (uri != null && bookmark.title == titleFromUrl(uri));
  }

  /// Fills in details found on the page: replaces a title Capsula derived
  /// from the URL (never one the user gave), and adds a missing description
  /// or image. [fallbackTitle] (e.g. text shared along with the link) is
  /// used when the page has no usable title.
  ///
  /// Returns the updated bookmark, or null when nothing changed. The
  /// update is applied locally at once and syncs in the background.
  Bookmark? applyMetadata(
    Bookmark bookmark,
    PageMetadata metadata, {
    String? fallbackTitle,
  }) {
    final rules = _cachedRules;
    final updated = _withMetadata(bookmark, metadata, fallbackTitle);
    if (updated == null) return null;
    // Re-checked against the stored copy, so a title the user typed
    // meanwhile on another device is never replaced. Rules run again, as
    // some look at the title.
    _modify(
      bookmark,
      (b) => applyRules(_withMetadata(b, metadata, fallbackTitle) ?? b, rules),
    ).ignore();
    return applyRules(updated, rules).copyWith(updatedAt: _now());
  }

  Bookmark? _withMetadata(
    Bookmark bookmark,
    PageMetadata metadata,
    String? fallbackTitle,
  ) {
    final title = hasAutoTitle(bookmark)
        ? _clip(metadata.title, 300) ?? _clip(fallbackTitle, 300)
        : null;
    final description = bookmark.description == null
        ? _clip(metadata.description, 500)
        : null;
    final image = metadata.image;
    final imageUrl =
        bookmark.imageUrl == null &&
            image != null &&
            (image.scheme == 'https' || image.scheme == 'http') &&
            image.toString().length <= 2000
        ? image.toString()
        : null;

    if ((title == null || title == bookmark.title) &&
        description == null &&
        imageUrl == null) {
      return null;
    }
    return bookmark.copyWith(
      title: title,
      description: description,
      imageUrl: imageUrl,
    );
  }

  /// Looks up the link's real title and details and saves them.
  Future<Bookmark?> fetchDetails(
    Bookmark bookmark,
    PageInfoSource pageInfo, {
    String? fallbackTitle,
  }) async {
    final uri = Uri.tryParse(bookmark.url);
    if (uri == null) return null;
    final metadata = await pageInfo.lookup(uri) ?? const PageMetadata();
    await _activeRules();
    return applyMetadata(bookmark, metadata, fallbackTitle: fallbackTitle);
  }

  /// Fetches details for recent bookmarks that still have a title
  /// made up from the URL, e.g. ones saved while offline.
  Future<int> backfillDetails(PageInfoSource pageInfo, {int limit = 25}) async {
    final recent = await _repository
        .watchList(const BookmarkQuery(view: BookmarkView.all), limit: limit)
        .first;
    var updated = 0;
    for (final bookmark in recent.where(
      (b) => hasAutoTitle(b) && b.description == null && b.imageUrl == null,
    )) {
      if (await fetchDetails(bookmark, pageInfo) != null) updated++;
    }
    return updated;
  }

  static String? _clip(String? text, int max) {
    final t = text?.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (t == null || t.isEmpty) return null;
    return t.length <= max ? t : '${t.substring(0, max - 1)}…';
  }

  /// Creates a label, or returns the existing one with the same name
  /// (ignoring case). Returns null for a blank name. The label is usable
  /// immediately; the write syncs in the background.
  Label? createLabel(
    LabelKind kind,
    String name,
    List<Label> existing, {
    String? parentId,
  }) {
    final normalized = normalizeLabelName(name);
    if (normalized == null) return null;
    final parent = kind == LabelKind.collection ? parentId : null;
    // Names are unique among siblings: "Papers" may exist under two parents.
    final match = existing.where(
      (l) =>
          l.kind == kind &&
          l.parentId == parent &&
          l.name.toLowerCase() == normalized.toLowerCase(),
    );
    if (match.isNotEmpty) return match.first;

    final label = Label(
      id: _labels.newId(kind),
      kind: kind,
      name: normalized,
      parentId: parent,
    );
    _labels.create(label).ignore();
    return label;
  }

  /// Moves a collection under [parentId] (null for the top level). Returns
  /// false when that would put it inside itself.
  Future<bool> moveCollection(
    Label label,
    String? parentId,
    List<Label> all,
  ) async {
    if (label.kind != LabelKind.collection) return false;
    if (parentId != null &&
        labelWithDescendants(label.id, all).contains(parentId)) {
      return false;
    }
    if (label.parentId == parentId) return true;
    await _labels.setParent(label, parentId);
    return true;
  }

  /// Returns false when [name] is blank or already used by another label.
  Future<bool> renameLabel(
    Label label,
    String name,
    List<Label> existing,
  ) async {
    final normalized = normalizeLabelName(name);
    if (normalized == null) return false;
    final clash = existing.any(
      (l) =>
          l.kind == label.kind &&
          l.id != label.id &&
          l.name.toLowerCase() == normalized.toLowerCase(),
    );
    if (clash) return false;
    await _labels.rename(label, normalized);
    return true;
  }

  Future<void> deleteLabel(Label label) => _labels.delete(label);
}
