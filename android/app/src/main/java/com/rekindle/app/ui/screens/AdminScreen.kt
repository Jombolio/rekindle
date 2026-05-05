package com.rekindle.app.ui.screens

import android.net.Uri
import android.provider.OpenableColumns
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
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.Add
import androidx.compose.material.icons.filled.AttachFile
import androidx.compose.material.icons.filled.Clear
import androidx.compose.material.icons.filled.CreateNewFolder
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.Edit
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.MoreVert
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ElevatedCard
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MenuAnchorType
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.SuggestionChip
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import kotlinx.coroutines.launch
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import coil.compose.AsyncImage
import coil.request.ImageRequest
import com.rekindle.app.domain.model.AdminUser
import com.rekindle.app.domain.model.Library
import com.rekindle.app.ui.viewmodel.AdminScreenState
import com.rekindle.app.ui.viewmodel.AdminViewModel
import com.rekindle.app.ui.viewmodel.LibraryState
import com.rekindle.app.ui.viewmodel.LibraryViewModel

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun AdminScreen(
    onBack: () -> Unit,
    vm: LibraryViewModel = hiltViewModel(),
    adminVm: AdminViewModel = hiltViewModel(),
) {
    val state by vm.state.collectAsState()
    val adminState by adminVm.state.collectAsState()
    val snackbarHostState = remember { SnackbarHostState() }
    val scope = rememberCoroutineScope()

    LaunchedEffect(Unit) {
        adminVm.cacheCleared.collect { freedBytes ->
            val mb = freedBytes / (1024.0 * 1024.0)
            val label = if (mb < 1024) "%.1f MB".format(mb) else "%.2f GB".format(mb / 1024.0)
            scope.launch { snackbarHostState.showSnackbar("Cache cleared — $label freed.") }
        }
    }

    var selectedTab by rememberSaveable { mutableIntStateOf(0) }

    var showAddDialog by remember { mutableStateOf(false) }
    var editTarget by remember { mutableStateOf<Library?>(null) }
    var deleteTarget by remember { mutableStateOf<Library?>(null) }

    var showAddUserDialog by remember { mutableStateOf(false) }
    var changePermTarget by remember { mutableStateOf<AdminUser?>(null) }
    var resetPasswordTarget by remember { mutableStateOf<AdminUser?>(null) }
    var deleteUserTarget by remember { mutableStateOf<AdminUser?>(null) }

    LaunchedEffect(selectedTab) {
        when (selectedTab) {
            1 -> adminVm.loadUsers()
            3 -> adminVm.loadStats()
            4 -> adminVm.loadApisConfig()
        }
    }

    Scaffold(
        snackbarHost = { SnackbarHost(snackbarHostState) },
        topBar = {
            TopAppBar(
                title = { Text("Admin Panel") },
                navigationIcon = {
                    IconButton(onClick = onBack) {
                        Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    when (selectedTab) {
                        0 -> IconButton(onClick = { showAddDialog = true }) {
                            Icon(Icons.Default.Add, contentDescription = "Add Library")
                        }
                        1 -> IconButton(onClick = { showAddUserDialog = true }) {
                            Icon(Icons.Default.Add, contentDescription = "Add User")
                        }
                        else -> {}
                    }
                },
            )
        },
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            TabRow(selectedTabIndex = selectedTab) {
                listOf("Libraries", "Users", "System", "APIs").forEachIndexed { idx, title ->
                    Tab(
                        selected = selectedTab == idx,
                        onClick = { selectedTab = idx },
                        text = { Text(title) },
                    )
                }
            }

            when (selectedTab) {
                0 -> LibrariesTabContent(
                    state = state,
                    onAddClick = { showAddDialog = true },
                    onEditClick = { editTarget = it },
                    onDeleteClick = { deleteTarget = it },
                    onScanClick = { vm.scan(it) },
                )
                1 -> UsersTabContent(
                    adminState = adminState,
                    onAddUserClick = { showAddUserDialog = true },
                    onChangePermClick = { changePermTarget = it },
                    onResetPasswordClick = { resetPasswordTarget = it },
                    onDeleteUserClick = { deleteUserTarget = it },
                )
                2 -> SystemTabContent(
                    adminVm = adminVm,
                    adminState = adminState,
                )
                3 -> ApisTabContent(
                    adminVm = adminVm,
                    adminState = adminState,
                )
            }
        }
    }

    // Libraries dialogs
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
            text = { Text("Remove \"${lib.name}\"? Media files will not be deleted.") },
            confirmButton = {
                TextButton(onClick = { vm.delete(lib.id); deleteTarget = null }) { Text("Delete") }
            },
            dismissButton = { TextButton(onClick = { deleteTarget = null }) { Text("Cancel") } },
        )
    }

    // Users dialogs
    if (showAddUserDialog) {
        AddUserDialog(
            onDismiss = { showAddUserDialog = false },
            onConfirm = { username, password, level ->
                adminVm.createUser(username, password, level)
                showAddUserDialog = false
            },
        )
    }
    changePermTarget?.let { user ->
        ChangePermissionDialog(
            user = user,
            onDismiss = { changePermTarget = null },
            onConfirm = { level ->
                adminVm.updatePermission(user.id, level)
                changePermTarget = null
            },
        )
    }
    resetPasswordTarget?.let { user ->
        ResetPasswordDialog(
            user = user,
            onDismiss = { resetPasswordTarget = null },
            onConfirm = { password ->
                adminVm.updatePassword(user.id, password)
                resetPasswordTarget = null
            },
        )
    }
    deleteUserTarget?.let { user ->
        AlertDialog(
            onDismissRequest = { deleteUserTarget = null },
            title = { Text("Delete user?") },
            text = { Text("Remove user \"${user.username}\"? This cannot be undone.") },
            confirmButton = {
                TextButton(onClick = { adminVm.deleteUser(user.id); deleteUserTarget = null }) {
                    Text("Delete")
                }
            },
            dismissButton = { TextButton(onClick = { deleteUserTarget = null }) { Text("Cancel") } },
        )
    }
}

