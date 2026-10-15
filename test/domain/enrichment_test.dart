import 'package:capsula_core/domain/bookmarks/bookmark_service.dart';
import 'package:capsula_core/domain/reader/page_info_service.dart';
import 'package:capsula_core/domain/reader/reader_content.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_content_fetcher.dart';

import 'package:capsula_core/testing/in_memory_bookmark_repository.dart';
import 'package:capsula_core/testing/in_memory_label_repository.dart';

void main() {
  late InMemoryBookmarkRepository repo;
  late BookmarkService service;

  setUp(() {
    repo = InMemoryBookmarkRepository();
    service = BookmarkService(repo, InMemoryLabelRepository(repo));
  });

  Future<String> save(String url, {String? title}) async =>
      ((await service.save(url, title: title)) as Saved).bookmark.id;

  const metadata = PageMetadata(
    title: 'The Real Title',
    description: 'A summary.',
    image: null,
  );

  test('replaces a title derived from the URL', () async {
    final id = await save('https://youtube.com/watch?v=abc');
    expect(repo.items[id]!.title, 'youtube.com');

    expect(service.applyMetadata(repo.items[id]!, metadata), isNotNull);
    expect(repo.items[id]!.title, 'The Real Title');
    expect(repo.items[id]!.description, 'A summary.');
  });

  test('never replaces a title the user gave', () async {
    final id = await save('https://example.com/a', title: 'My name for it');
    service.applyMetadata(repo.items[id]!, metadata);
    expect(repo.items[id]!.title, 'My name for it');
    expect(repo.items[id]!.description, 'A summary.', reason: 'was missing');
  });

  test('adds an image only when missing and only http(s)', () async {
    final id = await save('https://example.com/a');
    service.applyMetadata(
      repo.items[id]!,
      PageMetadata(image: Uri.parse('ftp://example.com/x.png')),
    );
    expect(repo.items[id]!.imageUrl, isNull);

    service.applyMetadata(
      repo.items[id]!,
      PageMetadata(image: Uri.parse('https://example.com/x.png')),
    );
    expect(repo.items[id]!.imageUrl, 'https://example.com/x.png');

    service.applyMetadata(
      repo.items[id]!,
      PageMetadata(image: Uri.parse('https://example.com/other.png')),
    );
    expect(repo.items[id]!.imageUrl, 'https://example.com/x.png');
  });

  test('reports no change when there is nothing new', () async {
    final id = await save('https://example.com/a', title: 'Mine');
    service.applyMetadata(repo.items[id]!, metadata);
    expect(service.applyMetadata(repo.items[id]!, metadata), isNull);
    expect(
      service.applyMetadata(repo.items[id]!, const PageMetadata()),
      isNull,
    );
  });

  test('clips long values', () async {
    final id = await save('https://example.com/');
    service.applyMetadata(
      repo.items[id]!,
      PageMetadata(title: 'T' * 500, description: 'D ' * 400),
    );
    expect(repo.items[id]!.title.length, 300);
    expect(repo.items[id]!.description!.length, 500);
  });

  test('uses the fallback title only when the page has none', () async {
    final id = await save('https://example.com/a');
    service.applyMetadata(
      repo.items[id]!,
      const PageMetadata(description: 'x'),
      fallbackTitle: 'Shared caption',
    );
    expect(repo.items[id]!.title, 'Shared caption');

    final other = await save('https://example.com/b');
    service.applyMetadata(
      repo.items[other]!,
      const PageMetadata(title: 'Page title'),
      fallbackTitle: 'Shared caption',
    );
    expect(repo.items[other]!.title, 'Page title');
  });

  test('backfills recent Inbox bookmarks that still have URL titles', () async {
    final auto = await save('https://example.com/some-page');
    final named = await save('https://example.com/other', title: 'Mine');
    final fetcher = FakeContentFetcher()
      ..html(
        'https://example.com/',
        '<meta property="og:title" content="Real Title">',
      );

    final updated = await service.backfillDetails(PageInfoService(fetcher));

    expect(updated, 1, reason: 'bookmarks with a chosen title are skipped');
    expect(repo.items[auto]!.title, 'Real Title');
    expect(repo.items[named]!.title, 'Mine');
  });
}
