import 'package:capsula_core/domain/bookmarks/bookmark_repository.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum LibraryLayout {
  list('List'),
  cards('Cards'),
  grid('Grid');

  const LibraryLayout(this.label);

  final String label;
}

/// How the library is shown on this device. Remembered between runs when
/// the platform allows it; works in memory otherwise.
class DisplayPreferences extends ChangeNotifier {
  DisplayPreferences({this._persist = true});

  final bool _persist;
  late final SharedPreferencesAsync _prefs = SharedPreferencesAsync();

  LibraryLayout _layout = LibraryLayout.list;
  BookmarkSort _sort = BookmarkSort.newest;
  bool _offerCopiedLinks = true;

  LibraryLayout get layout => _layout;
  BookmarkSort get sort => _sort;

  /// Offer to save a link the user copied in another app.
  bool get offerCopiedLinks => _offerCopiedLinks;

  Future<void> load() async {
    if (!_persist) return;
    try {
      final layout = await _prefs.getString('library_layout');
      final sort = await _prefs.getString('library_sort');
      _offerCopiedLinks =
          await _prefs.getBool('offer_copied_links') ?? _offerCopiedLinks;
      _layout = LibraryLayout.values.firstWhere(
        (l) => l.name == layout,
        orElse: () => _layout,
      );
      _sort = BookmarkSort.values.firstWhere(
        (s) => s.name == sort,
        orElse: () => _sort,
      );
      notifyListeners();
    } on Object {
      // Defaults are fine.
    }
  }

  void setLayout(LibraryLayout layout) {
    _layout = layout;
    notifyListeners();
    _save('library_layout', layout.name);
  }

  void setSort(BookmarkSort sort) {
    _sort = sort;
    notifyListeners();
    _save('library_sort', sort.name);
  }

  void setOfferCopiedLinks(bool offer) {
    _offerCopiedLinks = offer;
    notifyListeners();
    if (_persist) {
      _prefs.setBool('offer_copied_links', offer).catchError((Object _) {});
    }
  }

  void _save(String key, String value) {
    if (!_persist) return;
    _prefs.setString(key, value).catchError((Object _) {});
  }
}
