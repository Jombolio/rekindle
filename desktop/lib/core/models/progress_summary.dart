import 'reading_progress.dart';

/// Per-user reading state for one media item, as shown on its cover.
/// Mirrors the server's `ProgressSummary`.
class ProgressSummary {
  final String mediaId;

  /// Fraction read, 0 to 1. For a series, the average over all its chapters.
  final double progress;
  final bool isCompleted;

  /// Series only: chapters added since the user last read anything in it.
  final int newCount;

  /// Chapters only: added since the user last read the series, not opened yet.
  final bool isNew;

  /// The user marked it as read (a series: every chapter in it). It then counts
  /// as read while they reread, and their reading progress is kept.
  final bool markedRead;

  /// The user left it out of the series' progress (a folder: everything in
  /// it), like an annual they skip. Its own progress still shows.
  final bool ignored;

  const ProgressSummary({
    required this.mediaId,
    required this.progress,
    required this.isCompleted,
    this.newCount = 0,
    this.isNew = false,
    this.markedRead = false,
    this.ignored = false,
  });

  factory ProgressSummary.fromJson(Map<String, dynamic> j) => ProgressSummary(
        mediaId: j['mediaId'] as String,
        progress: ((j['progress'] ?? 0) as num).toDouble().clamp(0.0, 1.0),
        isCompleted: (j['isCompleted'] ?? false) as bool,
        newCount: (j['newCount'] ?? 0) as int,
        isNew: (j['isNew'] ?? false) as bool,
        markedRead: (j['markedRead'] ?? false) as bool,
        ignored: (j['ignored'] ?? false) as bool,
      );

  /// Builds a summary from this device's local progress, for when the server
  /// can't be reached. Only possible for a single archive: a series' progress
  /// spans chapters that may never have been opened here. Without a known
  /// [pageCount] the fraction can't be computed, so only completion shows.
  factory ProgressSummary.fromLocal(ReadingProgress p, int? pageCount) {
    final double fraction;
    if (p.isCompleted) {
      fraction = 1;
    } else if (pageCount != null && pageCount > 0) {
      fraction = (p.currentPage / pageCount).clamp(0.0, 1.0);
    } else {
      fraction = 0;
    }
    return ProgressSummary(
      mediaId: p.mediaId,
      progress: fraction,
      isCompleted: p.isCompleted,
    );
  }

  /// Whether there is anything to draw: started reading, or finished.
  bool get isStarted => isCompleted || progress > 0;

  int get percent => (progress * 100).round();
}
