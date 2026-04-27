package com.rekindle.app.ui.theme

import androidx.compose.runtime.Composable
import androidx.compose.ui.platform.LocalConfiguration

enum class WindowWidthClass { Compact, Medium, Expanded }

@Composable
fun currentWindowWidthClass(): WindowWidthClass {
    val widthDp = LocalConfiguration.current.screenWidthDp
    return when {
        widthDp >= 840 -> WindowWidthClass.Expanded
        widthDp >= 600 -> WindowWidthClass.Medium
        else -> WindowWidthClass.Compact
    }
}