// ── Libraries tab ─────────────────────────────────────────────────────────────

@Composable
private fun LibrariesTabContent(
    state: LibraryState,
    onAddClick: () -> Unit,
    onEditClick: (Library) -> Unit,
    onDeleteClick: (Library) -> Unit,
    onScanClick: (String) -> Unit,
) {
    when {
        state.loading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            CircularProgressIndicator()
        }
        state.error != null -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Text(state.error!!)
        }
        state.libraries.isEmpty() -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text("No libraries yet")
                Spacer(Modifier.height(16.dp))
                FilledTonalButton(onClick = onAddClick) {
                    Icon(Icons.Default.Add, null)
                    Spacer(Modifier.width(4.dp))
                    Text("Add Library")
                }
            }
        }
        else -> LazyColumn(Modifier.fillMaxSize()) {
            items(state.libraries, key = { it.id }) { lib ->
                AdminLibraryRow(
                    library = lib,
                    scanning = state.scanning == lib.id,
                    onScan = { onScanClick(lib.id) },
                    onEdit = { onEditClick(lib) },
                    onDelete = { onDeleteClick(lib) },
                )
            }
        }
    }
}

@Composable
private fun AdminLibraryRow(
    library: Library,
    scanning: Boolean,
    onScan: () -> Unit,
    onEdit: () -> Unit,
    onDelete: () -> Unit,
) {
    var menuExpanded by remember { mutableStateOf(false) }

    ListItem(
        headlineContent = { Text(library.name) },
        supportingContent = { Text("${library.type} · ${library.path}") },
        trailingContent = {
            Box {
                IconButton(onClick = { menuExpanded = true }) {
                    if (scanning) {
                        CircularProgressIndicator(modifier = Modifier.size(24.dp), strokeWidth = 2.dp)
                    } else {
                        Icon(Icons.Default.MoreVert, contentDescription = "Options")
                    }
                }
                DropdownMenu(expanded = menuExpanded, onDismissRequest = { menuExpanded = false }) {
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
        },
        modifier = Modifier.fillMaxWidth().clickable(onClick = onEdit),
    )
}

// ── Users tab ─────────────────────────────────────────────────────────────────

@Composable
private fun UsersTabContent(
    adminState: AdminScreenState,
    onAddUserClick: () -> Unit,
    onChangePermClick: (AdminUser) -> Unit,
    onResetPasswordClick: (AdminUser) -> Unit,
    onDeleteUserClick: (AdminUser) -> Unit,
) {
    when {
        adminState.usersLoading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            CircularProgressIndicator()
        }
        adminState.usersError != null -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Text(adminState.usersError!!)
        }
        adminState.users.isEmpty() -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Column(horizontalAlignment = Alignment.CenterHorizontally) {
                Text("No users")
                Spacer(Modifier.height(16.dp))
                FilledTonalButton(onClick = onAddUserClick) {
                    Icon(Icons.Default.Add, null)
                    Spacer(Modifier.width(4.dp))
                    Text("Add User")
                }
            }
        }
        else -> LazyColumn(Modifier.fillMaxSize()) {
            items(adminState.users, key = { it.id }) { user ->
                UserRow(
                    user = user,
                    onChangePermClick = { onChangePermClick(user) },
                    onResetPasswordClick = { onResetPasswordClick(user) },
                    onDeleteClick = { onDeleteUserClick(user) },
                )
            }
        }
    }
}

