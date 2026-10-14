import 'package:capsula/domain/bookmarks/bookmark.dart';
import 'package:capsula/domain/bookmarks/bookmark_service.dart';
import 'package:capsula/domain/bookmarks/bookmark_source.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/in_memory_bookmark_repository.dart';
import '../fakes/in_memory_label_repository.dart';

void main() {
  final now = DateTime.utc(2026, 10, 14, 12);
  late InMemoryBookmarkRepository repo;
  late InMemoryLabelRepository labels;
  late BookmarkService service;

  setUp(() {
    repo = InMemoryBookmarkRepository();
    labels = InMemoryLabelRepository(repo);
    service = BookmarkService(repo, labels, now: () => now);
  });

  test('saves a new link into the Inbox with detected source', () async {
    final result = await service.save(
      'https://www.reddit.com/r/FlutterDev/comments/abc/state_management_tips/?utm_source=share',
    );

    final saved = (result as Saved).bookmark;
    await result.committed;
    expect(repo.items[saved.id], same(saved));
    expect(saved.source, BookmarkSource.reddit);
    expect(saved.sourceDomain, 'reddit.com');
    expect(saved.title, 'state management tips');
    expect(saved.inInbox, isTrue);
    expect(saved.archived, isFalse);
    expect(saved.readingStatus, ReadingStatus.saved);
    expect(saved.createdAt, now);
    expect(
      saved.canonicalUrl,
      'https://reddit.com/r/FlutterDev/comments/abc/state_management_tips',
    );
    expect(saved.url, contains('utm_source=share'), reason: 'original kept');
  });

  test('uses the given title', () async {
    final result = await service.save('example.com/x', title: '  My title ');
    expect((result as Saved).bookmark.title, 'My title');
  });

  test('rejects invalid URLs without writing', () async {
    expect(await service.save('not a link'), isA<InvalidUrl>());
    expect(repo.items, isEmpty);
  });

  test('detects duplicates by canonical URL', () async {
    final first = await service.save('https://example.com/article');
    final second = await service.save('http://www.example.com/article/');

    expect(second, isA<AlreadySaved>());
    expect((second as AlreadySaved).existing.id, (first as Saved).bookmark.id);
    expect(repo.items, hasLength(1));
  });

  test('a rejected write is reported through committed', () async {
    repo.nextWriteError = Exception('permission-denied');
    final result = await service.save('https://example.com/a') as Saved;

    await expectLater(result.committed, throwsException);
  });

  test('archiving removes from the Inbox; unarchiving keeps it out', () async {
    final b = ((await service.save('https://example.com/a')) as Saved).bookmark;

    await service.setArchived(b, true);
    final archived = repo.items[b.id]!;
    expect(archived.archived, isTrue);
    expect(archived.inInbox, isFalse);

    await service.setArchived(archived, false);
    expect(repo.items[b.id]!.archived, isFalse);
    expect(repo.items[b.id]!.inInbox, isFalse);
  });

  test('updates reading status and timestamp', () async {
    final b = ((await service.save('https://example.com/a')) as Saved).bookmark;
    final later = BookmarkService(
      repo,
      labels,
      now: () => now.add(const Duration(hours: 1)),
    );

    await later.setReadingStatus(b, ReadingStatus.read);

    final updated = repo.items[b.id]!;
    expect(updated.readingStatus, ReadingStatus.read);
    expect(updated.updatedAt, now.add(const Duration(hours: 1)));
    expect(updated.createdAt, now);
  });

  test('deletes', () async {
    final b = ((await service.save('https://example.com/a')) as Saved).bookmark;
    await service.delete(b);
    expect(repo.items, isEmpty);
  });
}
