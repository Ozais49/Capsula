import 'package:flutter/material.dart';

import 'package:capsula_core/domain/bookmarks/bookmark.dart';
import 'package:capsula_core/domain/bookmarks/content_type.dart';
import 'package:capsula_core/domain/organization/label.dart';
import 'package:capsula_core/domain/rules/rule.dart';
import 'package:capsula_core/domain/sources/custom_source.dart';

import '../../app/dependencies.dart';
import '../../app/theme.dart';
import '../organization/label_picker_sheet.dart';
import '../organization/labels_builder.dart';

/// Lists the user's rules, which tag, file and star new bookmarks.
class RulesScreen extends StatefulWidget {
  const RulesScreen({super.key});

  @override
  State<RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends State<RulesScreen> {
  Stream<List<Rule>>? _rules;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _rules ??= AppDependencies.of(context).bookmarks.rules.watch();
  }

  Future<void> _apply() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final changed = await AppDependencies.of(context).bookmarks
          .applyRulesToAll();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            changed == 0
                ? 'Saved bookmarks already follow the rules'
                : 'Updated $changed bookmark${changed == 1 ? '' : 's'}',
          ),
        ),
      );
    } on Object catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('Could not update: $e')));
    }
  }

  Future<void> _setEnabled(Rule rule, bool enabled) async {
    final messenger = ScaffoldMessenger.of(context);
    final error = await AppDependencies.of(context).bookmarks
        .saveRule(rule.copyWith(enabled: enabled));
    if (error != null) {
      messenger.showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Rules')),
    floatingActionButton: FloatingActionButton.extended(
      onPressed: () => openRuleEditor(context),
      icon: const Icon(Icons.add),
      label: const Text('Add rule'),
    ),
    body: LabelsBuilder(
      builder: (context, labels) => StreamBuilder<List<Rule>>(
        stream: _rules,
        builder: (context, snapshot) {
          final rules = snapshot.data ?? const [];
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: ListView(
                padding: const EdgeInsets.only(bottom: 96),
                children: [
                  const Padding(
                    padding: EdgeInsets.all(Gap.md),
                    child: Text(
                      'Rules organize links as they are saved or imported: '
                      'when a link matches, it gets the rule\'s tags, '
                      'collection or star. Links no rule recognizes stay '
                      'unsorted. Rules only add, never remove.',
                    ),
                  ),
                  if (snapshot.hasData && rules.isEmpty)
                    const ListTile(title: Text('No rules yet')),
                  for (final rule in rules)
                    ListTile(
                      title: Text(rule.name),
                      subtitle: Text(
                        describeRule(rule, labels),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () => openRuleEditor(context, rule: rule),
                      trailing: Switch(
                        value: rule.enabled,
                        onChanged: (on) => _setEnabled(rule, on),
                      ),
                    ),
                  if (rules.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.all(Gap.md),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: OutlinedButton.icon(
                          icon: const Icon(Icons.refresh),
                          label: const Text('Apply to saved bookmarks'),
                          onPressed: _apply,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          );
        },
      ),
    ),
  );
}

/// A one-line summary: "Domain is amazon.com → #Shopping, Wishlist".
String describeRule(Rule rule, Labels labels) {
  String value(RuleCondition c) => switch (c.field) {
    RuleField.source =>
      allSources(labels.sources)
              .where((s) => s.id == c.value)
              .firstOrNull
              ?.name ??
          c.value,
    RuleField.kind => ContentType.values.asNameMap()[c.value]?.label ?? c.value,
    _ => c.value,
  };
  final conditions = rule.conditions
      .map((c) => '${c.field.label} ${c.op.label} ${value(c)}')
      .join(rule.matchAll ? ' and ' : ' or ');
  final actions = [
    for (final t in labels.resolve(LabelKind.tag, rule.tagIds)) '#${t.name}',
    if (rule.collectionId case final id?)
      if (labels.find(LabelKind.collection, id) case final c?) c.name,
    if (rule.favorite) '★',
  ];
  return '$conditions → ${actions.join(', ')}';
}

/// Opens the editor for [rule], or for a new rule, starting from [draft]
/// when given (e.g. made from a bookmark).
Future<void> openRuleEditor(BuildContext context, {Rule? rule, Rule? draft}) =>
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        fullscreenDialog: true,
        builder: (_) => _RuleEditor(rule: rule, draft: draft),
      ),
    );

/// A new rule matching the domain of [bookmark], to finish in the editor.
Rule ruleDraftFor(Bookmark bookmark) => Rule(
  id: '',
  name: bookmark.sourceDomain,
  conditions: [
    RuleCondition(RuleField.domain, RuleOp.isEqual, bookmark.sourceDomain),
  ],
  tagIds: bookmark.tagIds,
  collectionId: bookmark.collectionIds.firstOrNull,
);

class _RuleEditor extends StatefulWidget {
  const _RuleEditor({this.rule, this.draft});

  final Rule? rule;
  final Rule? draft;

  @override
  State<_RuleEditor> createState() => _RuleEditorState();
}

class _RuleEditorState extends State<_RuleEditor> {
  late Rule _rule =
      widget.rule ??
      widget.draft ??
      const Rule(
        id: '',
        name: '',
        conditions: [RuleCondition(RuleField.domain, RuleOp.isEqual, '')],
      );
  late final _name = TextEditingController(text: _rule.name);
  late final List<TextEditingController> _values = [
    for (final c in _rule.conditions) TextEditingController(text: c.value),
  ];
  String? _error;
  bool _saving = false;

  bool get _isNew => widget.rule == null;

  @override
  void dispose() {
    _name.dispose();
    for (final v in _values) {
      v.dispose();
    }
    super.dispose();
  }

  void _setCondition(int i, RuleCondition c) => setState(() {
    _rule = _rule.copyWith(conditions: [..._rule.conditions]..[i] = c);
  });

  void _addCondition() => setState(() {
    _values.add(TextEditingController());
    _rule = _rule.copyWith(
      conditions: [
        ..._rule.conditions,
        const RuleCondition(RuleField.title, RuleOp.contains, ''),
      ],
    );
  });

  void _removeCondition(int i) => setState(() {
    _values.removeAt(i).dispose();
    _rule = _rule.copyWith(conditions: [..._rule.conditions]..removeAt(i));
  });

  Future<void> _save() async {
    final service = AppDependencies.of(context).bookmarks;
    final rule = Rule(
      id: _isNew ? service.rules.newId() : _rule.id,
      name: _name.text,
      enabled: _rule.enabled,
      matchAll: _rule.matchAll,
      conditions: [
        for (var i = 0; i < _rule.conditions.length; i++)
          RuleCondition(
            _rule.conditions[i].field,
            _rule.conditions[i].op,
            _rule.conditions[i].field.isChoice
                ? _rule.conditions[i].value
                : _values[i].text,
          ),
      ],
      tagIds: _rule.tagIds,
      collectionId: _rule.collectionId,
      favorite: _rule.favorite,
    );
    setState(() => _saving = true);
    try {
      final error = await service.saveRule(rule, isNew: _isNew);
      if (!mounted) return;
      if (error != null) {
        setState(() {
          _error = error;
          _saving = false;
        });
        return;
      }
      Navigator.pop(context);
    } on Object catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Could not save: $e';
        _saving = false;
      });
    }
  }

  Future<void> _delete() async {
    final service = AppDependencies.of(context).bookmarks;
    final navigator = Navigator.of(context);
    await service.deleteRule(_rule);
    navigator.pop();
  }

  @override
  Widget build(BuildContext context) => LabelsBuilder(
    builder: (context, labels) => Scaffold(
      appBar: AppBar(
        title: Text(_isNew ? 'New rule' : 'Edit rule'),
        actions: [
          if (!_isNew)
            IconButton(
              tooltip: 'Delete rule',
              icon: const Icon(Icons.delete_outline),
              onPressed: _delete,
            ),
          Padding(
            padding: const EdgeInsets.only(right: Gap.sm),
            child: FilledButton(
              style: FilledButton.styleFrom(minimumSize: const Size(72, 40)),
              onPressed: _saving ? null : _save,
              child: const Text('Save'),
            ),
          ),
        ],
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            padding: const EdgeInsets.all(Gap.md),
            children: [
              TextField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Name'),
              ),
              // Near the top, so it's seen without scrolling.
              if (_error case final error?)
                Padding(
                  padding: const EdgeInsets.only(top: Gap.md),
                  child: Text(
                    error,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: Gap.lg),
              Row(
                children: [
                  Text(
                    'When a link matches',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(width: Gap.sm),
                  DropdownButton<bool>(
                    value: _rule.matchAll,
                    items: const [
                      DropdownMenuItem(value: true, child: Text('all of')),
                      DropdownMenuItem(value: false, child: Text('any of')),
                    ],
                    onChanged: (all) =>
                        setState(() => _rule = _rule.copyWith(matchAll: all)),
                  ),
                ],
              ),
              for (var i = 0; i < _rule.conditions.length; i++)
                _ConditionRow(
                  key: ObjectKey(_values[i]),
                  condition: _rule.conditions[i],
                  value: _values[i],
                  sources: labels.sources,
                  onChanged: (c) => _setCondition(i, c),
                  onRemove: _rule.conditions.length == 1
                      ? null
                      : () => _removeCondition(i),
                ),
              if (_rule.conditions.length < maxRuleConditions)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Add condition'),
                    onPressed: _addCondition,
                  ),
                ),
              const SizedBox(height: Gap.lg),
              Text('Then', style: Theme.of(context).textTheme.titleSmall),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.label_outline),
                title: const Text('Add tags'),
                subtitle: Text(
                  _rule.tagIds.isEmpty
                      ? 'None'
                      : labels
                            .resolve(LabelKind.tag, _rule.tagIds)
                            .map((t) => t.name)
                            .join(', '),
                ),
                onTap: () async {
                  final chosen = await showLabelPicker(
                    context,
                    kind: LabelKind.tag,
                    available: labels.tags,
                    selected: _rule.tagIds,
                  );
                  if (chosen != null) {
                    setState(
                      () => _rule = _rule.copyWith(tagIds: chosen.toList()),
                    );
                  }
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.folder_outlined),
                title: const Text('Add to collection'),
                trailing: DropdownButton<String?>(
                  value:
                      labels.find(
                            LabelKind.collection,
                            _rule.collectionId ?? '',
                          ) ==
                          null
                      ? null
                      : _rule.collectionId,
                  hint: const Text('None'),
                  items: [
                    const DropdownMenuItem(value: null, child: Text('None')),
                    for (final (c, _) in labelTree(labels.collections))
                      DropdownMenuItem(
                        value: c.id,
                        child: Text(labelPath(c, labels.collections)),
                      ),
                  ],
                  onChanged: (id) => setState(
                    () => _rule = _rule.copyWith(
                      collectionId: id,
                      clearCollection: id == null,
                    ),
                  ),
                ),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.star_outline),
                title: const Text('Add to favorites'),
                value: _rule.favorite,
                onChanged: (on) =>
                    setState(() => _rule = _rule.copyWith(favorite: on)),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.power_settings_new),
                title: const Text('Rule is on'),
                value: _rule.enabled,
                onChanged: (on) =>
                    setState(() => _rule = _rule.copyWith(enabled: on)),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

