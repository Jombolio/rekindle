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
