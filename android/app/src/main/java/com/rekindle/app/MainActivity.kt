package com.rekindle.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.lifecycle.lifecycleScope
import com.rekindle.app.core.connectivity.ConnectivityMonitor
import com.rekindle.app.core.prefs.PrefsStore
import com.rekindle.app.core.sync.SyncWorker
import com.rekindle.app.ui.RekindleApp
import com.rekindle.app.ui.theme.RekindleTheme
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.launch
import javax.inject.Inject

@AndroidEntryPoint
class MainActivity : ComponentActivity() {

    @Inject lateinit var connectivityMonitor: ConnectivityMonitor
    @Inject lateinit var prefs: PrefsStore

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()

        // Enqueue a sync whenever the device regains connectivity
        lifecycleScope.launch {
            connectivityMonitor.isOnline
                .distinctUntilChanged()
                .filter { it }
                .collect { SyncWorker.enqueue(this@MainActivity) }
        }

        setContent {
            val themeMode by prefs.themeMode.collectAsState(initial = "system")
            val darkTheme = when (themeMode) {
                "light" -> false
                "dark"  -> true
                else    -> isSystemInDarkTheme()
            }
            RekindleTheme(darkTheme = darkTheme) {
                RekindleApp()
            }
        }
    }
}
