package com.rekindle.app.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.Search
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
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
    val canDownload by vm.canDownload.collectAsState()
    val searchQuery by vm.searchQuery.collectAsState()
    val filteredItems by vm.filteredItems.collectAsState()
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
                placeholder = { Text("Search library…") },
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
                    filteredItems.isEmpty() && searchQuery.isNotBlank() -> Text(
                        text = "No results for \"$searchQuery\"",
                        modifier = Modifier.align(Alignment.Center),
                    )
                    else -> LazyVerticalGrid(
                        columns = GridCells.Adaptive(minSize = gridCellSize),
                        modifier = Modifier.fillMaxSize().padding(8.dp),
                    ) {
                        items(filteredItems, key = { it.id }) { media ->
                            val dlState = downloadStates[media.id] ?: vm.downloadStateFor(media.id)
                            MediaCard(
                                media = media,
                                coverUrl = vm.coverUrl(media.id),
                                authHeader = vm.authHeader,
                                downloadState = dlState,
                                canDownload = canDownload,
                                onDownload = { vm.download(media) },
                                onDeleteDownload = { vm.deleteDownload(media.id) },
                                onCancelDownload = { vm.cancelDownload(media.id) },
                                modifier = Modifier
                                    .fillMaxWidth()
                                    .aspectRatio(2f / 3f)
                                    .padding(4.dp)
                                    .clickable { onItemClick(media) },
                            )
                        }
                    }
                }
            }
        }
    }
}
