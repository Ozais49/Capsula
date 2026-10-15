import 'package:capsula/app/app.dart';
import 'package:capsula_core/domain/auth/app_user.dart';
import 'package:capsula_core/domain/bookmarks/bookmark.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_repository.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_source.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_view.dart';
import 'package:capsula_core/domain/bookmarks/content_type.dart';
import 'package:capsula_core/domain/bookmarks/url_normalizer.dart';
import 'package:capsula_core/domain/maintenance/maintenance.dart';
import 'package:capsula_core/domain/reader/content_fetcher.dart';
import 'package:capsula_core/testing/in_memory_bookmark_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_auth_repository.dart';
import '../fakes/fake_backend.dart';
import '../fakes/fake_content_fetcher.dart';
import '../fakes/fake_share_intake.dart';
import '../fakes/navigation.dart';
import '../fakes/test_dependencies.dart';

Bookmark _b(String id, String url, {int day = 1, String? title}) {
  final uri = Uri.parse(url);
  final t = DateTime(2026, 1, day);
  return Bookmark(
    id: id,
    url: url,
    canonicalUrl: canonicalizeUrl(uri),
    title: title ?? id,
    source: BookmarkSource.fromHost(displayHost(uri)),
    sourceDomain: displayHost(uri),
    createdAt: t,
    updatedAt: t,
  );
}

class _FakeChecker implements LinkChecker {
  @override
  Future<LinkCheck> check(Uri url) async => switch (url.path) {
    final p when p.contains('gone') => const LinkCheck(
      LinkHealth.broken,
      statusCode: 404,
      reason: 'Page not found',
    ),
    final p when p.contains('private') => const LinkCheck(LinkHealth.unknown),
    _ => const LinkCheck(LinkHealth.ok, statusCode: 200),
  };
}

void main() {
  test('content types from URLs', () {
    ContentType type(String url) {
      final uri = Uri.parse(url);
      return detectContentType(uri, BookmarkSource.fromHost(displayHost(uri)));
    }

    expect(type('https://youtu.be/abc'), ContentType.video);
    expect(type('https://www.instagram.com/reel/abc/'), ContentType.video);
    expect(type('https://www.instagram.com/p/abc/'), ContentType.post);
    expect(type('https://www.reddit.com/r/x/comments/1/a/'), ContentType.post);
    expect(type('https://vimeo.com/123'), ContentType.video);
    expect(type('https://example.com/paper.PDF'), ContentType.document);
    expect(type('https://example.com/photo.webp'), ContentType.image);
    expect(type('https://www.amazon.com/dp/B000'), ContentType.product);
    expect(type('https://www.etsy.com/listing/1'), ContentType.product);
    expect(type('https://blog.example.com/post'), ContentType.article);
    expect(type('https://medium.com/@a/story'), ContentType.article);
  });

  test('type views', () async {
    final repo = InMemoryBookmarkRepository()
      ..addAll([
        _b('v', 'https://youtu.be/abc'),
        _b('d', 'https://example.com/a.pdf'),
      ]);
    final videos = await repo
        .watchList(
          const BookmarkQuery(view: TypeView(ContentType.video)),
          limit: 10,
        )
        .first;
    expect(videos.map((b) => b.id), ['v']);
    expect(
      BookmarkView.parse('type:document'),
      const TypeView(ContentType.document),
    );
  });

  test('findDuplicates groups by canonical URL, oldest first', () {
    final groups = findDuplicates([
      _b('a1', 'https://example.com/a', day: 3),
      _b('a2', 'http://www.example.com/a/', day: 1),
      _b('b', 'https://example.com/b'),
      _b('c1', 'https://youtu.be/xyz', day: 5),
      _b('c2', 'https://www.youtube.com/watch?v=xyz&si=1', day: 6),
    ]);
    expect(groups.map((g) => g.map((b) => b.id).toList()), [
      ['c1', 'c2'],
      ['a2', 'a1'],
    ]);
  });

  test('link checks map statuses and failures', () async {
    expect(linkCheckFor(200).health, LinkHealth.ok);
    expect(linkCheckFor(301).health, LinkHealth.ok);
    expect(linkCheckFor(404).health, LinkHealth.broken);
    expect(linkCheckFor(410).health, LinkHealth.broken);
    expect(linkCheckFor(503).health, LinkHealth.broken);
    expect(linkCheckFor(403).health, LinkHealth.unknown);
    expect(linkCheckFor(429).health, LinkHealth.unknown);

    final fetcher = FakeContentFetcher();
    final checker = FetcherLinkChecker(fetcher);
    expect(
      (await checker.check(Uri.parse('https://nowhere.example'))).health,
      LinkHealth.broken,
      reason: 'unreachable',
    );
    fetcher.failure = const FetchException(FetchFailure.blocked);
    expect(
      (await checker.check(Uri.parse('https://example.com'))).health,
      LinkHealth.unknown,
    );
  });

  Future<FakeBackendConnector> pump(
    WidgetTester tester,
    List<Bookmark> bookmarks,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final connector = FakeBackendConnector(
      FakeAuthRepository(initialUser: const AppUser(id: 'u1')),
    );
    connector.bookmarks.addAll(bookmarks);
    await tester.pumpWidget(
      CapsulaApp(
        config: testConfig,
        backend: await startedBackendWith(connector),
        shareIntake: FakeShareIntake(),
        linkChecker: _FakeChecker(),
      ),
    );
    await tester.pumpAndSettle();
    await openNavigation(tester);
    await tester.ensureVisible(find.text('Maintenance'));
    await tester.tap(find.text('Maintenance'));
    await tester.pumpAndSettle();
    return connector;
  }

  testWidgets('finds broken links and archives one', (tester) async {
    final app = await pump(tester, [
      _b('ok', 'https://example.com/fine', title: 'Fine page'),
      _b('gone', 'https://example.com/gone', title: 'Gone page'),
      _b('priv', 'https://example.com/private', title: 'Private page'),
    ]);

    await tester.tap(find.widgetWithText(FilledButton, 'Check'));
    await tester.pumpAndSettle();

    expect(find.text('1 broken link'), findsOneWidget);
    expect(find.text('Gone page'), findsOneWidget);
    expect(find.textContaining("1 couldn't be checked"), findsOneWidget);

    await tester.tap(find.byTooltip('Fix Gone page'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    expect(app.bookmarks.items['gone']!.archived, isTrue);
    expect(find.text('Gone page'), findsNothing);
  });

  testWidgets('finds duplicates and keeps one', (tester) async {
    final app = await pump(tester, [
      _b('a1', 'https://example.com/a', day: 1, title: 'First copy'),
      _b('a2', 'http://www.example.com/a/', day: 2, title: 'Second copy'),
      _b('b', 'https://example.com/b', title: 'Unique'),
    ]);

    await tester.tap(find.widgetWithText(FilledButton, 'Find'));
    await tester.pumpAndSettle();
    expect(find.text('1 page saved more than once'), findsOneWidget);

    await tester.tap(find.text('Keep oldest of each'));
    await tester.pumpAndSettle();
    expect(app.bookmarks.items.keys, unorderedEquals(['a1', 'b']));
  });

  testWidgets('refreshes the library index', (tester) async {
    await pump(tester, [_b('a', 'https://example.com/a')]);
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Refresh'));
    await tester.tap(find.widgetWithText(FilledButton, 'Refresh'));
    await tester.pumpAndSettle();
    expect(find.text('Refreshed 1 bookmarks.'), findsOneWidget);
  });
}
