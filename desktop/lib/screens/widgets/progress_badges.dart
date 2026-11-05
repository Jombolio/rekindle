import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models/media.dart';
import '../../core/models/progress_summary.dart';
import '../../providers/progress_summary_provider.dart';
import '../../providers/reader_provider.dart';

/// The reading state to show for [media]: the server's summary when there is
/// one, otherwise this device's local progress (single archives only).
ProgressSummary? watchProgressSummary(
    WidgetRef ref, Media media, String chunkKey) {
  final remote = ref.watch(progressSummariesProvider(chunkKey)
      .select((s) => s.valueOrNull?[media.id]));
  if (remote != null || media.isFolder) return remote;

  final local = ref.watch(localProgressProvider(media.id)).valueOrNull;
  return local == null ? null : ProgressSummary.fromLocal(local, media.pageCount);
}

/// Re-fetches everything behind the badges: the server's summaries (this and
/// any other device's progress) and this device's local rows.
///
/// A refresh has to ask for this by hand: the summary chunks are keyed by the
/// ids they cover, so a reload that returns the same items hands the tiles back
/// the progress fetched when the screen opened — which is why progress made
/// elsewhere only caught up after leaving the screen and coming back.
void refreshProgressBadges(WidgetRef ref) {
  ref.invalidate(progressSummariesProvider);
  ref.invalidate(localProgressProvider);
}

/// Circular read-progress indicator for the bottom-left corner of a cover.
///
/// A partial orange ring while reading, a full green ring with a check once
/// finished, and nothing for items never started.
class ReadProgressRing extends StatelessWidget {
  final ProgressSummary? summary;
  final double size;
  final double inset;

  const ReadProgressRing({
    super.key,
    required this.summary,
    this.size = 26,
    this.inset = 4,
  });

  /// Smallest arc drawn for a started item, so a few pages into a long book
  /// still shows something.
  static const _minVisible = 0.04;

  @override
  Widget build(BuildContext context) {
    final s = summary;
    if (s == null || !s.isStarted) return const SizedBox.shrink();

    final completed = s.isCompleted;
    final label = completed ? 'Read' : '${s.percent}% read';

    return Positioned(
      bottom: inset,
      left: inset,
      child: Tooltip(
        message: label,
        child: Semantics(
          label: label,
          child: Container(
            width: size,
            height: size,
            padding: EdgeInsets.all(size * 0.1),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.6),
              shape: BoxShape.circle,
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                CircularProgressIndicator(
                  value: completed ? 1 : max(s.progress, _minVisible),
                  strokeWidth: size * 0.12,
                  color: completed ? Colors.green : Colors.orange,
                  backgroundColor: Colors.white24,
                ),
                if (completed)
                  Icon(Icons.check, size: size * 0.5, color: Colors.white),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// "3 NEW" badge for the top-right corner of a series cover: chapters added
/// since the user last read anything in it.
class NewChaptersBadge extends StatelessWidget {
  final int count;
  final double inset;

  const NewChaptersBadge({super.key, required this.count, this.inset = 4});

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    final scheme = Theme.of(context).colorScheme;
    final label = count == 1 ? '1 new chapter' : '$count new chapters';

    return Positioned(
      top: inset,
      right: inset,
      child: Tooltip(
        message: label,
        child: Semantics(
          label: label,
          excludeSemantics: true,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
            decoration: BoxDecoration(
              color: scheme.primary,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(
              '$count NEW',
              style: TextStyle(
                color: scheme.onPrimary,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