@Composable
private fun UserRow(
    user: AdminUser,
    onChangePermClick: () -> Unit,
    onResetPasswordClick: () -> Unit,
    onDeleteClick: () -> Unit,
) {
    var menuExpanded by remember { mutableStateOf(false) }

    ListItem(
        headlineContent = { Text(user.username) },
        supportingContent = { Text(user.permissionLabel) },
        trailingContent = {
            if (user.isAdmin) {
                SuggestionChip(
                    onClick = {},
                    label = { Text("Admin") },
                )
            } else {
                Box {
                    IconButton(onClick = { menuExpanded = true }) {
                        Icon(Icons.Default.MoreVert, contentDescription = "Options")
                    }
                    DropdownMenu(expanded = menuExpanded, onDismissRequest = { menuExpanded = false }) {
                        DropdownMenuItem(
                            text = { Text("Change permission") },
                            leadingIcon = { Icon(Icons.Default.Edit, null) },
                            onClick = { menuExpanded = false; onChangePermClick() },
                        )
                        DropdownMenuItem(
                            text = { Text("Reset password") },
                            leadingIcon = { Icon(Icons.Default.Lock, null) },
                            onClick = { menuExpanded = false; onResetPasswordClick() },
                        )
                        DropdownMenuItem(
                            text = { Text("Delete") },
                            leadingIcon = { Icon(Icons.Default.Delete, null) },
                            onClick = { menuExpanded = false; onDeleteClick() },
                        )
                    }
                }
            }
        },
        modifier = Modifier.fillMaxWidth(),
    )
}

