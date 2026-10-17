import 'package:capsula_core/domain/bookmarks/bookmark.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_service.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_source.dart';
import 'package:capsula_core/domain/import/import_service.dart';
import 'package:capsula_core/domain/import/imported_item.dart';
import 'package:capsula_core/domain/local/local_library.dart';
import 'package:capsula_core/domain/organization/label.dart';
import 'package:capsula_core/domain/reader/reader_content.dart';
import 'package:capsula_core/domain/rules/rule.dart';
import 'package:capsula_core/testing/in_memory_bookmark_repository.dart';
import 'package:capsula_core/testing/in_memory_label_repository.dart';
import 'package:capsula_core/testing/in_memory_rule_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/memory_local_storage.dart';

Bookmark _bookmark(String url, {String title = 'Title'}) {
  final uri = Uri.parse(url);
  final time = DateTime(2026, 10, 17);
  return Bookmark(
    id: 'b',
    url: url,
    canonicalUrl: url,
    title: title,
    source: BookmarkSource.fromHost(uri.host),
    sourceDomain: uri.host,
    createdAt: time,
    updatedAt: time,
  );
}

RuleCondition _c(RuleField f, RuleOp o, String v) => RuleCondition(f, o, v);

void main() {
  group('conditions', () {
    final b = _bookmark(
      'https://www.reddit.com/r/FlutterDev/comments/1',
      title: 'Flutter 4 is out',
    );

    test('compare text ignoring case', () {
      expect(_c(RuleField.title, RuleOp.contains, 'flutter').test(b), isTrue);
      expect(
        _c(RuleField.url, RuleOp.contains, '/r/flutterdev').test(b),
        isTrue,
      );
      expect(_c(RuleField.title, RuleOp.startsWith, 'FLUTTER').test(b), isTrue);
      expect(_c(RuleField.title, RuleOp.isEqual, 'flutter').test(b), isFalse);
    });

    test('a domain covers its subdomains', () {
      expect(
        _c(RuleField.domain, RuleOp.isEqual, 'reddit.com').test(b),
        isTrue,
      );
      expect(_c(RuleField.domain, RuleOp.isEqual, 'edit.com').test(b), isFalse);
    });

    test('source and kind compare IDs', () {
      expect(_c(RuleField.source, RuleOp.isEqual, 'reddit').test(b), isTrue);
      expect(_c(RuleField.kind, RuleOp.isEqual, 'post').test(b), isTrue);
    });

    test('patterns; an invalid one matches nothing', () {
      expect(
        _c(RuleField.title, RuleOp.matches, r'flutter \d').test(b),
        isTrue,
      );
      expect(_c(RuleField.title, RuleOp.matches, '(unclosed').test(b), isFalse);
      expect(_c(RuleField.title, RuleOp.contains, ' ').test(b), isFalse);
    });

    test('a missing value never matches', () {
      expect(_c(RuleField.importedFrom, RuleOp.contains, 'x').test(b), isFalse);
    });
  });

  test('rules only add, so applying twice changes nothing', () {
    const rule = Rule(
      id: 'r',
      name: 'Reddit',
      conditions: [RuleCondition(RuleField.source, RuleOp.isEqual, 'reddit')],
      tagIds: ['t1'],
      collectionId: 'c1',
      favorite: true,
    );
    final b = _bookmark('https://reddit.com/r/a/comments/1')
        .copyWith(tagIds: ['mine']);
    final once = rule.applyTo(b);
    expect(once.tagIds, ['mine', 't1']);
    expect(once.collectionIds, ['c1']);
    expect(once.favorite, isTrue);
    expect(identical(rule.applyTo(once), once), isTrue);

    expect(identical(rule.copyWith(enabled: false).applyTo(b), b), isTrue);
    final other = _bookmark('https://example.com/a');
    expect(identical(rule.applyTo(other), other), isTrue);
  });

  test('match all or any', () {
    final b = _bookmark('https://youtube.com/watch?v=1', title: 'Cooking');
    const all = Rule(
      id: 'r',
      name: 'r',
      conditions: [
        RuleCondition(RuleField.source, RuleOp.isEqual, 'youtube'),
        RuleCondition(RuleField.title, RuleOp.contains, 'chess'),
      ],
      tagIds: ['t'],
    );
    expect(all.appliesTo(b), isFalse);
    expect(all.copyWith(matchAll: false).appliesTo(b), isTrue);
  });

  test('rules survive a round trip through storage', () {
    const rule = Rule(
      id: 'r',
      name: 'Recipes',
      matchAll: false,
      conditions: [
        RuleCondition(RuleField.title, RuleOp.contains, 'recipe'),
        RuleCondition(RuleField.kind, RuleOp.isEqual, 'video'),
      ],
      tagIds: ['food'],
      collectionId: 'kitchen',
    );
    expect(Rule.fromJson('r', rule.toJson()), rule);
  });

  group('service', () {
    late InMemoryBookmarkRepository repo;
    late InMemoryLabelRepository labels;
    late InMemoryRuleRepository rules;
    late BookmarkService service;

    setUp(() {
      repo = InMemoryBookmarkRepository();
      labels = InMemoryLabelRepository(repo);
      rules = InMemoryRuleRepository();
      service = BookmarkService(repo, labels, rules: rules);
    });

    Future<Bookmark> save(String url) async {
      final saved = await service.save(url) as Saved;
      await saved.committed;
      return repo.items[saved.bookmark.id]!;
    }

    test('checks rules before saving them', () async {
      Future<String?> check(Rule r) => service.saveRule(r, isNew: true);
      const base = Rule(
        id: 'r',
        name: 'Rule',
        conditions: [RuleCondition(RuleField.domain, RuleOp.isEqual, 'a.com')],
        tagIds: ['t'],
      );
      expect(await check(base.copyWith(name: ' ')), 'Enter a name');
      expect(
        await check(
          base.copyWith(
            conditions: [
              const RuleCondition(RuleField.domain, RuleOp.isEqual, ' '),
            ],
          ),
        ),
        'Add a condition',
      );
      expect(
        await check(base.copyWith(tagIds: [])),
        'Choose tags, a collection or a star to add',
      );
      expect(
        await check(
          base.copyWith(
            conditions: [
              const RuleCondition(RuleField.title, RuleOp.matches, '(x'),
            ],
          ),
        ),
        '"(x" is not a valid pattern',
      );
      expect(await check(base), isNull);
      expect(rules.items, hasLength(1));
    });

    test('new links are organized as they are saved', () async {
      rules.addAll([
        const Rule(
          id: 'r',
          name: 'Shopping',
          conditions: [
            RuleCondition(RuleField.domain, RuleOp.isEqual, 'amazon.com'),
          ],
          tagIds: ['shop'],
        ),
      ]);
      expect((await save('https://amazon.com/dp/1')).tagIds, ['shop']);
      expect((await save('https://example.com/x')).tagIds, isEmpty);
    });

    test('rules on the title run once the title is found', () async {
      rules.addAll([
        const Rule(
          id: 'r',
          name: 'Recipes',
          conditions: [
            RuleCondition(RuleField.title, RuleOp.contains, 'recipe'),
          ],
          tagIds: ['food'],
        ),
      ]);
      final b = await save('https://example.com/p/123');
      expect(b.tagIds, isEmpty);

      service.applyMetadata(
        b,
        const PageMetadata(title: 'Best biryani recipe'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(repo.items[b.id]!.tagIds, ['food']);
    });

    test('rules apply to saved bookmarks on demand', () async {
      final a = await save('https://amazon.com/dp/1');
      await save('https://example.com/x');
      await service.saveRule(
        const Rule(
          id: 'r',
          name: 'Shopping',
          conditions: [
            RuleCondition(RuleField.domain, RuleOp.isEqual, 'amazon.com'),
          ],
          tagIds: ['shop'],
        ),
        isNew: true,
      );
      expect(await service.applyRulesToAll(), 1);
      expect(repo.items[a.id]!.tagIds, ['shop']);
      expect(await service.applyRulesToAll(), 0);
    });

    test('imports are organized too', () async {
      rules.addAll([
        const Rule(
          id: 'r',
          name: 'Videos',
          conditions: [RuleCondition(RuleField.kind, RuleOp.isEqual, 'video')],
          tagIds: ['video'],
        ),
      ]);
      final importer = ImportService(repo, labels, rules: rules);
      final plan = await importer.plan(const [
        ImportedItem(url: 'https://youtu.be/abc', title: 'A video'),
        ImportedItem(url: 'https://example.com/a', title: 'A page'),
      ]);
      await importer.run(plan, origin: ImportOrigin.file);
      final byUrl = {for (final b in repo.items.values) b.url: b.tagIds};
      expect(byUrl['https://youtu.be/abc'], ['video']);
      expect(byUrl['https://example.com/a'], isEmpty);
    });

    test('types become tags and rules, once', () async {
      labels.addAll([
        const Label(id: 'mine', kind: LabelKind.tag, name: 'video'),
      ]);
      final video = await save('https://youtu.be/abc');
      final page = await save('https://example.com/article');
      final meta = InMemoryLibraryMeta();

      expect(await service.upgradeLibrary(meta), isTrue);
      expect(meta.version, BookmarkService.schemaVersion);

      // An existing tag with the same name is reused.
      expect(repo.items[video.id]!.tagIds, ['mine']);
      // Articles (what detection falls back to) stay unsorted.
      expect(repo.items[page.id]!.tagIds, isEmpty);
      expect(
        labels.items.values.map((l) => l.name),
        unorderedEquals(['video', 'Image', 'Document', 'Post', 'Product']),
      );
      expect(rules.items.keys, containsAll(['kind-video', 'kind-post']));
      expect(rules.items['kind-video']!.tagIds, ['mine']);

      // New links of a kind are tagged by its rule.
      expect((await save('https://youtu.be/xyz')).tagIds, ['mine']);

      expect(await service.upgradeLibrary(meta), isFalse);
    });

    test('an interrupted migration finishes when run again', () async {
      final video = await save('https://youtu.be/abc');
      final meta = InMemoryLibraryMeta();
      // Stopped after creating tags and rules, before tagging bookmarks.
      repo.nextWriteError = Exception('connection lost');
      await expectLater(service.upgradeLibrary(meta), throwsException);
      expect(meta.version, 1);

      expect(await service.upgradeLibrary(meta), isTrue);
      expect(repo.items[video.id]!.tagIds, ['kind-video']);
      expect(labels.items.values.where((l) => l.name == 'Video'), hasLength(1));
      expect(
        rules.items.values.where((r) => r.id == 'kind-video'),
        hasLength(1),
      );
    });
  });

  test('the on-device library keeps rules and its version', () async {
    final storage = MemoryLocalStorage();
    final services = (await LocalLibrary.open(storage)).services();
    await services.bookmarks.upgradeLibrary(services.libraryMeta);

    final reopened = (await LocalLibrary.open(storage)).services();
    expect(
      await reopened.libraryMeta.schemaVersion(),
      BookmarkService.schemaVersion,
    );
    expect(
      (await reopened.ruleRepository.watch().first).map((r) => r.id),
      contains('kind-video'),
    );
    expect(
      await reopened.bookmarks.upgradeLibrary(reopened.libraryMeta),
      isFalse,
    );
  });
}
