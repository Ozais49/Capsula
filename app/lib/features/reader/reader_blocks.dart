import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../app/theme.dart';

import 'package:capsula_core/domain/reader/reader_content.dart';

import '../common/open_link.dart';
import '../highlights/highlight_widgets.dart';

import 'package:capsula_core/domain/highlights/highlight.dart';

/// Renders extracted article blocks as native widgets.
class ReaderBlocks extends StatelessWidget {
  const ReaderBlocks({super.key, required this.blocks, this.marks = const []});

  final List<ReaderBlock> blocks;

  /// Highlights to mark wherever their text appears.
  final List<Highlight> marks;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [for (final block in blocks) _block(context, block)],
  );

  Widget _block(BuildContext context, ReaderBlock block) {
    final theme = Theme.of(context);
    final body = theme.textTheme.bodyLarge?.copyWith(height: 1.6);

    return switch (block) {
      HeadingBlock(:final level, :final runs) => Padding(
        padding: const EdgeInsets.only(top: Gap.lg, bottom: Gap.sm),
        child: RichRuns(
          runs: runs,
          marks: marks,
          style: switch (level) {
            1 || 2 => theme.textTheme.headlineSmall,
            3 => theme.textTheme.titleLarge,
            _ => theme.textTheme.titleMedium,
          },
        ),
      ),
      ParagraphBlock(:final runs) => Padding(
        padding: const EdgeInsets.only(bottom: Gap.md),
        child: RichRuns(runs: runs, style: body, marks: marks),
      ),
      ListBlock(:final ordered, :final items) => Padding(
        padding: const EdgeInsets.only(bottom: Gap.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final (i, item) in items.indexed)
              Padding(
                padding: const EdgeInsets.only(bottom: Gap.xs),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 28,
                      child: Text(ordered ? '${i + 1}.' : '•', style: body),
                    ),
                    Expanded(
                      child: RichRuns(runs: item, style: body, marks: marks),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      QuoteBlock(:final blocks) => Container(
        margin: const EdgeInsets.only(bottom: Gap.md),
        padding: const EdgeInsets.only(left: Gap.md),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(color: theme.colorScheme.outlineVariant, width: 3),
          ),
        ),
        child: ReaderBlocks(blocks: blocks, marks: marks),
      ),
      CodeBlock(:final text) => Container(
        margin: const EdgeInsets.only(bottom: Gap.md),
        padding: const EdgeInsets.all(Gap.md),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SelectableText(
            text,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: 'monospace',
            ),
          ),
        ),
      ),
      ImageBlock(:final url, :final caption) => Padding(
        padding: const EdgeInsets.only(bottom: Gap.md),
        child: ReaderImage(url: url, caption: caption),
      ),
    };
  }
}

/// An image that disappears quietly if it can't be loaded.
class ReaderImage extends StatelessWidget {
  const ReaderImage({super.key, required this.url, this.caption});

  final Uri url;
  final String? caption;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            url.toString(),
            fit: BoxFit.contain,
            semanticLabel: caption,
            excludeFromSemantics: caption == null,
            // Use an <img> element on the web when the server doesn't allow
            // cross-origin image reads.
            webHtmlElementStrategy: WebHtmlElementStrategy.fallback,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : AspectRatio(
                    aspectRatio: 16 / 9,
                    child: ColoredBox(
                      color: theme.colorScheme.surfaceContainerHighest,
                    ),
                  ),
          ),
        ),
        if (caption case final caption?)
          Padding(
            padding: const EdgeInsets.only(top: Gap.xs),
            child: Text(
              caption,
              style: theme.textTheme.bodySmall,
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}

/// Formatted inline text with tappable links.
class RichRuns extends StatefulWidget {
  const RichRuns({
    super.key,
    required this.runs,
    this.style,
    this.marks = const [],
  });

  final List<InlineRun> runs;
  final TextStyle? style;
  final List<Highlight> marks;

  @override
  State<RichRuns> createState() => _RichRunsState();
}

class _RichRunsState extends State<RichRuns> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  TapGestureRecognizer _linkRecognizer(Uri link) {
    final recognizer = TapGestureRecognizer()
      ..onTap = () => openExternal(context, link);
    _recognizers.add(recognizer);
    return recognizer;
  }

  /// Highlighted character ranges of this text, with their colors.
  List<(int, int, HighlightColor)> _ranges(String plain) => [
    for (final h in widget.marks)
      for (final (start, end) in highlightRanges(plain, [h.text]))
        (start, end, h.color),
  ];

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ranges = widget.marks.isEmpty
        ? const <(int, int, HighlightColor)>[]
        : _ranges(widget.runs.map((r) => r.text).join());

    final spans = <InlineSpan>[];
    var offset = 0;
    for (final run in widget.runs) {
      final start = offset;
      final end = offset + run.text.length;
      offset = end;
      // Cut the run wherever a highlight starts or ends inside it.
      final cuts = {
        start,
        end,
        for (final (s, e, _) in ranges) ...[
          if (s > start && s < end) s,
          if (e > start && e < end) e,
        ],
      }.toList()..sort();
      for (var i = 0; i < cuts.length - 1; i++) {
        final (a, b) = (cuts[i], cuts[i + 1]);
        final mark = ranges.where((r) => r.$1 <= a && r.$2 >= b).firstOrNull;
        spans.add(
          TextSpan(
            text: run.text.substring(a - start, b - start),
            style: TextStyle(
              fontWeight: run.bold ? FontWeight.bold : null,
              fontStyle: run.italic ? FontStyle.italic : null,
              fontFamily: run.code ? 'monospace' : null,
              backgroundColor: mark != null
                  ? highlightColor(mark.$3, theme.brightness)
                  : run.code
                  ? scheme.surfaceContainerHighest
                  : null,
              color: run.link != null ? scheme.primary : null,
              decoration: run.link != null ? TextDecoration.underline : null,
            ),
            recognizer: run.link == null ? null : _linkRecognizer(run.link!),
          ),
        );
      }
    }
    return Text.rich(TextSpan(style: widget.style, children: spans));
  }
}
