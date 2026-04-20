package com.rekindle.app.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.lazy.grid.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
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
        when {
            state.loading -> Box(
                Modifier.fillMaxSize().padding(padding),
                contentAlignment = Alignment.Center,
            ) { CircularProgressIndicator() }

            state.error != null -> Box(
                Modifier.fillMaxSize().padding(padding),
                contentAlignment = Alignment.Center,
            ) { Text(state.error!!) }

            else -> LazyVerticalGrid(
                columns = GridCells.Adaptive(minSize = 140.dp),
                modifier = Modifier.fillMaxSize().padding(padding).padding(8.dp),
            ) {
                items(state.items, key = { it.id }) { media ->
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
