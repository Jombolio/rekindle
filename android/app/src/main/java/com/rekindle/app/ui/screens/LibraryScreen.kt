package com.rekindle.app.ui.screens

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AdminPanelSettings
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.DriveFileRenameOutline
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.automirrored.filled.Login
import androidx.compose.material.icons.filled.CloudUpload
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Storage
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.rekindle.app.domain.model.Library
import com.rekindle.app.domain.model.ServerSource
import com.rekindle.app.ui.viewmodel.MultiSourceLibraryViewModel
import com.rekindle.app.ui.viewmodel.SourceLibraryState

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LibraryScreen(
    onLibraryClick: (id: String, name: String, type: String) -> Unit,
    onSettingsClick: () -> Unit,
    onAdminClick: () -> Unit,
    onAddSource: () -> Unit,
    vm: MultiSourceLibraryViewModel = hiltViewModel(),
) {
    val states by vm.states.collectAsState()

    // Dialogs managed at this level so they appear above everything
    var renameTarget by remember { mutableStateOf<ServerSource?>(null) }
    var removeTarget by remember { mutableStateOf<ServerSource?>(null) }
    var addLibrarySourceId by remember { mutableStateOf<String?>(null) }
    var editLibrary by remember { mutableStateOf<Pair<String, Library>?>(null) }
    var deleteLibrary by remember { mutableStateOf<Pair<String, Library>?>(null) }
    var uploadSourceId by remember { mutableStateOf<String?>(null) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Rekindle") },
                actions = {
                    IconButton(onClick = onAddSource) {
                        Icon(Icons.Default.Add, contentDescription = "Add Server")
                    }
                    IconButton(onClick = onSettingsClick) {
                        Icon(Icons.Default.Settings, contentDescription = "Settings")
                    }
                },
            )
        }
    ) { padding ->
        if (states.isEmpty()) {
            // No sources added yet
            Box(
                Modifier.fillMaxSize().padding(padding),
                contentAlignment = Alignment.Center,
            ) {
                Column(
                    horizontalAlignment = Alignment.CenterHorizontally,
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Icon(
                        Icons.Default.Storage,
                        contentDescription = null,
                        modifier = Modifier.size(64.dp),
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(Modifier.height(8.dp))
                    Text("No servers added yet", style = MaterialTheme.typography.titleLarge)
                    Text(
                        "Add a Rekindle server to get started.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Spacer(Modifier.height(16.dp))
                    FilledTonalButton(onClick = onAddSource) {
                        Icon(Icons.Default.Add, contentDescription = null)
                        Spacer(Modifier.width(8.dp))
                        Text("Add Server")
                    }
                }
            }
        } else {
            LazyColumn(
                modifier = Modifier.fillMaxSize().padding(padding),
                contentPadding = androidx.compose.foundation.layout.PaddingValues(bottom = 24.dp),
            ) {
                states.forEach { sourceState ->
                    // ── Source section header ─────────────────────────────
                    item(key = "header_${sourceState.source.id}") {
                        SourceSectionHeader(
                            state = sourceState,
                            onAddLibrary = { addLibrarySourceId = sourceState.source.id },
                            onAdmin = {
                                vm.setActiveSource(sourceState.source.id)
                                onAdminClick()
                            },
                            onUpload = { uploadSourceId = sourceState.source.id },
                            onRename = { renameTarget = sourceState.source },
                            onSignOut = { vm.signOut(sourceState.source.id) },
                            onSignIn = {
                                vm.setActiveSource(sourceState.source.id)
                                onAddSource()
                            },
                            onRemove = { removeTarget = sourceState.source },
                            onRefresh = { vm.refresh(sourceState.source.id) },
                        )
                    }

                    // ── Source body ───────────────────────────────────────
                    when {
                        sourceState.source.token == null -> item(key = "signin_${sourceState.source.id}") {
                            SignInRow(onSignIn = {
                                vm.setActiveSource(sourceState.source.id)
                                onAddSource()
                            })
                        }
                        sourceState.loading -> item(key = "loading_${sourceState.source.id}") {
                            Box(
                                Modifier.fillMaxWidth().padding(vertical = 24.dp),
                                contentAlignment = Alignment.Center,
                            ) { CircularProgressIndicator() }
                        }
                        sourceState.error != null -> item(key = "error_${sourceState.source.id}") {
                            Text(
                                sourceState.error!!,
                                modifier = Modifier.padding(16.dp),
                                color = MaterialTheme.colorScheme.error,
                            )
                        }
                        sourceState.libraries.isEmpty() -> item(key = "empty_${sourceState.source.id}") {
                            EmptyLibrariesRow(
                                isAdmin = sourceState.source.permissionLevel >= 4,
                                onAdd = { addLibrarySourceId = sourceState.source.id },
                            )
                        }
                        else -> items(
                            sourceState.libraries,
                            key = { "${sourceState.source.id}_${it.id}" },
                        ) { lib ->
                            LibraryRow(
                                library = lib,
                                scanning = sourceState.scanning == lib.id,
                                isAdmin = sourceState.source.permissionLevel >= 4,
                                canManageMedia = sourceState.source.permissionLevel >= 3,
                                onTap = {
                                    vm.setActiveSource(sourceState.source.id)
                                    onLibraryClick(lib.id, lib.name, lib.type)
                                },
                                onScan = { vm.scan(sourceState.source.id, lib.id) },
                                onEdit = { editLibrary = sourceState.source.id to lib },
                                onDelete = { deleteLibrary = sourceState.source.id to lib },
                            )
                        }
                    }
                }
            }
        }
    }

    // ── Scan progress sheet ───────────────────────────────────────────────────

    val scanningState = states.firstOrNull { it.scanning != null }
    if (scanningState != null) {
        ModalBottomSheet(
            onDismissRequest = { /* non-dismissible during scan */ },
            sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        ) {
            val progress = scanningState.scanProgress
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 24.dp, vertical = 20.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                val scanningLib = scanningState.libraries
                    .find { it.id == scanningState.scanning }
                Text(
                    text = if (scanningLib != null) "Scanning \"${scanningLib.name}\"…"
                           else "Scanning library…",
                    style = MaterialTheme.typography.titleMedium,
                )
                if (progress != null && progress.filesTotal > 0) {
                    LinearProgressIndicator(
                        progress = { progress.filesProcessed.toFloat() / progress.filesTotal },
                        modifier = Modifier.fillMaxWidth(),
                    )
                    Text(
                        "${progress.filesProcessed} / ${progress.filesTotal} files",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    if (progress.added > 0 || progress.removed > 0) {
                        Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                            if (progress.added > 0)
                                Text("+ ${progress.added} added", style = MaterialTheme.typography.bodySmall)
                            if (progress.removed > 0)
                                Text("− ${progress.removed} removed", style = MaterialTheme.typography.bodySmall)
                        }
                    }
                    if (progress.coversQueued > 0) {
                        LinearProgressIndicator(
                            progress = { progress.coversGenerated.toFloat() / progress.coversQueued },
                            modifier = Modifier.fillMaxWidth(),
                        )
                        Text(
                            "Generating covers ${progress.coversGenerated} / ${progress.coversQueued}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                } else {
                    LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                    Text(
                        "Preparing scan…",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }

    // ── Upload sheet ──────────────────────────────────────────────────────────

    uploadSourceId?.let { srcId ->
        val uploadSource = states.find { it.source.id == srcId }
        if (uploadSource != null) {
            ModalBottomSheet(
                onDismissRequest = { uploadSourceId = null },
                sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
            ) {
                val adminVm: com.rekindle.app.ui.viewmodel.AdminViewModel =
                    androidx.hilt.navigation.compose.hiltViewModel()
                val adminState by adminVm.state.collectAsState()
                UploadTabContent(
                    libraries = uploadSource.libraries,
                    adminVm = adminVm,
                    adminState = adminState,
                )
            }
        }
    }

    // ── Dialogs ───────────────────────────────────────────────────────────────

    renameTarget?.let { source ->
        var name by rememberSaveable(source.id) { mutableStateOf(source.name) }
        AlertDialog(
            onDismissRequest = { renameTarget = null },
            title = { Text("Rename server") },
            text = {
                androidx.compose.material3.OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text("Display name") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
            },
            confirmButton = {
                TextButton(onClick = {
                    vm.renameSource(source.id, name.trim())
                    renameTarget = null
                }) { Text("Save") }
            },
            dismissButton = { TextButton(onClick = { renameTarget = null }) { Text("Cancel") } },
        )
    }

    removeTarget?.let { source ->
        AlertDialog(
            onDismissRequest = { removeTarget = null },
            title = { Text("Remove server?") },
            text = { Text("Remove \"${source.name}\" from this device? Your data on the server is not affected.") },
            confirmButton = {
                TextButton(onClick = { vm.removeSource(source.id); removeTarget = null }) {
                    Text("Remove")
                }
            },
            dismissButton = { TextButton(onClick = { removeTarget = null }) { Text("Cancel") } },
        )
    }

    addLibrarySourceId?.let { sourceId ->
        LibraryDialog(
            existing = null,
            onDismiss = { addLibrarySourceId = null },
            onConfirm = { name, rootPath, type ->
                vm.createLibrary(sourceId, name, rootPath, type)
                addLibrarySourceId = null
            },
        )
    }

    editLibrary?.let { (sourceId, lib) ->
        LibraryDialog(
            existing = lib,
            onDismiss = { editLibrary = null },
            onConfirm = { name, rootPath, type ->
                vm.updateLibrary(sourceId, lib.id, name, rootPath, type)
                editLibrary = null
            },
        )
    }

    deleteLibrary?.let { (sourceId, lib) ->
        AlertDialog(
            onDismissRequest = { deleteLibrary = null },
            title = { Text("Delete library?") },
            text = { Text("Remove \"${lib.name}\"? Media files will not be deleted.") },
            confirmButton = {
                TextButton(onClick = { vm.deleteLibrary(sourceId, lib.id); deleteLibrary = null }) {
                    Text("Delete")
                }
            },
            dismissButton = { TextButton(onClick = { deleteLibrary = null }) { Text("Cancel") } },
        )
    }
}

// ── Source section header ─────────────────────────────────────────────────────

@Composable
private fun SourceSectionHeader(
    state: SourceLibraryState,
    onAddLibrary: () -> Unit,
    onAdmin: () -> Unit,
    onUpload: () -> Unit,
    onRename: () -> Unit,
    onSignOut: () -> Unit,
    onSignIn: () -> Unit,
    onRemove: () -> Unit,
    onRefresh: () -> Unit,
) {
    val source = state.source
    val isAdmin = source.permissionLevel >= 4
    val canManageMedia = source.permissionLevel >= 3
    val hasToken = source.token != null
    var menuExpanded by remember { mutableStateOf(false) }

    Column {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(start = 16.dp, end = 4.dp, top = 20.dp, bottom = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                Icons.Default.Storage,
                contentDescription = null,
                modifier = Modifier.size(18.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.width(8.dp))
            Text(
                text = source.name,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.weight(1f),
            )
            // Upload button — level 3+ authenticated users
            AnimatedVisibility(visible = canManageMedia && hasToken, enter = fadeIn(), exit = fadeOut()) {
                IconButton(
                    onClick = onUpload,
                    modifier = Modifier.size(36.dp),
                ) {
                    Icon(Icons.Default.CloudUpload, contentDescription = "Upload Archive", modifier = Modifier.size(20.dp))
                }
            }
            // Add library button — only for authenticated admins
            AnimatedVisibility(visible = isAdmin && hasToken, enter = fadeIn(), exit = fadeOut()) {
                IconButton(
                    onClick = onAddLibrary,
                    modifier = Modifier.size(36.dp),
                ) {
                    Icon(Icons.Default.Add, contentDescription = "Add Library", modifier = Modifier.size(20.dp))
                }
            }
            // Source options menu
            Box {
                IconButton(
                    onClick = { menuExpanded = true },
                    modifier = Modifier.size(36.dp),
                ) {
                    Icon(Icons.Default.MoreVert, contentDescription = "Source options", modifier = Modifier.size(20.dp))
                }
                DropdownMenu(expanded = menuExpanded, onDismissRequest = { menuExpanded = false }) {
                    if (isAdmin && hasToken) {
                        DropdownMenuItem(
                            text = { Text("Admin Panel") },
                            leadingIcon = { Icon(Icons.Default.AdminPanelSettings, null) },
                            onClick = { menuExpanded = false; onAdmin() },
                        )
                    }
                    DropdownMenuItem(
                        text = { Text("Refresh") },
                        leadingIcon = { Icon(Icons.Default.Refresh, null) },
                        onClick = { menuExpanded = false; onRefresh() },
                    )
                    DropdownMenuItem(
                        text = { Text("Rename") },
                        leadingIcon = { Icon(Icons.Default.DriveFileRenameOutline, null) },
                        onClick = { menuExpanded = false; onRename() },
                    )
                    if (hasToken) {
                        DropdownMenuItem(
                            text = { Text("Sign out") },
                            leadingIcon = { Icon(Icons.AutoMirrored.Filled.Logout, null) },
                            onClick = { menuExpanded = false; onSignOut() },
                        )
                    } else {
                        DropdownMenuItem(
                            text = { Text("Sign in") },
                            leadingIcon = { Icon(Icons.AutoMirrored.Filled.Login, null) },
                            onClick = { menuExpanded = false; onSignIn() },
                        )
                    }
                    DropdownMenuItem(
                        text = { Text("Remove", color = MaterialTheme.colorScheme.error) },
                        leadingIcon = { Icon(Icons.Default.Delete, null, tint = MaterialTheme.colorScheme.error) },
                        onClick = { menuExpanded = false; onRemove() },
                    )
                }
            }
        }
        HorizontalDivider(modifier = Modifier.padding(horizontal = 16.dp))
    }
}

// ── Library row within a source section ──────────────────────────────────────

@Composable
private fun LibraryRow(
    library: Library,
    scanning: Boolean,
    isAdmin: Boolean,
    canManageMedia: Boolean,
    onTap: () -> Unit,
    onScan: () -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
) {
    var menuExpanded by remember { mutableStateOf(false) }
    val typeLabel = when (library.type) {
        "manga" -> "Manga"
        "book" -> "Books"
        else -> "Comics"
    }

    ListItem(
        headlineContent = { Text(library.name) },
        supportingContent = { Text(typeLabel) },
        trailingContent = if (canManageMedia) ({
            Box {
                IconButton(onClick = { menuExpanded = true }) {
                    if (scanning) {
                        CircularProgressIndicator(modifier = Modifier.size(20.dp), strokeWidth = 2.dp)
                    } else {
                        Icon(Icons.Default.MoreVert, contentDescription = "Library options")
                    }
                }
                DropdownMenu(expanded = menuExpanded, onDismissRequest = { menuExpanded = false }) {
                    if (isAdmin) {
                        DropdownMenuItem(
                            text = { Text("Edit") },
                            leadingIcon = { Icon(Icons.Default.Edit, null) },
                            onClick = { menuExpanded = false; onEdit() },
                        )
                    }
                    DropdownMenuItem(
                        text = { Text("Scan") },
                        leadingIcon = { Icon(Icons.Default.Refresh, null) },
                        onClick = { menuExpanded = false; onScan() },
                    )
                    if (isAdmin) {
                        DropdownMenuItem(
                            text = { Text("Delete") },
                            leadingIcon = { Icon(Icons.Default.Delete, null) },
                            onClick = { menuExpanded = false; onDelete() },
                        )
                    }
                }
            }
        }) else null,
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onTap),
    )
}

// ── Inline state rows ─────────────────────────────────────────────────────────

@Composable
private fun SignInRow(onSignIn: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            Icons.AutoMirrored.Filled.Logout,
            contentDescription = null,
            modifier = Modifier.size(20.dp),
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.width(12.dp))
        Text(
            "Not signed in.",
            modifier = Modifier.weight(1f),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        TextButton(onClick = onSignIn) { Text("Sign in") }
    }
}

@Composable
private fun EmptyLibrariesRow(isAdmin: Boolean, onAdd: () -> Unit) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 16.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            "No libraries",
            modifier = Modifier.weight(1f),
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        if (isAdmin) {
            TextButton(onClick = onAdd) {
                Icon(Icons.Default.Add, null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(4.dp))
                Text("Add")
            }
        }
    }
}
