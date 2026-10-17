import 'package:capsula_core/domain/organization/label.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../app/dependencies.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../common/open_link.dart';

/// Turns a collection's public read-only link on or off.
Future<void> showShareCollectionDialog(
  BuildContext context,
  Label collection,
) => showDialog<void>(
  context: context,
  builder: (_) => _ShareDialog(collection: collection),
);

class _ShareDialog extends StatefulWidget {
  const _ShareDialog({required this.collection});

  final Label collection;

  @override
  State<_ShareDialog> createState() => _ShareDialogState();
}

class _ShareDialogState extends State<_ShareDialog> {
  late bool _shared = widget.collection.shareId != null;
  Uri? _url;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (_shared) _load();
  }

  /// Fetches the existing link's URL (sharing again returns the same link).
  Future<void> _load() => _run(() async {
    _url = await AppDependencies.of(context)
        .apiClient()!
        .shareCollection(widget.collection.id);
  });

  Future<void> _toggle(bool on) => _run(() async {
    final api = AppDependencies.of(context).apiClient()!;
    if (on) {
      _url = await api.shareCollection(widget.collection.id);
    } else {
      await api.unshareCollection(widget.collection.id);
      _url = null;
    }
    _shared = on;
  });

  Future<void> _run(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on Object catch (e) {
      _error = 'Could not update the link: $e';
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasApi = AppDependencies.of(context).apiClient() != null;
    final url = _url;

    return AlertDialog(
      title: Text('Share "${widget.collection.name}"'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: !hasApi
            ? const Text(
                'Public links are served by your Capsula API server. Set it '
                'up under API & integrations first.',
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Public link'),
                    subtitle: const Text(
                      'Anyone with the link can see the titles and links in '
                      'this collection. Notes, tags and highlights stay '
                      'private.',
                    ),
                    value: _shared,
                    onChanged: _busy ? null : _toggle,
                  ),
                  if (_busy) const LinearProgressIndicator(),
                  if (_shared && url != null) ...[
                    const SizedBox(height: Gap.sm),
                    SelectableText(
                      url.toString(),
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: Gap.sm),
                    Wrap(
                      spacing: Gap.sm,
                      children: [
                        OutlinedButton.icon(
                          onPressed: () {
                            Clipboard.setData(
                              ClipboardData(text: url.toString()),
                            );
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Link copied')),
                            );
                          },
                          icon: const Icon(Icons.copy),
                          label: const Text('Copy link'),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => openExternal(context, url),
                          icon: const Icon(Icons.open_in_new),
                          label: const Text('Open'),
                        ),
                      ],
                    ),
                  ],
                  if (_error case final error?) ...[
                    const SizedBox(height: Gap.sm),
                    Text(
                      error,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                ],
              ),
      ),
      actions: [
        if (!hasApi)
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              context.push(AppRoutes.integrations);
            },
            child: const Text('Set up API'),
          ),
        FilledButton(
          style: FilledButton.styleFrom(minimumSize: const Size(88, 40)),
          onPressed: () => Navigator.pop(context),
          child: const Text('Done'),
        ),
      ],
    );
  }
}
