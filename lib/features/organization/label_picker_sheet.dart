import 'package:flutter/material.dart';

import '../../app/dependencies.dart';
import '../../app/theme.dart';
import '../../domain/organization/label.dart';

/// Lets the user choose labels of [kind], creating new ones inline.
/// Returns the chosen IDs, or null when dismissed.
Future<Set<String>?> showLabelPicker(
  BuildContext context, {
  required LabelKind kind,
  required List<Label> available,
  required Iterable<String> selected,
}) => showModalBottomSheet<Set<String>>(
  context: context,
  isScrollControlled: true,
  showDragHandle: true,
  builder: (_) => _LabelPicker(
    kind: kind,
    available: available,
    selected: selected.toSet(),
  ),
);

class _LabelPicker extends StatefulWidget {
  const _LabelPicker({
    required this.kind,
    required this.available,
    required this.selected,
  });

  final LabelKind kind;
  final List<Label> available;
  final Set<String> selected;

  @override
  State<_LabelPicker> createState() => _LabelPickerState();
}

class _LabelPickerState extends State<_LabelPicker> {
  late final Set<String> _selected = {...widget.selected};
  late List<Label> _labels = widget.available;
  final _newName = TextEditingController();

  @override
  void dispose() {
    _newName.dispose();
    super.dispose();
  }

  void _create() {
    final label = AppDependencies.of(context).bookmarks
        .createLabel(widget.kind, _newName.text, _labels);
    if (label == null) return;
    setState(() {
      if (!_labels.any((l) => l.id == label.id)) {
        _labels = sortLabels([..._labels, label]);
      }
      _selected.add(label.id);
      _newName.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final kind = widget.kind;

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
              child: Text(kind.plural, style: theme.textTheme.titleLarge),
            ),
            const SizedBox(height: Gap.sm),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gap.lg),
              child: TextField(
                controller: _newName,
                maxLength: maxLabelNameLength,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _create(),
                decoration: InputDecoration(
                  labelText: 'New ${kind.singular.toLowerCase()}',
                  counterText: '',
                  suffixIcon: IconButton(
                    tooltip: 'Create',
                    icon: const Icon(Icons.add),
                    onPressed: _create,
                  ),
                ),
              ),
            ),
            Flexible(
              child: _labels.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(Gap.lg),
                      child: Text(
                        'No ${kind.plural.toLowerCase()} yet.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : ListView(
                      shrinkWrap: true,
                      children: [
                        for (final label in _labels)
                          CheckboxListTile(
                            value: _selected.contains(label.id),
                            title: Text(label.name),
                            onChanged: (checked) => setState(
                              () => checked == true
                                  ? _selected.add(label.id)
                                  : _selected.remove(label.id),
                            ),
                          ),
                      ],
                    ),
            ),
            Padding(
              padding: const EdgeInsets.all(Gap.lg),
              child: FilledButton(
                onPressed: () => Navigator.pop(context, _selected),
                child: const Text('Done'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
