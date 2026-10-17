import 'package:capsula/app/router.dart';
import 'package:capsula_core/domain/bookmarks/bookmark.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_filters.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_source.dart';
import 'package:capsula_core/domain/bookmarks/bookmark_view.dart';
import 'package:capsula_core/domain/bookmarks/content_type.dart';
import 'package:flutter_test/flutter_test.dart';

Bookmark _bookmark({
  String url = 'https://reddit.com/r/flutter/1',
  BookmarkSource source = BookmarkSource.reddit,
  List<String> tags = const [],
  ReadingStatus status = ReadingStatus.saved,
}) {
  final time = DateTime(2026, 10, 17);
  return Bookmark(
    id: 'b',
    url: url,
    canonicalUrl: url,
    title: 'T',
    source: source,
    sourceDomain: 'reddit.com',
    createdAt: time,
    updatedAt: time,
    tagIds: tags,
    readingStatus: status,
  );
}

void main() {
  test('any value within a filter, every filter in use', () {
    const filters = BookmarkFilters(
      sources: {'reddit', 'youtube'},
      tagIds: {'a', 'b'},
    );
    expect(filters.matches(_bookmark(tags: ['b'])), isTrue);
    expect(filters.matches(_bookmark(tags: ['c'])), isFalse);
    expect(
      filters.matches(_bookmark(source: BookmarkSource.github, tags: ['a'])),
      isFalse,
    );
    expect(BookmarkFilters.none.matches(_bookmark()), isTrue);
    expect(
      const BookmarkFilters(
        kinds: {ContentType.post},
        statuses: {ReadingStatus.read},
      ).matches(_bookmark(status: ReadingStatus.read)),
      isTrue,
    );
  });

  test('round-trips through URL parameters, ignoring unknown values', () {
    const filters = BookmarkFilters(
      sources: {'youtube', 'reddit'},
      tagIds: {'t1'},
      kinds: {ContentType.video},
      statuses: {ReadingStatus.readLater},
    );
    expect(filters.toQuery(), {
      'source': 'reddit,youtube',
      'tag': 't1',
      'kind': 'video',
      'status': 'readLater',
    });
    expect(BookmarkFilters.fromQuery(filters.toQuery()), filters);
    expect(
      BookmarkFilters.fromQuery({'kind': 'video,hologram', 'status': ''}),
      const BookmarkFilters(kinds: {ContentType.video}),
    );
  });

  test('library links carry the view and filters', () {
    expect(AppRoutes.library(BookmarkView.all), '/');
    expect(AppRoutes.library(BookmarkView.inbox), '/?view=inbox');
    expect(
      AppRoutes.library(
        BookmarkView.all,
        const BookmarkFilters(sources: {'reddit'}),
      ),
      '/?source=reddit',
    );
    final (view, filters) = libraryLocation(
      Uri.parse('/?view=trash&tag=a,b').queryParameters,
    );
    expect(view, BookmarkView.trash);
    expect(filters.tagIds, {'a', 'b'});
  });

  test('old source and type links open All with a filter', () {
    var (view, filters) = libraryLocation({'view': 'source:youtube'});
    expect(view, BookmarkView.all);
    expect(filters.sources, {'youtube'});

    (view, filters) = libraryLocation({'view': 'type:video', 'tag': 'x'});
    expect(view, BookmarkView.all);
    expect(
      filters,
      const BookmarkFilters(kinds: {ContentType.video}, tagIds: {'x'}),
    );
  });
}
