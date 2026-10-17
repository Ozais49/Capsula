import 'dart:convert';

import 'package:capsula/app/app.dart';
import 'package:capsula/features/highlights/highlights_screen.dart';
import 'package:capsula_core/domain/auth/app_user.dart';
import 'package:capsula_core/domain/bookmarks/bookmark.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_service.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_source.dart';
import 'package:capsula_core/domain/export/library_export.dart';
import 'package:capsula_core/domain/highlights/highlight.dart';
import 'package:capsula_core/domain/reader/reader_service.dart';
import 'package:capsula_core/testing/in_memory_bookmark_repository.dart';
import 'package:capsula_core/testing/in_memory_highlight_repository.dart';
import 'package:capsula_core/testing/in_memory_label_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/fake_auth_repository.dart';
import '../fakes/fake_backend.dart';
import '../fakes/fake_content_fetcher.dart';
import '../fakes/fake_share_intake.dart';
import '../fakes/navigation.dart';
import '../fakes/test_dependencies.dart';

final _t = DateTime(2026, 1, 1);

Bookmark _bookmark() => Bookmark(
  id: 'b1',
  url: 'https://blog.example.com/rice',
  canonicalUrl: 'https://blog.example.com/rice',
  title: 'Rice guide',
  source: BookmarkSource.website,
  sourceDomain: 'blog.example.com',
  createdAt: _t,
  updatedAt: _t,
);

Highlight _h(String id, String text, {String? note}) =>
    Highlight(id: id, bookmarkId: 'b1', text: text, note: note, createdAt: _t);

class _App {
  _App(this.connector);
  final FakeBackendConnector connector;
  InMemoryBookmarkRepository get bookmarks => connector.bookmarks;
  InMemoryHighlightRepository get highlights => connector.highlights;
}

Future<_App> _pump(
  WidgetTester tester, {
  List<Highlight> highlights = const [],
  FakeContentFetcher? fetcher,
}) async {
  tester.view.physicalSize = const Size(800, 1600);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final connector = FakeBackendConnector(
    FakeAuthRepository(initialUser: const AppUser(id: 'u1')),
  );
  connector.bookmarks.addAll([_bookmark()]);
  connector.highlights.addAll(highlights);
  await tester.pumpWidget(
    CapsulaApp(
      config: testConfig,
      backend: await startedBackendWith(connector),
      shareIntake: FakeShareIntake(),
      reader: ReaderService(fetcher ?? FakeContentFetcher()),
    ),
  );
  await tester.pumpAndSettle();
  return _App(connector);
}

void main() {
  group('highlightRanges', () {
    test('finds passages ignoring whitespace and case, merging overlaps', () {
      const text = 'Rinse the rice.\nThen  soak it for thirty minutes.';
      expect(highlightRanges(text, ['then soak it']), [(16, 29)]);
      expect(highlightRanges(text, ['rice', 'the rice']), [
        (6, 14),
      ], reason: 'overlapping ranges merge');
      expect(highlightRanges(text, ['missing']), isEmpty);
    });
  });

  group('service', () {
    test('creates, annotates and deletes with the bookmark', () async {
      final repo = InMemoryBookmarkRepository()..addAll([_bookmark()]);
      final highlights = InMemoryHighlightRepository();
      final service = BookmarkService(
        repo,
        InMemoryLabelRepository(repo),
        highlights: highlights,
      );

      expect(service.addHighlight(_bookmark(), '   '), isNull);
      final h = service.addHighlight(_bookmark(), ' An  important\npoint ')!;
      expect(h.text, 'An important point');

      await service.updateHighlight(h, note: 'Why it matters');
      expect(highlights.items[h.id]!.note, 'Why it matters');
      await service.updateHighlight(
        highlights.items[h.id]!,
        note: '',
        color: HighlightColor.pink,
      );
      expect(highlights.items[h.id]!.note, isNull);
      expect(highlights.items[h.id]!.color, HighlightColor.pink);

      await service.setNote(_bookmark(), '  My note ');
      expect(repo.items['b1']!.note, 'My note');
      await service.setNote(repo.items['b1']!, '');
      expect(repo.items['b1']!.note, isNull);

      await service.delete(repo.items['b1']!);
      expect(highlights.items, isEmpty);
    });

    test('notes are searchable and exported with highlights', () {
      final b = _bookmark().copyWith(note: 'carbonara recipe', favorite: true);
      expect(b.searchableText, contains('carbonara recipe'));

      final json = jsonDecode(
        exportLibrary(
          ExportFormat.json,
          [b],
          const [],
          now: _t,
          highlights: [_h('h1', 'Rinse first', note: 'Important')],
        ),
      ) as Map;
      final exported = (json['bookmarks'] as List).single as Map;
      expect(exported['note'], 'carbonara recipe');
      expect(exported['favorite'], isTrue);
      expect((exported['highlights'] as List).single['note'], 'Important');
    });
  });

  testWidgets('add a note from the detail page', (tester) async {
    final app = await _pump(tester);
    await tester.tap(find.text('Rice guide'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Add a note'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Note'),
      'Try with jasmine rice',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();

    expect(app.bookmarks.items['b1']!.note, 'Try with jasmine rice');
    expect(find.text('Try with jasmine rice'), findsOneWidget);
  });

  testWidgets('detail lists highlights and edits their notes', (tester) async {
    final app = await _pump(tester, highlights: [_h('h1', 'Rinse first')]);
    await tester.tap(find.text('Rice guide'));
    await tester.pumpAndSettle();

    expect(find.text('Highlights (1)'), findsOneWidget);
    expect(find.text('Rinse first'), findsOneWidget);

    await tester.tap(find.byTooltip('Highlight options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add note'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextField, 'Note'),
      'Removes starch',
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Save'));
    await tester.pumpAndSettle();
    expect(app.highlights.items['h1']!.note, 'Removes starch');

    await tester.tap(find.byTooltip('Highlight options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(app.highlights.items, isEmpty);
  });

  testWidgets('the reader marks highlighted text', (tester) async {
    final fetcher = FakeContentFetcher()
      ..html(
        'https://blog.example.com/',
        '<html><head><title>Rice guide</title></head><body><article>'
            '${List.generate(6, (i) => '<p>Step $i: rinse the rice well, soak it, simmer gently and rest it before serving.</p>').join()}'
            '</article></body></html>',
      );
    await _pump(
      tester,
      fetcher: fetcher,
      highlights: [_h('h1', 'soak it, simmer gently')],
    );
    await tester.tap(find.text('Rice guide'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.chrome_reader_mode_outlined));
    await tester.pumpAndSettle();

    final marked = tester
        .widgetList<RichText>(find.byType(RichText))
        .expand((r) {
          final spans = <TextSpan>[];
          r.text.visitChildren((s) {
            if (s is TextSpan) spans.add(s);
            return true;
          });
          return spans;
        })
        .where((s) => s.style?.backgroundColor != null && s.text != null)
        .map((s) => s.text)
        .toList();
    expect(marked, contains('soak it, simmer gently'));
  });

  testWidgets('Highlights screen lists all highlights by bookmark', (
    tester,
  ) async {
    await _pump(
      tester,
      highlights: [_h('h1', 'Rinse first'), _h('h2', 'Rest ten minutes')],
    );
    await openNavigation(tester);
    await tester.tap(find.text('Highlights'));
    await tester.pumpAndSettle();

    expect(find.byType(HighlightsScreen), findsOneWidget);
    expect(find.text('Rice guide'), findsOneWidget);
    expect(find.text('Rinse first'), findsOneWidget);
    expect(find.text('Rest ten minutes'), findsOneWidget);
  });
}
