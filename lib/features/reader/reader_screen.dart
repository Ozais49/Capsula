import 'package:flutter/material.dart';

import '../../app/dependencies.dart';
import '../../app/theme.dart';
import '../../domain/bookmarks/bookmark.dart';
import '../../domain/reader/reader_content.dart';
import '../../domain/reader/reader_service.dart';
import '../common/open_link.dart';
import 'reader_blocks.dart';

/// In-app reading view. The original page is always one tap away.
class ReaderScreen extends StatefulWidget {
  const ReaderScreen({super.key, required this.bookmarkId});

  final String bookmarkId;

  @override
  State<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends State<ReaderScreen> {
  Stream<Bookmark?>? _bookmark;
  Future<ReaderContent>? _content;
  String? _loadedUrl;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _bookmark ??= AppDependencies.of(context).bookmarks.repository
        .watch(widget.bookmarkId);
  }

  /// Loads once per URL, so saving enriched details doesn't reload.
  Future<ReaderContent> _contentFor(Bookmark bookmark) {
    if (_content == null || _loadedUrl != bookmark.url) {
      _loadedUrl = bookmark.url;
      _content = _load(bookmark);
    }
    return _content!;
  }

  Future<ReaderContent> _load(Bookmark bookmark) async {
    final deps = AppDependencies.of(context);
    final content = await deps.reader.load(bookmark);
    final metadata = metadataFrom(content);
    if (metadata != null) {
      // Best effort; the reader works the same if this fails.
      deps.bookmarks.applyMetadata(bookmark, metadata);
    }
    return content;
  }

  void _retry(Bookmark bookmark) => setState(() {
    _content = _load(bookmark);
  });

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Bookmark?>(
      stream: _bookmark,
      builder: (context, snapshot) {
        final bookmark = snapshot.data;
        return Scaffold(
          appBar: AppBar(
            title: Text(bookmark?.sourceDomain ?? ''),
            actions: [
              if (bookmark != null)
                IconButton(
                  tooltip: 'Open in browser',
                  icon: const Icon(Icons.open_in_new),
                  onPressed: () =>
                      openExternal(context, Uri.parse(bookmark.url)),
                ),
            ],
          ),
          body: switch (snapshot) {
            AsyncSnapshot(hasError: true) => _centered(
              Text('Could not load: ${snapshot.error}'),
            ),
            AsyncSnapshot(connectionState: ConnectionState.waiting) =>
              const Center(child: CircularProgressIndicator()),
            _ when bookmark == null => _centered(
              const Text('This bookmark no longer exists.'),
            ),
            _ => FutureBuilder<ReaderContent>(
              future: _contentFor(bookmark),
              builder: (context, content) => switch (content) {
                AsyncSnapshot(:final data?) => _ReaderBody(
                  bookmark: bookmark,
                  content: data,
                  onRetry: () => _retry(bookmark),
                ),
                AsyncSnapshot(hasError: true) => _ReaderBody(
                  bookmark: bookmark,
                  content: const Unavailable(UnavailableReason.failed),
                  onRetry: () => _retry(bookmark),
                ),
                _ => const _Loading(),
              },
            ),
          },
        );
      },
    );
  }

  static Widget _centered(Widget child) => Center(
    child: Padding(padding: const EdgeInsets.all(Gap.lg), child: child),
  );
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) => const Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        CircularProgressIndicator(),
        SizedBox(height: Gap.md),
        Text('Loading reader view…'),
      ],
    ),
  );
}

class _ReaderBody extends StatelessWidget {
  const _ReaderBody({
    required this.bookmark,
    required this.content,
    required this.onRetry,
  });

  final Bookmark bookmark;
  final ReaderContent content;
  final VoidCallback onRetry;