// ── Upload tab ────────────────────────────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun UploadTabContent(
    libraries: List<Library>,
    adminVm: AdminViewModel,
    adminState: AdminScreenState,
) {
    val coverBaseUrl by adminVm.coverBaseUrl.collectAsState()
    val authHeader by adminVm.authHeader.collectAsState()
    val context = LocalContext.current

    var selectedLibrary by remember { mutableStateOf<Library?>(null) }
    var libDropdownExpanded by remember { mutableStateOf(false) }

    var folderText by rememberSaveable { mutableStateOf("") }
    var folderDropdownExpanded by remember { mutableStateOf(false) }

    var selectedFileUri by remember { mutableStateOf<Uri?>(null) }
    var selectedFileName by remember { mutableStateOf<String?>(null) }

    val filePicker = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocument(),
    ) { uri ->
        if (uri != null) {
            selectedFileUri = uri
            selectedFileName = context.contentResolver.query(uri, null, null, null, null)?.use { cursor ->
                val idx = cursor.getColumnIndex(OpenableColumns.DISPLAY_NAME)
                cursor.moveToFirst()
                if (idx >= 0) cursor.getString(idx) else null
            } ?: uri.lastPathSegment
        }
    }

    val folders = adminState.uploadFolders
    val filteredFolders = remember(folderText, folders) {
        if (folderText.isBlank()) folders
        else folders.filter { it.relativePath.contains(folderText.trimEnd('/'), ignoreCase = true) }
    }
    val showCreateOption = folderText.isNotBlank() &&
        !folders.any { it.relativePath.equals(folderText.trimEnd('/'), ignoreCase = true) }

    LaunchedEffect(selectedLibrary) {
        selectedLibrary?.let { adminVm.loadFoldersForLibrary(it.id) }
    }

    LaunchedEffect(Unit) {
        adminVm.clearUploadStatus()
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        // Library selector
        ExposedDropdownMenuBox(
            expanded = libDropdownExpanded,
            onExpandedChange = { libDropdownExpanded = it },
        ) {
            OutlinedTextField(
                value = selectedLibrary?.name ?: "",
                onValueChange = {},
                readOnly = true,
                label = { Text("Target library") },
                trailingIcon = { ExposedDropdownMenuDefaults.TrailingIcon(expanded = libDropdownExpanded) },
                modifier = Modifier
                    .menuAnchor(MenuAnchorType.PrimaryNotEditable)
                    .fillMaxWidth(),
            )
            ExposedDropdownMenu(
                expanded = libDropdownExpanded,
                onDismissRequest = { libDropdownExpanded = false },
            ) {
                libraries.forEach { lib ->
                    DropdownMenuItem(
                        text = { Text(lib.name) },
                        onClick = {
                            selectedLibrary = lib
                            libDropdownExpanded = false
                            folderText = ""
                        },
                        contentPadding = ExposedDropdownMenuDefaults.ItemContentPadding,
                    )
                }
            }
        }

        // Folder location with autocomplete
        ExposedDropdownMenuBox(
            expanded = folderDropdownExpanded,
            onExpandedChange = { if (selectedLibrary != null) folderDropdownExpanded = it },
        ) {
            OutlinedTextField(
                value = folderText,
                onValueChange = { text ->
                    folderText = text
                    folderDropdownExpanded = text.isNotEmpty() && selectedLibrary != null
                },
                label = { Text("Upload into…") },
                placeholder = { Text("FolderName/") },
                singleLine = true,
                enabled = selectedLibrary != null,
                trailingIcon = {
                    if (folderText.isNotEmpty()) {
                        IconButton(onClick = { folderText = ""; folderDropdownExpanded = false }) {
                            Icon(Icons.Default.Clear, contentDescription = "Clear")
                        }
                    }
                },
                modifier = Modifier
                    .menuAnchor(MenuAnchorType.PrimaryEditable)
                    .fillMaxWidth(),
            )
            ExposedDropdownMenu(
                expanded = folderDropdownExpanded,
                onDismissRequest = { folderDropdownExpanded = false },
            ) {
                if (showCreateOption) {
                    DropdownMenuItem(
                        text = { Text("Create \"${folderText.trimEnd('/')}/\"") },
                        leadingIcon = { Icon(Icons.Default.CreateNewFolder, null) },
                        onClick = {
                            folderText = "${folderText.trimEnd('/')}/"
                            folderDropdownExpanded = false
                        },
                        contentPadding = ExposedDropdownMenuDefaults.ItemContentPadding,
                    )
                }
                filteredFolders.forEach { folder ->
                    DropdownMenuItem(
                        text = {
                            Column {
                                Text(folder.displayTitle)
                                Text(
                                    "${folder.relativePath}/",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                        },
                        leadingIcon = {
                            AsyncImage(
                                model = ImageRequest.Builder(context)
                                    .data("$coverBaseUrl/api/media/${folder.id}/cover")
                                    .addHeader("Authorization", authHeader)
                                    .diskCacheKey(folder.coverCachePath ?: folder.id)
                                    .crossfade(true)
                                    .build(),
                                contentDescription = null,
                                contentScale = ContentScale.Crop,
                                modifier = Modifier.size(width = 28.dp, height = 40.dp),
                            )
                        },
                        onClick = {
                            folderText = "${folder.relativePath}/"
                            folderDropdownExpanded = false
                        },
                        contentPadding = ExposedDropdownMenuDefaults.ItemContentPadding,
                    )
                }
            }
        }

        // File picker
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            OutlinedButton(
                onClick = { filePicker.launch(arrayOf("*/*")) },
                modifier = Modifier.weight(1f),
            ) {
                Icon(Icons.Default.AttachFile, null)
                Spacer(Modifier.width(8.dp))
                Text(
                    text = selectedFileName ?: "Select archive…",
                    maxLines = 1,
                )
            }
            if (selectedFileUri != null) {
                IconButton(onClick = { selectedFileUri = null; selectedFileName = null }) {
                    Icon(Icons.Default.Clear, contentDescription = "Clear selection")
                }
            }
        }

        // Upload button
        Button(
            onClick = {
                val uri = selectedFileUri ?: return@Button
                val lib = selectedLibrary ?: return@Button
                adminVm.uploadFile(uri, lib.id, folderText.trimEnd('/').ifBlank { null })
                selectedFileUri = null
                selectedFileName = null
                folderText = ""
            },
            enabled = selectedFileUri != null && selectedLibrary != null && !adminState.uploadLoading,
            modifier = Modifier.fillMaxWidth(),
        ) {
            if (adminState.uploadLoading) {
                CircularProgressIndicator(
                    modifier = Modifier.size(18.dp),
                    strokeWidth = 2.dp,
                    color = MaterialTheme.colorScheme.onPrimary,
                )
                Spacer(Modifier.width(8.dp))
            }
            Text("Upload")
        }

        adminState.uploadSuccess?.let { msg ->
            Text(msg, color = MaterialTheme.colorScheme.primary)
        }
        adminState.uploadError?.let { err ->
            Text(err, color = MaterialTheme.colorScheme.error)
        }
    }
}

