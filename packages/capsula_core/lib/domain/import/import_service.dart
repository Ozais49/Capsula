import '../bookmarks/bookmark.dart';
import '../bookmarks/bookmark_patch.dart';
import '../bookmarks/bookmark_repository.dart';
import '../bookmarks/bookmark_source.dart';
import '../bookmarks/url_normalizer.dart';
import '../organization/label.dart';
import '../sources/custom_source.dart';
import 'imported_item.dart';

/// An item that passed validation and isn't in the library yet.
class PlannedItem {
  const PlannedItem(this.item, this.uri, this.canonicalUrl);

  final ImportedItem item;
  final Uri uri;
  final String canonicalUrl;
}

/// What an import would do, shown to the user before anything is written.
class ImportPlan {
  const ImportPlan({
    required this.found,
    required this.newItems,
    required this.alreadySaved,
    required this.repeatedInFile,
    required this.invalid,
  });

  /// Links found in the file.
  final int found;
  final List<PlannedItem> newItems;

  /// Already in the library.
  final int alreadySaved;

  /// Same link appearing more than once in the file.
  final int repeatedInFile;

  /// Entries whose URL isn't a web address.
  final List<String> invalid;

  int get duplicates => alreadySaved + repeatedInFile;

  Set<String> get folders => {for (final p in newItems) ?p.item.folder};

  Set<String> get tags => {for (final p in newItems) ...p.item.tags};
}

class ImportOptions {
  const ImportOptions({
    this.addToInbox = true,
    this.foldersAsCollections = true,
    this.keepTags = true,
  });

  final bool addToInbox;
  final bool foldersAsCollections;
  final bool keepTags;
}

class ImportResult {
  const ImportResult({
    required this.imported,
    required this.duplicates,
    required this.invalid,
    required this.failed,
  });

  final int imported;
  final int duplicates;
  final int invalid;

  /// Bookmarks that couldn't be written (e.g. connection lost mid-import).
  /// Running the import again adds only these, since the rest are duplicates.
  final int failed;
}

class ImportService {
  ImportService(
    this._bookmarks,
    this._labels, {
    this._sources,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  final SourceRepository? _sources;
  final BookmarkRepository _bookmarks;
  final LabelRepository _labels;
  final DateTime Function() _now;

  static const batchSize = 400;

  Future<ImportPlan> plan(List<ImportedItem> items) async {
    final invalid = <String>[];
    final unique = <String, PlannedItem>{};
    var repeated = 0;

    for (final item in items) {
      final uri = parseWebUrl(item.url);
      if (uri == null || item.url.length > 4096) {
        invalid.add(item.url);
        continue;
      }
      final canonical = canonicalizeUrl(uri);
      if (unique.containsKey(canonical)) {
        repeated++;
        continue;
      }
      unique[canonical] = PlannedItem(item, uri, canonical);
    }

    final existing = await _bookmarks.existingCanonicalUrls(unique.keys);
    return ImportPlan(
      found: items.length,
      newItems: [
        for (final p in unique.values)
          if (!existing.contains(p.canonicalUrl)) p,
      ],
      alreadySaved: existing.length,
      repeatedInFile: repeated,
      invalid: invalid,
    );
  }

  Future<ImportResult> run(
    ImportPlan plan, {
    required ImportOrigin origin,
    ImportOptions options = const ImportOptions(),
    List<Label> existingLabels = const [],
    void Function(int done, int total)? onProgress,
  }) async {
    final now = _now();
    final collections = options.foldersAsCollections
        ? await _ensureLabels(
            LabelKind.collection,
            plan.folders,
            existingLabels,
          )
        : const <String, String>{};
    final tags = options.keepTags
        ? await _ensureLabels(LabelKind.tag, plan.tags, existingLabels)
        : const <String, String>{};

    final custom = await _sources?.watch().first ?? const <CustomSource>[];
    final bookmarks = [
      for (final p in plan.newItems)
        _toBookmark(p, origin, options, now, collections, tags, custom),
    ];

    var imported = 0;
    var failed = 0;
    onProgress?.call(0, bookmarks.length);
    for (var i = 0; i < bookmarks.length; i += batchSize) {
      final batch = bookmarks.sublist(
        i,
        (i + batchSize).clamp(0, bookmarks.length),
      );
      try {
        await _bookmarks.createMany(batch);
        imported += batch.length;
      } on Object {
        failed += batch.length;
      }
      onProgress?.call(imported + failed, bookmarks.length);
    }

    return ImportResult(
      imported: imported,
      duplicates: plan.duplicates,
      invalid: plan.invalid.length,
      failed: failed,
    );
  }

  /// Maps lowercased names to label IDs, creating labels that don't exist.
  Future<Map<String, String>> _ensureLabels(
    LabelKind kind,
    Set<String> names,
    List<Label> existing,
  ) async {
    final ids = {
      for (final l in existing.where((l) => l.kind == kind))
        l.name.toLowerCase(): l.id,
    };
    for (final raw in names) {
      final name = normalizeLabelName(raw);
      if (name == null || ids.containsKey(name.toLowerCase())) continue;
      final label = Label(id: _labels.newId(kind), kind: kind, name: name);
      await _labels.create(label);
      ids[name.toLowerCase()] = label.id;
    }
    return ids;
  }

  Bookmark _toBookmark(
    PlannedItem p,
    ImportOrigin origin,
    ImportOptions options,
    DateTime now,
    Map<String, String> collections,
    Map<String, String> tags,
    List<CustomSource> custom,
  ) {
    String? idFor(Map<String, String> ids, String? name) {
      final normalized = name == null ? null : normalizeLabelName(name);
      return normalized == null ? null : ids[normalized.toLowerCase()];
    }

    final host = displayHost(p.uri);
    final title = p.item.title?.trim();
    final description = p.item.description?.trim();
    return Bookmark(
      id: bookmarkIdFor(p.canonicalUrl),
      url: p.uri.toString(),
      canonicalUrl: p.canonicalUrl,
      title: title == null || title.isEmpty
          ? titleFromUrl(p.uri)
          : _clip(title, 1000),
      description: description == null || description.isEmpty
          ? null
          : _clip(description, 2000),
      source: BookmarkSource.fromHost(host),
      customSourceId: detectCustomSource(host, custom),
      sourceDomain: host,
      createdAt: p.item.createdAt ?? now,
      updatedAt: now,
      inInbox: options.addToInbox,
      collectionIds: [?idFor(collections, p.item.folder)],
      tagIds: {for (final t in p.item.tags) ?idFor(tags, t)}.take(100).toList(),
      importedFrom: origin.label,
      importedAt: now,
    );
  }

  static String _clip(String text, int max) =>
      text.length <= max ? text : text.substring(0, max);
}
