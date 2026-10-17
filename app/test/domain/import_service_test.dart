import 'package:capsula_core/domain/bookmarks/bookmark.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_source.dart';
import 'package:capsula_core/domain/import/import_service.dart';
import 'package:capsula_core/domain/import/imported_item.dart';
import 'package:capsula_core/domain/organization/label.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:capsula_core/testing/in_memory_bookmark_repository.dart';
import 'package:capsula_core/testing/in_memory_label_repository.dart';

void main() {
  final now = DateTime.utc(2026, 10, 14, 12);
  late InMemoryBookmarkRepository bookmarks;
  late InMemoryLabelRepository labels;
  late ImportService importer;

  setUp(() {
    bookmarks = InMemoryBookmarkRepository();
    labels = InMemoryLabelRepository(bookmarks);
    importer = ImportService(bookmarks, labels, now: () => now);
  });

  Bookmark existing(String url) => Bookmark(
    id: 'old',
    url: url,
    canonicalUrl: url,
    title: 'Old',
    source: BookmarkSource.website,
    sourceDomain: 'example.com',
    createdAt: now,
    updatedAt: now,
  );

  test('plans new, duplicate and invalid items', () async {
    bookmarks.addAll([existing('https://example.com/saved')]);

    final plan = await importer.plan(const [
      ImportedItem(url: 'https://example.com/new'),
      ImportedItem(url: 'http://www.example.com/saved/'),
      ImportedItem(url: 'https://example.com/new/'),
      ImportedItem(url: 'javascript:void(0)'),
      ImportedItem(url: 'not a url'),
    ]);

    expect(plan.found, 5);
    expect(plan.newItems.map((p) => p.canonicalUrl), [
      'https://example.com/new',
    ]);
    expect(plan.alreadySaved, 1);
    expect(plan.repeatedInFile, 1);
    expect(plan.duplicates, 2);
    expect(plan.invalid, ['javascript:void(0)', 'not a url']);
  });

  test('imports with provenance, original dates, folders and tags', () async {
    labels.addAll(const [
      Label(id: 'c-existing', kind: LabelKind.collection, name: 'AI Research'),
    ]);
    final saved = DateTime.utc(2019, 5, 1);
    final plan = await importer.plan([
      ImportedItem(
        url: 'https://www.reddit.com/r/MachineLearning/comments/x/paper/',
        title: 'Paper discussion',
        description: 'Worth reading',
        folder: 'ai research',
        tags: const ['AI', 'papers'],
        createdAt: saved,
      ),
      const ImportedItem(url: 'https://example.com/untitled-page'),
    ]);

    final result = await importer.run(
      plan,
      origin: ImportOrigin.chrome,
      existingLabels: labels.items.values.toList(),
    );

    expect(result.imported, 2);
    expect(result.failed, 0);

    final reddit = bookmarks.items.values.firstWhere(
      (b) => b.source == BookmarkSource.reddit,
    );
    expect(reddit.title, 'Paper discussion');
    expect(reddit.description, 'Worth reading');
    expect(reddit.createdAt, saved, reason: 'original date kept');
    expect(reddit.importedFrom, 'Chrome');
    expect(reddit.importedAt, now);
    expect(reddit.inInbox, isTrue);
    expect(reddit.collectionIds, ['c-existing'], reason: 'reused by name');

    final tagNames = reddit.tagIds.map((id) => labels.items[id]!.name);
    expect(tagNames, unorderedEquals(['AI', 'papers']));

    final untitled = bookmarks.items.values.firstWhere(
      (b) => b.sourceDomain == 'example.com',
    );
    expect(untitled.title, 'untitled page');
    expect(untitled.createdAt, now);
  });

  test('options can skip Inbox, folders and tags', () async {
    final plan = await importer.plan(const [
      ImportedItem(url: 'https://example.com/a', folder: 'F', tags: ['t']),
    ]);
    await importer.run(
      plan,
      origin: ImportOrigin.raindrop,
      options: const ImportOptions(
        addToInbox: false,
        foldersAsCollections: false,
        keepTags: false,
      ),
    );
    final b = bookmarks.items.values.single;
    expect(b.inInbox, isFalse);
    expect(b.collectionIds, isEmpty);
    expect(b.tagIds, isEmpty);
    expect(labels.items, isEmpty);
  });

  test('writes in batches, reports progress and partial failure', () async {
    final items = [
      for (var i = 0; i < 1000; i++)
        ImportedItem(url: 'https://example.com/page-$i'),
    ];
    final plan = await importer.plan(items);
    bookmarks.failBatch = 1;
    final progress = <int>[];

    final result = await importer.run(
      plan,
      origin: ImportOrigin.file,
      onProgress: (done, total) => progress.add(done),
    );

    expect(bookmarks.batchSizes, [400, 400, 200]);
    expect(result.imported, 600);
    expect(result.failed, 400);
    expect(progress, [0, 400, 800, 1000]);

    // Running again imports only what failed.
    bookmarks.failBatch = null;
    final retry = await importer.plan(items);
    expect(retry.newItems, hasLength(400));
    expect(retry.alreadySaved, 600);
  });
}
