import 'package:capsula_core/domain/bookmarks/bookmark.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_repository.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_service.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_source.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_view.dart';
import 'package:capsula_core/domain/organization/label.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:capsula_core/testing/in_memory_bookmark_repository.dart';
import 'package:capsula_core/testing/in_memory_label_repository.dart';

Bookmark _b({
  bool archived = false,
  bool inInbox = true,
  BookmarkSource source = BookmarkSource.website,
  List<String> tagIds = const [],
  List<String> collectionIds = const [],
}) {
  final t = DateTime(2026);
  return Bookmark(
    id: 'x',
    url: 'https://example.com',
    canonicalUrl: 'https://example.com',
    title: 'x',
    source: source,
    sourceDomain: 'example.com',
    createdAt: t,
    updatedAt: t,
    archived: archived,
    inInbox: inInbox,
    tagIds: tagIds,
    collectionIds: collectionIds,
  );
}

void main() {
  group('BookmarkView', () {
    test('round-trips through its key', () {
      for (final view in <BookmarkView>[
        BookmarkView.inbox,
        BookmarkView.all,
        BookmarkView.archived,
        const SourceView(BookmarkSource.reddit),
        const LabelView(LabelKind.tag, 'abc'),
        const LabelView(LabelKind.collection, 'def'),
      ]) {
        expect(BookmarkView.parse(view.key), view, reason: view.key);
      }
    });

    test('unknown keys fall back to the Inbox', () {
      for (final key in [null, '', 'nope', 'tag:', 'weird:value']) {
        expect(BookmarkView.parse(key), BookmarkView.inbox, reason: key);
      }
    });

    test('membership is independent per dimension', () {
      final b = _b(
        source: BookmarkSource.reddit,
        tagIds: ['ai'],
        collectionIds: ['research'],
      );
      // Organized, so not unsorted.
      expect(bookmarkInView(b, BookmarkView.inbox), isFalse);
      expect(bookmarkInView(b, BookmarkView.all), isTrue);
      expect(
        bookmarkInView(b, const SourceView(BookmarkSource.reddit)),
        isTrue,
      );
      expect(bookmarkInView(b, const LabelView(LabelKind.tag, 'ai')), isTrue);
      expect(
        bookmarkInView(b, const LabelView(LabelKind.collection, 'research')),
        isTrue,
      );
      expect(bookmarkInView(b, BookmarkView.archived), isFalse);
      expect(bookmarkInView(b, const SourceView(BookmarkSource.x)), isFalse);
      expect(
        bookmarkInView(b, const LabelView(LabelKind.tag, 'research')),
        isFalse,
      );
    });

    test('archived bookmarks only appear in Archived', () {
      final b = _b(archived: true, tagIds: ['ai']);
      expect(bookmarkInView(b, BookmarkView.archived), isTrue);
      expect(bookmarkInView(b, BookmarkView.all), isFalse);
      expect(bookmarkInView(b, const LabelView(LabelKind.tag, 'ai')), isFalse);
    });

    test('Unsorted holds bookmarks without tags or collections', () {
      expect(bookmarkInView(_b(), BookmarkView.inbox), isTrue);
      expect(bookmarkInView(_b(tagIds: ['ai']), BookmarkView.inbox), isFalse);
      expect(
        bookmarkInView(_b(collectionIds: ['c']), BookmarkView.inbox),
        isFalse,
      );
      // The old Inbox flag no longer matters.
      expect(bookmarkInView(_b(inInbox: false), BookmarkView.inbox), isTrue);
      expect(bookmarkInView(_b(tagIds: ['ai']), BookmarkView.all), isTrue);
    });
  });

  test('normalizeLabelName trims, collapses and caps', () {
    expect(normalizeLabelName('  Machine   learning '), 'Machine learning');
    expect(normalizeLabelName('   '), isNull);
    expect(normalizeLabelName('x' * 80)!.length, maxLabelNameLength);
  });

  group('labels in BookmarkService', () {
    late InMemoryBookmarkRepository repo;
    late InMemoryLabelRepository labels;
    late BookmarkService service;

    setUp(() {
      repo = InMemoryBookmarkRepository();
      labels = InMemoryLabelRepository(repo);
      service = BookmarkService(repo, labels);
    });

    test('creates labels and reuses one with the same name', () {
      final ai = service.createLabel(LabelKind.tag, ' AI ', const [])!;
      expect(ai.name, 'AI');
      expect(labels.items[ai.id], ai);

      final again = service.createLabel(LabelKind.tag, 'ai', [ai]);
      expect(again, ai);
      expect(labels.items, hasLength(1));

      final collection = service.createLabel(LabelKind.collection, 'AI', [ai]);
      expect(collection!.id, isNot(ai.id), reason: 'kinds are separate');

      expect(service.createLabel(LabelKind.tag, '   ', const []), isNull);
    });

    test('rename rejects blanks and clashes', () async {
      final a = service.createLabel(LabelKind.tag, 'A', const [])!;
      final b = service.createLabel(LabelKind.tag, 'B', [a])!;

      expect(await service.renameLabel(a, 'b', [a, b]), isFalse);
      expect(await service.renameLabel(a, ' ', [a, b]), isFalse);
      expect(await service.renameLabel(a, 'Alpha', [a, b]), isTrue);
      expect(labels.items[a.id]!.name, 'Alpha');
      expect(await service.renameLabel(a, 'alpha', [a, b]), isTrue);
    });

    test('assigns labels and inbox state', () async {
      final saved = await service.save('https://example.com/a') as Saved;
      final tag = service.createLabel(LabelKind.tag, 'AI', const [])!;

      await service.setLabels(saved.bookmark, LabelKind.tag, [tag.id, tag.id]);
      expect(repo.items[saved.bookmark.id]!.tagIds, [tag.id]);

      await service.setInInbox(repo.items[saved.bookmark.id]!, false);
      final updated = repo.items[saved.bookmark.id]!;
      expect(updated.inInbox, isFalse);
      expect(updated.tagIds, [tag.id], reason: 'other fields kept');
    });

    test('deleting a label removes it from bookmarks', () async {
      final saved = await service.save('https://example.com/a') as Saved;
      final tag = service.createLabel(LabelKind.tag, 'AI', const [])!;
      await service.setLabels(saved.bookmark, LabelKind.tag, [tag.id]);

      await service.deleteLabel(tag);

      expect(labels.items, isEmpty);
      expect(repo.items[saved.bookmark.id]!.tagIds, isEmpty);
    });
  });
}
