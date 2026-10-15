import '../organization/label.dart';
import '../reader/page_info_service.dart';
import '../reader/reader_content.dart';
import 'bookmark.dart';
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
  BookmarkService(this._repository, this._labels, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

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
    if (existing != null) return AlreadySaved(existing);

    final now = _now();
    final host = displayHost(uri);
    final bookmark = Bookmark(
      id: _repository.newId(),
      url: uri.toString(),
      canonicalUrl: canonicalUrl,
      title: (title?.trim().isNotEmpty ?? false)
          ? title!.trim()
          : titleFromUrl(uri),
      source: BookmarkSource.fromHost(host),
      sourceDomain: host,
      createdAt: now,
      updatedAt: now,
    );
    // Callers may not wait for the backend; ignore() keeps an unobserved
    // failure from surfacing as an unhandled error.
    return Saved(bookmark, _repository.create(bookmark)..ignore());
  }

  Future<void> setReadingStatus(Bookmark bookmark, ReadingStatus status) =>
      _repository.update(
        bookmark.copyWith(readingStatus: status, updatedAt: _now()),
      );

  /// Archiving also takes the bookmark out of the Inbox.
  Future<void> setArchived(Bookmark bookmark, bool archived) =>
      _repository.update(
        bookmark.copyWith(
          archived: archived,
          inInbox: archived ? false : bookmark.inInbox,
          updatedAt: _now(),
        ),
      );

  Future<void> rename(Bookmark bookmark, String title) => _repository.update(
    bookmark.copyWith(title: title.trim(), updatedAt: _now()),
  );

  /// Takes the bookmark out of the Inbox ("done organizing"), or puts it back.
  Future<void> setInInbox(Bookmark bookmark, bool inInbox) => _repository
      .update(bookmark.copyWith(inInbox: inInbox, updatedAt: _now()));

  Future<void> setLabels(
    Bookmark bookmark,
    LabelKind kind,
    Iterable<String> labelIds,
  ) {
    final ids = labelIds.toSet().toList();
    return _repository.update(switch (kind) {
      LabelKind.tag => bookmark.copyWith(tagIds: ids, updatedAt: _now()),
      LabelKind.collection => bookmark.copyWith(
        collectionIds: ids,
        updatedAt: _now(),
      ),
    });
  }

  Future<void> delete(Bookmark bookmark) => _repository.delete(bookmark.id);

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
    final updated = bookmark.copyWith(
      title: title,
      description: description,
      imageUrl: imageUrl,
      updatedAt: _now(),
    );
    _repository.update(updated).ignore();
    return updated;
  }

  /// Looks up the link's real title and details and saves them.
  Future<Bookmark?> fetchDetails(
    Bookmark bookmark,
    PageInfoService pageInfo, {
    String? fallbackTitle,
  }) async {
    final uri = Uri.tryParse(bookmark.url);
    if (uri == null) return null;
    final metadata = await pageInfo.lookup(uri) ?? const PageMetadata();
    return applyMetadata(bookmark, metadata, fallbackTitle: fallbackTitle);
  }

  /// Fetches details for recent Inbox bookmarks that still have a title
  /// made up from the URL, e.g. ones saved while offline.
  Future<int> backfillDetails(
    PageInfoService pageInfo, {
    int limit = 25,
  }) async {
    final recent = await _repository
        .watchList(const BookmarkQuery(view: BookmarkView.inbox), limit: limit)
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
  Label? createLabel(LabelKind kind, String name, List<Label> existing) {
    final normalized = normalizeLabelName(name);
    if (normalized == null) return null;
    final match = existing.where(
      (l) => l.kind == kind && l.name.toLowerCase() == normalized.toLowerCase(),
    );
    if (match.isNotEmpty) return match.first;

    final label = Label(id: _labels.newId(kind), kind: kind, name: normalized);
    _labels.create(label).ignore();
    return label;
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
