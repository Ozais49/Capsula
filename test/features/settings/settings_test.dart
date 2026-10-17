import 'package:capsula/app/app.dart';
import 'package:capsula/app/display_preferences.dart';
import 'package:capsula/features/auth/sign_in_screen.dart';
import 'package:capsula/features/bookmarks/library_screen.dart';
import 'package:capsula/platform/clipboard_reader.dart';
import 'package:capsula_core/domain/auth/app_user.dart';
import 'package:capsula_core/domain/bookmarks/bookmark.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_source.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_service.dart';
import 'package:capsula_core/domain/organization/label.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fakes/fake_auth_repository.dart';
import '../../fakes/fake_backend.dart';
import '../../fakes/fake_share_intake.dart';
import '../../fakes/navigation.dart';
import '../../fakes/test_dependencies.dart';

class _FakeClipboard implements ClipboardReader {
  _FakeClipboard(this.text);
  String? text;

  @override
  Future<String?> read() async => text;
}

Future<FakeBackendConnector> _pump(
  WidgetTester tester, {
  ClipboardReader clipboard = const _NoClipboard(),
}) async {
  final connector = FakeBackendConnector(
    FakeAuthRepository(
      initialUser: const AppUser(id: 'u1', email: 'maya@example.com'),
    ),
  );
  await tester.pumpWidget(
    CapsulaApp(
      config: testConfig,
      backend: await startedBackendWith(connector),
      shareIntake: FakeShareIntake(),
      clipboard: clipboard,
    ),
  );
  await tester.pumpAndSettle();
  return connector;
}

class _NoClipboard implements ClipboardReader {
  const _NoClipboard();

  @override
  Future<String?> read() async => null;
}

void main() {
  setUp(() => LibraryScreen.lastOfferedLink = null);

  testWidgets('navigation greets the user and can log out', (tester) async {
    await _pump(tester);
    await openNavigation(tester);
    expect(find.text('Hello, @maya'), findsOneWidget);
    expect(find.text('Import bookmarks'), findsNothing, reason: 'in Settings');

    await tester.tap(find.byTooltip('Log out'));
    await tester.pumpAndSettle();
    expect(find.byType(SignInScreen), findsOneWidget);
  });

  testWidgets('settings lists the library tools and integrations', (
    tester,
  ) async {
    await _pump(tester);
    await openNavigation(tester);
    await tester.tap(find.byTooltip('Settings'));
    await tester.pumpAndSettle();

    for (final item in [
      '@maya',
      'Import bookmarks',
      'Export library',
      'Sources',
      'Maintenance',
      'Offer to save copied links',
    ]) {
      await tester.scrollUntilVisible(
        find.text(item),
        100,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text(item), findsOneWidget, reason: item);
    }
    await tester.scrollUntilVisible(
      find.text('Connection settings'),
      100,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('API & integrations'), findsOneWidget);
  });

  testWidgets('offers to save a copied link once', (tester) async {
    final clipboard = _FakeClipboard('look https://news.example.com/story');
    final connector = await _pump(tester, clipboard: clipboard);

    expect(find.textContaining('Save the link you copied?'), findsOneWidget);
    await tester.tap(find.widgetWithText(SnackBarAction, 'Save'));
    await tester.pumpAndSettle();
    expect(
      connector.bookmarks.items.values.map((b) => b.url),
      contains('https://news.example.com/story'),
    );

    // Coming back to the app doesn't offer the same link again.
    _resume(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('Save the link you copied?'), findsNothing);
  });

  testWidgets('does not offer links already saved or when turned off', (
    tester,
  ) async {
    final t = DateTime(2026, 1, 1);
    final clipboard = _FakeClipboard('https://saved.example.com/a');
    final connector = FakeBackendConnector(
      FakeAuthRepository(initialUser: const AppUser(id: 'u1')),
    );
    connector.bookmarks.addAll([
      Bookmark(
        id: 'a',
        url: 'https://saved.example.com/a',
        canonicalUrl: 'https://saved.example.com/a',
        title: 'Saved',
        source: BookmarkSource.website,
        sourceDomain: 'saved.example.com',
        createdAt: t,
        updatedAt: t,
      ),
    ]);
    final display = DisplayPreferences(persist: false);
    await tester.pumpWidget(
      CapsulaApp(
        config: testConfig,
        backend: await startedBackendWith(connector),
        shareIntake: FakeShareIntake(),
        clipboard: clipboard,
        display: display,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('Save the link you copied?'), findsNothing);

    display.setOfferCopiedLinks(false);
    clipboard.text = 'https://new.example.com/b';
    _resume(tester);
    await tester.pumpAndSettle();
    expect(find.textContaining('Save the link you copied?'), findsNothing);
  });

  testWidgets('add a source and apply it to saved bookmarks', (tester) async {
    final connector = await _pump(tester);
    final time = DateTime(2026, 10, 17);
    connector.bookmarks.addAll([
      Bookmark(
        id: 'a',
        url: 'https://amazon.com/dp/1',
        canonicalUrl: 'https://amazon.com/dp/1',
        title: 'Kettle',
        source: BookmarkSource.website,
        sourceDomain: 'amazon.com',
        createdAt: time,
        updatedAt: time,
      ),
    ]);
    await openSettingsItem(tester, 'Sources');
    expect(find.text('None yet'), findsOneWidget);

    await tester.tap(find.text('Add source'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Amazon');
    await tester.enterText(
      find.widgetWithText(TextField, 'Domains'),
      'not a domain',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(find.text('"not" is not a domain'), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, 'Domains'),
      'amazon.com, amzn.to',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    // Offered right away for bookmarks already saved.
    await tester.tap(find.widgetWithText(FilledButton, 'Apply'));
    await tester.pumpAndSettle();
    expect(find.text('Updated 1 bookmark'), findsOneWidget);
    expect(find.text('amazon.com, amzn.to'), findsOneWidget);

    final amazon = connector.sources.items.values.single;
    expect(connector.bookmarks.items['a']!.customSourceId, amazon.id);
  });

  testWidgets('make a rule that tags links from a site', (tester) async {
    final connector = await _pump(tester);
    connector.labels.addAll([
      const Label(id: 'shop', kind: LabelKind.tag, name: 'Shopping'),
    ]);
    await openSettingsItem(tester, 'Rules');
    expect(find.text('No rules yet'), findsOneWidget);

    await tester.tap(find.text('Add rule'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, 'Name'), 'Amazon');
    await tester.enterText(
      find.widgetWithText(TextField, 'amazon.com'),
      'amazon.com',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(
      find.text(
        'Choose tags, a collection or a star to add',
        skipOffstage: false,
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Add tags'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(CheckboxListTile, 'Shopping'));
    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    final rule = connector.rules.items.values.single;
    expect(rule.name, 'Amazon');
    expect(rule.tagIds, ['shop']);
    expect(find.text('Domain is amazon.com → #Shopping'), findsOneWidget);

    // New links follow it.
    final service = BookmarkService(
      connector.bookmarks,
      connector.labels,
      rules: connector.rules,
    );
    final saved = await service.save('https://amazon.com/dp/1') as Saved;
    expect(saved.bookmark.tagIds, ['shop']);
  });
}

/// Leaves the app and comes back to it.
void _resume(WidgetTester tester) {
  for (final state in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(state);
  }
}
