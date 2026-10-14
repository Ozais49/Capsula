import 'package:capsula/app/app.dart';
import 'package:capsula/config/app_config.dart';
import 'package:capsula/domain/auth/app_user.dart';
import 'package:capsula/domain/bookmarks/bookmark.dart';
import 'package:capsula/domain/bookmarks/bookmark_source.dart';
import 'package:capsula/features/bookmarks/bookmark_detail_screen.dart';
import 'package:capsula/features/bookmarks/library_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_auth_repository.dart';
import '../../fakes/fake_backend.dart';
import '../../fakes/in_memory_bookmark_repository.dart';

Bookmark _bookmark(
  String id,
  String title, {
  int day = 1,
  bool archived = false,
  BookmarkSource source = BookmarkSource.website,
}) {
  final time = DateTime(2026, 1, day);
  return Bookmark(
    id: id,
    url: 'https://example.com/$id',
    canonicalUrl: 'https://example.com/$id',
    title: title,
    source: source,
    sourceDomain: 'example.com',
    createdAt: time,
    updatedAt: time,
    archived: archived,
  );
}

Future<InMemoryBookmarkRepository> _pumpSignedIn(
  WidgetTester tester, [
  List<Bookmark> bookmarks = const [],
]) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final repo = InMemoryBookmarkRepository()..addAll(bookmarks);
  final backend = await startedBackend(
    FakeAuthRepository(
      initialUser: const AppUser(id: 'u1', email: 'a@example.com'),
    ),
    bookmarks: repo,
  );
  await tester.pumpWidget(
    CapsulaApp(
      config: const AppConfig(
        environment: AppEnvironment.dev,
        useFirebaseEmulators: false,
        firebaseEmulatorHost: 'localhost',
      ),
      backend: backend,
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

Future<void> _addLink(WidgetTester tester, String url) async {
  await tester.tap(find.text('Add'));
  await tester.pumpAndSettle();
  await tester.enterText(find.widgetWithText(TextField, 'URL'), url);
  await tester.tap(find.widgetWithText(FilledButton, 'Save'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('empty library invites adding a link', (tester) async {
    await _pumpSignedIn(tester);

    expect(find.byType(LibraryScreen), findsOneWidget);
    expect(find.textContaining('No bookmarks yet'), findsOneWidget);
  });

  testWidgets('lists bookmarks newest first and hides archived', (
    tester,
  ) async {
    await _pumpSignedIn(tester, [
      _bookmark('a', 'Older', day: 1),
      _bookmark('b', 'Newer', day: 2),
      _bookmark('c', 'Put away', day: 3, archived: true),
    ]);

    final newer = tester.getTopLeft(find.text('Newer')).dy;
    final older = tester.getTopLeft(find.text('Older')).dy;
    expect(newer, lessThan(older));
    expect(find.text('Put away'), findsNothing);

    await tester.tap(find.text('Archived'));
    await tester.pumpAndSettle();
    expect(find.text('Put away'), findsOneWidget);
    expect(find.text('Newer'), findsNothing);
  });

  testWidgets('search filters the list', (tester) async {
    await _pumpSignedIn(tester, [
      _bookmark('a', 'Flutter layout guide'),
      _bookmark('b', 'Cooking rice'),
    ]);

    await tester.enterText(find.byType(SearchBar), 'flut');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(find.text('Flutter layout guide'), findsOneWidget);
    expect(find.text('Cooking rice'), findsNothing);

    await tester.enterText(find.byType(SearchBar), 'python');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(find.textContaining('No bookmarks match'), findsOneWidget);
  });

  testWidgets('adding a link saves it to the Inbox', (tester) async {
    final repo = await _pumpSignedIn(tester);

    await _addLink(tester, 'https://www.youtube.com/watch?v=abc123&si=x');

    expect(find.text('Saved to Inbox'), findsOneWidget);
    expect(repo.items.values.single.source, BookmarkSource.youtube);
    expect(repo.items.values.single.inInbox, isTrue);
    expect(find.text('youtube.com'), findsWidgets);
  });

  testWidgets('adding an invalid link shows an error', (tester) async {
    final repo = await _pumpSignedIn(tester);

    await _addLink(tester, 'not a link');

    expect(find.textContaining('Enter a web address'), findsOneWidget);
    expect(repo.items, isEmpty);
  });

  testWidgets('adding a duplicate offers the existing bookmark', (
    tester,
  ) async {
    final repo = await _pumpSignedIn(tester, [_bookmark('a', 'The article')]);

    await _addLink(tester, 'http://www.example.com/a/');

    expect(find.text('Already saved'), findsOneWidget);
    expect(repo.items, hasLength(1));

    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    expect(find.byType(BookmarkDetailScreen), findsOneWidget);
  });

  testWidgets('a sync failure after saving is reported', (tester) async {
    final repo = await _pumpSignedIn(tester);
    repo.nextWriteError = Exception('permission-denied');

    await _addLink(tester, 'https://example.com/x');

    expect(find.textContaining('sync failed'), findsOneWidget);
  });

  testWidgets('detail shows the bookmark and changes reading status', (
    tester,
  ) async {
    final repo = await _pumpSignedIn(tester, [
      _bookmark('a', 'Deep dive', source: BookmarkSource.github),
    ]);

    await tester.tap(find.text('Deep dive'));
    await tester.pumpAndSettle();

    expect(find.byType(BookmarkDetailScreen), findsOneWidget);
    expect(find.text('GitHub'), findsOneWidget);
    expect(find.text('https://example.com/a'), findsOneWidget);
    expect(find.text('Open in browser'), findsOneWidget);

    await tester.tap(find.text('Reading'));
    await tester.pumpAndSettle();
    expect(repo.items['a']!.readingStatus, ReadingStatus.reading);
  });

  testWidgets('archive from detail moves the bookmark to Archived', (
    tester,
  ) async {
    final repo = await _pumpSignedIn(tester, [_bookmark('a', 'Keep later')]);

    await tester.tap(find.text('Keep later'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Archive'));
    await tester.pumpAndSettle();

    expect(repo.items['a']!.archived, isTrue);
    expect(find.byTooltip('Unarchive'), findsOneWidget);
  });

  testWidgets('delete asks for confirmation and returns to the list', (
    tester,
  ) async {
    final repo = await _pumpSignedIn(tester, [_bookmark('a', 'Remove me')]);

    await tester.tap(find.text('Remove me'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.items, contains('a'));

    await tester.tap(find.byTooltip('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(repo.items, isEmpty);
    expect(find.byType(LibraryScreen), findsOneWidget);
    expect(find.text('Remove me'), findsNothing);
  });
}
