import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/dependencies.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../domain/bookmarks/bookmark.dart';
import '../../domain/bookmarks/bookmark_service.dart';
import 'bookmark_display.dart';

Future<void> showAddBookmarkSheet(BuildContext context) =>
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => const _AddBookmarkSheet(),
    );

class _AddBookmarkSheet extends StatefulWidget {
  const _AddBookmarkSheet();

  @override
  State<_AddBookmarkSheet> createState() => _AddBookmarkSheetState();
}

class _AddBookmarkSheetState extends State<_AddBookmarkSheet> {
  final _url = TextEditingController();
  final _title = TextEditingController();
  bool _saving = false;
  String? _error;
  Bookmark? _duplicate;

  @override
  void dispose() {
    _url.dispose();
    _title.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final service = AppDependencies.of(context).bookmarks;
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _saving = true;
      _error = null;
      _duplicate = null;
    });

    final SaveResult result;
    try {
      result = await service.save(_url.text, title: _title.text);
    } on Object catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not save: $e';
        });
      }
      return;
    }
    if (!mounted) return;

    switch (result) {
      case InvalidUrl():
        setState(() {
          _saving = false;
          _error = 'Enter a web address, like example.com/article.';
        });
      case AlreadySaved(:final existing):
        setState(() {
          _saving = false;
          _duplicate = existing;
        });
      case Saved(:final committed):
        Navigator.of(context).pop();
        messenger.showSnackBar(const SnackBar(content: Text('Saved to Inbox')));
        committed.catchError((Object e) {
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(
            SnackBar(
              content: Text('Saved on this device, but sync failed: $e'),
            ),
          );
        });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final duplicate = _duplicate;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        Gap.lg,
        0,
        Gap.lg,
        Gap.lg + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Add bookmark', style: theme.textTheme.titleLarge),
          const SizedBox(height: Gap.md),
          TextField(
            controller: _url,
            autofocus: true,
            enabled: !_saving,
            keyboardType: TextInputType.url,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(labelText: 'URL', errorText: _error),
          ),
          const SizedBox(height: Gap.md),
          TextField(
            controller: _title,
            enabled: !_saving,
            textInputAction: TextInputAction.done,
            onSubmitted: (_) => _save(),
            decoration: const InputDecoration(labelText: 'Title (optional)'),
          ),
          if (duplicate != null) ...[
            const SizedBox(height: Gap.md),
            Card(
              color: theme.colorScheme.secondaryContainer,
              child: ListTile(
                leading: const Icon(Icons.bookmark_added_outlined),
                title: const Text('Already saved'),
                subtitle: Text(
                  '${formatSavedDate(duplicate.createdAt)} · '
                  '${duplicate.source.label}',
                ),
                trailing: TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    context.push(AppRoutes.bookmark(duplicate.id));
                  },
                  child: const Text('View'),
                ),
              ),
            ),
          ],
          const SizedBox(height: Gap.lg),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }
}
