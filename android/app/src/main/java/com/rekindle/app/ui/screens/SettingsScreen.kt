package com.rekindle.app.ui.screens

import android.content.Intent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.FolderOpen
import androidx.compose.material.icons.filled.PhoneAndroid
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.rekindle.app.domain.model.ServerSource
import com.rekindle.app.core.prefs.MAX_CHAPTER_CONFIRM_MS
import com.rekindle.app.core.prefs.MIN_CHAPTER_CONFIRM_MS
import com.rekindle.app.ui.viewmodel.SettingsViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    onBack: () -> Unit,
    onAddSource: () -> Unit,
    onSourceSwitch: () -> Unit,
    vm: SettingsViewModel = hiltViewModel(),
) {
    val state by vm.state.collectAsState()
    val sources by vm.sources.collectAsState()
    val activeSourceId by vm.activeSourceId.collectAsState()
    val context = LocalContext.current

    var renameTarget by remember { mutableStateOf<ServerSource?>(null) }
    var deleteTarget by remember { mutableStateOf<ServerSource?>(null) }

    // SAF folder picker — launched when the user taps "Choose folder".
    val folderPickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocumentTree(),
    ) { uri ->
        if (uri != null) {
            // Take persistent read+write permission so it survives app restarts.
            context.contentResolver.takePersistableUriPermission(
                uri,
                Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_GRANT_WRITE_URI_PERMISSION,
            )
            vm.setDownloadSafUri(uri.toString())
        }
    }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Settings") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
            )
        }
    ) { padding ->
        Box(
            modifier = Modifier.fillMaxSize().padding(padding),
            contentAlignment = Alignment.TopCenter,
        ) {
            Column(
                Modifier
                    .widthIn(max = 640.dp)
                    .fillMaxWidth()
                    .verticalScroll(rememberScrollState())
                    .padding(horizontal = 16.dp, vertical = 8.dp),
            ) {

                // ── Servers ───────────────────────────────────────────────────────
                SectionHeader("Servers")

                sources.forEach { source ->
                    val isActive = source.id == activeSourceId
                    ListItem(
                        headlineContent = {
                            Text(source.name, fontWeight = if (isActive) FontWeight.Bold else FontWeight.Normal)
                        },
                        supportingContent = { Text(source.baseUrl) },
                        leadingContent = if (isActive) ({
                            Icon(Icons.Default.Check, null, tint = MaterialTheme.colorScheme.primary)
                        }) else null,
                        trailingContent = {
                            Row {
                                if (sources.size > 1) {
                                    IconButton(onClick = { deleteTarget = source }) {
                                        Icon(Icons.Default.Delete, contentDescription = "Remove server")
                                    }
                                }
                            }
                        },
                        colors = if (isActive)
                            ListItemDefaults.colors(containerColor = MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.3f))
                        else
                            ListItemDefaults.colors(),
                        modifier = Modifier
                            .fillMaxWidth()
                            .clickable(enabled = !isActive) {
                                if (source.token != null) {
                                    vm.switchSource(source)
                                    onSourceSwitch()
                                } else {
                                    vm.switchSource(source)
                                    onAddSource()
                                }
                            },
                    )
                }

                Spacer(Modifier.height(4.dp))
                TextButton(
                    onClick = onAddSource,
                    modifier = Modifier.align(Alignment.End),
                ) {
                    Icon(Icons.Default.Add, null)
                    Text("Add Server")
                }

                // ── Appearance ────────────────────────────────────────────────────
                SectionHeader("Appearance")

                val modes = listOf("system" to "System", "light" to "Light", "dark" to "Dark")
                SingleChoiceSegmentedButtonRow(Modifier.fillMaxWidth()) {
                    modes.forEachIndexed { index, (key, label) ->
                        SegmentedButton(
                            selected = state.themeMode == key,
                            onClick = { vm.setThemeMode(key) },
                            shape = SegmentedButtonDefaults.itemShape(index, modes.size),
                            label = { Text(label) },
                        )
                    }
                }

                // ── Reader ────────────────────────────────────────────────────────
                SectionHeader("Reader")

                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f)) {
                        Text("Confirm chapter change", style = MaterialTheme.typography.bodyLarge)
                        Text(
                            "Turning past the last or first page needs a second tap, " +
                                "so a stray input cannot leave the chapter by itself.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    Spacer(Modifier.width(16.dp))
                    Switch(
                        checked = state.confirmChapterChange,
                        onCheckedChange = { vm.setConfirmChapterChange(it) },
                    )
                }

                if (state.confirmChapterChange) {
                    Spacer(Modifier.height(8.dp))
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Text(
                            "Confirmation window",
                            style = MaterialTheme.typography.bodyLarge,
                            modifier = Modifier.weight(1f),
                        )
                        Text(
                            formatConfirmWindow(state.chapterConfirmMs),
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.primary,
                        )
                    }
                    Text(
                        "How long the second tap stays accepted.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Slider(
                        value = state.chapterConfirmMs
                            .coerceIn(MIN_CHAPTER_CONFIRM_MS, MAX_CHAPTER_CONFIRM_MS)
                            .toFloat(),
                        onValueChange = { vm.setChapterConfirmMs(it.toInt()) },
                        valueRange = MIN_CHAPTER_CONFIRM_MS.toFloat()..MAX_CHAPTER_CONFIRM_MS.toFloat(),
                        // 250 ms steps; steps counts the gaps *between* endpoints.
                        steps = (MAX_CHAPTER_CONFIRM_MS - MIN_CHAPTER_CONFIRM_MS) / 250 - 1,
                    )
                }

                // ── Downloads / Storage ───────────────────────────────────────────
                SectionHeader("Downloads")

                val usingCustomFolder = state.downloadSafUri.isNotBlank()

                // Active location card
                Surface(
                    color = MaterialTheme.colorScheme.surfaceContainerHigh,
                    shape = MaterialTheme.shapes.medium,
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                        Row(
                            verticalAlignment = Alignment.CenterVertically,
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                        ) {
                            Icon(
                                imageVector = if (usingCustomFolder) Icons.Default.FolderOpen else Icons.Default.PhoneAndroid,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.primary,
                            )
                            Text(
                                text = if (usingCustomFolder) "Custom folder" else "App-private storage",
                                style = MaterialTheme.typography.titleSmall,
                            )
                        }
                        Text(
                            text = if (usingCustomFolder)
                                state.downloadLocationLabel.ifBlank { state.downloadSafUri }
                            else
                                vm.appPrivatePath,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                        if (!usingCustomFolder) {
                            Text(
                                text = "Files are stored in the app's private directory. No storage permission is required, but files are removed if the app is uninstalled.",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        } else {
                            Text(
                                text = "Files are stored in the folder you chose. They remain on the device if the app is uninstalled and are accessible from any file manager.",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                }

                Spacer(Modifier.height(8.dp))

                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    OutlinedButton(
                        onClick = { folderPickerLauncher.launch(null) },
                        modifier = Modifier.weight(1f),
                    ) {
                        Icon(Icons.Default.FolderOpen, contentDescription = null)
                        Spacer(Modifier.padding(horizontal = 4.dp))
                        Text("Choose folder")
                    }

                    if (usingCustomFolder) {
                        OutlinedButton(
                            onClick = vm::clearDownloadSafUri,
                            modifier = Modifier.weight(1f),
                        ) {
                            Icon(Icons.Default.PhoneAndroid, contentDescription = null)
                            Spacer(Modifier.padding(horizontal = 4.dp))
                            Text("Use app storage")
                        }
                    }
                }
            }
        }
    }

    // Rename dialog
    renameTarget?.let { source ->
        var name by rememberSaveable { mutableStateOf(source.name) }
        AlertDialog(
            onDismissRequest = { renameTarget = null },
            title = { Text("Rename Server") },
            text = {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text("Name") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    vm.renameSource(source.id, name.trim().ifBlank { source.baseUrl })
                    renameTarget = null
                }) { Text("Save") }
            },
            dismissButton = {
                TextButton(onClick = { renameTarget = null }) { Text("Cancel") }
            },
        )
    }

    // Delete confirmation
    deleteTarget?.let { source ->
        AlertDialog(
            onDismissRequest = { deleteTarget = null },
            title = { Text("Remove server?") },
            text = { Text("\"${source.name}\" will be removed from this device.") },
            confirmButton = {
                TextButton(onClick = { vm.removeSource(source.id); deleteTarget = null }) {
                    Text("Remove")
                }
            },
            dismissButton = {
                TextButton(onClick = { deleteTarget = null }) { Text("Cancel") }
            },
        )
    }
}

/** "750 ms" below a second, "1.5 s" above — the slider steps in 250 ms, so one
 *  decimal is always enough. Matches the desktop client's wording. */
private fun formatConfirmWindow(ms: Int): String {
    if (ms < 1000) return "$ms ms"
    val seconds = ms / 1000.0
    val text = if (seconds == Math.floor(seconds)) seconds.toInt().toString()
    else String.format(java.util.Locale.US, "%.1f", seconds)
    return "$text s"
}

@Composable
private fun SectionHeader(title: String) {
    Text(
        text = title,
        style = MaterialTheme.typography.labelLarge,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(top = 24.dp, bottom = 8.dp),
    )
}
