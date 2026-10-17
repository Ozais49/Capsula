import 'package:capsula_core/domain/bookmarks/bookmark_repository.dart';
import 'package:flutter/material.dart';

import '../../app/dependencies.dart';

/// A small cloud icon shown while changes made on this device are waiting
/// for the backend (for example while offline). Nothing otherwise.
class SyncIndicator extends StatefulWidget {
  const SyncIndicator({super.key});

  @override
  State<SyncIndicator> createState() => _SyncIndicatorState();
}

class _SyncIndicatorState extends State<SyncIndicator> {
  BookmarkRepository? _repository;
  Stream<bool>? _pending;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // A new stream only when the library changes (signing in or out,
    // switching to the on-device library), not on every rebuild.
    final repository = AppDependencies.of(context).bookmarks.repository;
    if (!identical(repository, _repository)) {
      _repository = repository;
      _pending = repository.watchPendingWrites();
    }
  }

  @override
  Widget build(BuildContext context) => StreamBuilder<bool>(
    stream: _pending,
    builder: (context, pending) => pending.data ?? false
        ? const Tooltip(
            message: 'Waiting to sync. Changes are saved on this device.',
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: 8),
              child: Icon(Icons.cloud_upload_outlined, size: 20),
            ),
          )
        : const SizedBox.shrink(),
  );
}
