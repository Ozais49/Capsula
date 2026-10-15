import 'package:capsula/app/app.dart';
import 'package:capsula/config/app_config.dart';
import 'package:capsula_core/domain/auth/app_user.dart';
import 'package:capsula_core/domain/bookmarks/bookmark.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_source.dart';
import 'package:capsula_core/domain/organization/label.dart';
import 'package:capsula/features/bookmarks/library_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_auth_repository.dart';
import '../../fakes/fake_backend.dart';
import '../../fakes/fake_share_intake.dart';
import '../../fakes/navigation.dart';

import 'package:capsula_core/testing/in_memory_bookmark_repository.dart';
import 'package:capsula_core/testing/in_memory_label_repository.dart';

Bookmark _bookmark(
  String id,
  String title, {
  int day = 1,
  bool inInbox = true,
  BookmarkSource source = BookmarkSource.website,
  List<String> tagIds = const [],
  List<String> collectionIds = const [],
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
    inInbox: inInbox,
    tagIds: tagIds,
    collectionIds: collectionIds,
  );
}

class _App {
  _App(this.bookmarks, this.labels);

  final InMemoryBookmarkRepository bookmarks;
  final InMemoryLabelRepository labels;
}

Future<_App> _pump(
  WidgetTester tester, {
  List<Bookmark> bookmarks = const [],
  List<Label> labels = const [],
  Size size = const Size(600, 1200),
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final repo = InMemoryBookmarkRepository()..addAll(bookmarks);
  final connector = FakeBackendConnector(
    FakeAuthRepository(initialUser: const AppUser(id: 'u1')),
    bookmarks: repo,
  );
  connector.labels.addAll(labels);
  final backend = await startedBackendWith(connector);
  await tester.pumpWidget(
    CapsulaApp(
      config: const AppConfig(
        environment: AppEnvironment.dev,
        useFirebaseEmulators: false,
        firebaseEmulatorHost: 'localhost',
      ),
      backend: backend,
      shareIntake: FakeShareIntake(),
    ),
  );
  await tester.pumpAndSettle();
  return _App(repo, connector.labels);
}

Future<void> _openDrawer(WidgetTester tester) async {
  await tester.tap(find.byTooltip('Open navigation menu'));
  await tester.pumpAndSettle();
}

Future<void> _openView(WidgetTester tester, String name) =>
    tapNavigationItem(tester, name);

const _ai = Label(id: 't-ai', kind: LabelKind.tag, name: 'AI');
const _research = Label(
  id: 'c-research',
  kind: LabelKind.collection,
  name: 'Research',
);

void main() {
  testWidgets('starts on the Inbox and shows the Inbox count', (tester) async {
    await _pump(
      tester,
      bookmarks: [
        _bookmark('a', 'New one'),
        _bookmark('b', 'Organized', inInbox: false),
      ],
    );

    expect(find.widgetWithText(AppBar, 'Inbox'), findsOneWidget);
    expect(find.text('New one'), findsOneWidget);
    expect(find.text('Organized'), findsNothing);

    await _openDrawer(tester);
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('source, tag and collection views filter the library', (
    tester,
  ) async {
    await _pump(
      tester,
      labels: [_ai, _research],
      bookmarks: [
        _bookmark('a', 'Reddit thread', source: BookmarkSource.reddit),
        _bookmark('b', 'Tagged paper', tagIds: ['t-ai']),
        _bookmark('c', 'Collected paper', collectionIds: ['c-research']),
      ],
    );

    await _openView(tester, 'Reddit');
    expect(find.widgetWithText(AppBar, 'Reddit'), findsOneWidget);
    expect(find.text('Reddit thread'), findsOneWidget);
    expect(find.text('Tagged paper'), findsNothing);

    await _openView(tester, 'AI');
    expect(find.text('Tagged paper'), findsOneWidget);
    expect(find.text('Reddit thread'), findsNothing);

    await _openView(tester, 'Research');
    expect(find.text('Collected paper'), findsOneWidget);
    expect(find.text('Tagged paper'), findsNothing);

    await _openView(tester, 'All bookmarks');
    expect(find.text('Reddit thread'), findsOneWidget);
    expect(find.text('Tagged paper'), findsOneWidget);
    expect(find.text('Collected paper'), findsOneWidget);
  });

  testWidgets('swiping in the Inbox removes from Inbox, with undo', (
    tester,
  ) async {
    final app = await _pump(tester, bookmarks: [_bookmark('a', 'Swipe me')]);

    await tester.drag(find.text('Swipe me'), const Offset(500, 0));
    await tester.pumpAndSettle();

    expect(app.bookmarks.items['a']!.inInbox, isFalse);
    expect(find.text('Swipe me'), findsNothing);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(app.bookmarks.items['a']!.inInbox, isTrue);
    expect(find.text('Swipe me'), findsOneWidget);
  });

  testWidgets('tag a bookmark from detail, creating the tag', (tester) async {
    final app = await _pump(tester, bookmarks: [_bookmark('a', 'Paper')]);

    await tester.tap(find.text('Paper'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add tag'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'New tag'), 'AI');
    await tester.tap(find.byTooltip('Create'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      isTrue,
    );

    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();

    final tag = app.labels.items.values.single;
    expect(tag.name, 'AI');
    expect(app.bookmarks.items['a']!.tagIds, [tag.id]);
    expect(find.widgetWithText(ActionChip, 'AI'), findsOneWidget);
  });

  testWidgets('remove from Inbox from detail', (tester) async {
    final app = await _pump(tester, bookmarks: [_bookmark('a', 'Paper')]);

    await tester.tap(find.text('Paper'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Done, remove from Inbox'));
    await tester.pumpAndSettle();

    expect(app.bookmarks.items['a']!.inInbox, isFalse);
    expect(find.text('Move back to Inbox'), findsOneWidget);
  });

  testWidgets('search suggests matching tags and collections', (tester) async {
    await _pump(
      tester,
      labels: [_ai, _research],
      bookmarks: [
        _bookmark('b', 'Tagged paper', tagIds: ['t-ai']),
      ],
    );

    await tester.enterText(find.byKey(LibraryScreen.searchFieldKey), 'resea');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ActionChip, 'Research'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Research'), findsOneWidget);
  });

  testWidgets('create, rename and delete a collection from navigation', (
    tester,
  ) async {
    final app = await _pump(
      tester,
      bookmarks: [
        _bookmark('a', 'Paper', collectionIds: ['c-research']),
      ],
      labels: [_research],
    );

    await _openDrawer(tester);
    await tester.tap(find.byTooltip('New collection'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Name'),
      'Japan Trip',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();
    expect(
      app.labels.items.values.map((l) => l.name),
      containsAll(['Research', 'Japan Trip']),
    );

    await tester.tap(find.byTooltip('Research options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Papers');
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(app.labels.items['c-research']!.name, 'Papers');

    await tester.tap(find.byTooltip('Papers options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(app.labels.items.containsKey('c-research'), isFalse);
    expect(app.bookmarks.items['a']!.collectionIds, isEmpty);
    expect(app.bookmarks.items, contains('a'), reason: 'bookmark kept');
  });

  testWidgets('wide screens show navigation beside the list', (tester) async {
    await _pump(tester, size: const Size(1400, 900));

    expect(find.byTooltip('Open navigation menu'), findsNothing);
    expect(find.text('All bookmarks'), findsOneWidget);

    await tester.tap(find.text('Archived'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Archived'), findsOneWidget);
  });
}
