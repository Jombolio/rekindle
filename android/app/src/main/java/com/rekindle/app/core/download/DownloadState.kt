package com.rekindle.app.core.download

enum class DownloadStatus { IDLE, DOWNLOADING, EXTRACTING, COMPLETE, FAILED }

data class DownloadState(
    val status: DownloadStatus = DownloadStatus.IDLE,
    val progress: Float = 0f,
    val localPath: String? = null,
    val extractedDir: String? = null,
    val error: String? = null,
) {
    val isDownloaded: Boolean get() = status == DownloadStatus.COMPLETE && localPath != null
    val isAvailableOffline: Boolean get() = isDownloaded
    val isExtracted: Boolean get() = extractedDir != null
}

// ---------------------------------------------------------------------------
// Folder-level download state
// ---------------------------------------------------------------------------

enum class FolderDownloadStatus { IDLE, FETCHING, DOWNLOADING, COMPLETE, FAILED }

data class FolderDownloadState(
    val status: FolderDownloadStatus = FolderDownloadStatus.IDLE,
    val total: Int = 0,
    val completed: Int = 0,
    val error: String? = null,
) {
    val progress: Float get() = if (total == 0) 0f else completed.toFloat() / total
}
