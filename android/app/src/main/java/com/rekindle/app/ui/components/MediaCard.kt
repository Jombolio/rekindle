package com.rekindle.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.basicMarquee
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.LibraryBooks
import androidx.compose.material.icons.filled.OfflineBolt
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalMinimumInteractiveComponentSize
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import coil.request.ImageRequest
import com.rekindle.app.core.download.DownloadState
import com.rekindle.app.core.download.DownloadStatus
import com.rekindle.app.domain.model.Media

@Composable
fun MediaCard(
    media: Media,
    coverUrl: String,
    authHeader: String,
    downloadState: DownloadState,
    canDownload: Boolean,
    onDownload: () -> Unit,
    onDeleteDownload: () -> Unit,
    onCancelDownload: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val isOffline = downloadState.status == DownloadStatus.COMPLETE

    Column(modifier = modifier) {
        // Cover image — fills the box via ContentScale.Crop so covers are always visible.
        Box(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth(),
        ) {
            AsyncImage(
                model = ImageRequest.Builder(LocalContext.current)
                    .data(coverUrl)
                    .addHeader("Authorization", authHeader)
                    // Use coverCachePath as disk-cache key so Coil fetches a
                    // fresh image when the server regenerates the cover.
                    .diskCacheKey(media.coverCachePath ?: media.id)
                    .crossfade(true)
                    .build(),
                contentDescription = media.displayTitle,
                contentScale = ContentScale.Crop,
                modifier = Modifier.matchParentSize(),
            )

            // Offline badge — top-right
            if (isOffline) {
                Box(
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .padding(4.dp)
                        .background(
                            color = Color(0xFF4CAF50).copy(alpha = 0.85f),
                            shape = RoundedCornerShape(4.dp),
                        )
                        .padding(3.dp),
                ) {
                    Icon(
                        imageVector = Icons.Default.OfflineBolt,
                        contentDescription = "Available offline",
                        tint = Color.White,
                        modifier = Modifier.size(14.dp),
                    )
                }
            }

            // Folder badge — bottom-left
            if (media.isFolder) {
                Row(
                    modifier = Modifier
                        .align(Alignment.BottomStart)
                        .padding(4.dp)
                        .background(
                            color = Color.Black.copy(alpha = 0.65f),
                            shape = RoundedCornerShape(4.dp),
                        )
                        .padding(horizontal = 4.dp, vertical = 2.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        Icons.Default.LibraryBooks,
                        contentDescription = null,
                        tint = Color.White,
                        modifier = Modifier.size(12.dp),
                    )
                }
            }

            // Download button — bottom-right overlay.
            // LocalMinimumInteractiveComponentSize suppresses the 48dp Material3
            // minimum touch target so the button's clickable area is exactly its
            // 32dp visual size and does not bleed into the image tap area.
            if (canDownload) {
                CompositionLocalProvider(LocalMinimumInteractiveComponentSize provides Dp.Unspecified) {
                    Box(
                        modifier = Modifier
                            .align(Alignment.BottomEnd)
                            .padding(4.dp)
                            .background(
                                color = Color.Black.copy(alpha = 0.55f),
                                shape = RoundedCornerShape(6.dp),
                            )
                            .size(32.dp),
                        contentAlignment = Alignment.Center,
                    ) {
                        DownloadButton(
                            media = media,
                            downloadState = downloadState,
                            onDownload = onDownload,
                            onDelete = onDeleteDownload,
                            onCancel = onCancelDownload,
                            modifier = Modifier.size(32.dp),
                        )
                    }
                }
            }
        }

        // Title — single line, auto-scrolling marquee, centred.
        Text(
            text = media.displayTitle,
            style = MaterialTheme.typography.labelSmall,
            maxLines = 1,
            textAlign = TextAlign.Center,
            modifier = Modifier
                .fillMaxWidth()
                .padding(top = 4.dp, start = 2.dp, end = 2.dp)
                .basicMarquee(),
        )
    }
}
