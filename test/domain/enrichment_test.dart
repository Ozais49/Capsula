import 'package:capsula/domain/bookmarks/bookmark_service.dart';
import 'package:capsula/domain/reader/reader_content.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/in_memory_bookmark_repository.dart';
import '../fakes/in_memory_label_repository.dart';

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

    expect(await service.applyMetadata(repo.items[id]!, metadata), isTrue);
    expect(repo.items[id]!.title, 'The Real Title');
    expect(repo.items[id]!.description, 'A summary.');
  });

  test('never replaces a title the user gave', () async {
    final id = await save('https://example.com/a', title: 'My name for it');
    await service.applyMetadata(repo.items[id]!, metadata);
    expect(repo.items[id]!.title, 'My name for it');
    expect(repo.items[id]!.description, 'A summary.', reason: 'was missing');
  });

  test('adds an image only when missing and only http(s)', () async {
    final id = await save('https://example.com/a');
    await service.applyMetadata(
      repo.items[id]!,
      PageMetadata(image: Uri.parse('ftp://example.com/x.png')),
    );
    expect(repo.items[id]!.imageUrl, isNull);

    await service.applyMetadata(
      repo.items[id]!,
      PageMetadata(image: Uri.parse('https://example.com/x.png')),
    );
    expect(repo.items[id]!.imageUrl, 'https://example.com/x.png');

    await service.applyMetadata(
      repo.items[id]!,
      PageMetadata(image: Uri.parse('https://example.com/other.png')),
    );
    expect(repo.items[id]!.imageUrl, 'https://example.com/x.png');
  });

  test('reports no change when there is nothing new', () async {
    final id = await save('https://example.com/a', title: 'Mine');
    await service.applyMetadata(repo.items[id]!, metadata);
    expect(await service.applyMetadata(repo.items[id]!, metadata), isFalse);
    expect(
      await service.applyMetadata(repo.items[id]!, const PageMetadata()),
      isFalse,
    );
  });

  test('clips long values', () async {
    final id = await save('https://example.com/');
    await service.applyMetadata(
      repo.items[id]!,
      PageMetadata(title: 'T' * 500, description: 'D ' * 400),
    );
    expect(repo.items[id]!.title.length, 300);
    expect(repo.items[id]!.description!.length, 500);
  });
}
