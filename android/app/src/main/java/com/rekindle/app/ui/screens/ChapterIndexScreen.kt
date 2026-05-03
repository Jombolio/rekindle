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
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.ExpandLess
import androidx.compose.material.icons.filled.ExpandMore
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
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.MenuAnchorType
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.OutlinedTextField
import com.rekindle.app.core.download.FolderDownloadStatus
import com.rekindle.app.domain.model.MangaMetadata
import com.rekindle.app.domain.model.Media
import com.rekindle.app.domain.model.ScrapeResult
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
    val isAdmin        by vm.isAdmin.collectAsState()
    val canManageMedia by vm.canManageMedia.collectAsState()
    val showAbout = vm.libraryType == "manga" || vm.libraryType == "comic"

    // ── Metadata dialogs ──────────────────────────────────────────────────────

    if (state.metadataNoChange) {
        AlertDialog(
            onDismissRequest = { vm.dismissNoChange() },
            title = { Text("No changes") },
            text  = { Text("The scraped metadata matches what is already stored. No update was needed.") },
            confirmButton = {
                TextButton(onClick = { vm.dismissNoChange() }) { Text("OK") }
            },
        )
    }

    state.metadataError?.let { error ->
        AlertDialog(
            onDismissRequest = { vm.dismissMetadataError() },
            title = { Text("Metadata scrape failed") },
            text  = { Text(error) },
            confirmButton = {
                TextButton(onClick = { vm.dismissMetadataError() }) { Text("OK") }
            },
        )
    }

    state.metadataConflict?.let { conflict ->
        MetadataConflictDialog(
            conflict  = conflict,
            onDismiss = { vm.dismissConflict() },
            onCommit  = { vm.commitMetadata(conflict.data) },
        )
    }

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
                if (showAbout) {
                    item(key = "about") {
                        AboutSection(
                            metadata = state.metadata,
                            isLoading = state.metadataLoading,
                            isScraping = state.metadataScraping,
                            isAdmin = isAdmin,
                            canEdit = canManageMedia,
                            onScrape = { vm.scrapeMetadata() },
                            onEdit = { vm.updateMetadata(it) },
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
private fun AboutSection(
    metadata: MangaMetadata?,
    isLoading: Boolean,
    isScraping: Boolean,
    isAdmin: Boolean,
    canEdit: Boolean,
    onScrape: () -> Unit,
    onEdit: (MangaMetadata) -> Unit,
    modifier: Modifier = Modifier,
) {
    var expanded by remember { mutableStateOf(false) }
    var showFullSynopsis by remember { mutableStateOf(false) }
    var showEditDialog by remember { mutableStateOf(false) }
    val hasMeta = metadata != null

    if (!hasMeta && !isAdmin && !isLoading) return

    if (showEditDialog && metadata != null) {
        MetadataEditDialog(
            initial = metadata,
            onDismiss = { showEditDialog = false },
            onSave = { edited -> onEdit(edited); showEditDialog = false },
        )
    }

    ElevatedCard(modifier = modifier.fillMaxWidth()) {
        Column(modifier = Modifier.animateContentSize()) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable(enabled = hasMeta) { expanded = !expanded }
                    .padding(horizontal = 16.dp, vertical = 12.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(Icons.Default.Info, null,
                    tint = MaterialTheme.colorScheme.primary, modifier = Modifier.size(18.dp))
                Spacer(Modifier.size(8.dp))
                Text(
                    text = when {
                        isLoading -> "Loading metadata…"
                        hasMeta   -> metadata!!.title ?: "About"
                        else      -> "No metadata scraped"
                    },
                    style = MaterialTheme.typography.titleSmall,
                    modifier = Modifier.weight(1f),
                )
                if (canEdit && hasMeta) {
                    IconButton(onClick = { showEditDialog = true }, modifier = Modifier.size(32.dp)) {
                        Icon(Icons.Default.Edit, "Edit metadata", modifier = Modifier.size(18.dp))
                    }
                    Spacer(Modifier.size(4.dp))
                }
                if (isAdmin) {
                    if (isScraping)
                        CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                    else
                        IconButton(onClick = onScrape, modifier = Modifier.size(32.dp)) {
                            Icon(Icons.Default.Refresh, "Scrape metadata", modifier = Modifier.size(18.dp))
                        }
                    Spacer(Modifier.size(4.dp))
                }
                if (hasMeta) {
                    Icon(
                        if (expanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
                        contentDescription = null,
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            if (hasMeta && expanded) {
                HorizontalDivider(modifier = Modifier.padding(horizontal = 16.dp))
                Column(modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp)) {
                    FlowRow(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        metadata!!.year?.let {
                            SuggestionChip(onClick = {},
                                label = { Text("$it", style = MaterialTheme.typography.labelSmall) },
                                icon  = { Icon(Icons.Default.CalendarToday, null, modifier = Modifier.size(14.dp)) })
                        }
                        metadata.score?.let {
                            SuggestionChip(onClick = {},
                                label = { Text("%.1f".format(it), style = MaterialTheme.typography.labelSmall) },
                                icon  = { Icon(Icons.Default.Star, null, modifier = Modifier.size(14.dp)) })
                        }
                        metadata.status?.let {
                            SuggestionChip(onClick = {},
                                label = { Text(metadata.formatStatus(), style = MaterialTheme.typography.labelSmall) })
                        }
                        metadata.source?.let { src ->
                            val label = when (src) { "mal" -> "MAL"; "anilist" -> "AniList"; "comicvine" -> "ComicVine"; else -> src }
                            SuggestionChip(onClick = {},
                                label = { Text(label, style = MaterialTheme.typography.labelSmall) },
                                icon  = { Icon(Icons.Default.Public, null, modifier = Modifier.size(14.dp)) })
                        }
                    }
                    if (metadata!!.genreList.isNotEmpty()) {
                        Spacer(Modifier.height(4.dp))
                        FlowRow(horizontalArrangement = Arrangement.spacedBy(6.dp)) {
                            metadata.genreList.forEach { genre ->
                                AssistChip(onClick = {},
                                    label = { Text(genre, style = MaterialTheme.typography.labelSmall) })
                            }
                        }
                    }
                    val synopsis = metadata.synopsis?.replace(Regex("<[^>]*>"), "")?.trim()
                    if (!synopsis.isNullOrEmpty()) {
                        Spacer(Modifier.height(8.dp))
                        Text(text = synopsis,
                            style    = MaterialTheme.typography.bodySmall,
                            color    = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = if (showFullSynopsis) Int.MAX_VALUE else 4,
                            overflow = if (showFullSynopsis) TextOverflow.Visible else TextOverflow.Ellipsis)
                        Spacer(Modifier.height(4.dp))
                        Text(
                            text     = if (showFullSynopsis) "Show less" else "Show more",
                            style    = MaterialTheme.typography.labelSmall,
                            color    = MaterialTheme.colorScheme.primary,
                            modifier = Modifier.clickable { showFullSynopsis = !showFullSynopsis },
                        )
                    }
                }
            }
        }
    }
}

// ── Metadata edit dialog ──────────────────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun MetadataEditDialog(
    initial: MangaMetadata,
    onDismiss: () -> Unit,
    onSave: (MangaMetadata) -> Unit,
) {
    var title    by remember { mutableStateOf(initial.title    ?: "") }
    var synopsis by remember { mutableStateOf(initial.synopsis ?: "") }
    var genres   by remember { mutableStateOf(initial.genres   ?: "") }
    var score    by remember { mutableStateOf(initial.score?.let { "%.1f".format(it) } ?: "") }
    var year     by remember { mutableStateOf(initial.year?.toString() ?: "") }
    var status   by remember { mutableStateOf(initial.status) }
    var statusExpanded by remember { mutableStateOf(false) }

    val statuses = listOf(null, "FINISHED", "RELEASING", "NOT_YET_RELEASED", "CANCELLED", "HIATUS")
    fun statusLabel(s: String?) = when (s) {
        "FINISHED"         -> "Finished"
        "RELEASING"        -> "Releasing"
        "NOT_YET_RELEASED" -> "Not yet released"
        "CANCELLED"        -> "Cancelled"
        "HIATUS"           -> "Hiatus"
        else               -> "Unknown"
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Edit metadata") },
        text = {
            Column(
                modifier = Modifier.verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                OutlinedTextField(value = title, onValueChange = { title = it },
                    label = { Text("Title") }, modifier = Modifier.fillMaxWidth(), singleLine = true)

                OutlinedTextField(value = synopsis, onValueChange = { synopsis = it },
                    label = { Text("Synopsis") }, modifier = Modifier.fillMaxWidth(), minLines = 3, maxLines = 6)

                OutlinedTextField(value = genres, onValueChange = { genres = it },
                    label = { Text("Genres (comma-separated)") }, modifier = Modifier.fillMaxWidth(), singleLine = true)

                Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    OutlinedTextField(value = score, onValueChange = { score = it },
                        label = { Text("Score (0–10)") },
                        keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
                            keyboardType = androidx.compose.ui.text.input.KeyboardType.Decimal),
                        modifier = Modifier.weight(1f), singleLine = true)
                    OutlinedTextField(value = year, onValueChange = { year = it },
                        label = { Text("Year") },
                        keyboardOptions = androidx.compose.foundation.text.KeyboardOptions(
                            keyboardType = androidx.compose.ui.text.input.KeyboardType.Number),
                        modifier = Modifier.weight(1f), singleLine = true)
                }

                ExposedDropdownMenuBox(
                    expanded = statusExpanded,
                    onExpandedChange = { statusExpanded = it },
                ) {
                    OutlinedTextField(
                        value = statusLabel(status),
                        onValueChange = {},
                        readOnly = true,
                        label = { Text("Status") },
                        trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(statusExpanded) },
                        modifier = Modifier.fillMaxWidth().menuAnchor(MenuAnchorType.PrimaryNotEditable),
                    )
                    ExposedDropdownMenu(expanded = statusExpanded, onDismissRequest = { statusExpanded = false }) {
                        statuses.forEach { s ->
                            DropdownMenuItem(
                                text = { Text(statusLabel(s)) },
                                onClick = { status = s; statusExpanded = false },
                            )
                        }
                    }
                }
            }
        },
        confirmButton = {
            FilledTonalButton(onClick = {
                onSave(initial.copy(
                    title    = title.trim().ifBlank { null },
                    synopsis = synopsis.trim().ifBlank { null },
                    genres   = genres.trim().ifBlank { null },
                    score    = score.trim().toDoubleOrNull(),
                    year     = year.trim().toIntOrNull(),
                    status   = status,
                ))
            }) { Text("Save") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

// ── Metadata conflict dialog ──────────────────────────────────────────────────

@Composable
private fun MetadataConflictDialog(
    conflict: ScrapeResult,
    onDismiss: () -> Unit,
    onCommit: () -> Unit,
) {
    val existing = conflict.existing ?: return
    val proposed = conflict.data

    data class Diff(val field: String, val old: String?, val new_: String?)

    val diffs = buildList {
        fun add(field: String, a: String?, b: String?) { if (a != b) add(Diff(field, a, b)) }
        add("Title",  existing.title,  proposed.title)
        add("Year",   existing.year?.toString(),  proposed.year?.toString())
        add("Status", existing.status, proposed.status)
        add("Score",  existing.score?.let { "%.1f".format(it) }, proposed.score?.let { "%.1f".format(it) })
        add("Genres", existing.genres, proposed.genres)
        add("Source", existing.source, proposed.source)
        // Truncate synopsis
        fun truncate(s: String?) = s?.replace(Regex("<[^>]*>"), "")?.trim()
            ?.let { if (it.length > 120) "${it.take(120)}…" else it }
        add("Synopsis", truncate(existing.synopsis), truncate(proposed.synopsis))
    }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Metadata conflict") },
        text = {
            Column(modifier = Modifier.verticalScroll(rememberScrollState())) {
                Text(
                    "The scraped data differs from what is stored. " +
                        "Review the changes below before deciding which to keep.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                Spacer(Modifier.height(12.dp))
                Row(modifier = Modifier.fillMaxWidth()) {
                    Spacer(Modifier.weight(0.28f))
                    Text("Stored",  style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.weight(0.36f))
                    Text("New", style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.primary, modifier = Modifier.weight(0.36f))
                }
                HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))
                diffs.forEach { diff ->
                    Row(
                        modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp),
                        verticalAlignment = Alignment.Top,
                    ) {
                        Text(diff.field,
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.weight(0.28f))
                        Text(diff.old ?: "—",
                            style = MaterialTheme.typography.bodySmall.copy(
                                textDecoration = androidx.compose.ui.text.style.TextDecoration.LineThrough),
                            color = MaterialTheme.colorScheme.onSurface.copy(alpha = 0.45f),
                            modifier = Modifier.weight(0.36f))
                        Text(diff.new_ ?: "—",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.primary,
                            fontWeight = androidx.compose.ui.text.font.FontWeight.Medium,
                            modifier = Modifier.weight(0.36f))
                    }
                }
            }
        },
        confirmButton = {
            FilledTonalButton(onClick = { onCommit(); }) { Text("Use new data") }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Keep existing") }
        },
    )
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
