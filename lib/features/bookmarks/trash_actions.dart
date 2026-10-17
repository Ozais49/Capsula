import 'package:flutter/material.dart';

/// Asks before deleting [count] bookmarks for good. True to go ahead.
Future<bool> confirmDeleteForever(BuildContext context, int count) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          count == 1 ? 'Delete forever?' : 'Delete $count bookmarks forever?',
        ),
        content: const Text(
          "Highlights and saved page text go too. This can't be undone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(minimumSize: const Size(88, 40)),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete forever'),
          ),
        ],
      ),
    ) ??
    false;
