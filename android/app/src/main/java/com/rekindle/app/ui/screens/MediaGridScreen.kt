package com.rekindle.app.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.GridItemSpan
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.foundation.lazy.grid.rememberLazyGridState
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import coil.compose.AsyncImage
import coil.request.ImageRequest
import com.rekindle.app.domain.model.Media
import com.rekindle.app.ui.components.MediaCard
import com.rekindle.app.ui.theme.WindowWidthClass
import com.rekindle.app.ui.theme.currentWindowWidthClass
import com.rekindle.app.ui.viewmodel.MediaGridViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MediaGridScreen(
    libraryId: String,
    libraryName: String?,
    onItemClick: (Media) -> Unit,
    onBack: () -> Unit,
    vm: MediaGridViewModel = hiltViewModel(),
) {
    val state by vm.state.collectAsState()
    val downloadStates by vm.downloadStates.collectAsState()
    val folderDownloadStates by vm.folderDownloadStates.collectAsState()
    val searchQuery by vm.searchQuery.collectAsState()
    val searchResults by vm.searchResults.collectAsState()
    val searchLoading by vm.searchLoading.collectAsState()
    val gridCellSize = when (currentWindowWidthClass()) {
        WindowWidthClass.Expanded -> 180.dp
        WindowWidthClass.Medium -> 160.dp
        WindowWidthClass.Compact -> 140.dp
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(libraryName ?: "Library") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(
                        onClick = { /* search bar below is always visible */ },
                    ) {
                        Icon(Icons.Default.Search, contentDescription = "Search folders")
                    }
                    IconButton(onClick = vm::refresh) {
                        Icon(Icons.Default.Refresh, contentDescription = "Refresh")
                    }
                },
            )
        }
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            OutlinedTextField(
                value = searchQuery,
                onValueChange = vm::setSearchQuery,
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 8.dp, vertical = 4.dp),
                placeholder = { Text("Search folders…") },
                leadingIcon = { Icon(Icons.Default.Search, contentDescription = null) },
                trailingIcon = {
                    if (searchQuery.isNotEmpty()) {
                        IconButton(onClick = { vm.setSearchQuery("") }) {
                            Icon(Icons.Default.Clear, contentDescription = "Clear search")
                        }
                    }
                },
                singleLine = true,
            )

            Box(Modifier.weight(1f).fillMaxWidth()) {
                when {
                    state.loading -> CircularProgressIndicator(
                        modifier = Modifier.align(Alignment.Center),
                    )
                    state.error != null -> Text(
                        text = state.error!!,
                        modifier = Modifier.align(Alignment.Center),
                    )
                    searchQuery.isNotBlank() -> when {
                        searchLoading -> CircularProgressIndicator(
                            modifier = Modifier.align(Alignment.Center),
                        )
                        searchResults.isEmpty() -> Text(
                            text = "No folders found for \"$searchQuery\"",
                            modifier = Modifier.align(Alignment.Center),
                        )
                        else -> LazyColumn(Modifier.fillMaxSize()) {
                            items(searchResults, key = { it.id }) { folder ->
                                ListItem(
                                    leadingContent = {
                                        AsyncImage(
                                            model = ImageRequest.Builder(LocalContext.current)
                                                .data(vm.coverUrl(folder.id))
                                                .addHeader("Authorization", vm.authHeader)
                                                .diskCacheKey(folder.coverCachePath ?: folder.id)
                                                .crossfade(true)
                                                .build(),
                                            contentDescription = null,
                                            contentScale = ContentScale.Crop,
                                            modifier = Modifier.size(width = 44.dp, height = 62.dp),
                                        )
                                    },
                                    headlineContent = { Text(folder.displayTitle) },
                                    supportingContent = {
                                        Text(
                                            "${folder.relativePath}/",
                                            style = MaterialTheme.typography.bodySmall,
                                        )
                                    },
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .clickable { onItemClick(folder) },
                                )
                            }
                        }
                    }
                    else -> {
                        val gridState = rememberLazyGridState()

                        // Trigger loadMore when the user is within 4 items of the end.
                        // Keyed on both nearEnd AND items.size so the effect re-fires after
                        // each page loads — without this, nearEnd stays true on small screens
                        // and the effect never re-triggers once the first page is shown.
                        val nearEnd by remember {
                            derivedStateOf {
                                val info = gridState.layoutInfo
                                val lastVisible = info.visibleItemsInfo.lastOrNull()?.index ?: -1
                                lastVisible >= info.totalItemsCount - 4
                            }
                        }
                        LaunchedEffect(nearEnd, state.items.size) {
                            if (nearEnd && state.hasMore && !state.loadingMore && !state.loading) {
                                vm.loadMore()
                            }
                        }

                        LazyVerticalGrid(
                            state = gridState,
                            columns = GridCells.Adaptive(minSize = gridCellSize),
                            modifier = Modifier.fillMaxSize().padding(8.dp),
                        ) {
                            items(state.items, key = { it.id }) { media ->
                                val dlState = downloadStates[media.id] ?: vm.downloadStateFor(media.id)
                                val folderDlState = folderDownloadStates[media.id]
                                MediaCard(
                                    media = media,
                                    coverUrl = vm.coverUrl(media.id),
                                    authHeader = vm.authHeader,
                                    downloadState = dlState,
                                    folderDownloadState = folderDlState
                                        ?: com.rekindle.app.core.download.FolderDownloadState(),
                                    modifier = Modifier
                                        .fillMaxWidth()
                                        .aspectRatio(2f / 3f)
                                        .padding(4.dp)
                                        .clickable { onItemClick(media) },
                                )
                            }

                            // Full-width bottom spinner while fetching the next page
                            if (state.loadingMore) {
                                item(span = { GridItemSpan(maxLineSpan) }) {
                                    Box(
                                        modifier = Modifier
                                            .fillMaxWidth()
                                            .padding(16.dp),
                                        contentAlignment = Alignment.Center,
                                    ) {
                                        CircularProgressIndicator(modifier = Modifier.size(32.dp))
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