// ── System tab ────────────────────────────────────────────────────────────────

@Composable
private fun SystemTabContent(
    adminVm: AdminViewModel,
    adminState: AdminScreenState,
) {
    var showClearCacheDialog by remember { mutableStateOf(false) }

    when {
        adminState.statsLoading -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            CircularProgressIndicator()
        }
        adminState.statsError != null -> Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Text(adminState.statsError!!)
        }
        else -> Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(12.dp),
        ) {
            adminState.stats?.let { stats ->
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    StatCard(label = "Users", value = "${stats.userCount}", modifier = Modifier.weight(1f))
                    StatCard(label = "Libraries", value = "${stats.libraryCount}", modifier = Modifier.weight(1f))
                }
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    StatCard(label = "Media items", value = "${stats.mediaCount}", modifier = Modifier.weight(1f))
                    StatCard(label = "Cover cache", value = stats.cacheSizeLabel, modifier = Modifier.weight(1f))
                }
            }

            Spacer(Modifier.height(8.dp))

            Button(
                onClick = { showClearCacheDialog = true },
                enabled = !adminState.clearingCache,
                modifier = Modifier.fillMaxWidth(),
            ) {
                if (adminState.clearingCache) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(18.dp),
                        strokeWidth = 2.dp,
                        color = MaterialTheme.colorScheme.onPrimary,
                    )
                    Spacer(Modifier.width(8.dp))
                }
                Text("Clear Cover Cache")
            }
        }
    }

    if (showClearCacheDialog) {
        AlertDialog(
            onDismissRequest = { showClearCacheDialog = false },
            title = { Text("Clear cover cache?") },
            text = { Text("All generated cover thumbnails will be deleted. They will be regenerated on the next scan.") },
            confirmButton = {
                TextButton(onClick = { adminVm.clearCache(); showClearCacheDialog = false }) {
                    Text("Clear")
                }
            },
            dismissButton = {
                TextButton(onClick = { showClearCacheDialog = false }) { Text("Cancel") }
            },
        )
    }
}

