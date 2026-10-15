import 'package:capsula/app/app.dart';
import 'package:capsula/app/display_preferences.dart';
import 'package:capsula/features/bookmarks/bookmark_cards.dart';
import 'package:capsula_core/domain/auth/app_user.dart';
import 'package:capsula_core/domain/bookmarks/bookmark.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_source.dart';
import 'package:capsula_core/domain/organization/label.dart';
import 'package:capsula_core/testing/in_memory_bookmark_repository.dart';
import 'package:capsula_core/testing/in_memory_label_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_auth_repository.dart';
import '../fakes/fake_backend.dart';
import '../fakes/fake_share_intake.dart';
import '../fakes/navigation.dart';
import '../fakes/test_dependencies.dart';

Bookmark _b(String id, String title, {int day = 1}) {
  final t = DateTime(2026, 1, day);
  return Bookmark(
    id: id,
    url: 'https://example.com/$id',
    canonicalUrl: 'https://example.com/$id',
    title: title,
    source: BookmarkSource.website,
    sourceDomain: 'example.com',
    createdAt: t,
    updatedAt: t,
  );
}

class _App {
  _App(this.bookmarks, this.labels, this.display);

  final InMemoryBookmarkRepository bookmarks;
  final InMemoryLabelRepository labels;
  final DisplayPreferences display;
}

Future<_App> _pump(
  WidgetTester tester, {
  List<Bookmark> bookmarks = const [],
  List<Label> labels = const [],
}) async {
  tester.view.physicalSize = const Size(800, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final connector = FakeBackendConnector(
    FakeAuthRepository(initialUser: const AppUser(id: 'u1')),
  );
  connector.bookmarks.addAll(bookmarks);
  connector.labels.addAll(labels);
  final display = DisplayPreferences(persist: false);
  await tester.pumpWidget(
    CapsulaApp(
      config: testConfig,
      backend: await startedBackendWith(connector),
      shareIntake: FakeShareIntake(),
      display: display,
    ),
  );
  await tester.pumpAndSettle();
  return _App(connector.bookmarks, connector.labels, display);
}

Future<void> _openView(WidgetTester tester, String name) =>
    tapNavigationItem(tester, name);

void main() {
  testWidgets('star from detail and see it under Favorites', (tester) async {
    final app = await _pump(tester, bookmarks: [_b('a', 'Paper')]);

    await tester.tap(find.text('Paper'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add to favorites'));
    await tester.pumpAndSettle();
    expect(app.bookmarks.items['a']!.favorite, isTrue);
    expect(find.byTooltip('Remove from favorites'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await _openView(tester, 'Favorites');
    expect(find.widgetWithText(AppBar, 'Favorites'), findsOneWidget);
    expect(find.text('Paper'), findsOneWidget);
  });

  testWidgets('switch to cards and grid; sort oldest first', (tester) async {
    final app = await _pump(
      tester,
      bookmarks: [_b('a', 'Older', day: 1), _b('b', 'Newer', day: 2)],
    );

    await tester.tap(find.byTooltip('Display'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Grid'));
    await tester.pumpAndSettle();
    expect(app.display.layout, LibraryLayout.grid);
    expect(find.byType(BookmarkCard), findsNWidgets(2));

    await tester.tap(find.byTooltip('Display'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Oldest first'));
    await tester.pumpAndSettle();
    final older = tester.getTopLeft(find.text('Older'));
    final newer = tester.getTopLeft(find.text('Newer'));
    expect(older.dx < newer.dx || older.dy < newer.dy, isTrue);

    await tester.tap(find.byTooltip('Display'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cards'));
    await tester.pumpAndSettle();
    expect(find.byType(BookmarkCard), findsNWidgets(2));
  });

  testWidgets('long-press to select, then bulk favorite and archive', (
    tester,
  ) async {
    final app = await _pump(
      tester,
      bookmarks: [_b('a', 'One'), _b('b', 'Two'), _b('c', 'Three')],
    );

    await tester.longPress(find.text('One'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Two'));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.byTooltip('Add to favorites'));
    await tester.pumpAndSettle();
    expect(app.bookmarks.items['a']!.favorite, isTrue);
    expect(app.bookmarks.items['b']!.favorite, isTrue);
    expect(app.bookmarks.items['c']!.favorite, isFalse);
    expect(find.text('2 selected'), findsNothing, reason: 'selection ends');

    await tester.longPress(find.text('Three'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More actions'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    expect(app.bookmarks.items['c']!.archived, isTrue);
    expect(find.text('Three'), findsNothing);
  });

  testWidgets('bulk add to a collection', (tester) async {
    final app = await _pump(
      tester,
      bookmarks: [_b('a', 'One'), _b('b', 'Two')],
      labels: const [Label(id: 'c1', kind: LabelKind.collection, name: 'Work')],
    );

    await tester.longPress(find.text('One'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Two'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add to collection'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Work'));
    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();

    expect(app.bookmarks.items['a']!.collectionIds, ['c1']);
    expect(app.bookmarks.items['b']!.collectionIds, ['c1']);
  });

  testWidgets('cancel selection with the close button', (tester) async {
    await _pump(tester, bookmarks: [_b('a', 'One')]);
    await tester.longPress(find.text('One'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Cancel selection'));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsNothing);
    expect(find.text('Add'), findsOneWidget);
  });

  testWidgets('create a sub-collection and move it to the top level', (
    tester,
  ) async {
    final app = await _pump(
      tester,
      labels: const [Label(id: 'w', kind: LabelKind.collection, name: 'Work')],
    );

    await openNavigation(tester);
    await tester.tap(find.byTooltip('Work options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New collection inside'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Reports');
    await tester.tap(find.widgetWithText(FilledButton, 'Create'));
    await tester.pumpAndSettle();

    final reports = app.labels.items.values.firstWhere(
      (l) => l.name == 'Reports',
    );
    expect(reports.parentId, 'w');
    final workLeft = tester.getTopLeft(find.text('Work')).dx;
    final reportsLeft = tester.getTopLeft(find.text('Reports')).dx;
    expect(reportsLeft, greaterThan(workLeft), reason: 'indented under Work');

    await tester.tap(find.byTooltip('Reports options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move to…'));
    await tester.pumpAndSettle();
    expect(
      find.text('Work / Reports'),
      findsNothing,
      reason: 'not into itself',
    );
    await tester.tap(find.text('Top level'));
    await tester.pumpAndSettle();
    expect(app.labels.items[reports.id]!.parentId, isNull);
  });
}
