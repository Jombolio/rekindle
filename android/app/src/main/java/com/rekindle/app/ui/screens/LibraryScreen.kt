package com.rekindle.app.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.Logout
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
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
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import com.rekindle.app.domain.model.Library
import com.rekindle.app.ui.viewmodel.LibraryViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LibraryScreen(
    onLibraryClick: (id: String, name: String) -> Unit,
    onSettingsClick: () -> Unit,
    onLogout: () -> Unit,
    vm: LibraryViewModel = hiltViewModel(),
) {
    val state by vm.state.collectAsState()
    val isAdmin by vm.isAdmin.collectAsState()

    var showAddDialog by remember { mutableStateOf(false) }
    var editTarget by remember { mutableStateOf<Library?>(null) }
    var deleteTarget by remember { mutableStateOf<Library?>(null) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Libraries") },
                actions = {
                    if (isAdmin) {
                        IconButton(onClick = { showAddDialog = true }) {
                            Icon(Icons.Default.Add, contentDescription = "Add Library")
                        }
                    }
                    IconButton(onClick = onSettingsClick) {
                        Icon(Icons.Default.Settings, contentDescription = "Settings")
                    }
                    IconButton(onClick = { vm.logout(); onLogout() }) {
                        Icon(Icons.AutoMirrored.Filled.Logout, contentDescription = "Logout")
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

            state.libraries.isEmpty() -> Box(
                Modifier.fillMaxSize().padding(padding),
                contentAlignment = Alignment.Center,
            ) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("No libraries yet")
                    if (isAdmin) {
                        Spacer(Modifier.height(16.dp))
                        FilledTonalButton(onClick = { showAddDialog = true }) {
                            Icon(Icons.Default.Add, contentDescription = null)
                            Text("Add Library")
                        }
                    }
                }
            }

            else -> LazyColumn(Modifier.fillMaxSize().padding(padding)) {
                items(state.libraries, key = { it.id }) { lib ->
                    LibraryRow(
                        library = lib,
                        isAdmin = isAdmin,
                        scanning = state.scanning == lib.id,
                        onClick = { onLibraryClick(lib.id, lib.name) },
                        onScan = { vm.scan(lib.id) },
                        onEdit = { editTarget = lib },
                        onDelete = { deleteTarget = lib },
                    )
                }
            }
        }
    }

    if (showAddDialog) {
        LibraryDialog(
            existing = null,
            onDismiss = { showAddDialog = false },
            onConfirm = { name, rootPath, type ->
                vm.create(name, rootPath, type)
                showAddDialog = false
            },
        )
    }

    editTarget?.let { lib ->
        LibraryDialog(
            existing = lib,
            onDismiss = { editTarget = null },
            onConfirm = { name, rootPath, type ->
                vm.update(lib.id, name, rootPath, type)
                editTarget = null
            },
        )
    }

    deleteTarget?.let { lib ->
        AlertDialog(
            onDismissRequest = { deleteTarget = null },
            title = { Text("Delete library?") },
            text = { Text("Remove \"${lib.name}\" from Rekindle? Media files will not be deleted.") },
            confirmButton = {
                TextButton(onClick = { vm.delete(lib.id); deleteTarget = null }) {
                    Text("Delete")
                }
            },
            dismissButton = {
                TextButton(onClick = { deleteTarget = null }) { Text("Cancel") }
            },
        )
    }
}

@Composable
private fun LibraryRow(
    library: Library,
    isAdmin: Boolean,
    scanning: Boolean,
    onClick: () -> Unit,
    onScan: () -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
) {
    var menuExpanded by remember { mutableStateOf(false) }

    ListItem(
        headlineContent = { Text(library.name) },
        supportingContent = { Text(library.path) },
        trailingContent = {
            if (isAdmin) {
                Box {
                    IconButton(onClick = { menuExpanded = true }) {
                        if (scanning) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(24.dp),
                                strokeWidth = 2.dp,
                            )
                        } else {
                            Icon(Icons.Default.MoreVert, contentDescription = "Library options")
                        }
                    }
                    DropdownMenu(
                        expanded = menuExpanded,
                        onDismissRequest = { menuExpanded = false },
                    ) {
                        DropdownMenuItem(
                            text = { Text("Edit") },
                            leadingIcon = { Icon(Icons.Default.Edit, null) },
                            onClick = { menuExpanded = false; onEdit() },
                        )
                        DropdownMenuItem(
                            text = { Text("Scan") },
                            leadingIcon = { Icon(Icons.Default.Refresh, null) },
                            onClick = { menuExpanded = false; onScan() },
                        )
                        DropdownMenuItem(
                            text = { Text("Delete") },
                            leadingIcon = { Icon(Icons.Default.Delete, null) },
                            onClick = { menuExpanded = false; onDelete() },
                        )
                    }
                }
            } else if (scanning) {
                CircularProgressIndicator(modifier = Modifier.size(24.dp), strokeWidth = 2.dp)
            }
        },
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick),
    )
}

@Composable
private fun LibraryDialog(
    existing: Library?,
    onDismiss: () -> Unit,
    onConfirm: (name: String, rootPath: String, type: String) -> Unit,
) {
    val isEditing = existing != null
    var name by rememberSaveable { mutableStateOf(existing?.name ?: "") }
    var rootPath by rememberSaveable { mutableStateOf(existing?.path ?: "") }
    var type by rememberSaveable { mutableStateOf("comic") }
    var error by remember { mutableStateOf<String?>(null) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (isEditing) "Edit Library" else "Add Library") },
        text = {
            Column {
                error?.let {
                    Text(it, modifier = Modifier.padding(bottom = 8.dp))
                }
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it; error = null },
                    label = { Text("Library Name") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                Spacer(Modifier.height(12.dp))
                OutlinedTextField(
                    value = rootPath,
                    onValueChange = { rootPath = it; error = null },
                    label = { Text("Path on server") },
                    placeholder = { Text("/media/comics") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                Spacer(Modifier.height(12.dp))
                // Type selector — three options as text buttons acting as a toggle group
                Text("Type: $type")
                Spacer(Modifier.height(4.dp))
                androidx.compose.foundation.layout.Row {
                    listOf("comic" to "Comics", "manga" to "Manga", "book" to "Books")
                        .forEach { (value, label) ->
                            TextButton(
                                onClick = { type = value },
                                modifier = Modifier.weight(1f),
                            ) {
                                Text(
                                    label,
                                    fontWeight = if (type == value)
                                        androidx.compose.ui.text.font.FontWeight.Bold
                                    else
                                        androidx.compose.ui.text.font.FontWeight.Normal,
                                )
                            }
                        }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = {
                if (name.isBlank() || rootPath.isBlank()) {
                    error = "Name and path are required."
                } else {
                    onConfirm(name.trim(), rootPath.trim(), type)
                }
            }) {
                Text(if (isEditing) "Save" else "Add")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text("Cancel") }
        },
    )
}
