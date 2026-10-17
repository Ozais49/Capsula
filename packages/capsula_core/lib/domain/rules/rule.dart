import '../bookmarks/bookmark.dart';
import '../bookmarks/content_type.dart';

/// What a rule condition looks at.
enum RuleField {
  /// Built-in source ID (`reddit`, `website`, …) or custom source ID.
  source('Source'),
  domain('Domain'),
  url('Link'),
  title('Title'),

  /// Detected kind of content (`video`, `article`, …).
  kind('Kind'),
  importedFrom('Imported from');

  const RuleField(this.label);

  final String label;

  /// Fields whose values are picked from a list, compared exactly.
  bool get isChoice => this == source || this == kind;
}

enum RuleOp {
  isEqual('is'),
  contains('contains'),
  startsWith('starts with'),
  matches('matches pattern');

  const RuleOp(this.label);

  final String label;
}

class RuleCondition {
  const RuleCondition(this.field, this.op, this.value);

  final RuleField field;
  final RuleOp op;
  final String value;

  String? _text(Bookmark b) => switch (field) {
    RuleField.source => b.sourceKey,
    RuleField.domain => b.sourceDomain,
    RuleField.url => b.url,
    RuleField.title => b.title,
    RuleField.kind => b.type.name,
    RuleField.importedFrom => b.importedFrom,
  };

  /// Text comparisons ignore case. A pattern that isn't a valid regular
  /// expression matches nothing.
  bool test(Bookmark b) {
    final text = _text(b)?.toLowerCase();
    final value = this.value.trim().toLowerCase();
    if (text == null || value.isEmpty) return false;
    return switch (op) {
      RuleOp.isEqual =>
        field == RuleField.domain
            ? text == value || text.endsWith('.$value')
            : text == value,
      RuleOp.contains => text.contains(value),
      RuleOp.startsWith => text.startsWith(value),
      RuleOp.matches => _regex(value)?.hasMatch(text) ?? false,
    };
  }

  static RegExp? _regex(String pattern) {
    if (pattern.length > maxRuleValueLength) return null;
    try {
      return RegExp(pattern, caseSensitive: false);
    } on FormatException {
      return null;
    }
  }

  Map<String, Object?> toJson() => {
    'field': field.name,
    'op': op.name,
    'value': value,
  };

  static RuleCondition? fromJson(Object? json) {
    if (json is! Map) return null;
    final field = RuleField.values.asNameMap()[json['field']];
    final op = RuleOp.values.asNameMap()[json['op']];
    final value = json['value'];
    if (field == null || op == null || value is! String) return null;
    return RuleCondition(field, op, value);
  }

  @override
  bool operator ==(Object other) =>
      other is RuleCondition &&
      other.field == field &&
      other.op == op &&
      other.value == value;

  @override
  int get hashCode => Object.hash(field, op, value);
}

const maxRuleValueLength = 500;
const maxRuleConditions = 10;

/// Organizes new bookmarks automatically: when a bookmark matches the
/// conditions, the actions add tags, a collection or a star. Rules only
/// ever add, so they never undo what the user did, and running them again
/// changes nothing.
class Rule {
  const Rule({
    required this.id,
    required this.name,
    required this.conditions,
    this.matchAll = true,
    this.enabled = true,
    this.tagIds = const [],
    this.collectionId,
    this.favorite = false,
  });

  final String id;
  final String name;
  final bool enabled;

  /// Whether every condition must match (otherwise any one).
  final bool matchAll;
  final List<RuleCondition> conditions;

  final List<String> tagIds;
  final String? collectionId;
  final bool favorite;

  bool get hasActions => tagIds.isNotEmpty || collectionId != null || favorite;

  bool appliesTo(Bookmark b) {
    if (!enabled || conditions.isEmpty) return false;
    return matchAll
        ? conditions.every((c) => c.test(b))
        : conditions.any((c) => c.test(b));
  }

