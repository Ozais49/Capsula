import 'dart:async';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../app/dependencies.dart';
import '../../app/router.dart';
import '../../app/theme.dart';

import 'package:capsula_core/domain/bookmarks/bookmark_service.dart';
import 'package:capsula_core/domain/bookmarks/shared_content.dart';

import '../bookmarks/bookmark_display.dart';

/// Shown over the sharing app when a link is shared to Capsula. Saves to
/// the Inbox without asking anything, then closes.
class ShareScreen extends StatefulWidget {
  const ShareScreen({super.key});

  /// How long the confirmation stays before closing on its own.
  static const autoCloseDelay = Duration(milliseconds: 1200);

  /// How long to wait for a link's title before closing anyway; the title
  /// is fetched again the next time Capsula opens.
  static const titleTimeout = Duration(seconds: 6);

  @override
  State<ShareScreen> createState() => _ShareScreenState();
}

sealed class _State {
  const _State();
}

class _Working extends _State {
  const _Working([this.message = 'Saving to Capsula…']);
  final String message;
}

class _NothingToSave extends _State {
  const _NothingToSave(this.message);
  final String message;
}

class _Finished extends _State {
  const _Finished(this.results, this.titles);
  final List<SaveResult> results;

  /// Titles of newly saved bookmarks, after looking them up.
  final List<String> titles;
}

class _Failed extends _State {
  const _Failed(this.error);
  final Object error;
}

class _ShareScreenState extends State<ShareScreen> {
  _State _state = const _Working();
  bool _started = false;
  Timer? _autoClose;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    _process();
  }

  @override
  void dispose() {
    _autoClose?.cancel();
    super.dispose();
  }

  Future<void> _process() async {
    final deps = AppDependencies.of(context);
    try {
      final content = await deps.shareIntake.take();
      if (content == null) {
        return _show(const _NothingToSave('Nothing was shared.'));
      }
      final links = extractSharedLinks(content);
      if (links.urls.isEmpty) {
        return _show(const _NothingToSave('No link found in what was shared.'));
      }

      final results = <SaveResult>[];
      for (final url in links.urls) {
        results.add(await deps.bookmarks.save(url.toString()));
      }

      // Saved already; now get each link's real title from its source.
      // Text shared along with a single link is the fallback.
      final saved = results.whereType<Saved>().map((s) => s.bookmark).toList();
      var titles = saved.map((b) => b.displayTitle).toList();
      if (saved.isNotEmpty) {
        _show(const _Working('Saved. Getting the title…'));
        titles = await Future.wait([
          for (final b in saved)
            deps.bookmarks
                .fetchDetails(b, deps.pageInfo, fallbackTitle: links.title)
                .then((updated) => (updated ?? b).displayTitle)
                .timeout(
                  ShareScreen.titleTimeout,
                  onTimeout: () => b.displayTitle,
                ),
        ]);
      }
      _show(_Finished(results, titles));

      if (results.every((r) => r is Saved)) {
        _autoClose = Timer(ShareScreen.autoCloseDelay, _close);
      }
    } on Object catch (e) {
      _show(_Failed(e));
    }
  }

  void _show(_State state) {
    if (mounted) setState(() => _state = state);
  }

  void _close() {
    _autoClose?.cancel();
    AppDependencies.of(context).shareIntake.finish();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.black38,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _state is _Working ? null : _close,
        child: SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: GestureDetector(
                onTap: () {}, // Taps on the card don't close it.
                child: Card(
                  margin: const EdgeInsets.all(Gap.md),
                  child: Padding(
                    padding: const EdgeInsets.all(Gap.lg),
                    child: switch (_state) {
                      _Working(:final message) => _Row(
                        leading: SizedBox.square(
                          dimension: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        text: message,
                      ),
                      _NothingToSave(:final message) => _Summary(
                        icon: Icons.link_off,
                        iconColor: theme.colorScheme.error,
                        title: message,
                        onDone: _close,
                      ),
                      _Failed(:final error) => _Summary(
                        icon: Icons.error_outline,
                        iconColor: theme.colorScheme.error,
                        title: 'Could not save',
                        detail: '$error',
                        onDone: _close,
                      ),
                      _Finished(:final results, :final titles) => _finished(
                        results,
                        titles,
                        theme,
                      ),
                    },
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _finished(
    List<SaveResult> results,
    List<String> titles,
    ThemeData theme,
  ) {
    final saved = results.whereType<Saved>().length;
    final duplicates = results.whereType<AlreadySaved>().toList();
    final invalid = results.whereType<InvalidUrl>().length;

    if (results.length == 1 && duplicates.length == 1) {
      final existing = duplicates.single.existing;
      return _Summary(
        icon: Icons.bookmark_added_outlined,
        iconColor: theme.colorScheme.primary,
        title: 'Already in Capsula',
        detail:
            '${existing.displayTitle}\n'
            'Saved ${formatSavedDate(existing.createdAt).toLowerCase()} · '
            '${existing.source.label}',
        onDone: _close,
        secondary: TextButton(
          onPressed: () {
            _autoClose?.cancel();
            context.push(AppRoutes.bookmark(existing.id));
          },
          child: const Text('View'),
        ),
      );
    }

    final parts = [
      if (saved > 0)
        saved == 1 ? 'Saved to Inbox' : 'Saved $saved links to Inbox',
      if (duplicates.isNotEmpty) '${duplicates.length} already saved',
      if (invalid > 0) '$invalid not saved',
    ];
    return _Summary(
      icon: saved > 0 ? Icons.check_circle_outline : Icons.bookmark_added,
      iconColor: theme.colorScheme.primary,
      title: parts.join(' · '),
      detail: titles.isEmpty ? null : titles.join('\n'),
      onDone: _close,
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.leading, required this.text});

  final Widget leading;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      leading,
      const SizedBox(width: Gap.md),
      Expanded(
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      ),
    ],
  );
}

class _Summary extends StatelessWidget {
  const _Summary({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.onDone,
    this.detail,
    this.secondary,
  });

  final IconData icon;
  final Color iconColor;
  final String title;
  final String? detail;
  final VoidCallback onDone;
  final Widget? secondary;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Row(
          leading: Icon(icon, color: iconColor),
          text: title,
        ),
        if (detail case final detail?) ...[
          const SizedBox(height: Gap.sm),
          Text(
            detail,
            style: theme.textTheme.bodySmall,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
          ),
        ],
        const SizedBox(height: Gap.md),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            ?secondary,
            const SizedBox(width: Gap.sm),
            FilledButton(
              // The theme's full-width minimum doesn't fit inside a Row.
              style: FilledButton.styleFrom(minimumSize: const Size(88, 40)),
              onPressed: onDone,
              child: const Text('Done'),
            ),
          ],
        ),
      ],
    );
  }
}
