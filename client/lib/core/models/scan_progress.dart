class ScanProgress {
  final String phase;
  final int filesTotal;
  final int filesProcessed;
  final int added;
  final int removed;
  final int folders;
  final int coversQueued;
  final int coversGenerated;

  const ScanProgress({
    this.phase = 'idle',
    this.filesTotal = 0,
    this.filesProcessed = 0,
    this.added = 0,
    this.removed = 0,
    this.folders = 0,
    this.coversQueued = 0,
    this.coversGenerated = 0,
  });

  factory ScanProgress.fromJson(Map<String, dynamic> json) => ScanProgress(
        phase: json['phase'] as String? ?? 'idle',
        filesTotal: json['filesTotal'] as int? ?? 0,
        filesProcessed: json['filesProcessed'] as int? ?? 0,
        added: json['added'] as int? ?? 0,
        removed: json['removed'] as int? ?? 0,
        folders: json['folders'] as int? ?? 0,
        coversQueued: json['coversQueued'] as int? ?? 0,
        coversGenerated: json['coversGenerated'] as int? ?? 0,
      );

  bool get isComplete => phase == 'complete';

  double get scanProgress =>
      filesTotal == 0 ? 0.0 : filesProcessed / filesTotal;

  double get coverProgress =>
      coversQueued == 0 ? 0.0 : coversGenerated / coversQueued;
}
