import 'package:capsula/features/bookmarks/library_navigation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Makes the library navigation visible: opens the drawer on narrow
/// layouts; on wide layouts it is already shown beside the list.
Future<void> openNavigation(WidgetTester tester) async {
  final menu = find.byTooltip('Open navigation menu');
  if (menu.evaluate().isNotEmpty) {
    await tester.tap(menu);
    await tester.pumpAndSettle();
  }
}

/// Opens navigation and taps the item labelled [text], scrolling the
/// (lazily built) list until it exists.
Future<void> tapNavigationItem(WidgetTester tester, String text) async {
  await openNavigation(tester);
  final list = find
      .descendant(
        of: find.byType(LibraryNavigation),
        matching: find.byType(Scrollable),
      )
      .first;
  final item = find.descendant(
    of: find.byType(LibraryNavigation),
    matching: find.text(text),
  );
  await tester.scrollUntilVisible(item, 100, scrollable: list);
  await tester.pumpAndSettle();
  await tester.tap(item.first);
  await tester.pumpAndSettle();
}

/// Opens Settings from the navigation header and taps the item labelled
/// [text].
Future<void> openSettingsItem(WidgetTester tester, String text) async {
  await openNavigation(tester);
  await tester.tap(find.byTooltip('Settings'));
  await tester.pumpAndSettle();
  final item = find.text(text);
  await tester.scrollUntilVisible(
    item,
    100,
    scrollable: find.byType(Scrollable).last,
  );
  await tester.pumpAndSettle();
  await tester.tap(item.first);
  await tester.pumpAndSettle();
}
