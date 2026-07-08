package com.rekindle.app.ui.screens

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.MenuBook
import androidx.compose.material.icons.filled.Book
import androidx.compose.material.icons.filled.DownloadForOffline
import androidx.compose.material.icons.filled.Folder
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import coil.compose.AsyncImage
import coil.request.ImageRequest
import com.rekindle.app.ui.viewmodel.DownloadFolder
import com.rekindle.app.ui.viewmodel.DownloadItem
import com.rekindle.app.ui.viewmodel.DownloadsViewModel
import java.io.File

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun DownloadsScreen(
    onOpen: (mediaId: String, format: String) -> Unit,
    onBack: () -> Unit,
    vm: DownloadsViewModel = hiltViewModel(),
) {
    val folders by vm.folders.collectAsState()
    val authHeader by vm.authHeader.collectAsState()
    var selectedSeries by rememberSaveable { mutableStateOf<String?>(null) }
    var deleteTarget by remember { mutableStateOf<DownloadItem?>(null) }

    val currentFolder = folders.firstOrNull { it.series == selectedSeries }

    // Drop a stale selection if that series no longer has any downloads.
    LaunchedEffect(folders) {
        if (selectedSeries != null && folders.none { it.series == selectedSeries }) selectedSeries = null
    }
    // Inside a folder, system back returns to the folder list first.
    BackHandler(enabled = currentFolder != null) { selectedSeries = null }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(currentFolder?.series ?: "Downloads") },
                navigationIcon = {
                    IconButton(onClick = { if (currentFolder != null) selectedSeries = null else onBack() }) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        },
    ) { padding ->
        when {
            folders.isEmpty() -> EmptyState(padding)

            currentFolder == null -> LazyVerticalGrid(
                columns = GridCells.Adaptive(minSize = 150.dp),
                modifier = Modifier.fillMaxSize().padding(padding),
                contentPadding = PaddingValues(12.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                items(folders, key = { it.series }) { folder ->
                    FolderGridItem(
                        folder = folder,
                        authHeader = authHeader,
                        onClick = { selectedSeries = folder.series },
                    )
                }
            }

            else -> LazyVerticalGrid(
                columns = GridCells.Adaptive(minSize = 110.dp),
                modifier = Modifier.fillMaxSize().padding(padding),
                contentPadding = PaddingValues(12.dp),
                horizontalArrangement = Arrangement.spacedBy(12.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                items(currentFolder.items, key = { it.mediaId }) { item ->
                    DownloadGridItem(
                        item = item,
                        authHeader = authHeader,
                        onClick = { onOpen(item.mediaId, item.format) },
                        onLongClick = { deleteTarget = item },
                    )
                }
            }
        }
    }

    deleteTarget?.let { target ->
        AlertDialog(
            onDismissRequest = { deleteTarget = null },
            title = { Text("Remove download?") },
            text = { Text("Delete \"${target.title}\" from this device? It stays on the server.") },
            confirmButton = {
                TextButton(onClick = { vm.delete(target.mediaId); deleteTarget = null }) { Text("Delete") }
            },
            dismissButton = { TextButton(onClick = { deleteTarget = null }) { Text("Cancel") } },
        )
    }
}

@Composable
private fun EmptyState(padding: PaddingValues) {
    Box(
        Modifier.fillMaxSize().padding(padding),
        contentAlignment = Alignment.Center,
    ) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Icon(
                Icons.Default.DownloadForOffline,
                contentDescription = null,
                modifier = Modifier.size(64.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(8.dp))
            Text("No downloads yet", style = MaterialTheme.typography.titleMedium)
            Text(
                "Downloaded items appear here and open offline.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

/**
 * Renders a cover: a placeholder icon with the real cover layered on top. The cover
 * prefers a local downloaded file and otherwise loads from the server endpoint (with
 * auth). While loading or on failure, the placeholder shows through.
 */
@Composable
private fun BoxScope.Cover(
    coverPath: String?,
    coverUrl: String?,
    authHeader: String,
    placeholder: ImageVector,
    placeholderSize: Int,
    contentDescription: String,
) {
    Icon(
        placeholder,
        contentDescription = null,
        tint = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.size(placeholderSize.dp).align(Alignment.Center),
    )
    val data: Any? = coverPath?.let { File(it) } ?: coverUrl
    if (data != null) {
        AsyncImage(
            model = ImageRequest.Builder(LocalContext.current)
                .data(data)
                .addHeader("Authorization", authHeader) // ignored when data is a local File
                .crossfade(true)
                .build(),
            contentDescription = contentDescription,
            contentScale = ContentScale.Crop,
            modifier = Modifier.matchParentSize(),
        )
    }
}

@Composable
private fun FolderGridItem(
    folder: DownloadFolder,
    authHeader: String,
    onClick: () -> Unit,
) {
    Column(modifier = Modifier.clickable(onClick = onClick)) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(0.7f)
                .clip(RoundedCornerShape(8.dp))
                .background(MaterialTheme.colorScheme.surfaceVariant),
        ) {
            Cover(
                coverPath = folder.coverPath,
                coverUrl = folder.coverUrl,
                authHeader = authHeader,
                placeholder = Icons.Default.Folder,
                placeholderSize = 40,
                contentDescription = folder.series,
            )
            Text(
                text = folder.count.toString(),
                style = MaterialTheme.typography.labelSmall,
                color = Color.White,
                modifier = Modifier
                    .align(Alignment.BottomEnd)
                    .padding(4.dp)
                    .background(Color.Black.copy(alpha = 0.6f), RoundedCornerShape(4.dp))
                    .padding(horizontal = 5.dp, vertical = 1.dp),
            )
        }
        Text(
            text = folder.series,
            style = MaterialTheme.typography.labelMedium,
            fontWeight = FontWeight.Medium,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
        )
        Text(
            text = if (folder.count == 1) "1 chapter" else "${folder.count} chapters",
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun DownloadGridItem(
    item: DownloadItem,
    authHeader: String,
    onClick: () -> Unit,
    onLongClick: () -> Unit,
) {
    Column(
        modifier = Modifier.combinedClickable(onClick = onClick, onLongClick = onLongClick),
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth()
                .aspectRatio(0.7f)
                .clip(RoundedCornerShape(8.dp))
                .background(MaterialTheme.colorScheme.surfaceVariant),
        ) {
            Cover(
                coverPath = item.coverPath,
                coverUrl = item.coverUrl,
                authHeader = authHeader,
                placeholder = if (item.isImageBased) Icons.Default.Book else Icons.AutoMirrored.Filled.MenuBook,
                placeholderSize = 36,
                contentDescription = item.title,
            )
            Text(
                text = item.format.uppercase(),
                style = MaterialTheme.typography.labelSmall,
                color = Color.White,
                modifier = Modifier
                    .align(Alignment.BottomStart)
                    .padding(4.dp)
                    .background(Color.Black.copy(alpha = 0.6f), RoundedCornerShape(4.dp))
                    .padding(horizontal = 4.dp, vertical = 1.dp),
            )
        }
        Text(
            text = item.title,
            style = MaterialTheme.typography.labelSmall,
            maxLines = 2,
            overflow = TextOverflow.Ellipsis,
            modifier = Modifier.fillMaxWidth().padding(top = 4.dp),
        )
    }
}
