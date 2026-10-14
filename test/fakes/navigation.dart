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
