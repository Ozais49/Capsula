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
      _collapsed = {...?await _prefs.getStringList('nav_collapsed')};
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
    _store((p) => p.setBool('offer_copied_links', offer));
  }

  void _save(String key, String value) =>
      _store((p) => p.setString(key, value));

  /// Saves a preference in the background. Preferences are a convenience:
  /// if they can't be stored (no storage available), the choice still
  /// applies for this run.
  void _store(Future<void> Function(SharedPreferencesAsync prefs) write) {
    if (!_persist) return;
    try {
      write(_prefs).catchError((Object _) {});
    } on Object {
      // Storage isn't available.
    }
  }

  // Sidebar sections and collections the user has collapsed, by key
  // (e.g. `section:collection`, `collection:<id>`). Everything starts open.
  Set<String> _collapsed = {};

  bool isCollapsed(String key) => _collapsed.contains(key);

  void toggleCollapsed(String key) {
    _collapsed = {..._collapsed};
    if (!_collapsed.remove(key)) _collapsed.add(key);
    notifyListeners();
    _store((p) => p.setStringList('nav_collapsed', _collapsed.toList()));
  }
}
