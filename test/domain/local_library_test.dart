import 'package:capsula_core/domain/bookmarks/bookmark_service.dart';
import 'package:capsula_core/domain/highlights/highlight.dart';
import 'package:capsula_core/domain/local/local_library.dart';
import 'package:capsula_core/domain/organization/label.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/memory_local_storage.dart';

void main() {
  test('everything saved comes back after reopening', () async {
    final storage = MemoryLocalStorage();
    final services = (await LocalLibrary.open(storage)).services();

    final saved = await services.bookmarks.save('https://example.com/a');
    final bookmark = (saved as Saved).bookmark;
    await saved.committed;
    final labels = services.labelRepository;
    final collection = Label(
      id: labels.newId(LabelKind.collection),
      kind: LabelKind.collection,
      name: 'Recipes',
    );
    await labels.create(collection);
    await services.bookmarkRepository.update(
      bookmark.copyWith(collectionIds: [collection.id], favorite: true),
    );
    final highlights = services.highlightRepository;
    await highlights.save(
      Highlight(
        id: highlights.newId(),
        bookmarkId: bookmark.id,
        text: 'A quote',
        createdAt: DateTime(2026, 3, 1),
      ),
    );
    await services.contentIndex.save(bookmark.id, ['biryani']);

    final reopened = (await LocalLibrary.open(storage)).services();
    final all = await reopened.bookmarkRepository.fetchAll();
    expect(all.single.url, 'https://example.com/a');
    expect(all.single.favorite, isTrue);
    expect(all.single.collectionIds, [collection.id]);
    expect(all.single.createdAt, bookmark.createdAt);
    expect(
      (await reopened.labelRepository.watch(LabelKind.collection).first)
          .single
          .name,
      'Recipes',
    );
    expect(
      (await reopened.highlightRepository.watchForBookmark(bookmark.id).first)
          .single
          .text,
      'A quote',
    );
    expect(await reopened.contentIndex.search('biryani'), [bookmark.id]);
    expect(
      await reopened.authRepository.authStateChanges().first,
      LocalLibrary.user,
    );
  });

  test('IDs stay unique across runs', () async {
    final storage = MemoryLocalStorage();
    final first = (await LocalLibrary.open(storage)).services();
    final second = (await LocalLibrary.open(storage)).services();
    final ids = {
      for (var i = 0; i < 50; i++) first.bookmarkRepository.newId(),
      for (var i = 0; i < 50; i++) second.bookmarkRepository.newId(),
    };
    expect(ids, hasLength(100));
  });

  test('deleting a label is saved along with its bookmarks', () async {
    final storage = MemoryLocalStorage();
    final services = (await LocalLibrary.open(storage)).services();
    final tag = Label(
      id: services.labelRepository.newId(LabelKind.tag),
      kind: LabelKind.tag,
      name: 'later',
    );
    await services.labelRepository.create(tag);
    final saved =
        await services.bookmarks.save('https://example.com/b') as Saved;
    await services.bookmarkRepository.update(
      saved.bookmark.copyWith(tagIds: [tag.id]),
    );
    await services.labelRepository.delete(tag);

    final reopened = (await LocalLibrary.open(storage)).services();
    expect((await reopened.bookmarkRepository.fetchAll()).single.tagIds, []);
  });
}
