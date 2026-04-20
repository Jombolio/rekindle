package com.rekindle.app.ui.components

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.DownloadDone
import androidx.compose.material.icons.filled.ErrorOutline
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.rekindle.app.core.download.DownloadState
import com.rekindle.app.core.download.DownloadStatus
import com.rekindle.app.domain.model.Media

@Composable
fun DownloadButton(
    media: Media,
    downloadState: DownloadState,
    onDownload: () -> Unit,
    onDelete: () -> Unit,
    onCancel: () -> Unit,
    modifier: Modifier = Modifier,
) {
    if (media.isFolder) return

    var showDeleteDialog by remember { mutableStateOf(false) }

    if (showDeleteDialog) {
        AlertDialog(
            onDismissRequest = { showDeleteDialog = false },
            title = { Text("Delete download?") },
            text = { Text("\"${media.displayTitle}\" will be removed from this device.") },
            confirmButton = {
                TextButton(onClick = { showDeleteDialog = false; onDelete() }) {
                    Text("Delete", color = Color.Red)
                }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteDialog = false }) { Text("Cancel") }
            },
        )
    }

    Box(modifier = modifier, contentAlignment = Alignment.Center) {
        when (downloadState.status) {
            DownloadStatus.IDLE, DownloadStatus.FAILED -> IconButton(onClick = onDownload) {
                Icon(
                    imageVector = if (downloadState.status == DownloadStatus.FAILED)
                        Icons.Default.ErrorOutline else Icons.Default.Download,
                    contentDescription = "Download",
                    tint = if (downloadState.status == DownloadStatus.FAILED) Color.Red else Color.Unspecified,
                )
            }

            DownloadStatus.DOWNLOADING -> Box(
                modifier = Modifier.size(40.dp),
                contentAlignment = Alignment.Center,
            ) {
                CircularProgressIndicator(
                    progress = { downloadState.progress.takeIf { it > 0f } ?: 0f },
                    modifier = Modifier.size(32.dp),
                    strokeWidth = 2.dp,
                )
                IconButton(onClick = onCancel, modifier = Modifier.size(24.dp)) {
                    Icon(Icons.Default.Close, "Cancel", modifier = Modifier.size(16.dp))
                }
            }

            DownloadStatus.EXTRACTING -> CircularProgressIndicator(
                modifier = Modifier.size(32.dp),
                strokeWidth = 2.dp,
            )

            DownloadStatus.COMPLETE -> IconButton(onClick = { showDeleteDialog = true }) {
                Icon(Icons.Default.DownloadDone, "Delete download", tint = Color(0xFF4CAF50))
            }
        }
    }
}