  /// [b] with this rule's actions, or [b] itself when nothing is added.
  Bookmark applyTo(Bookmark b) {
    if (!appliesTo(b)) return b;
    final tags = [
      ...b.tagIds,
      for (final t in tagIds)
        if (!b.tagIds.contains(t)) t,
    ];
    final collection = collectionId;
    final collections =
        collection == null || b.collectionIds.contains(collection)
        ? b.collectionIds
        : [...b.collectionIds, collection];
    if (tags.length == b.tagIds.length &&
        collections.length == b.collectionIds.length &&
        (!favorite || b.favorite)) {
      return b;
    }
    return b.copyWith(
      tagIds: tags,
      collectionIds: collections,
      favorite: favorite ? true : null,
    );
  }

  Rule copyWith({
    String? name,
    bool? enabled,
    bool? matchAll,
    List<RuleCondition>? conditions,
    List<String>? tagIds,
    String? collectionId,
    bool clearCollection = false,
    bool? favorite,
  }) => Rule(
    id: id,
    name: name ?? this.name,
    enabled: enabled ?? this.enabled,
    matchAll: matchAll ?? this.matchAll,
    conditions: conditions ?? this.conditions,
    tagIds: tagIds ?? this.tagIds,
    collectionId: clearCollection ? null : collectionId ?? this.collectionId,
    favorite: favorite ?? this.favorite,
  );

  /// Stored fields (without `createdAt`, which only creating sets).
  Map<String, Object?> toJson() => {
    'name': name,
    'enabled': enabled,
    'matchAll': matchAll,
    'conditions': [for (final c in conditions) c.toJson()],
    'tagIds': tagIds,
    'collectionId': ?collectionId,
    if (favorite) 'favorite': true,
  };

  static Rule fromJson(String id, Map<String, Object?> json) => Rule(
    id: id,
    name: json['name'] as String? ?? '',
    enabled: json['enabled'] as bool? ?? true,
    matchAll: json['matchAll'] as bool? ?? true,
    conditions: [
      for (final c in json['conditions'] as List? ?? const [])
        ?RuleCondition.fromJson(c),
    ],
    tagIds: [
      for (final t in json['tagIds'] as List? ?? const [])
        if (t is String) t,
    ],
    collectionId: json['collectionId'] as String?,
    favorite: json['favorite'] as bool? ?? false,
  );

  @override
  bool operator ==(Object other) =>
      other is Rule &&
      other.id == id &&
      other.name == name &&
      other.enabled == enabled &&
      other.matchAll == matchAll &&
      _sameList(other.conditions, conditions) &&
      _sameList(other.tagIds, tagIds) &&
      other.collectionId == collectionId &&
      other.favorite == favorite;

  @override
  int get hashCode => Object.hash(
    id,
    name,
    enabled,
    matchAll,
    Object.hashAll(conditions),
    Object.hashAll(tagIds),
    collectionId,
    favorite,
  );

  static bool _sameList<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// [b] with the actions of every rule it matches.
Bookmark applyRules(Bookmark b, List<Rule> rules) {
  var result = b;
  for (final rule in rules) {
    result = rule.applyTo(result);
  }
  return result;
}

/// The user's rules.
abstract interface class RuleRepository {
  String newId();

  /// Sorted by name.
  Stream<List<Rule>> watch();

  Future<void> create(Rule rule);

  Future<void> update(Rule rule);

  Future<void> delete(String id);
}

List<Rule> sortRules(Iterable<Rule> rules) =>
    rules.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

/// The kinds that get a tag and a rule when types become tags. Article is
/// what detection falls back to when it can't tell, so it gets none: such
/// links stay unsorted until someone sorts them.
const kindsWithDefaultRules = [
  ContentType.video,
  ContentType.image,
  ContentType.document,
  ContentType.post,
  ContentType.product,
];

/// Tag name for a kind: Video, Image, …
String kindTagName(ContentType kind) => switch (kind) {
  ContentType.article => 'Article',
  ContentType.video => 'Video',
  ContentType.image => 'Image',
  ContentType.document => 'Document',
  ContentType.post => 'Post',
  ContentType.product => 'Product',
};

/// ID of the default rule for a kind, the same everywhere so creating the
/// defaults twice (on two devices) gives one rule.
String defaultRuleId(ContentType kind) => 'kind-${kind.name}';
