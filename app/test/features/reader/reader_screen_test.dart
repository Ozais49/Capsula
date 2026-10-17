import 'package:capsula/app/app.dart';
import 'package:capsula/config/app_config.dart';
import 'package:capsula_core/domain/auth/app_user.dart';
import 'package:capsula_core/domain/bookmarks/bookmark.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_source.dart';
import 'package:capsula_core/domain/reader/reader_service.dart';
import 'package:capsula/features/reader/reader_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_auth_repository.dart';
import '../../fakes/fake_backend.dart';
import '../../fakes/fake_content_fetcher.dart';
import '../../fakes/fake_share_intake.dart';

import 'package:capsula_core/testing/in_memory_bookmark_repository.dart';

Bookmark _bookmark(String url, String title, BookmarkSource source) {
  final t = DateTime(2026);
  final host = Uri.parse(url).host.replaceFirst('www.', '');
  return Bookmark(
    id: 'b1',
    url: url,
    canonicalUrl: url,
    title: title,
    source: source,
    sourceDomain: host,
    createdAt: t,
    updatedAt: t,
  );
}

Future<InMemoryBookmarkRepository> _openReader(
  WidgetTester tester,
  Bookmark bookmark,
  FakeContentFetcher fetcher,
) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final repo = InMemoryBookmarkRepository()..addAll([bookmark]);
  await tester.pumpWidget(
    CapsulaApp(
      config: const AppConfig(
        environment: AppEnvironment.dev,
        useFirebaseEmulators: false,
        firebaseEmulatorHost: 'localhost',
      ),
      backend: await startedBackend(
        FakeAuthRepository(initialUser: const AppUser(id: 'u1')),
        bookmarks: repo,
      ),
      shareIntake: FakeShareIntake(),
      reader: ReaderService(fetcher),
    ),
  );
  await tester.pumpAndSettle();

  await tester.tap(find.text(bookmark.title));
  await tester.pumpAndSettle();
  await tester.tap(find.byIcon(Icons.chrome_reader_mode_outlined));
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  testWidgets('shows an extracted article and enriches the title', (
    tester,
  ) async {
    final fetcher = FakeContentFetcher()
      ..html(
        'https://blog.example.com/',
        '<html><head><meta property="og:title" content="Cooking Perfect Rice">'
            '<meta property="og:site_name" content="Example Blog"></head><body><article>'
            '${List.generate(8, (i) => '<p>Step $i: rinse, soak, simmer, and rest the rice, which takes a little patience.</p>').join()}'
            '<p>More at <a href="/more">the full guide</a>.</p>'
            '</article></body></html>',
      );
    final repo = await _openReader(
      tester,
      _bookmark(
        'https://blog.example.com/rice',
        'rice',
        BookmarkSource.website,
      ),
      fetcher,
    );

    expect(find.byType(ReaderScreen), findsOneWidget);
    expect(find.text('Cooking Perfect Rice'), findsOneWidget);
    expect(find.text('Example Blog'), findsOneWidget);
    expect(find.textContaining('Step 0: rinse'), findsOneWidget);
    expect(find.text('Read on blog.example.com'), findsOneWidget);
    expect(find.byTooltip('Open in browser'), findsOneWidget);

    expect(repo.items['b1']!.title, 'Cooking Perfect Rice');
  });

  testWidgets('shows a video card for YouTube', (tester) async {
    final fetcher = FakeContentFetcher()
      ..json(
        'https://www.youtube.com/oembed',
        '{"title": "Dart in 10 minutes", "author_name": "Dash"}',
      );
    await _openReader(
      tester,
      _bookmark(
        'https://www.youtube.com/watch?v=abc',
        'youtube.com',
        BookmarkSource.youtube,
      ),
      fetcher,
    );

    expect(find.text('Dart in 10 minutes'), findsOneWidget);
    expect(find.text('Dash'), findsOneWidget);
    expect(find.text('Watch video'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  testWidgets('a failed read keeps the bookmark and offers the browser', (
    tester,
  ) async {
    final fetcher = FakeContentFetcher(); // Every request fails as offline.
    final repo = await _openReader(
      tester,
      _bookmark('https://example.com/a', 'My page', BookmarkSource.website),
      fetcher,
    );

    expect(find.textContaining('Couldn\'t reach this page'), findsOneWidget);
    expect(
      find.text('Your bookmark is saved. You can open the original page.'),
      findsOneWidget,
    );
    expect(
      find.widgetWithText(FilledButton, 'Open in browser'),
      findsOneWidget,
    );
    expect(repo.items['b1']!.title, 'My page', reason: 'bookmark untouched');

    fetcher.html(
      'https://example.com/',
      '<meta property="og:title" content="Now online">',
    );
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(find.text('Now online'), findsOneWidget);
  });

  testWidgets('login-required pages explain why', (tester) async {
    final fetcher = FakeContentFetcher()
      ..html('https://example.com/', 'denied', status: 403);
    await _openReader(
      tester,
      _bookmark(
        'https://example.com/private',
        'Private',
        BookmarkSource.website,
      ),
      fetcher,
    );
    expect(find.text('This page requires signing in.'), findsOneWidget);
    expect(find.text('Try again'), findsNothing);
  });
}
