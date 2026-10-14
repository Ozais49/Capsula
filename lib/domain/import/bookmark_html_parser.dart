import 'package:html/dom.dart' as dom;
import 'package:html/parser.dart' as html_parser;

import 'imported_item.dart';

/// Browser root folders that hold everything and aren't real collections.
const _rootFolders = {
  'bookmarks',
  'bookmarks bar',
  'bookmarks toolbar',
  'bookmarks menu',
  'other bookmarks',
  'mobile bookmarks',
  'favorites',
  'favorites bar',
  'favourites',
  'unsorted',
  'imported',
};

/// True when [text] looks like a Netscape bookmark file, the format browsers
/// and most bookmark services export.
bool looksLikeBookmarkHtml(String text) {
  final head = text.length > 2000 ? text.substring(0, 2000) : text;
  return RegExp(
    r'NETSCAPE-Bookmark-file|<DT>\s*<A\s',
    caseSensitive: false,
  ).hasMatch(head);
}

/// Reads links from a Netscape bookmark file. Each link's nearest named
/// folder becomes its folder; `TAGS` and `ADD_DATE` are kept.
List<ImportedItem> parseBookmarkHtml(String text, {DateTime? now}) {
  final doc = html_parser.parse(text);
  final items = <ImportedItem>[];

  for (final anchor in doc.querySelectorAll('a[href]')) {
    final href = anchor.attributes['href']!.trim();
    if (href.isEmpty) continue;

    final title = anchor.text.trim();
    items.add(
      ImportedItem(
        url: href,
        title: title.isEmpty ? null : title,
        description: _description(anchor),
        folder: _folderOf(anchor),
        tags: splitTags(anchor.attributes['tags']),
        createdAt: parseImportDate(anchor.attributes['add_date'], now: now),
      ),
    );
  }
  return items;
}

/// The `<DD>` note following a link, if any.
String? _description(dom.Element anchor) {
  final dt = anchor.parent;
  var sibling = dt?.nextElementSibling;
  // The HTML parser may nest DD inside DT instead.
  sibling ??= dt?.querySelector('dd');
  if (sibling?.localName != 'dd') return null;
  final text = sibling!.nodes
      .whereType<dom.Text>()
      .map((t) => t.text)
      .join()
      .trim();
  return text.isEmpty ? null : text;
}

/// Name of the closest enclosing folder that isn't a browser root folder.
String? _folderOf(dom.Element anchor) {
  dom.Element? node = anchor;
  while (node != null) {
    final list = _enclosingList(node);
    if (list == null) return null;
    final heading = _headingFor(list);
    final name = heading?.text.trim();
    if (name != null &&
        name.isNotEmpty &&
        !_rootFolders.contains(name.toLowerCase())) {
      return name;
    }
    node = list;
  }
  return null;
}

dom.Element? _enclosingList(dom.Element node) {
  var parent = node.parent;
  while (parent != null && parent.localName != 'dl') {
    parent = parent.parent;
  }
  return parent;
}

/// The `<H3>` naming a `<DL>`: its previous sibling, or the H3 in the `<DT>`
/// the parser nested it into.
dom.Element? _headingFor(dom.Element list) {
  final previous = list.previousElementSibling;
  if (previous?.localName == 'h3') return previous;
  final parent = list.parent;
  if (parent?.localName == 'dt') {
    for (final child in parent!.children) {
      if (child.localName == 'h3') return child;
    }
  }
  return null;
}