@Composable
private fun StatCard(label: String, value: String, modifier: Modifier = Modifier) {
    ElevatedCard(modifier = modifier) {
        Column(modifier = Modifier.padding(16.dp)) {
            Text(value, style = MaterialTheme.typography.headlineMedium)
            Text(
                label,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

// ── APIs tab ──────────────────────────────────────────────────────────────────

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ApisTabContent(
    adminVm: AdminViewModel,
    adminState: AdminScreenState,
) {
    var malClientId by rememberSaveable { mutableStateOf("") }
    var comicvineApiKey by rememberSaveable { mutableStateOf("") }
    var obscureMal by rememberSaveable { mutableStateOf(true) }
    var obscureCv by rememberSaveable { mutableStateOf(true) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text("Metadata API Keys", style = MaterialTheme.typography.titleMedium)
        Text(
            "API keys are stored on the server and used to scrape manga metadata. " +
                "AniList works without a key.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        if (adminState.apisLoading) {
            CircularProgressIndicator(modifier = Modifier.align(Alignment.CenterHorizontally))
            return@Column
        }

        adminState.apisError?.let {
            Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
        }
        if (adminState.apisSaveSuccess) {
            Text("API key saved.", color = MaterialTheme.colorScheme.primary, style = MaterialTheme.typography.bodySmall)
        }

        // ComicVine
        ElevatedCard(modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("ComicVine", style = MaterialTheme.typography.titleSmall)
                    if (adminState.cvKeySet) SuggestionChip(onClick = {}, label = { Text("Key set") })
                }
                Text(
                    "Used for comic metadata. Register at comicvine.gamespot.com/api. " +
                        "Rate limit: 200 requests/resource/hour.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                OutlinedTextField(
                    value = comicvineApiKey,
                    onValueChange = { comicvineApiKey = it },
                    label = { Text(if (adminState.cvKeySet) "New API Key (blank = keep current)" else "ComicVine API Key") },
                    visualTransformation = if (obscureCv) androidx.compose.ui.text.input.PasswordVisualTransformation()
                    else androidx.compose.ui.text.input.VisualTransformation.None,
                    trailingIcon = {
                        IconButton(onClick = { obscureCv = !obscureCv }) {
                            Icon(
                                if (obscureCv) androidx.compose.material.icons.Icons.Default.Lock
                                else androidx.compose.material.icons.Icons.Default.Edit,
                                contentDescription = null, modifier = Modifier.size(18.dp),
                            )
                        }
                    },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }

        // MAL
        ElevatedCard(modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("MyAnimeList", style = MaterialTheme.typography.titleSmall)
                    if (adminState.malKeySet) SuggestionChip(onClick = {}, label = { Text("Key set") })
                }
                Text(
                    "Used for manga metadata. Register at myanimelist.net/apiconfig to get a Client ID.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
                OutlinedTextField(
                    value = malClientId,
                    onValueChange = { malClientId = it },
                    label = { Text(if (adminState.malKeySet) "New Client ID (blank = keep current)" else "MAL Client ID") },
                    visualTransformation = if (obscureMal) androidx.compose.ui.text.input.PasswordVisualTransformation()
                    else androidx.compose.ui.text.input.VisualTransformation.None,
                    trailingIcon = {
                        IconButton(onClick = { obscureMal = !obscureMal }) {
                            Icon(
                                if (obscureMal) androidx.compose.material.icons.Icons.Default.Lock
                                else androidx.compose.material.icons.Icons.Default.Edit,
                                contentDescription = null, modifier = Modifier.size(18.dp),
                            )
                        }
                    },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }

        // Save button
        Button(
            onClick = {
                adminVm.saveApiKeys(
                    malClientId = malClientId.trim().ifBlank { null },
                    comicvineApiKey = comicvineApiKey.trim().ifBlank { null },
                )
            },
            enabled = (malClientId.isNotBlank() || comicvineApiKey.isNotBlank()) && !adminState.apisSaving,
            modifier = Modifier.fillMaxWidth(),
        ) {
            if (adminState.apisSaving) {
                CircularProgressIndicator(modifier = Modifier.size(18.dp), strokeWidth = 2.dp)
                Spacer(Modifier.width(8.dp))
            }
            Text("Save API Keys")
        }

        // AniList
        ElevatedCard(modifier = Modifier.fillMaxWidth()) {
            Column(modifier = Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("AniList", style = MaterialTheme.typography.titleSmall)
                    SuggestionChip(onClick = {}, label = { Text("No key needed") })
                }
                Text(
                    "AniList public GraphQL API requires no authentication. " +
                        "Rekindle enforces a 30-request/minute rate limit.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

// ── User dialogs ──────────────────────────────────────────────────────────────

private val permissionLabels = mapOf(1 to "Read-only", 2 to "Download", 3 to "Manage Media", 4 to "Admin")

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun AddUserDialog(
    onDismiss: () -> Unit,
    onConfirm: (username: String, password: String, permissionLevel: Int) -> Unit,
) {
    var username by rememberSaveable { mutableStateOf("") }
    var password by rememberSaveable { mutableStateOf("") }
    var permissionLevel by rememberSaveable { mutableIntStateOf(2) }
    var permDropdownExpanded by remember { mutableStateOf(false) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Add User") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = username,
                    onValueChange = { username = it },
                    label = { Text("Username") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = password,
                    onValueChange = { password = it },
                    label = { Text("Password") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                ExposedDropdownMenuBox(
                    expanded = permDropdownExpanded,
                    onExpandedChange = { permDropdownExpanded = it },
                ) {
                    OutlinedTextField(
                        value = permissionLabels[permissionLevel] ?: "Level $permissionLevel",
                        onValueChange = {},
                        readOnly = true,
                        label = { Text("Permission") },
                        trailingIcon = {
                            ExposedDropdownMenuDefaults.TrailingIcon(expanded = permDropdownExpanded)
                        },
                        modifier = Modifier
                            .menuAnchor(MenuAnchorType.PrimaryNotEditable)
                            .fillMaxWidth(),
                    )
                    ExposedDropdownMenu(
                        expanded = permDropdownExpanded,
                        onDismissRequest = { permDropdownExpanded = false },
                    ) {
                        permissionLabels.forEach { (level, label) ->
                            DropdownMenuItem(
                                text = { Text(label) },
                                onClick = { permissionLevel = level; permDropdownExpanded = false },
                                contentPadding = ExposedDropdownMenuDefaults.ItemContentPadding,
                            )
                        }
                    }
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    if (username.isNotBlank() && password.isNotBlank())
                        onConfirm(username.trim(), password, permissionLevel)
                },
            ) { Text("Add") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ChangePermissionDialog(
    user: AdminUser,
    onDismiss: () -> Unit,
    onConfirm: (Int) -> Unit,
) {
    var permissionLevel by rememberSaveable { mutableIntStateOf(user.permissionLevel) }
    var permDropdownExpanded by remember { mutableStateOf(false) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Change permission") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("User: ${user.username}")
                ExposedDropdownMenuBox(
                    expanded = permDropdownExpanded,
                    onExpandedChange = { permDropdownExpanded = it },
                ) {
                    OutlinedTextField(
                        value = permissionLabels[permissionLevel] ?: "Level $permissionLevel",
                        onValueChange = {},
                        readOnly = true,
                        label = { Text("Permission") },
                        trailingIcon = {
                            ExposedDropdownMenuDefaults.TrailingIcon(expanded = permDropdownExpanded)
                        },
                        modifier = Modifier
                            .menuAnchor(MenuAnchorType.PrimaryNotEditable)
                            .fillMaxWidth(),
                    )
                    ExposedDropdownMenu(
                        expanded = permDropdownExpanded,
                        onDismissRequest = { permDropdownExpanded = false },
                    ) {
                        permissionLabels.forEach { (level, label) ->
                            DropdownMenuItem(
                                text = { Text(label) },
                                onClick = { permissionLevel = level; permDropdownExpanded = false },
                                contentPadding = ExposedDropdownMenuDefaults.ItemContentPadding,
                            )
                        }
                    }
                }
            }
        },
        confirmButton = {
            TextButton(onClick = { onConfirm(permissionLevel) }) { Text("Save") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

@Composable
private fun ResetPasswordDialog(
    user: AdminUser,
    onDismiss: () -> Unit,
    onConfirm: (String) -> Unit,
) {
    var password by rememberSaveable { mutableStateOf("") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("Reset password") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("User: ${user.username}")
                OutlinedTextField(
                    value = password,
                    onValueChange = { password = it },
                    label = { Text("New password") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = { if (password.isNotBlank()) onConfirm(password) },
            ) { Text("Reset") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}

// ── Library dialog (shared with AdminScreen) ──────────────────────────────────

@Composable
internal fun LibraryDialog(
    existing: Library?,
    onDismiss: () -> Unit,
    onConfirm: (name: String, rootPath: String, type: String) -> Unit,
) {
    var name by rememberSaveable { mutableStateOf(existing?.name ?: "") }
    var rootPath by rememberSaveable { mutableStateOf(existing?.path ?: "") }
    var type by rememberSaveable { mutableStateOf(existing?.type ?: "comic") }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(if (existing == null) "Add Library" else "Edit Library") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                OutlinedTextField(
                    value = name,
                    onValueChange = { name = it },
                    label = { Text("Name") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = rootPath,
                    onValueChange = { rootPath = it },
                    label = { Text("Root path") },
                    placeholder = { Text("/media/comics") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
                OutlinedTextField(
                    value = type,
                    onValueChange = { type = it },
                    label = { Text("Type (comic / manga / book)") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = {
                    if (name.isNotBlank() && rootPath.isNotBlank())
                        onConfirm(name.trim(), rootPath.trim(), type.trim().ifBlank { "comic" })
                },
            ) { Text(if (existing == null) "Add" else "Save") }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text("Cancel") } },
    )
}
