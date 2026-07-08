package com.rekindle.app.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.rekindle.app.data.repository.DownloadRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import javax.inject.Inject

data class DownloadItem(
    val mediaId: String,
    val title: String,
    val format: String,
    val coverPath: String?,
) {
    val isImageBased: Boolean get() = format.lowercase() in listOf("cbz", "cbr", "pdf")
}

/**
 * Backs the offline Downloads screen. Reads the local `downloads` table directly
 * (no server call) so downloaded items are browsable and openable with no network.
 */
@HiltViewModel
class DownloadsViewModel @Inject constructor(
    private val downloadRepo: DownloadRepository,
) : ViewModel() {

    val downloads: StateFlow<List<DownloadItem>> = downloadRepo.completedDownloads()
        .map { list ->
            list.map {
                DownloadItem(
                    mediaId = it.mediaId,
                    title = it.title,
                    format = it.format,
                    coverPath = downloadRepo.localCoverPath(it.mediaId),
                )
            }
        }
        // localCoverPath does a blocking File.exists() stat — keep the mapping off the main thread.
        // (The EPUB reader restores its own state via awaitState, so no map-warming is needed here.)
        .flowOn(Dispatchers.IO)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    fun delete(mediaId: String) = downloadRepo.delete(mediaId)
}
