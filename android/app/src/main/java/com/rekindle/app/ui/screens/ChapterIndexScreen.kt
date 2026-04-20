package com.rekindle.app.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import coil.compose.AsyncImage
import coil.request.ImageRequest
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
    val canDownload by vm.canDownload.collectAsState()

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text(title ?: "Series") },
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

            else -> LazyColumn(Modifier.fillMaxSize().padding(padding)) {
                items(state.chapters, key = { it.id }) { chapter ->
                    val dlState = downloadStates[chapter.id] ?: vm.downloadStateFor(chapter.id)
                    ListItem(
                        leadingContent = {
                            AsyncImage(
                                model = ImageRequest.Builder(LocalContext.current)
                                    .data(vm.coverUrl(chapter.id))
                                    .addHeader("Authorization", vm.authHeader)
                                    .crossfade(true)
                                    .build(),
                                contentDescription = null,
                                contentScale = ContentScale.Crop,
                                modifier = Modifier
                                    .size(width = 48.dp, height = 68.dp)
                                    .clip(RoundedCornerShape(4.dp)),
                            )
                        },
                        headlineContent = { Text(chapter.displayTitle) },
                        supportingContent = chapter.pageCount?.let {
                            { Text("$it pages") }
                        },
                        trailingContent = if (canDownload) ({
                            DownloadButton(
                                media = chapter,
                                downloadState = dlState,
                                onDownload = { vm.download(chapter) },
                                onDelete = { vm.deleteDownload(chapter.id) },
                                onCancel = {},
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
