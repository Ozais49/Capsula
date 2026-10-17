import 'package:capsula/app/app.dart';
import 'package:capsula/features/bookmarks/bookmark_display.dart';
import 'package:capsula_core/domain/auth/app_user.dart';
import 'package:capsula_core/domain/bookmarks/bookmark.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_repository.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_service.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_source.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_view.dart';
import 'package:capsula_core/testing/in_memory_bookmark_repository.dart';
import 'package:capsula_core/testing/in_memory_label_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_auth_repository.dart';
import '../fakes/fake_backend.dart';
import '../fakes/fake_share_intake.dart';
import '../fakes/navigation.dart';
import '../fakes/test_dependencies.dart';

Bookmark _b(String id, {DateTime? remindAt, bool archived = false}) {
  final t = DateTime(2026, 1, 1);
  return Bookmark(
    id: id,
    url: 'https://example.com/$id',
    canonicalUrl: 'https://example.com/$id',
    title: 'Item $id',
    source: BookmarkSource.website,
    sourceDomain: 'example.com',
    createdAt: t,
    updatedAt: t,
    remindAt: remindAt,
    archived: archived,
  );
}

void main() {
  final now = DateTime(2026, 10, 15, 12);

  test('due when the time has come', () {
    expect(_b('a', remindAt: now).isDue(now), isTrue);
    expect(
      _b('a', remindAt: now.add(const Duration(minutes: 1))).isDue(now),
      isFalse,
    );
    expect(_b('a').isDue(now), isFalse);
  });

  test('Reminders view: only reminders, soonest first, no archived', () async {
    final repo = InMemoryBookmarkRepository()
      ..addAll([
        _b('later', remindAt: now.add(const Duration(days: 3))),
        _b('none'),
        _b('soon', remindAt: now.add(const Duration(hours: 1))),
        _b('archived', remindAt: now, archived: true),
      ]);
    final list = await repo
        .watchList(const BookmarkQuery(view: BookmarkView.reminders), limit: 10)
        .first;
    expect(list.map((b) => b.id), ['soon', 'later']);
  });

  test('set and clear', () async {
    final repo = InMemoryBookmarkRepository()..addAll([_b('a')]);
    final service = BookmarkService(repo, InMemoryLabelRepository(repo));
    await service.setReminder(repo.items['a']!, now);
    expect(repo.items['a']!.remindAt, now);
    await service.setReminder(repo.items['a']!, null);
    expect(repo.items['a']!.remindAt, isNull);
  });

  test('formatReminder', () {
    expect(
      formatReminder(DateTime(2026, 10, 15, 14, 30), now: now),
      'Today 14:30',
    );
    expect(
      formatReminder(DateTime(2026, 10, 16, 9), now: now),
      'Tomorrow 09:00',
    );
    expect(formatReminder(DateTime(2026, 12, 1, 18), now: now), 'Dec 1 18:00');
    expect(
      formatReminder(DateTime(2027, 1, 2, 8), now: now),
      'Jan 2, 2027 08:00',
    );
  });

  testWidgets('set a reminder from detail, see it, clear it', (tester) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final connector = FakeBackendConnector(
      FakeAuthRepository(initialUser: const AppUser(id: 'u1')),
    );
    connector.bookmarks.addAll([
      _b('a'),
      _b('due', remindAt: DateTime.now().subtract(const Duration(hours: 1))),
    ]);
    await tester.pumpWidget(
      CapsulaApp(
        config: testConfig,
        backend: await startedBackendWith(connector),
        shareIntake: FakeShareIntake(),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Item a'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remind me'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Tomorrow morning (09:00)'));
    await tester.pumpAndSettle();

    final remindAt = connector.bookmarks.items['a']!.remindAt!;
    expect(remindAt.hour, 9);
    expect(find.textContaining('Remind Tomorrow 09:00'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear reminder'));
    await tester.pumpAndSettle();
    expect(connector.bookmarks.items['a']!.remindAt, isNull);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await openNavigation(tester);
    expect(find.text('1'), findsWidgets, reason: 'one reminder is due');
    await tester.tap(find.text('Reminders'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(AppBar, 'Reminders'), findsOneWidget);
    expect(find.text('Item due'), findsOneWidget);
    expect(find.text('Item a'), findsNothing);
  });
}