class _ConditionRow extends StatelessWidget {
  const _ConditionRow({
    super.key,
    required this.condition,
    required this.value,
    required this.sources,
    required this.onChanged,
    required this.onRemove,
  });

  final RuleCondition condition;
  final TextEditingController value;
  final List<CustomSource> sources;
  final ValueChanged<RuleCondition> onChanged;
  final VoidCallback? onRemove;

  static String _firstChoice(RuleField field, List<CustomSource> sources) =>
      switch (field) {
        RuleField.source => allSources(sources).first.id,
        RuleField.kind => ContentType.video.name,
        _ => '',
      };

  @override
  Widget build(BuildContext context) {
    final field = condition.field;
    final ops = field.isChoice ? const [RuleOp.isEqual] : RuleOp.values;
    final choices = switch (field) {
      RuleField.source => [for (final s in allSources(sources)) (s.id, s.name)],
      RuleField.kind => [for (final k in ContentType.values) (k.name, k.label)],
      _ => const <(String, String)>[],
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Gap.xs),
      child: Wrap(
        spacing: Gap.sm,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DropdownButton<RuleField>(
            value: field,
            items: [
              for (final f in RuleField.values)
                DropdownMenuItem(value: f, child: Text(f.label)),
            ],
            onChanged: (f) {
              if (f == null || f == field) return;
              value.clear();
              onChanged(
                RuleCondition(
                  f,
                  f.isChoice ? RuleOp.isEqual : condition.op,
                  _firstChoice(f, sources),
                ),
              );
            },
          ),
          DropdownButton<RuleOp>(
            value: ops.contains(condition.op) ? condition.op : ops.first,
            items: [
              for (final o in ops)
                DropdownMenuItem(value: o, child: Text(o.label)),
            ],
            onChanged: (o) => onChanged(
              RuleCondition(field, o ?? condition.op, condition.value),
            ),
          ),
          if (field.isChoice)
            DropdownButton<String>(
              value: choices.any((c) => c.$1 == condition.value)
                  ? condition.value
                  : null,
              items: [
                for (final (id, name) in choices)
                  DropdownMenuItem(value: id, child: Text(name)),
              ],
              onChanged: (v) =>
                  onChanged(RuleCondition(field, condition.op, v ?? '')),
            )
          else
            SizedBox(
              width: 220,
              child: TextField(
                controller: value,
                decoration: InputDecoration(
                  hintText: switch (field) {
                    RuleField.domain => 'amazon.com',
                    RuleField.url => '/r/flutter',
                    RuleField.title => 'recipe',
                    RuleField.importedFrom => 'Chrome',
                    _ => '',
                  },
                ),
              ),
            ),
          if (onRemove != null)
            IconButton(
              tooltip: 'Remove condition',
              icon: const Icon(Icons.remove_circle_outline),
              onPressed: onRemove,
            ),
        ],
      ),
    );
  }
}
