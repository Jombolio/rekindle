class ReadingProgress {
  final String userId;
  final String mediaId;
  final int currentPage;
  final bool isCompleted;

  /// How far through the current chapter, 0 to 1. Text books only.
  final double? positionFraction;

  const ReadingProgress({
    required this.userId,
    required this.mediaId,
    required this.currentPage,
    required this.isCompleted,
    this.positionFraction,
  });

  factory ReadingProgress.fromJson(Map<String, dynamic> j) => ReadingProgress(
        userId: (j['userId'] ?? '') as String,
        mediaId: (j['mediaId'] ?? '') as String,
        currentPage: (j['currentPage'] ?? 0) as int,
        isCompleted: (j['isCompleted'] ?? false) as bool,
        positionFraction: (j['positionFraction'] as num?)?.toDouble(),
      );
}
