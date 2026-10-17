import 'dart:convert';

import 'package:capsula_core/domain/bookmarks/bookmark.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_patch.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_service.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_source.dart';
import 'package:capsula_core/domain/local/local_library.dart';
import 'package:capsula_core/domain/organization/label.dart';
import 'package:capsula_core/domain/reader/reader_content.dart';
import 'package:capsula_core/testing/in_memory_bookmark_repository.dart';
import 'package:capsula_core/testing/in_memory_label_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/memory_local_storage.dart';

Bookmark _bookmark({
  String id = 'b1',
  List<String> tags = const [],
  String? note,
}) {
  final time = DateTime.utc(2026, 10, 17);
  return Bookmark(
    id: id,
    url: 'https://example.com/$id',
    canonicalUrl: 'https://example.com/$id',
    title: 'Title',
    source: BookmarkSource.website,
    sourceDomain: 'example.com',
    createdAt: time,
    updatedAt: time,
    tagIds: tags,
    note: note,
  );
}

void main() {
  group('BookmarkPatch', () {
    test('holds only the fields that changed', () {
      final before = _bookmark().copyWith(remindAt: DateTime.utc(2026, 11));
      final patch = BookmarkPatch.between(
        before,
        before.copyWith(favorite: true, clearReminder: true),
      );
      expect(patch.set, {'favorite': true});
      expect(patch.removed, {'remindAt'});
      expect(patch.added, isEmpty);

      // Search words are derived, so they follow text changes.
      expect(
        BookmarkPatch.between(before, before.copyWith(note: 'new')).set.keys,
        unorderedEquals(['note', 'searchTokens']),
      );
    });

    test('expresses label changes as additions and removals', () {
      final before = _bookmark(tags: ['a', 'b']);
      expect(
        BookmarkPatch.between(
          before,
          before.copyWith(tagIds: ['a', 'b', 'c']),
        ).added,
        {
          'tagIds': ['c'],
        },
      );
      expect(
        BookmarkPatch.between(before, before.copyWith(tagIds: ['a'])).pulled,
        {
          'tagIds': ['b'],
        },
      );
      // Both at once can't be one write, so the list is written whole.
      expect(
        BookmarkPatch.between(before, before.copyWith(tagIds: ['a', 'c'])).set,
        {
          'tagIds': ['a', 'c'],
        },
      );
    });

    test('merges with a change made elsewhere when applied', () {
      final mine = _bookmark(tags: ['a']);
      final patch = BookmarkPatch.between(
        mine,
        mine.copyWith(tagIds: ['a', 'mine']),
      );
      // Meanwhile another device added "theirs".
      final stored = {
        'tagIds': ['a', 'theirs'],
        'title': 'Title',
      };
      expect(patch.applyTo(stored)['tagIds'], ['a', 'theirs', 'mine']);
    });

    test('leaves fields from newer app versions alone', () {
      final b = _bookmark();
      final stored = {
        ...BookmarkPatch.between(b, b).applyTo(const {}),
        'fieldFromTheFuture': 1,
      };
      final patch = BookmarkPatch.fromDocuments(stored, {'title': 'x'});
      expect(patch.removed, isNot(contains('fieldFromTheFuture')));
    });
  });

  test('bookmark IDs come from the link, the same on every device', () {
    const url = 'https://example.com/article';
    expect(bookmarkIdFor(url), bookmarkIdFor(url));
    expect(bookmarkIdFor(url), isNot(bookmarkIdFor('$url-2')));
    expect(bookmarkIdFor(url), matches(RegExp(r'^u[0-9a-z]{14}$')));
    // Pinned, so a change to the hash (which would split the same link
    // into two bookmarks across app versions) fails loudly.
    // The first half is the standard FNV-1a hash of "a" (0xe40c292c).
    expect(bookmarkIdFor('a'), 'u1r9wi7g0v7dxei');
  });

  group('service edits keep concurrent changes', () {
    late InMemoryBookmarkRepository repo;
    late BookmarkService service;

    setUp(() {
      repo = InMemoryBookmarkRepository()
        ..addAll([
          _bookmark(tags: ['a']),
        ]);
      service = BookmarkService(repo, InMemoryLabelRepository(repo));
    });

    test('choosing tags from an old copy keeps tags added elsewhere', () async {
      final stale = repo.items['b1']!;
      await repo.modify('b1', (b) => b.copyWith(tagIds: [...b.tagIds, 'c']));

      await service.setLabels(stale, LabelKind.tag, ['a', 'd']);
      expect(repo.items['b1']!.tagIds, ['a', 'c', 'd']);

      // Removing works on the latest copy too.
      await service.setLabels(stale, LabelKind.tag, const []);
      expect(repo.items['b1']!.tagIds, ['c', 'd']);
    });

    test('an edit from an old copy keeps other fields', () async {
      final stale = repo.items['b1']!;
      await service.setNote(stale, 'from the phone');
      await service.setFavorite(stale, true);
      final b = repo.items['b1']!;
      expect(b.note, 'from the phone');
      expect(b.favorite, isTrue);
    });

    test('a fetched title never replaces one typed meanwhile', () async {
      final saved = _bookmark().copyWith(title: 'example.com');
      repo.addAll([saved]);
      await service.rename(saved, 'My title');
      service.applyMetadata(saved, const PageMetadata(title: 'Page title'));
      await Future<void>.delayed(Duration.zero);
      expect(repo.items['b1']!.title, 'My title');
    });

    test('bulk edits are written in batches', () async {
      repo.addAll([for (var i = 0; i < 1000; i++) _bookmark(id: 'x$i')]);
      final all = repo.items.values.toList();
      await service.updateMany(all, (b) => b.copyWith(favorite: true));
      expect(repo.modifyBatchSizes, [450, 450, 101]);
      expect(repo.items.values.every((b) => b.favorite), isTrue);
    });
  });

  group('on-device library shared by two tabs', () {
    test('saves from both tabs are kept', () async {
      final storage = MemoryLocalStorage();
      final tabA = (await LocalLibrary.open(storage)).services();
      final tabB = (await LocalLibrary.open(storage)).services();

      await (await tabA.bookmarks.save(
        'https://example.com/a',
      ) as Saved).committed;
      await (await tabB.bookmarks.save(
        'https://example.com/b',
      ) as Saved).committed;

      final reopened = (await LocalLibrary.open(storage)).services();
      final urls = (await reopened.bookmarkRepository.fetchAll()).map(
        (b) => b.url,
      );
      expect(
        urls,
        unorderedEquals(['https://example.com/a', 'https://example.com/b']),
      );
    });

    test('a tab picks up another tab\'s save when told', () async {
      final shared = <String, String>{};
      final storageA = MemoryLocalStorage(shared);
      final tabA = (await LocalLibrary.open(storageA)).services();
      final tabB = (await LocalLibrary.open(MemoryLocalStorage(shared)))
          .services();

      await (await tabB.bookmarks.save(
        'https://example.com/b',
      ) as Saved).committed;
      expect(await tabA.bookmarkRepository.fetchAll(), isEmpty);

      storageA.notifyExternalChange(LocalLibrary.libraryKey);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(
        (await tabA.bookmarkRepository.fetchAll()).single.url,
        'https://example.com/b',
      );
    });

    test('an edit in one tab and a delete in the other both stick', () async {
      final storage = MemoryLocalStorage();
      final tabA = (await LocalLibrary.open(storage)).services();
      final one = await tabA.bookmarks.save('https://example.com/1') as Saved;
      final two = await tabA.bookmarks.save('https://example.com/2') as Saved;
      await one.committed;
      await two.committed;

      final tabB = (await LocalLibrary.open(storage)).services();
      await tabA.bookmarks.setFavorite(one.bookmark, true);
      await tabB.bookmarks.delete(two.bookmark);

      final all = await (await LocalLibrary.open(storage))
          .services()
          .bookmarkRepository
          .fetchAll();
      expect(all.single.url, 'https://example.com/1');
      expect(all.single.favorite, isTrue);
    });
  });

  group('on-device library recovery', () {
    test('an unreadable library falls back to the backup', () async {
      final storage = MemoryLocalStorage();
      final services = (await LocalLibrary.open(storage)).services();
      await (await services.bookmarks.save(
        'https://example.com/a',
      ) as Saved).committed;
      await (await services.bookmarks.save(
        'https://example.com/b',
      ) as Saved).committed;

      storage.values[LocalLibrary.libraryKey] = '{"bookmarks": {broken';
      final library = await LocalLibrary.open(storage);

      expect(library.restoredFromBackup, isTrue);
      // The backup is the save before the last one.
      expect(library.bookmarkCount, 1);
      expect(storage.values[LocalLibrary.unreadableKey], contains('broken'));
    });

    test('a failed write is kept and saved with the next change', () async {
      final storage = MemoryLocalStorage();
      final services = (await LocalLibrary.open(storage)).services();

      storage.writeError = Exception('quota exceeded');
      final first = await services.bookmarks.save('https://example.com/a');
      await expectLater((first as Saved).committed, throwsException);

      storage.writeError = null;
      await (await services.bookmarks.save(
        'https://example.com/b',
      ) as Saved).committed;

      final stored = jsonDecode(
        storage.values[LocalLibrary.libraryKey]!,
      ) as Map<String, Object?>;
      expect((stored['bookmarks']! as Map).length, 2);
    });
  });
}
