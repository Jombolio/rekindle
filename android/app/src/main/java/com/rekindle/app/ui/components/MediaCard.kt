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
import androidx.compose.material.icons.automirrored.filled.LibraryBooks
import androidx.compose.material.icons.filled.OfflineBolt
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import coil.compose.AsyncImage
import coil.request.ImageRequest
import com.rekindle.app.core.download.DownloadState
import com.rekindle.app.core.download.DownloadStatus
import com.rekindle.app.core.download.FolderDownloadState
import com.rekindle.app.core.download.FolderDownloadStatus
import com.rekindle.app.domain.model.Media

private enum class DownloadBadge { ALL, MIXED }

@Composable
fun MediaCard(
    media: Media,
    coverUrl: String,
    authHeader: String,
    downloadState: DownloadState,
    folderDownloadState: FolderDownloadState = FolderDownloadState(),
    modifier: Modifier = Modifier,
) {
    // Determine which badge (if any) to show:
    //  ALL  = green  → everything is available offline
    //  MIXED = amber → partially downloaded (folder in-progress or some chapters done)
    //  null  = nothing shown (on server, not downloaded)
    val badge: DownloadBadge? = when {
        media.isFolder -> when (folderDownloadState.status) {
            FolderDownloadStatus.COMPLETE    -> DownloadBadge.ALL
            FolderDownloadStatus.FETCHING,
            FolderDownloadStatus.DOWNLOADING -> DownloadBadge.MIXED
            else                             -> null
        }
        else -> when (downloadState.status) {
            DownloadStatus.COMPLETE    -> DownloadBadge.ALL
            DownloadStatus.DOWNLOADING,
            DownloadStatus.EXTRACTING  -> DownloadBadge.MIXED
            else                       -> null
        }
    }

    Column(modifier = modifier) {
        Box(
            modifier = Modifier
                .weight(1f)
                .fillMaxWidth(),
        ) {
            AsyncImage(
                model = ImageRequest.Builder(LocalContext.current)
                    .data(coverUrl)
                    .addHeader("Authorization", authHeader)
                    .diskCacheKey(media.coverCachePath ?: media.id)
                    .crossfade(true)
                    .build(),
                contentDescription = media.displayTitle,
                contentScale = ContentScale.Crop,
                modifier = Modifier.matchParentSize(),
            )

            // Download status badge — bottom-right, non-interactive
            if (badge != null) {
                val badgeColor = when (badge) {
                    DownloadBadge.ALL   -> Color(0xFF4CAF50)
                    DownloadBadge.MIXED -> Color(0xFFFF9800)
                }
                Box(
                    modifier = Modifier
                        .align(Alignment.BottomEnd)
                        .padding(4.dp)
                        .background(
                            color = badgeColor.copy(alpha = 0.85f),
                            shape = RoundedCornerShape(4.dp),
                        )
                        .padding(3.dp),
                ) {
                    Icon(
                        imageVector = Icons.Default.OfflineBolt,
                        contentDescription = when (badge) {
                            DownloadBadge.ALL   -> "Available offline"
                            DownloadBadge.MIXED -> "Partially downloaded"
                        },
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
                        Icons.AutoMirrored.Filled.LibraryBooks,
                        contentDescription = null,
                        tint = Color.White,
                        modifier = Modifier.size(12.dp),
                    )
                }
            }
        }

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
