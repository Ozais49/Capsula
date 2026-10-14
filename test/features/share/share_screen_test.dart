import 'package:capsula/app/app.dart';
import 'package:capsula/config/app_config.dart';
import 'package:capsula/domain/auth/app_user.dart';
import 'package:capsula/domain/bookmarks/bookmark.dart';
import 'package:capsula/domain/bookmarks/bookmark_source.dart';
import 'package:capsula/domain/bookmarks/shared_content.dart';
import 'package:capsula/features/auth/sign_in_screen.dart';
import 'package:capsula/features/bookmarks/bookmark_detail_screen.dart';
import 'package:capsula/features/share/share_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_auth_repository.dart';
import '../../fakes/fake_backend.dart';
import '../../fakes/fake_share_intake.dart';
import '../../fakes/in_memory_bookmark_repository.dart';

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
    ),
  );
  await tester.pumpAndSettle();
  return _Harness(repo, intake, auth);
}

void main() {
  testWidgets('saves a shared link to the Inbox and closes', (tester) async {
    final h = await _share(
      tester,
      const SharedContent(
        text: 'https://www.reddit.com/r/flutterdev/comments/abc/hot_reload/',
        subject: 'Hot reload explained',
      ),
    );

    expect(find.text('Saved to Inbox'), findsOneWidget);
    final saved = h.repo.items.values.single;
    expect(saved.source, BookmarkSource.reddit);
    expect(saved.title, 'Hot reload explained');
    expect(saved.inInbox, isTrue);

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

    expect(find.text('Saved 2 links to Inbox'), findsOneWidget);
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
    expect(find.text('Saved to Inbox'), findsOneWidget);
    expect(h.repo.items.values.single.url, 'https://example.com/later');
    await tester.pump(ShareScreen.autoCloseDelay);
  });
}
