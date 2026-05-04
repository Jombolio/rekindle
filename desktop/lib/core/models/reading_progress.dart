class ReadingProgress {
  final String userId;
  final String mediaId;
  final int currentPage;
  final bool isCompleted;

  const ReadingProgress({
    required this.userId,
    required this.mediaId,
    required this.currentPage,
    required this.isCompleted,
  });

  factory ReadingProgress.fromJson(Map<String, dynamic> j) => ReadingProgress(
        userId: (j['userId'] ?? '') as String,
        mediaId: (j['mediaId'] ?? '') as String,
        currentPage: (j['currentPage'] ?? 0) as int,
        isCompleted: (j['isCompleted'] ?? false) as bool,
      );
}
