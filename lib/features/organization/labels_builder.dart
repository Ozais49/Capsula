import 'package:flutter/material.dart';

import '../../app/dependencies.dart';

import 'package:capsula_core/domain/organization/label.dart';

/// The user's tags and collections, kept up to date.
class Labels {
  const Labels({this.tags = const [], this.collections = const []});

  final List<Label> tags;
  final List<Label> collections;

  List<Label> of(LabelKind kind) => switch (kind) {
    LabelKind.tag => tags,
    LabelKind.collection => collections,
  };

  Label? find(LabelKind kind, String id) =>
      of(kind).where((l) => l.id == id).firstOrNull;

  /// Names for [ids], skipping labels that no longer exist.
  List<Label> resolve(LabelKind kind, Iterable<String> ids) =>
      ids.map((id) => find(kind, id)).nonNulls.toList();
}

/// Subscribes to tags and collections and rebuilds when either changes.
class LabelsBuilder extends StatefulWidget {
  const LabelsBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, Labels labels) builder;

  @override
  State<LabelsBuilder> createState() => _LabelsBuilderState();
}

class _LabelsBuilderState extends State<LabelsBuilder> {
  Stream<List<Label>>? _tags;
  Stream<List<Label>>? _collections;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final repo = AppDependencies.of(context).bookmarks.labels;
    _tags ??= repo.watch(LabelKind.tag);
    _collections ??= repo.watch(LabelKind.collection);
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<List<Label>>(
    stream: _tags,
    builder: (context, tags) => StreamBuilder<List<Label>>(
      stream: _collections,
      builder: (context, collections) => widget.builder(
        context,
        Labels(
          tags: tags.data ?? const [],
          collections: collections.data ?? const [],
        ),
      ),
    ),
  );
}
