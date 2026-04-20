enum DownloadStatus { idle, downloading, extracting, complete, failed }

class DownloadState {
  final DownloadStatus status;
  final double progress;
  final String? localPath;
  final String? extractedDir;
  final String? error;

  const DownloadState({
    this.status = DownloadStatus.idle,
    this.progress = 0,
    this.localPath = null,
    this.extractedDir = null,
    this.error = null,
  });

  const DownloadState.idle() : this();

  bool get isDownloaded => status == DownloadStatus.complete && localPath != null;
  bool get isExtracted => extractedDir != null;
  bool get isAvailableOffline => isDownloaded;

  DownloadState copyWith({
    DownloadStatus? status,
    double? progress,
    String? localPath,
    String? extractedDir,
    String? error,
  }) =>
      DownloadState(
        status: status ?? this.status,
        progress: progress ?? this.progress,
        localPath: localPath ?? this.localPath,
        extractedDir: extractedDir ?? this.extractedDir,
        error: error ?? this.error,
      );
}
