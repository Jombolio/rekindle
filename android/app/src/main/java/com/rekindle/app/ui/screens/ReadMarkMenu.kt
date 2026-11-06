package com.rekindle.app.ui.screens

import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.DoneAll
import androidx.compose.material.icons.filled.RemoveDone
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable

/**
 * The long-press menu for a chapter or series.
 *
 * - Mark as read: counts the chapter as read however far into it the reader is,
 *   and stays while they reread or catch up, until removed; their place in it is
 *   never changed.
 * - Ignore archive tracking: leaves it out of the series' progress, so an annual
 *   or bundled volume the reader skips doesn't keep the series from looking
 *   finished or up to date. Its own progress is kept.
 *
 * On a series or folder each applies to everything in it, so both directions are
 * offered there. [extra] adds items of the caller's own.
 */
@Composable
fun ReadMarkMenu(
    expanded: Boolean,
    onDismiss: () -> Unit,
    markedRead: Boolean,
    isSeries: Boolean,
    onSetReadMark: (Boolean) -> Unit,
    ignored: Boolean = false,
    onSetIgnored: ((Boolean) -> Unit)? = null,
    extra: @Composable ColumnScope.() -> Unit = {},
) {
    DropdownMenu(expanded = expanded, onDismissRequest = onDismiss) {
        if (!markedRead) {
            DropdownMenuItem(
                text = { Text(if (isSeries) "Mark series as read" else "Mark as read") },
                leadingIcon = { Icon(Icons.Default.DoneAll, null) },
                onClick = { onDismiss(); onSetReadMark(true) },
            )
        }
        if (markedRead || isSeries) {
            DropdownMenuItem(
                text = { Text(if (isSeries) "Remove read marks" else "Remove read mark") },
                leadingIcon = { Icon(Icons.Default.RemoveDone, null) },
                onClick = { onDismiss(); onSetReadMark(false) },
            )
        }
        if (onSetIgnored != null) {
            HorizontalDivider()
            if (!ignored) {
                DropdownMenuItem(
                    text = { Text("Ignore archive tracking") },
                    leadingIcon = { Icon(Icons.Default.VisibilityOff, null) },
                    onClick = { onDismiss(); onSetIgnored(true) },
                )
            }
            if (ignored || isSeries) {
                DropdownMenuItem(
                    text = { Text(if (isSeries) "Track archives again" else "Track archive again") },
                    leadingIcon = { Icon(Icons.Default.Visibility, null) },
                    onClick = { onDismiss(); onSetIgnored(false) },
                )
            }
        }
        extra()
    }
}
