package com.rekindle.app.ui.screens

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.expandVertically
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.basicMarquee
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.CalendarToday
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.DownloadDone
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Public
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Star
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.AssistChip
import androidx.compose.material3.Card
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilterChip
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SuggestionChip
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
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import coil.compose.AsyncImage
import coil.request.ImageRequest
import com.rekindle.app.core.download.FolderDownloadStatus
import com.rekindle.app.domain.model.MangaMetadata
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
    val isAdmin by vm.isAdmin.collectAsState()
    val isManga = vm.libraryType == "manga"

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
                if (isManga) {
                    item(key = "about") {
                        MangaAboutSection(
                            metadata = state.metadata,
                            isLoading = state.metadataLoading,
                            isScraping = state.metadataScraping,
                            isAdmin = isAdmin,
                            onScrape = { vm.scrapeMetadata() },
                            modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                        )
                    }
                }

                items(state.chapters, key = { it.id }) { chapter ->
                    val dlState = downloadStates[chapter.id] ?: vm.downloadStateFor(chapter.id)
                    val progress = state.readProgress[chapter.id]
                    val isCompleted = progress?.isCompleted == true
                    val inProgress = progress != null && !progress.isCompleted && progress.currentPage > 0
                    val readLabel = when {
                        isCompleted -> "Read"
                        inProgress -> chapter.pageCount
                            ?.let { "In progress · ${progress!!.currentPage + 1} / $it" }
                            ?: "In progress"
                        else -> chapter.pageCount?.let { "$it pages" }
                    }
                    val labelColor = when {
                        isCompleted -> MaterialTheme.colorScheme.primary
                        inProgress -> MaterialTheme.colorScheme.tertiary
                        else -> MaterialTheme.colorScheme.onSurfaceVariant
                    }
                    ListItem(
                        leadingContent = {
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
                            Text(
                                text = chapter.displayTitle,
                                maxLines = 1,
                                modifier = Modifier.basicMarquee(),
                            )
                        },
                        supportingContent = readLabel?.let {
                            { Text(it, color = labelColor, style = MaterialTheme.typography.bodySmall) }
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

// ── Manga About section ───────────────────────────────────────────────────────

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun MangaAboutSection(
    metadata: MangaMetadata?,
    isLoading: Boolean,
    isScraping: Boolean,
    isAdmin: Boolean,
    onScrape: () -> Unit,
    modifier: Modifier = Modifier,
) {
    var expanded by remember { mutableStateOf(false) }
    var showFullSynopsis by remember { mutableStateOf(false) }
    val hasMeta = metadata != null

    if (!hasMeta && !isAdmin && !isLoading) return

    ElevatedCard(modifier = modifier.fillMaxWidth()) {
        Column(modifier = Modifier.animateContentSize()) {
            // Header row
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(enabled = hasMeta) { expanded = !expanded }
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    Icons.Default.Info,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(18.dp),
                )
                Spacer(Modifier.size(8.dp))
                Text(
                    text = when {
                        isLoading -> "Loading metadata…"
                        hasMeta -> metadata!!.title ?: "About"
                        else -> "No metadata scraped"
                    },
                    style = MaterialTheme.typography.titleSmall,
                    modifier = Modifier.weight(1f),
                )
                if (isAdmin) {
                    if (isScraping) {
                        CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                    } else {
                        IconButton(onClick = onScrape, modifier = Modifier.size(32.dp)) {
                            Icon(Icons.Default.Refresh, contentDescription = "Scrape metadata", modifier = Modifier.size(18.dp))
                        }
                    }
                }
            }

            // Expanded body
            if (hasMeta && expanded) {
                HorizontalDivider(modifier = Modifier.padding(horizontal = 16.dp))
                Column(modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp)) {

                    // Info chips
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        metadata!!.year?.let {
                            SuggestionChip(
                                onClick = {},
                                label = { Text("$it", style = MaterialTheme.typography.labelSmall) },
                                icon = { Icon(Icons.Default.CalendarToday, null, modifier = Modifier.size(14.dp)) },
                            )
                        }
                        metadata.score?.let {
                            SuggestionChip(
                                onClick = {},
                                label = { Text("%.1f".format(it), style = MaterialTheme.typography.labelSmall) },
                                icon = { Icon(Icons.Default.Star, null, modifier = Modifier.size(14.dp)) },
                            )
                        }
                        metadata.status?.let {
                            SuggestionChip(
                                onClick = {},
                                label = { Text(metadata.formatStatus(), style = MaterialTheme.typography.labelSmall) },
                            )
                        }
                        metadata.source?.let {
                            SuggestionChip(
                                onClick = {},
                                label = { Text(if (it == "mal") "MAL" else "AniList", style = MaterialTheme.typography.labelSmall) },
                                icon = { Icon(Icons.Default.Public, null, modifier = Modifier.size(14.dp)) },
                            )
                        }
                    }

                    // Genres
                    if (metadata!!.genreList.isNotEmpty()) {
                        Spacer(Modifier.height(4.dp))
                        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            metadata.genreList.forEach { genre ->
                                AssistChip(
                                    onClick = {},
                                    label = { Text(genre, style = MaterialTheme.typography.labelSmall) },
                                )
                            }
                        }
                    }

                    // Synopsis
                    val synopsis = metadata.synopsis?.replace(Regex("<[^>]*>"), "")?.trim()
                    if (!synopsis.isNullOrEmpty()) {
                        Spacer(Modifier.height(8.dp))
                        Text(
                            text = synopsis,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = if (showFullSynopsis) Int.MAX_VALUE else 4,
                            overflow = if (showFullSynopsis) TextOverflow.Visible else TextOverflow.Ellipsis,
                        )
                        Spacer(Modifier.height(4.dp))
                        Text(
                            text = if (showFullSynopsis) "Show less" else "Show more",
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.clickable { showFullSynopsis = !showFullSynopsis },
                        )
                    }
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
