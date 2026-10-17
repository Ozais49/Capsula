import 'package:capsula_core/domain/bookmarks/bookmark.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_filters.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_repository.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_service.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_source.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_view.dart';
import 'package:capsula_core/domain/local/local_library.dart';
import 'package:capsula_core/domain/sources/custom_source.dart';
import 'package:capsula_core/testing/in_memory_bookmark_repository.dart';
import 'package:capsula_core/testing/in_memory_label_repository.dart';
import 'package:capsula_core/testing/in_memory_source_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/memory_local_storage.dart';

void main() {
  test('domains are cleaned up from what people type', () {
    expect(normalizeSourceDomain('Amazon.com'), 'amazon.com');
    expect(normalizeSourceDomain('https://www.amazon.de/deals'), 'amazon.de');
    expect(
      normalizeSourceDomain(' news.ycombinator.com '),
      'news.ycombinator.com',
    );
    expect(normalizeSourceDomain('not a domain'), isNull);
    expect(normalizeSourceDomain('localhost'), isNull);
    expect(normalizeSourceDomain(''), isNull);
  });

  test('the most specific domain wins', () {
    const google = CustomSource(
      id: 'g',
      name: 'Google',
      domains: ['google.com'],
    );
    const docs = CustomSource(
      id: 'd',
      name: 'Docs',
      domains: ['docs.google.com'],
    );
    expect(detectCustomSource('docs.google.com', [google, docs]), 'd');
    expect(detectCustomSource('mail.google.com', [google, docs]), 'g');
    expect(detectCustomSource('notgoogle.com', [google, docs]), isNull);
  });

  group('service', () {
    late InMemoryBookmarkRepository repo;
    late InMemorySourceRepository sources;
    late BookmarkService service;

    setUp(() {
      repo = InMemoryBookmarkRepository();
      sources = InMemorySourceRepository();
      service = BookmarkService(
        repo,
        InMemoryLabelRepository(repo),
        sources: sources,
      );
    });

    Future<Bookmark> save(String url) async {
      final saved = await service.save(url) as Saved;
      await saved.committed;
      return repo.items[saved.bookmark.id]!;
    }

    Future<List<CustomSource>> list() => sources.watch().first;

    test('checks names and domains', () async {
      expect(await service.addSource(' ', ['a.com'], []), 'Enter a name');
      expect(
        await service.addSource('Shop', [], []),
        'Enter at least one domain',
      );
      expect(
        await service.addSource('Shop', ['no spaces please'], []),
        '"no spaces please" is not a domain',
      );
      expect(
        await service.addSource('YouTube', ['yt.example'], []),
        '"YouTube" is already a source',
      );
      expect(
        await service.addSource('Amazon', [
          'https://www.Amazon.com/',
          'amzn.to',
        ], []),
        isNull,
      );
      final amazon = (await list()).single;
      expect(amazon.domains, ['amazon.com', 'amzn.to']);
      expect(
        await service.addSource('amazon', ['amazon.de'], await list()),
        '"amazon" is already a source',
      );
    });

    test('new links get the source; built-in handling stays', () async {
      await service.addSource('Amazon', ['amazon.com'], []);
      final b = await save('https://smile.amazon.com/dp/B000');
      final amazon = (await list()).single;
      expect(b.customSourceId, amazon.id);
      expect(b.source, BookmarkSource.website);
      expect(sourceOf(b, await list()).name, 'Amazon');

      // A source can also rename a built-in platform's links.
      await service.addSource('Shorts', ['youtube.com'], await list());
      final video = await save('https://youtube.com/shorts/abc');
      expect(sourceOf(video, await list()).name, 'Shorts');
      expect(video.source, BookmarkSource.youtube);
    });

    test('filters match custom and built-in sources', () async {
      await service.addSource('Amazon', ['amazon.com'], []);
      await save('https://amazon.com/dp/1');
      await save('https://example.com/a');
      final amazon = (await list()).single;
      Future<int> count(Set<String> s) async =>
          (await repo
                  .watchList(
                    BookmarkQuery(
                      view: BookmarkView.all,
                      filters: BookmarkFilters(sources: s),
                    ),
                    limit: 10,
                  )
                  .first)
              .length;
      expect(await count({amazon.id}), 1);
      expect(await count({'website'}), 1);
    });

    test('applying sources to saved bookmarks is repeatable', () async {
      final old = await save('https://amazon.com/dp/1');
      final other = await save('https://example.com/a');
      expect(old.customSourceId, isNull);

      await service.addSource('Amazon', ['amazon.com'], []);
      expect(await service.redetectSources(), 1);
      expect(repo.items[old.id]!.customSourceId, (await list()).single.id);
      expect(repo.items[other.id]!.customSourceId, isNull);
      expect(await service.redetectSources(), 0);

      // Removing a domain moves bookmarks back.
      final amazon = (await list()).single;
      await service.updateSource(
        amazon.copyWith(domains: ['amazon.de']),
        await list(),
      );
      expect(await service.redetectSources(), 1);
      expect(repo.items[old.id]!.customSourceId, isNull);
    });

    test('deleting a source returns its bookmarks to Webpage', () async {
      await service.addSource('Amazon', ['amazon.com'], []);
      final b = await save('https://amazon.com/dp/1');
      await service.deleteSource((await list()).single);
      expect(await list(), isEmpty);
      expect(repo.items[b.id]!.customSourceId, isNull);
      expect(repo.items[b.id]!.sourceKey, 'website');
    });
  });

  test('the on-device library keeps sources', () async {
    final storage = MemoryLocalStorage();
    final services = (await LocalLibrary.open(storage)).services();
    await services.bookmarks.addSource('Amazon', ['amazon.com'], []);

    final reopened = (await LocalLibrary.open(storage)).services();
    final sources = await reopened.sourceRepository.watch().first;
    expect(sources.single.name, 'Amazon');
    expect(sources.single.domains, ['amazon.com']);
  });
}
