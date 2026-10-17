import 'package:capsula/app/app.dart';
import 'package:capsula_core/domain/auth/app_user.dart';
import 'package:capsula_core/domain/bookmarks/bookmark.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_service.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_source.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_view.dart';
import 'package:capsula_core/domain/reader/reader_content.dart';
import 'package:capsula_core/domain/reader/reader_service.dart';
import 'package:capsula_core/domain/search/full_text.dart';
import 'package:capsula_core/testing/in_memory_bookmark_repository.dart';
import 'package:capsula_core/testing/in_memory_content_index.dart';
import 'package:capsula_core/testing/in_memory_label_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_auth_repository.dart';
import '../fakes/fake_backend.dart';
import '../fakes/fake_content_fetcher.dart';
import '../fakes/fake_share_intake.dart';
import '../fakes/navigation.dart';
import '../fakes/test_dependencies.dart';

Bookmark _b(String id, {bool archived = false}) {
  final t = DateTime(2026, 1, 1);
  return Bookmark(
    id: id,
    url: 'https://blog.example.com/$id',
    canonicalUrl: 'https://blog.example.com/$id',
    title: 'Post $id',
    source: BookmarkSource.website,
    sourceDomain: 'blog.example.com',
    createdAt: t,
    updatedAt: t,
    archived: archived,
  );
}

ArticleContent _article(String text) => ArticleContent(
  title: 'An article',
  blocks: [
    ParagraphBlock([InlineRun(text)]),
    const ListBlock(
      ordered: false,
      items: [
        [InlineRun('Saffron and cardamom')],
      ],
    ),
  ],
);

void main() {
  group('words', () {
    test('index words skip short and filler words, most frequent first', () {
      final words = contentWords(['The rice and the RICE, then risotto. Go!']);
      expect(words.first, 'rice');
      expect(words, containsAll(['risotto']));
      expect(words, isNot(contains('the')));
      expect(words, isNot(contains('go')));
    });

    test('articles index headings, lists and paragraphs', () {
      final words = contentWords(
        articleTexts(_article('Biryani needs basmati')),
      );
      expect(words, containsAll(['biryani', 'basmati', 'saffron', 'cardamom']));
    });

    test('a match needs every query word', () {
      final indexed = {'biryani', 'basmati', 'saffron'};
      expect(fullTextMatches(indexed, 'Basmati biryani'), isTrue);
      expect(fullTextMatches(indexed, 'basmati pilaf'), isFalse);
      expect(fullTextMatches(indexed, 'the and'), isFalse, reason: 'no words');
      expect(fullTextLookupWord('a biryani rice'), 'biryani');
    });
  });

  test('service indexes, searches by view and cleans up', () async {
    final repo = InMemoryBookmarkRepository()
      ..addAll([_b('a'), _b('b'), _b('c', archived: true)]);
    final index = InMemoryContentIndex();
    final service = BookmarkService(
      repo,
      InMemoryLabelRepository(repo),
      contentIndex: index,
    );

    expect(
      await service.indexContent(repo.items['a']!, _article('Biryani recipe')),
      isTrue,
    );
    await service.indexContent(repo.items['b']!, _article('Pasta recipe'));
    await service.indexContent(repo.items['c']!, _article('Biryani history'));
    expect(
      await service.indexContent(
        repo.items['b']!,
        const Unavailable(UnavailableReason.network),
      ),
      isFalse,
    );
    expect(repo.items['a']!.contentIndexedAt, isNotNull);

    final found = await service.searchContent('biryani');
    expect(found.map((b) => b.id), ['a'], reason: 'archived excluded');
    final archived = await service.searchContent(
      'biryani',
      view: BookmarkView.archived,
    );
    expect(archived.map((b) => b.id), ['c']);

    await service.delete(repo.items['a']!);
    expect(index.items.containsKey('a'), isFalse);
  });

  testWidgets('reading a page makes its text searchable', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final connector = FakeBackendConnector(
      FakeAuthRepository(initialUser: const AppUser(id: 'u1')),
    );
    connector.bookmarks.addAll([_b('a'), _b('b')]);
    final fetcher = FakeContentFetcher()
      ..html(
        'https://blog.example.com/a',
        '<html><head><title>Post a</title></head><body><article>'
            '${List.generate(6, (i) => '<p>Paragraph $i about slow-cooked biryani with fragrant basmati rice and spices.</p>').join()}'
            '</article></body></html>',
      );
    await tester.pumpWidget(
      CapsulaApp(
        config: testConfig,
        backend: await startedBackendWith(connector),
        shareIntake: FakeShareIntake(),
        reader: ReaderService(fetcher),
      ),
    );
    await tester.pumpAndSettle();

    // Open the reader for "Post a" so it gets indexed.
    await tester.tap(find.text('Post a'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.chrome_reader_mode_outlined));
    await tester.pumpAndSettle();
    expect(connector.contentIndex.items['a'], contains('biryani'));
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await tapNavigationItem(tester, 'All bookmarks');

    await tester.enterText(find.byType(TextField).first, 'biryani');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.text('Post a'), findsNothing, reason: 'not in the title');

    await tester.tap(find.text('Page text'));
    await tester.pumpAndSettle();
    expect(find.text('Post a'), findsOneWidget);
    expect(find.text('Post b'), findsNothing);
  });
}
