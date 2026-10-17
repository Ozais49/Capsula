import 'package:capsula_core/domain/bookmarks/bookmark.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_repository.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_service.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_view.dart';
import 'package:capsula_core/domain/highlights/highlight.dart';
import 'package:capsula_core/testing/in_memory_bookmark_repository.dart';
import 'package:capsula_core/testing/in_memory_content_index.dart';
import 'package:capsula_core/testing/in_memory_highlight_repository.dart';
import 'package:capsula_core/testing/in_memory_label_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late InMemoryBookmarkRepository repo;
  late InMemoryHighlightRepository highlights;
  late InMemoryContentIndex content;
  late BookmarkService service;
  var now = DateTime(2026, 10, 17);

  setUp(() {
    now = DateTime(2026, 10, 17);
    repo = InMemoryBookmarkRepository();
    highlights = InMemoryHighlightRepository();
    content = InMemoryContentIndex();
    service = BookmarkService(
      repo,
      InMemoryLabelRepository(repo),
      highlights: highlights,
      contentIndex: content,
      now: () => now,
    );
  });

  Future<Bookmark> save(String url) async {
    final result = await service.save(url) as Saved;
    await result.committed;
    return repo.items[result.bookmark.id]!;
  }

  Future<List<Bookmark>> view(BookmarkView v) =>
      repo.watchList(BookmarkQuery(view: v), limit: 100).first;

  test('trashed bookmarks leave every view but the Trash', () async {
    final a = await save('https://example.com/a');
    await service.setFavorite(a, true);
    await service.moveToTrash([repo.items[a.id]!]);

    for (final v in [
      BookmarkView.inbox,
      BookmarkView.all,
      BookmarkView.favorites,
      BookmarkView.archived,
    ]) {
      expect(await view(v), isEmpty, reason: v.key);
    }
    final trash = await view(BookmarkView.trash);
    expect(trash.single.deletedAt, now);
    // Kept as it was, ready to come back.
    expect(trash.single.favorite, isTrue);
  });

  test('undo puts bookmarks back exactly where they were', () async {
    final inbox = await save('https://example.com/inbox');
    final archived = await save('https://example.com/archived');
    await service.setArchived(archived, true);
    final before = [repo.items[inbox.id]!, repo.items[archived.id]!];

    await service.moveToTrash(before);
    await service.restore(before);

    expect(repo.items[inbox.id]!.inInbox, isTrue);
    expect(repo.items[inbox.id]!.archived, isFalse);
    expect(repo.items[archived.id]!.archived, isTrue);
    expect(repo.items.values.any((b) => b.isTrashed), isFalse);
  });

  test('restoring from the Trash brings bookmarks into the library', () async {
    final a = await save('https://example.com/a');
    await service.moveToTrash([a]);
    await service.restore(await view(BookmarkView.trash));
    expect((await view(BookmarkView.all)).single.id, a.id);
  });

  test('saving a link that is in the Trash restores it', () async {
    final a = await save('https://example.com/a');
    await service.moveToTrash([a]);

    final result = await service.save('https://example.com/a');
    expect(result, isA<Saved>());
    await (result as Saved).committed;
    expect(repo.items[a.id]!.isTrashed, isFalse);
    expect(repo.items, hasLength(1));
  });

  test('bookmarks are deleted for good 30 days after trashing', () async {
    final old = await save('https://example.com/old');
    final recent = await save('https://example.com/recent');
    await service.moveToTrash([old]);
    highlights.addAll([
      Highlight(id: 'h', bookmarkId: old.id, text: 'Quote', createdAt: now),
    ]);
    await content.save(old.id, ['words']);

    now = now.add(const Duration(days: 20));
    await service.moveToTrash([recent]);
    expect(await service.purgeTrash(), 0);

    now = now.add(const Duration(days: 11));
    expect(await service.purgeTrash(), 1);
    expect(repo.items.keys, [recent.id]);
    expect(highlights.items, isEmpty);
    expect(await content.search('words'), isEmpty);

    // Running it again (say, on another device) changes nothing.
    expect(await service.purgeTrash(), 0);
  });

  test('emptying the Trash deletes only trashed bookmarks', () async {
    final keep = await save('https://example.com/keep');
    final a = await save('https://example.com/a');
    final b = await save('https://example.com/b');
    await service.moveToTrash([a, b]);

    expect(await service.emptyTrash(), 2);
    expect(repo.items.keys, [keep.id]);
  });
}
