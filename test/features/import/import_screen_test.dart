import 'package:capsula/app/app.dart';
import 'package:capsula/config/app_config.dart';
import 'package:capsula/domain/auth/app_user.dart';
import 'package:capsula/domain/bookmarks/bookmark_source.dart';
import 'package:capsula/features/import/import_screen.dart';
import 'package:capsula/platform/import_file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../domain/import_parsers_test.dart' show chromeExport;
import '../../fakes/fake_auth_repository.dart';
import '../../fakes/fake_backend.dart';
import '../../fakes/fake_share_intake.dart';
import '../../fakes/in_memory_bookmark_repository.dart';
import '../../fakes/navigation.dart';

class _FakePicker implements ImportFilePicker {
  PickedImportFile? next;

  @override
  Future<PickedImportFile?> pick() async => next;
}

class _Harness {
  _Harness(this.connector, this.picker);

  final FakeBackendConnector connector;
  final _FakePicker picker;

  InMemoryBookmarkRepository get bookmarks => connector.bookmarks;
}

Future<_Harness> _openImport(WidgetTester tester) async {
  tester.view.physicalSize = const Size(700, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);

  final connector = FakeBackendConnector(
    FakeAuthRepository(initialUser: const AppUser(id: 'u1')),
  );
  final picker = _FakePicker();
  await tester.pumpWidget(
    CapsulaApp(
      config: const AppConfig(
        environment: AppEnvironment.dev,
        useFirebaseEmulators: false,
        firebaseEmulatorHost: 'localhost',
      ),
      backend: await startedBackendWith(connector),
      shareIntake: FakeShareIntake(),
      importFilePicker: picker,
    ),
  );
  await tester.pumpAndSettle();
  await openNavigation(tester);
  await tester.tap(find.text('Import bookmarks'));
  await tester.pumpAndSettle();
  return _Harness(connector, picker);
}

void main() {
  testWidgets('imports a Chrome export after a preview', (tester) async {
    final h = await _openImport(tester);
    expect(find.byType(ImportScreen), findsOneWidget);

    h.picker.next = const PickedImportFile('bookmarks.html', chromeExport);
    await tester.tap(find.text('Chrome'));
    await tester.pumpAndSettle();

    expect(find.text('Import preview'), findsOneWidget);
    expect(find.text('bookmarks.html · from Chrome'), findsOneWidget);
    expect(h.bookmarks.items, isEmpty, reason: 'nothing written yet');

    await tester.tap(find.text('Import 4 bookmarks'));
    await tester.pumpAndSettle();

    expect(find.text('Import complete'), findsOneWidget);
    expect(h.bookmarks.items, hasLength(4));
    expect(
      h.bookmarks.items.values.every((b) => b.importedFrom == 'Chrome'),
      isTrue,
    );
    final collections = h.connector.labels.items.values.map((l) => l.name);
    expect(collections, containsAll(['AI Research', 'Papers to read']));

    await tester.tap(find.widgetWithText(FilledButton, 'Done'));
    await tester.pumpAndSettle();
    expect(find.byType(ImportScreen), findsNothing);
  });

  testWidgets('maps columns of an unknown CSV', (tester) async {
    final h = await _openImport(tester);

    h.picker.next = const PickedImportFile(
      'export.csv',
      'Address,Name,Kind\n'
          'https://github.com/flutter/flutter,Flutter repo,dev\n'
          'https://example.com/a,Example,misc\n',
    );
    await tester.tap(find.text('Other file'));
    await tester.pumpAndSettle();

    expect(find.text('Match the columns'), findsOneWidget);
    // "Address" and "Name" are recognized; pick "Kind" as the folder.
    await tester.tap(find.text('Folder → Collection'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kind').last);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import 2 bookmarks'));
    await tester.pumpAndSettle();

    final github = h.bookmarks.items.values.firstWhere(
      (b) => b.source == BookmarkSource.github,
    );
    expect(github.title, 'Flutter repo');
    expect(h.connector.labels.items[github.collectionIds.single]!.name, 'dev');
  });

  testWidgets('reports when everything is already saved', (tester) async {
    final h = await _openImport(tester);
    h.picker.next = const PickedImportFile('a.html', chromeExport);
    await tester.tap(find.text('Chrome'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import 4 bookmarks'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Import another file'));
    await tester.pumpAndSettle();

    h.picker.next = const PickedImportFile('a.html', chromeExport);
    await tester.tap(find.text('Chrome'));
    await tester.pumpAndSettle();

    expect(find.text('Nothing new to import.'), findsOneWidget);
    expect(h.bookmarks.items, hasLength(4));
  });

  testWidgets('explains unreadable files', (tester) async {
    final h = await _openImport(tester);
    h.picker.next = const PickedImportFile('empty.csv', 'url,title\n');
    await tester.tap(find.text('Other file'));
    await tester.pumpAndSettle();
    expect(find.text('No bookmarks found in this file.'), findsOneWidget);
  });
}