  Uri get _url => Uri.parse(bookmark.url);

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Gap.lg),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: SelectionArea(
            child: switch (content) {
              final ArticleContent article => _article(context, article),
              final VideoContent video => _video(context, video),
              final PreviewContent preview => _preview(context, preview),
              final Unavailable unavailable => _unavailable(
                context,
                unavailable,
              ),
            },
          ),
        ),
      ),
    );
  }

  Widget _openButton(
    BuildContext context, {
    String label = 'Open in browser',
  }) => FilledButton.icon(
    onPressed: () => openExternal(context, _url),
    icon: const Icon(Icons.open_in_new),
    label: Text(label),
  );

  Widget _article(BuildContext context, ArticleContent article) {
    final theme = Theme.of(context);
    final meta = [
      ?article.siteName,
      ?article.byline,
    ].where((s) => s.isNotEmpty).join(' · ');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          article.title.isEmpty ? bookmark.displayTitle : article.title,
          style: theme.textTheme.headlineMedium,
        ),
        if (meta.isNotEmpty) ...[
          const SizedBox(height: Gap.sm),
          Text(meta, style: theme.textTheme.bodyMedium),
        ],
        const SizedBox(height: Gap.lg),
        if (article.leadImage case final image?) ...[
          ReaderImage(url: image),
          const SizedBox(height: Gap.lg),
        ],
        ReaderBlocks(blocks: article.blocks),
        const Divider(height: Gap.xl),
        _openButton(context, label: 'Read on ${bookmark.sourceDomain}'),
      ],
    );
  }

  Widget _video(BuildContext context, VideoContent video) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (video.thumbnail case final thumbnail?)
          InkWell(
            onTap: () => openExternal(context, video.videoUrl),
            borderRadius: BorderRadius.circular(12),
            child: Stack(
              alignment: Alignment.center,
              children: [
                ReaderImage(url: thumbnail),
                const CircleAvatar(
                  radius: 32,
                  backgroundColor: Colors.black54,
                  child: Icon(Icons.play_arrow, color: Colors.white, size: 40),
                ),
              ],
            ),
          ),
        const SizedBox(height: Gap.md),
        Text(video.title, style: theme.textTheme.headlineSmall),
        if (video.channel case final channel?) ...[
          const SizedBox(height: Gap.xs),
          Text(channel, style: theme.textTheme.bodyMedium),
        ],
        const SizedBox(height: Gap.lg),
        _openButton(context, label: 'Watch video'),
      ],
    );
  }

  Widget _preview(BuildContext context, PreviewContent preview) {
    final theme = Theme.of(context);
    final meta = preview.metadata;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (meta.image case final image?) ...[
          ReaderImage(url: image),
          const SizedBox(height: Gap.md),
        ],
        Text(
          meta.title ?? bookmark.displayTitle,
          style: theme.textTheme.headlineSmall,
        ),
        if (meta.siteName case final site?) ...[
          const SizedBox(height: Gap.xs),
          Text(site, style: theme.textTheme.bodyMedium),
        ],
        if (meta.description case final description?) ...[
          const SizedBox(height: Gap.md),
          Text(description, style: theme.textTheme.bodyLarge),
        ],
        if (preview.note case final note?) ...[
          const SizedBox(height: Gap.md),
          Text(note, style: theme.textTheme.bodySmall),
        ],
        const SizedBox(height: Gap.lg),
        _openButton(context),
      ],
    );
  }

  Widget _unavailable(BuildContext context, Unavailable unavailable) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SizedBox(height: Gap.xl),
        Icon(
          Icons.chrome_reader_mode_outlined,
          size: 48,
          color: theme.colorScheme.outline,
        ),
        const SizedBox(height: Gap.md),
        Text(
          unavailable.reason.message,
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: Gap.xs),
        Text(
          'Your bookmark is saved. You can open the original page.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: Gap.lg),
        _openButton(context),
        if (unavailable.reason == UnavailableReason.network ||
            unavailable.reason == UnavailableReason.failed) ...[
          const SizedBox(height: Gap.sm),
          TextButton(onPressed: onRetry, child: const Text('Try again')),
        ],
      ],
    );
  }
}
