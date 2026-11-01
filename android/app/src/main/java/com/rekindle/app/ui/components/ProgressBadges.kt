package com.rekindle.app.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.rekindle.app.domain.model.ProgressSummary

private val ReadingColor = Color(0xFFFF9800)
private val CompletedColor = Color(0xFF4CAF50)

/** Smallest arc drawn for a started item, so a few pages in still shows something. */
private const val MIN_VISIBLE_PROGRESS = 0.04f

/**
 * Circular read-progress indicator for the corner of a cover: a partial orange
 * ring while reading, a full green ring with a check once finished, and nothing
 * for items never started.
 */
@Composable
fun ReadProgressRing(
    summary: ProgressSummary?,
    modifier: Modifier = Modifier,
    size: Dp = 26.dp,
) {
    if (summary == null || !summary.isStarted) return
    val completed = summary.isCompleted
    val label = if (completed) "Read" else "${summary.percent}% read"

    Box(
        contentAlignment = Alignment.Center,
        modifier = modifier
            .size(size)
            .background(Color.Black.copy(alpha = 0.6f), CircleShape)
            .padding(size * 0.1f)
            .semantics { contentDescription = label },
    ) {
        CircularProgressIndicator(
            progress = { if (completed) 1f else maxOf(summary.progress, MIN_VISIBLE_PROGRESS) },
            color = if (completed) CompletedColor else ReadingColor,
            trackColor = Color.White.copy(alpha = 0.25f),
            strokeWidth = size * 0.12f,
            modifier = Modifier.size(size * 0.8f),
        )
        if (completed) {
            Icon(
                Icons.Default.Check,
                contentDescription = null,
                tint = Color.White,
                modifier = Modifier.size(size * 0.5f),
            )
        }
    }
}

/** "3 NEW" badge for a series cover: chapters added since the user last read it. */
@Composable
fun NewChaptersBadge(count: Int, modifier: Modifier = Modifier) {
    if (count <= 0) return
    val label = if (count == 1) "1 new chapter" else "$count new chapters"

    Text(
        text = "$count NEW",
        color = MaterialTheme.colorScheme.onPrimary,
        fontSize = 10.sp,
        fontWeight = FontWeight.Bold,
        modifier = modifier
            .background(MaterialTheme.colorScheme.primary, RoundedCornerShape(4.dp))
            .padding(horizontal = 5.dp, vertical = 2.dp)
            .semantics { contentDescription = label },
    )
}
