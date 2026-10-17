import 'dart:async';

import 'package:capsula/app/app.dart';
import 'package:capsula/config/app_config.dart';
import 'package:capsula_core/domain/auth/app_user.dart';
import 'package:capsula_core/domain/bookmarks/bookmark.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_source.dart';
import 'package:capsula_core/domain/bookmarks/shared_content.dart';
import 'package:capsula_core/domain/reader/page_info_service.dart';
import 'package:capsula_core/domain/reader/reader_content.dart';
import 'package:capsula/features/auth/sign_in_screen.dart';
import 'package:capsula/features/bookmarks/bookmark_detail_screen.dart';
import 'package:capsula/features/share/share_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_auth_repository.dart';
import '../../fakes/fake_backend.dart';
import '../../fakes/fake_content_fetcher.dart';
import '../../fakes/fake_share_intake.dart';

import 'package:capsula_core/testing/in_memory_bookmark_repository.dart';

class _Harness {
  _Harness(this.repo, this.intake, this.auth);

  final InMemoryBookmarkRepository repo;
  final FakeShareIntake intake;
  final FakeAuthRepository auth;
}

/// Launches the app at `/share`, the way ShareActivity does.
Future<_Harness> _share(
  WidgetTester tester,
  SharedContent content, {
  bool signedIn = true,
  List<Bookmark> existing = const [],
  FakeContentFetcher? fetcher,
  PageInfoSource? pageInfo,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  tester.platformDispatcher.defaultRouteNameTestValue = '/share';
  addTearDown(tester.platformDispatcher.clearDefaultRouteNameTestValue);

  final auth = FakeAuthRepository(
    initialUser: signedIn
        ? const AppUser(id: 'u1', email: 'a@example.com')
        : null,
  )..accounts['a@example.com'] = 'secret1';
  final repo = InMemoryBookmarkRepository()..addAll(existing);
  final intake = FakeShareIntake(content);

  await tester.pumpWidget(
    CapsulaApp(
      config: const AppConfig(
        environment: AppEnvironment.dev,
        useFirebaseEmulators: false,
        firebaseEmulatorHost: 'localhost',
      ),
      backend: await startedBackend(auth, bookmarks: repo),
      shareIntake: intake,
      pageInfo: pageInfo ?? PageInfoService(fetcher ?? FakeContentFetcher()),
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(repo, intake, auth);
}

void main() {
  testWidgets('saves a shared link and closes', (tester) async {
    final h = await _share(
      tester,
      const SharedContent(
        text: 'https://www.reddit.com/r/flutterdev/comments/abc/hot_reload/',
        subject: 'Hot reload explained',
      ),
    );

    expect(find.text('Saved'), findsOneWidget);
    final saved = h.repo.items.values.single;
    expect(saved.source, BookmarkSource.reddit);
    expect(saved.title, 'Hot reload explained');
    expect(saved.isUnsorted, isTrue);

    expect(h.intake.finishCalls, 0);
    await tester.pump(ShareScreen.autoCloseDelay);
    expect(h.intake.finishCalls, 1);
  });

  testWidgets('saves every link in shared text', (tester) async {
    final h = await _share(
      tester,
      const SharedContent(
        text: 'https://example.com/a and https://youtu.be/xyz987',
      ),
    );

    expect(find.text('Saved 2 links'), findsOneWidget);
    expect(h.repo.items, hasLength(2));
    await tester.pump(ShareScreen.autoCloseDelay);
  });

  testWidgets('reports an already-saved link and stays open', (tester) async {
    final time = DateTime(2026, 3, 5);
    final h = await _share(
      tester,
      const SharedContent(text: 'http://www.example.com/a/'),
      existing: [
        Bookmark(
          id: 'old',
          url: 'https://example.com/a',
          canonicalUrl: 'https://example.com/a',
          title: 'Older copy',
          source: BookmarkSource.website,
          sourceDomain: 'example.com',
          createdAt: time,
          updatedAt: time,
        ),
      ],
    );

    expect(find.text('Already in Capsula'), findsOneWidget);
    expect(find.textContaining('Older copy'), findsOneWidget);
    expect(h.repo.items, hasLength(1));

    await tester.pump(ShareScreen.autoCloseDelay * 2);
    expect(h.intake.finishCalls, 0, reason: 'waits for the user');

    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    expect(find.byType(BookmarkDetailScreen), findsOneWidget);
  });

  testWidgets('explains when no link was shared', (tester) async {
    final h = await _share(
      tester,
      const SharedContent(text: 'Just a thought, no link'),
    );

    expect(find.text('No link found in what was shared.'), findsOneWidget);
    expect(h.repo.items, isEmpty);

    await tester.tap(find.text('Done'));
    await tester.pump();
    expect(h.intake.finishCalls, 1);
  });

  testWidgets('signed-out user signs in first, then the link is saved', (
    tester,
  ) async {
    final h = await _share(
      tester,
      const SharedContent(text: 'https://example.com/later'),
      signedIn: false,
    );

    expect(find.byType(SignInScreen), findsOneWidget);
    expect(h.repo.items, isEmpty);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Email'),
      'a@example.com',
    );
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Password'),
      'secret1',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pumpAndSettle();

    expect(find.byType(ShareScreen), findsOneWidget);
    expect(find.text('Saved'), findsOneWidget);
    expect(h.repo.items.values.single.url, 'https://example.com/later');
    await tester.pump(ShareScreen.autoCloseDelay);
  });

  testWidgets('hides at once and gets the title in the background', (
    tester,
  ) async {
    final lookup = _SlowPageInfo();
    final h = await _share(
      tester,
      const SharedContent(text: 'https://youtu.be/lHhRhPV--G0?si=abc'),
      pageInfo: lookup,
    );

    // Saved and confirmed without waiting for the title.
    expect(find.text('Saved'), findsOneWidget);
    expect(h.repo.items, hasLength(1));
    await tester.pump(ShareScreen.autoCloseDelay);
    expect(h.intake.moveToBackgroundCalls, 1);
    expect(h.intake.finishCalls, 0);

    // The title arrives later, and then the app closes.
    lookup.answer.complete(const PageMetadata(title: 'Flutter in 100 Seconds'));
    await tester.pumpAndSettle();
    expect(h.repo.items.values.single.title, 'Flutter in 100 Seconds');
    expect(h.intake.finishCalls, 1);
  });

  testWidgets('closes anyway when the title never comes', (tester) async {
    final lookup = _SlowPageInfo();
    final h = await _share(
      tester,
      const SharedContent(text: 'https://example.com/slow'),
      pageInfo: lookup,
    );
    await tester.pump(ShareScreen.autoCloseDelay);
    expect(h.intake.moveToBackgroundCalls, 1);

    await tester.pump(ShareScreen.backgroundTimeout);
    await tester.pumpAndSettle();
    expect(h.intake.finishCalls, 1);
    // Saved with the title made from the link; looked up again later.
    expect(h.repo.items, hasLength(1));
  });
}

/// A title lookup that answers only when told to.
class _SlowPageInfo implements PageInfoSource {
  final answer = Completer<PageMetadata?>();

  @override
  Future<PageMetadata?> lookup(Uri url) => answer.future;
}
