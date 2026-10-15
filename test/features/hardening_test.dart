import 'dart:convert';
import 'dart:typed_data';

import 'package:capsula/app/app.dart';
import 'package:capsula/config/app_config.dart';
import 'package:capsula_core/domain/auth/app_user.dart';
import 'package:capsula_core/domain/bookmarks/bookmark.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_source.dart';
import 'package:capsula/features/auth/sign_in_screen.dart';
import 'package:capsula/platform/file_saver.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_auth_repository.dart';
import '../fakes/fake_backend.dart';
import '../fakes/fake_share_intake.dart';

import 'package:capsula_core/testing/in_memory_bookmark_repository.dart';

import '../fakes/navigation.dart';

class _FakeSaver implements FileSaver {
  String? name;
  String? mimeType;
  Uint8List? bytes;
  bool accept = true;

  @override
  Future<bool> save(String name, String mimeType, Uint8List bytes) async {
    if (!accept) return false;
    this.name = name;
    this.mimeType = mimeType;
    this.bytes = bytes;
    return true;
  }
}

Bookmark _bookmark(String id, String title) {
  final t = DateTime(2026, 1, 1);
  return Bookmark(
    id: id,
    url: 'https://example.com/$id',
    canonicalUrl: 'https://example.com/$id',
    title: title,
    source: BookmarkSource.github,
    sourceDomain: 'example.com',
    createdAt: t,
    updatedAt: t,
  );
}

Future<InMemoryBookmarkRepository> _pump(
  WidgetTester tester, {
  bool signedIn = true,
  FileSaver? saver,
  List<Bookmark> bookmarks = const [],
}) async {
  tester.view.physicalSize = const Size(600, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final repo = InMemoryBookmarkRepository()..addAll(bookmarks);
  await tester.pumpWidget(
    CapsulaApp(
      config: const AppConfig(
        environment: AppEnvironment.dev,
        useFirebaseEmulators: false,
        firebaseEmulatorHost: 'localhost',
      ),
      backend: await startedBackend(
        FakeAuthRepository(
          initialUser: signedIn ? const AppUser(id: 'u1') : null,
        ),
        bookmarks: repo,
      ),
      shareIntake: FakeShareIntake(),
      fileSaver: saver ?? _FakeSaver(),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

void main() {
  group('export', () {
    testWidgets('saves a JSON backup of the library', (tester) async {
      final saver = _FakeSaver();
      await _pump(
        tester,
        saver: saver,
        bookmarks: [_bookmark('a', 'One'), _bookmark('b', 'Two')],
      );

      await openSettingsItem(tester, 'Export library');
      await tester.tap(find.widgetWithText(FilledButton, 'Export'));
      await tester.pumpAndSettle();

      expect(saver.name, matches(RegExp(r'^capsula-\d{4}-\d{2}-\d{2}\.json$')));
      expect(saver.mimeType, 'application/json');
      final json = jsonDecode(utf8.decode(saver.bytes!)) as Map;
      expect((json['bookmarks'] as List).length, 2);
      expect(find.text('Exported 2 bookmarks'), findsOneWidget);
    });

    testWidgets('can export browser HTML; cancelling keeps the dialog', (
      tester,
    ) async {
      final saver = _FakeSaver()..accept = false;
      await _pump(tester, saver: saver, bookmarks: [_bookmark('a', 'One')]);

      await openSettingsItem(tester, 'Export library');
      await tester.tap(find.text('Browser bookmarks (HTML)'));
      await tester.tap(find.widgetWithText(FilledButton, 'Export'));
      await tester.pumpAndSettle();
      expect(find.text('Export library'), findsWidgets, reason: 'still open');

      saver.accept = true;
      await tester.tap(find.widgetWithText(FilledButton, 'Export'));
      await tester.pumpAndSettle();
      expect(saver.mimeType, 'text/html');
      expect(utf8.decode(saver.bytes!), contains('NETSCAPE-Bookmark-file-1'));
    });
  });

  testWidgets('edit a bookmark title', (tester) async {
    final repo = await _pump(tester, bookmarks: [_bookmark('a', 'Old title')]);

    await tester.tap(find.text('Old title'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Edit title'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Title'),
      'New title',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(repo.items['a']!.title, 'New title');
    expect(find.text('New title'), findsOneWidget);
  });

  testWidgets('inbox items offer a screen reader action instead of swiping', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    final repo = await _pump(tester, bookmarks: [_bookmark('a', 'Paper')]);

    final node = tester.getSemantics(find.text('Paper'));
    final actions = node.getSemanticsData().customSemanticsActionIds ?? [];
    expect(actions, isNotEmpty);

    node.owner!.performAction(
      node.id,
      SemanticsAction.customAction,
      actions.first,
    );
    await tester.pumpAndSettle();
    expect(repo.items['a']!.inInbox, isFalse);
    handle.dispose();
  });

  group('accessibility guidelines', () {
    Future<void> checkGuidelines(WidgetTester tester) async {
      await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
      await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
      await expectLater(tester, meetsGuideline(textContrastGuideline));
    }

    testWidgets('sign-in screen', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, signedIn: false);
      expect(find.byType(SignInScreen), findsOneWidget);
      await checkGuidelines(tester);
      handle.dispose();
    });

    testWidgets('library', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, bookmarks: [_bookmark('a', 'Paper')]);
      await checkGuidelines(tester);
      handle.dispose();
    });

    testWidgets('bookmark detail', (tester) async {
      final handle = tester.ensureSemantics();
      await _pump(tester, bookmarks: [_bookmark('a', 'Paper')]);
      await tester.tap(find.text('Paper'));
      await tester.pumpAndSettle();
      await checkGuidelines(tester);
      handle.dispose();
    });
  });
}
