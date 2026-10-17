import '../bookmarks/bookmark.dart';
import '../bookmarks/bookmark_source.dart';

/// A source the user adds on top of the built-in ones, such as "Amazon"
/// for `amazon.com`, or "Hacker News" for `news.ycombinator.com`.
class CustomSource {
  const CustomSource({
    required this.id,
    required this.name,
    required this.domains,
  });

  final String id;
  final String name;

  /// Hosts the source covers, without `www.`. Subdomains match too:
  /// `amazon.com` covers `smile.amazon.com`.
  final List<String> domains;

  bool matches(String host) {
    final h = host.toLowerCase();
    return domains.any((d) => h == d || h.endsWith('.$d'));
  }

  CustomSource copyWith({String? name, List<String>? domains}) => CustomSource(
    id: id,
    name: name ?? this.name,
    domains: domains ?? this.domains,
  );

  @override
  bool operator ==(Object other) =>
      other is CustomSource &&
      other.id == id &&
      other.name == name &&
      other.domains.join(',') == domains.join(',');

  @override
  int get hashCode => Object.hash(id, name, domains.join(','));
}

const maxSourceDomains = 20;

/// Cleans up what the user typed as a domain: a bare host, lower case,
/// without scheme, path or `www.`. Null when it isn't a usable host.
String? normalizeSourceDomain(String input) {
  var text = input.trim().toLowerCase();
  if (text.isEmpty) return null;
  if (!text.contains('://')) text = 'https://$text';
  final host = Uri.tryParse(text)?.host ?? '';
  final bare = host.startsWith('www.') ? host.substring(4) : host;
  if (!RegExp(r'^[a-z0-9-]+(\.[a-z0-9-]+)+$').hasMatch(bare)) return null;
  return bare;
}

/// The source of a link on [host]: the first of [custom] covering it (more
/// specific domains first), else null. The built-in source is detected
/// separately and still decides how the link is read.
String? detectCustomSource(String host, List<CustomSource> custom) {
  CustomSource? best;
  var bestLength = -1;
  for (final source in custom) {
    for (final d in source.domains) {
      final h = host.toLowerCase();
      if ((h == d || h.endsWith('.$d')) && d.length > bestLength) {
        best = source;
        bestLength = d.length;
      }
    }
  }
  return best?.id;
}

/// The source a bookmark is shown and filtered under: its custom source
/// when it has one that still exists, else its built-in source.
({String id, String name, bool custom}) sourceOf(
  Bookmark b,
  List<CustomSource> custom,
) {
  final own = custom.where((s) => s.id == b.customSourceId).firstOrNull;
  return own != null
      ? (id: own.id, name: own.name, custom: true)
      : (id: b.source.id, name: b.source.label, custom: false);
}

/// The user's own sources.
abstract interface class SourceRepository {
  String newId();

  /// Sorted by name.
  Stream<List<CustomSource>> watch();

  Future<void> create(CustomSource source);

  /// Saves a new name or domains.
  Future<void> update(CustomSource source);

  /// Deletes the source. Bookmarks from it show their built-in source
  /// (usually Webpage) again.
  Future<void> delete(String id);
}

List<CustomSource> sortSources(Iterable<CustomSource> sources) =>
    sources.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

/// Sources for a list of custom sources and the built-in ones, as filter
/// choices: built-in first in their usual order, then the user's.
List<({String id, String name, bool custom})> allSources(
  List<CustomSource> custom,
) => [
  for (final s in BookmarkSource.values)
    (id: s.id, name: s.label, custom: false),
  for (final s in sortSources(custom)) (id: s.id, name: s.name, custom: true),
];

/// Stored fields of a source (without `createdAt`, which only creating
/// sets). Shared by every backend.
Map<String, Object?> encodeSource(CustomSource s) => {
  'name': s.name,
  'domains': s.domains,
};

CustomSource decodeSource(String id, Map<String, Object?> data) => CustomSource(
  id: id,
  name: data['name'] as String? ?? '',
  domains: [
    for (final d in data['domains'] as List? ?? const [])
      if (d is String) d,
  ],
);
