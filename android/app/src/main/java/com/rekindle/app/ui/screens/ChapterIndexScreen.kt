package com.rekindle.app.ui.screens

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.basicMarquee
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.DownloadDone
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import coil.compose.AsyncImage
import coil.request.ImageRequest
import com.rekindle.app.core.download.FolderDownloadStatus
import com.rekindle.app.domain.model.Media
import com.rekindle.app.ui.components.DownloadButton
import com.rekindle.app.ui.viewmodel.ChapterIndexViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChapterIndexScreen(
    folderId: String,
    title: String?,
    onChapterClick: (Media) -> Unit,
    onBack: () -> Unit,
    vm: ChapterIndexViewModel = hiltViewModel(),
) {
    val state by vm.state.collectAsState()
    val downloadStates by vm.downloadStates.collectAsState()
    val folderDlState by vm.folderDownloadState.collectAsState()
    val canDownload by vm.canDownload.collectAsState()

    var showConfirmDialog by remember { mutableStateOf(false) }

    if (showConfirmDialog) {
        AlertDialog(
            onDismissRequest = { showConfirmDialog = false },
            title = { Text("Download all chapters?") },
            text = {
                Text(
                    "All chapters in this series will be downloaded for offline reading. " +
                        "This may use significant storage.",
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    showConfirmDialog = false
                    vm.downloadFolder()
                }) { Text("Download") }
            },
            dismissButton = {
                TextButton(onClick = { showConfirmDialog = false }) { Text("Cancel") }
            },
        )
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(title ?: "Series") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    if (canDownload) {
                        when (folderDlState.status) {
                            FolderDownloadStatus.IDLE ->
                                IconButton(onClick = { showConfirmDialog = true }) {
                                    Icon(Icons.Default.Download, contentDescription = "Download all")
                                }
                            FolderDownloadStatus.FETCHING, FolderDownloadStatus.DOWNLOADING ->
                                IconButton(onClick = { vm.cancelFolderDownload() }) {
                                    CircularProgressIndicator(
                                        modifier = Modifier.size(20.dp),
                                        strokeWidth = 2.dp,
                                    )
                                }
                            FolderDownloadStatus.COMPLETE ->
                                Icon(
                                    Icons.Default.DownloadDone,
                                    contentDescription = "All downloaded",
                                    tint = MaterialTheme.colorScheme.primary,
                                    modifier = Modifier.padding(horizontal = 12.dp),
                                )
                            FolderDownloadStatus.FAILED ->
                                IconButton(onClick = { showConfirmDialog = true }) {
                                    Icon(
                                        Icons.Default.ErrorOutline,
                                        contentDescription = "Download failed — retry",
                                        tint = MaterialTheme.colorScheme.error,
                                    )
                                }
                        }
                    }
                },
            )
        },
        bottomBar = {
            // Progress bar — slides in when a folder download is active.
            if (canDownload) {
                FolderDownloadBar(
                    status = folderDlState.status,
                    progress = folderDlState.progress,
                    completed = folderDlState.completed,
                    total = folderDlState.total,
                    error = folderDlState.error,
                    onCancel = { vm.cancelFolderDownload() },
                )
            }
        },
    ) { padding ->
        when {
            state.loading -> Box(
                Modifier.fillMaxSize().padding(padding),
                contentAlignment = Alignment.Center,
            ) { CircularProgressIndicator() }

            state.error != null -> Box(
                Modifier.fillMaxSize().padding(padding),
                contentAlignment = Alignment.Center,
            ) { Text(state.error!!) }

            else -> LazyColumn(Modifier.fillMaxSize().padding(padding)) {
                items(state.chapters, key = { it.id }) { chapter ->
                    val dlState = downloadStates[chapter.id] ?: vm.downloadStateFor(chapter.id)
                    ListItem(
                        leadingContent = {
                            // Cover — no rounding, full image visible (ContentScale.Fit).
                            AsyncImage(
                                model = ImageRequest.Builder(LocalContext.current)
                                    .data(vm.coverUrl(chapter.id))
                                    .addHeader("Authorization", vm.authHeader)
                                    .diskCacheKey(chapter.coverCachePath ?: chapter.id)
                                    .crossfade(true)
                                    .build(),
                                contentDescription = null,
                                contentScale = ContentScale.Fit,
                                modifier = Modifier.size(width = 48.dp, height = 68.dp),
                            )
                        },
                        headlineContent = {
                            // Single-line title with auto-scrolling marquee on overflow.
                            Text(
                                text = chapter.displayTitle,
                                maxLines = 1,
                                modifier = Modifier.basicMarquee(),
                            )
                        },
                        supportingContent = chapter.pageCount?.let {
                            { Text("$it pages") }
                        },
                        trailingContent = if (canDownload) ({
                            DownloadButton(
                                media = chapter,
                                downloadState = dlState,
                                onDownload = { vm.download(chapter) },
                                onDelete = { vm.deleteDownload(chapter.id) },
                                onCancel = { vm.cancelDownload(chapter.id) },
                                modifier = Modifier.size(40.dp),
                            )
                        }) else null,
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 4.dp)
                            .clickable { onChapterClick(chapter) },
                    )
                }
            }
        }
    }
}

// ── Download progress bar ─────────────────────────────────────────────────────

@Composable
private fun FolderDownloadBar(
    status: FolderDownloadStatus,
    progress: Float,
    completed: Int,
    total: Int,
    error: String?,
    onCancel: () -> Unit,
) {
    val visible = status == FolderDownloadStatus.FETCHING ||
        status == FolderDownloadStatus.DOWNLOADING ||
        status == FolderDownloadStatus.FAILED

    AnimatedVisibility(
        visible = visible,
        enter = expandVertically(expandFrom = Alignment.Bottom),
        exit = shrinkVertically(shrinkTowards = Alignment.Bottom),
    ) {
        val isError = status == FolderDownloadStatus.FAILED
        val label = when (status) {
            FolderDownloadStatus.FETCHING -> "Preparing download…"
            FolderDownloadStatus.DOWNLOADING -> "Downloading $completed / $total"
            FolderDownloadStatus.FAILED -> error ?: "Download failed"
            else -> ""
        }

        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(bottom = 0.dp),
        ) {
            LinearProgressIndicator(
                progress = { if (status == FolderDownloadStatus.FETCHING) 0f else progress },
                modifier = Modifier.fillMaxWidth(),
                color = if (isError) MaterialTheme.colorScheme.error
                else MaterialTheme.colorScheme.primary,
            )
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 6.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = label,
                    style = MaterialTheme.typography.bodySmall,
                    color = if (isError) MaterialTheme.colorScheme.error
                    else MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.weight(1f),
                )
                if (!isError) {
                    TextButton(onClick = onCancel) {
                        Text("Cancel", color = MaterialTheme.colorScheme.error)
                    }
                }
            }
        }
    }
}
