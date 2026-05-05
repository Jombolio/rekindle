import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/admin_api.dart';
import '../core/api/api_client.dart';
import '../core/api/libraries_api.dart';
import '../core/api/media_api.dart';
import '../core/api/metadata_api.dart';
import '../core/models/library.dart';
import '../core/models/media.dart';
import '../providers/sources_provider.dart';
import 'widgets/cover_image.dart';

// ── Per-source providers ──────────────────────────────────────────────────

/// Builds an ApiClient for a specific source by ID.
final _sourceClientProvider =
    Provider.autoDispose.family<ApiClient, String>((ref, sourceId) {
  final sources = ref.watch(sourcesProvider);
  final source = sources.where((s) => s.id == sourceId).firstOrNull;
  if (source == null) return ApiClient(baseUrl: '', token: null);
  return ApiClient(baseUrl: source.baseUrl, token: source.token);
});

final _statsProvider =
    FutureProvider.autoDispose.family<AdminStats, String>((ref, sourceId) {
  final client = ref.watch(_sourceClientProvider(sourceId));
  return AdminApi(client).getStats();
});

final _usersProvider = AsyncNotifierProviderFamily<_UsersNotifier,
    List<AdminUser>, String>(_UsersNotifier.new);

class _UsersNotifier extends FamilyAsyncNotifier<List<AdminUser>, String> {
  @override
  Future<List<AdminUser>> build(String sourceId) => _fetch();

  Future<List<AdminUser>> _fetch() {
    return AdminApi(_client).getUsers();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }

  ApiClient get _client =>
      ref.read(_sourceClientProvider(arg));

  Future<void> createUser(
      String username, String password, int permissionLevel) async {
    await AdminApi(_client).createUser(
        username: username, password: password, permissionLevel: permissionLevel);
    await refresh();
  }

  Future<void> updatePermission(String userId, int level) async {
    await AdminApi(_client).updatePermission(userId, level);
    await refresh();
  }

  Future<void> updatePassword(String userId, String password) async {
    await AdminApi(_client).updatePassword(userId, password);
  }

  Future<void> deleteUser(String userId) async {
    await AdminApi(_client).deleteUser(userId);
    await refresh();
  }
}

final _librariesProvider =
    FutureProvider.autoDispose.family<List<Library>, String>((ref, sourceId) {
  final client = ref.watch(_sourceClientProvider(sourceId));
  return LibrariesApi(client).getAll();
});

// ── Screen ────────────────────────────────────────────────────────────────

class AdminPanelScreen extends ConsumerWidget {
  final String sourceId;
  const AdminPanelScreen({super.key, required this.sourceId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(sourcesProvider);
    final source = sources.where((s) => s.id == sourceId).firstOrNull;
    final sourceName = source?.name ?? 'Admin Panel';

    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: Text('$sourceName — Admin'),
          bottom: const TabBar(
            tabs: [
              Tab(icon: Icon(Icons.people_outline), text: 'Users'),
              Tab(icon: Icon(Icons.monitor_heart_outlined), text: 'System'),
              Tab(icon: Icon(Icons.api_outlined), text: 'APIs'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _UsersTab(sourceId: sourceId),
            _SystemTab(sourceId: sourceId),
            _ApisTab(sourceId: sourceId),
          ],
        ),
      ),
    );
  }
}

// ── Users tab ─────────────────────────────────────────────────────────────

class _UsersTab extends ConsumerWidget {
  final String sourceId;
  const _UsersTab({required this.sourceId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersState = ref.watch(_usersProvider(sourceId));

    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateDialog(context, ref),
        icon: const Icon(Icons.person_add_outlined),
        label: const Text('Add User'),
      ),
      body: usersState.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (users) => ListView.separated(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
          itemCount: users.length,
          separatorBuilder: (_, __) => const SizedBox(height: 4),
          itemBuilder: (_, i) => _UserTile(user: users[i], sourceId: sourceId),
        ),
      ),
    );
  }

  Future<void> _showCreateDialog(BuildContext context, WidgetRef ref) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _CreateUserDialog(ref: ref, sourceId: sourceId),
    );
  }
}

class _UserTile extends ConsumerWidget {
  final AdminUser user;
  final String sourceId;
  const _UserTile({required this.user, required this.sourceId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdminAccount = user.isAdmin;

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: isAdminAccount
              ? Theme.of(context).colorScheme.primaryContainer
              : null,
          child: Icon(
            isAdminAccount ? Icons.admin_panel_settings : Icons.person_outline,
          ),
        ),
        title: Text(user.username),
        subtitle: Text(user.permissionLabel),
        trailing: isAdminAccount
            ? const Chip(label: Text('Admin'))
            : PopupMenuButton<String>(
                onSelected: (action) => _onAction(context, ref, action),
                itemBuilder: (_) => const [
                  PopupMenuItem(
                      value: 'permission', child: Text('Change permission')),
                  PopupMenuItem(
                      value: 'password', child: Text('Reset password')),
                  PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete',
                          style: TextStyle(color: Colors.red))),
                ],
              ),
      ),
    );
  }

  Future<void> _onAction(
      BuildContext context, WidgetRef ref, String action) async {
    final notifier = ref.read(_usersProvider(sourceId).notifier);
    switch (action) {
      case 'permission':
        await showDialog<void>(
          context: context,
          builder: (_) =>
              _EditPermissionDialog(user: user, ref: ref, sourceId: sourceId),
        );
      case 'password':
        await showDialog<void>(
          context: context,
          builder: (_) =>
              _ResetPasswordDialog(user: user, ref: ref, sourceId: sourceId),
        );
      case 'delete':
        final confirm = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Delete user?'),
            content:
                Text('Permanently delete "${user.username}"? This cannot be undone.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel')),
              FilledButton(
                style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error),
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        );
        if (confirm == true) {
          try {
            await notifier.deleteUser(user.id);
          } catch (e) {
            if (context.mounted) _showError(context, e);
          }
        }
    }
  }
}

// ── User dialogs ──────────────────────────────────────────────────────────

class _CreateUserDialog extends StatefulWidget {
  final WidgetRef ref;
  final String sourceId;
  const _CreateUserDialog({required this.ref, required this.sourceId});

  @override
  State<_CreateUserDialog> createState() => _CreateUserDialogState();
}

class _CreateUserDialogState extends State<_CreateUserDialog> {
  final _userCtrl = TextEditingController();
  final _passCtrl = TextEditingController();
  int _level = 2;
  bool _obscure = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _userCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final username = _userCtrl.text.trim();
    final password = _passCtrl.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = 'Username and password are required.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await widget.ref
          .read(_usersProvider(widget.sourceId).notifier)
          .createUser(username, password, _level);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() { _saving = false; _error = _apiError(e); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add User'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null) ...[
              _ErrorText(_error!),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _userCtrl,
              decoration: const InputDecoration(
                  labelText: 'Username', border: OutlineInputBorder()),
              autofocus: true,
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _passCtrl,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'Password',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<int>(
              value: _level, // ignore: deprecated_member_use
              decoration: const InputDecoration(
                  labelText: 'Permission level', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 1, child: Text('1 — Read-only')),
                DropdownMenuItem(value: 2, child: Text('2 — Download')),
                DropdownMenuItem(value: 3, child: Text('3 — Manage Media')),
                DropdownMenuItem(value: 4, child: Text('4 — Admin')),
              ],
              onChanged: (v) => setState(() => _level = v!),
            ),
          ],
        ),
      ),
      actions: _dialogActions(context, _saving, _save),
    );
  }
}

class _EditPermissionDialog extends StatefulWidget {
  final AdminUser user;
  final WidgetRef ref;
  final String sourceId;
  const _EditPermissionDialog(
      {required this.user, required this.ref, required this.sourceId});

  @override
  State<_EditPermissionDialog> createState() => _EditPermissionDialogState();
}

class _EditPermissionDialogState extends State<_EditPermissionDialog> {
  late int _level;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _level = widget.user.permissionLevel.clamp(1, 3);
  }

  Future<void> _save() async {
    setState(() { _saving = true; _error = null; });
    try {
      await widget.ref
          .read(_usersProvider(widget.sourceId).notifier)
          .updatePermission(widget.user.id, _level);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() { _saving = false; _error = _apiError(e); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Edit ${widget.user.username}'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null) ...[
              _ErrorText(_error!),
              const SizedBox(height: 12),
            ],
            DropdownButtonFormField<int>(
              value: _level, // ignore: deprecated_member_use
              decoration: const InputDecoration(
                  labelText: 'Permission level', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 1, child: Text('1 — Read-only')),
                DropdownMenuItem(value: 2, child: Text('2 — Download')),
                DropdownMenuItem(value: 3, child: Text('3 — Manage Media')),
                DropdownMenuItem(value: 4, child: Text('4 — Admin')),
              ],
              onChanged: (v) => setState(() => _level = v!),
            ),
          ],
        ),
      ),
      actions: _dialogActions(context, _saving, _save, label: 'Save'),
    );
  }
}

class _ResetPasswordDialog extends StatefulWidget {
  final AdminUser user;
  final WidgetRef ref;
  final String sourceId;
  const _ResetPasswordDialog(
      {required this.user, required this.ref, required this.sourceId});

  @override
  State<_ResetPasswordDialog> createState() => _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends State<_ResetPasswordDialog> {
  final _passCtrl = TextEditingController();
  bool _obscure = true;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final password = _passCtrl.text;
    if (password.length < 8) {
      setState(() => _error = 'Password must be at least 8 characters.');
      return;
    }
    setState(() { _saving = true; _error = null; });
    try {
      await widget.ref
          .read(_usersProvider(widget.sourceId).notifier)
          .updatePassword(widget.user.id, password);
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Password updated for ${widget.user.username}.')),
        );
      }
    } catch (e) {
      setState(() { _saving = false; _error = _apiError(e); });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Reset password — ${widget.user.username}'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null) ...[
              _ErrorText(_error!),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _passCtrl,
              obscureText: _obscure,
              decoration: InputDecoration(
                labelText: 'New password',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_off : Icons.visibility),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              autofocus: true,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _save(),
            ),
          ],
        ),
      ),
      actions: _dialogActions(context, _saving, _save, label: 'Reset'),
    );
  }
}

// ── Upload panel — shown as a dialog from the library screen ─────────────────

class UploadPanel extends ConsumerStatefulWidget {
  final String sourceId;
  const UploadPanel({super.key, required this.sourceId});

  @override
  ConsumerState<UploadPanel> createState() => _UploadPanelState();
}

class _UploadPanelState extends ConsumerState<UploadPanel> {
  Library? _selectedLibrary;
  // Relative path to upload into (null = library root). Updated whenever the
  // text field changes, so no explicit confirm step is needed.
  String? _uploadRelPath;
  List<Media> _folders = [];
  bool _loadingFolders = false;
  Key _locationKey = UniqueKey();

  String? _filePath;
  String? _fileName;
  double? _progress;
  String? _error;
  String? _success;
  bool _uploading = false;

  Future<void> _onLibraryChanged(Library? lib) async {
    setState(() {
      _selectedLibrary = lib;
      _uploadRelPath = null;
      _folders = [];
      _loadingFolders = lib != null;
      _locationKey = UniqueKey();
    });
    if (lib == null) return;
    try {
      final client = ref.read(_sourceClientProvider(widget.sourceId));
      final page = await MediaApi(client).getPaged(libraryId: lib.id, pageSize: 200);
      if (mounted) {
        setState(() {
          _folders = page.items.where((m) => m.isFolder).toList();
          _loadingFolders = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loadingFolders = false);
    }
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['cbz', 'cbr', 'pdf', 'epub', 'mobi', 'CBZ', 'CBR', 'PDF', 'EPUB', 'MOBI'],
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return;
    setState(() {
      _filePath = result.files.single.path;
      _fileName = result.files.single.name;
      _error = null;
      _success = null;
    });
  }

  Future<void> _upload() async {
    if (_selectedLibrary == null || _filePath == null) return;
    setState(() { _uploading = true; _progress = 0; _error = null; _success = null; });
    try {
      final client = ref.read(_sourceClientProvider(widget.sourceId));
      final msg = await AdminApi(client).uploadFile(
        libraryId: _selectedLibrary!.id,
        relativePath: _uploadRelPath,
        filePath: _filePath!,
        fileName: _fileName!,
        onProgress: (sent, total) {
          if (total > 0) setState(() => _progress = sent / total);
        },
      );
      setState(() {
        _success = msg;
        _filePath = null;
        _fileName = null;
        _progress = null;
        _uploading = false;
      });
    } catch (e) {
      setState(() {
        _error = _apiError(e);
        _progress = null;
        _uploading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final librariesState = ref.watch(_librariesProvider(widget.sourceId));
    final client = ref.read(_sourceClientProvider(widget.sourceId));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Upload Archive to Library',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 24),
            if (_error != null) ...[
              _ErrorText(_error!),
              const SizedBox(height: 16),
            ],
            if (_success != null) ...[
              _SuccessText(_success!),
              const SizedBox(height: 16),
            ],

            // ── Library ──────────────────────────────────────────────────
            librariesState.when(
              loading: () => const LinearProgressIndicator(),
              error: (e, _) => _ErrorText(e.toString()),
              data: (libs) => DropdownButtonFormField<Library>(
                value: _selectedLibrary, // ignore: deprecated_member_use
                decoration: const InputDecoration(
                    labelText: 'Target library',
                    border: OutlineInputBorder()),
                items: libs
                    .map((l) => DropdownMenuItem(value: l, child: Text(l.name)))
                    .toList(),
                onChanged: _uploading ? null : _onLibraryChanged,
              ),
            ),

            // ── Location ─────────────────────────────────────────────────
            const SizedBox(height: 16),
            if (_loadingFolders)
              const LinearProgressIndicator(minHeight: 2)
            else
              _FolderLocationField(
                key: _locationKey,
                folders: _folders,
                client: client,
                enabled: _selectedLibrary != null && !_uploading,
                hint: _selectedLibrary == null
                    ? 'Select a library first'
                    : 'Library root — search or type a path',
                onChange: (path) => setState(() => _uploadRelPath = path),
              ),

            // ── File picker ───────────────────────────────────────────────
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _uploading ? null : _pickFile,
              icon: const Icon(Icons.folder_open_outlined),
              label: Text(_fileName ?? 'Choose file…'),
            ),
            if (_fileName != null) ...[
              const SizedBox(height: 6),
              Text(_fileName!,
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis),
            ],

            // ── Progress + submit ─────────────────────────────────────────
            const SizedBox(height: 24),
            if (_progress != null) ...[
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 8),
              Text('${((_progress ?? 0) * 100).toStringAsFixed(1)}%',
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
            ],
            FilledButton.icon(
              onPressed:
                  (_uploading || _selectedLibrary == null || _filePath == null)
                      ? null
                      : _upload,
              icon: _uploading
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.cloud_upload_outlined),
              label: Text(_uploading ? 'Uploading…' : 'Upload'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Folder location autocomplete ──────────────────────────────────────────

// Option type used by the Autocomplete widget.
// _ExistingFolder wraps an existing Media folder from the library.
// _NewFolder represents a user-defined path that may not yet exist on disk.
sealed class _FolderOption { const _FolderOption(); }
final class _ExistingFolder extends _FolderOption {
  final Media folder;
  const _ExistingFolder(this.folder);
}
final class _NewFolder extends _FolderOption {
  final String path; // raw text in the field at the time this option was built
  const _NewFolder(this.path);
}

/// Autocomplete text field for choosing (or creating) a destination folder.
///
/// * Text always reflects the relative path with a trailing slash, e.g.
///   `Absolute Superman/` or `Manga/One Piece/Volume 3/`.
/// * The first entry in the dropdown is always a "Create …" option so the
///   user can create new directories without them existing yet.
/// * Selecting an existing folder fills the field with `relativePath/` and
///   shows the folder's cover thumbnail as the prefix icon.
/// * Every keystroke fires [onChange] so the parent always has the latest
///   path even if the user never taps a suggestion.
class _FolderLocationField extends StatefulWidget {
  final List<Media> folders;
  final ApiClient client;
  final bool enabled;
  final String hint;
  final void Function(String? relativePath) onChange;

  const _FolderLocationField({
    super.key,
    required this.folders,
    required this.client,
    required this.enabled,
    required this.hint,
    required this.onChange,
  });

  @override
  State<_FolderLocationField> createState() => _FolderLocationFieldState();
}

class _FolderLocationFieldState extends State<_FolderLocationField> {
  // The Autocomplete widget owns its TextEditingController; we get a reference
  // in fieldViewBuilder and attach our listener exactly once per controller.
  TextEditingController? _ctrl;
  // Folder whose cover is shown as the prefix icon (null = plain folder icon).
  Media? _previewFolder;

  @override
  void dispose() {
    _ctrl?.removeListener(_onTextChanged);
    super.dispose();
  }

  // Attach listener once; safe to call on every build because it checks identity.
  void _attach(TextEditingController ctrl) {
    if (_ctrl == ctrl) return;
    _ctrl?.removeListener(_onTextChanged);
    _ctrl = ctrl;
    ctrl.addListener(_onTextChanged);
  }

  void _onTextChanged() {
    final ctrl = _ctrl;
    if (ctrl == null) return;
    // Strip the display-only trailing slash to get the real path.
    final raw = ctrl.text;
    final path = raw.endsWith('/') ? raw.substring(0, raw.length - 1) : raw;
    final trimmed = path.trim();

    // Update the cover preview when the text exactly matches a known folder.
    Media? matched;
    if (trimmed.isNotEmpty) {
      for (final f in widget.folders) {
        if (f.relativePath.toLowerCase() == trimmed.toLowerCase() ||
            f.displayTitle.toLowerCase() == trimmed.toLowerCase()) {
          matched = f;
          break;
        }
      }
    }
    if (matched != _previewFolder) setState(() => _previewFolder = matched);
    widget.onChange(trimmed.isEmpty ? null : trimmed);
  }

  void _clear(TextEditingController ctrl) {
    ctrl.clear();
    setState(() => _previewFolder = null);
    widget.onChange(null);
  }

  @override
  Widget build(BuildContext context) {
    return Autocomplete<_FolderOption>(
      // What goes into the text field after a selection.
      displayStringForOption: (opt) => switch (opt) {
        _ExistingFolder(:final folder) => '${folder.relativePath}/',
        _NewFolder(:final path) when path.isNotEmpty =>
            path.endsWith('/') ? path : '$path/',
        _ => '',
      },
      optionsBuilder: (textValue) {
        final raw = textValue.text;
        // Strip trailing slash — preserve original case for the Create option
        // and the value sent to the server.
        final display = (raw.endsWith('/')
                ? raw.substring(0, raw.length - 1)
                : raw)
            .trim();
        // Lowercase only for case-insensitive matching.
        final q = display.toLowerCase();

        final existing = widget.folders
            .where((f) =>
                q.isEmpty ||
                f.displayTitle.toLowerCase().contains(q) ||
                f.relativePath.toLowerCase().contains(q))
            .map((f) => _ExistingFolder(f) as _FolderOption);

        // "Create" option is always first so it's immediately reachable.
        return [_NewFolder(display), ...existing];
      },
      onSelected: (opt) {
        switch (opt) {
          case _ExistingFolder(:final folder):
            setState(() => _previewFolder = folder);
            widget.onChange(folder.relativePath);
          case _NewFolder(:final path) when path.isNotEmpty:
            setState(() => _previewFolder = null);
            widget.onChange(path);
          default:
            break; // empty path — user hasn't typed yet; do nothing
        }
      },
      fieldViewBuilder: (context, ctrl, focusNode, onSubmit) {
        _attach(ctrl);
        return TextField(
          controller: ctrl,
          focusNode: focusNode,
          enabled: widget.enabled,
          onSubmitted: (_) => onSubmit(),
          decoration: InputDecoration(
            labelText: 'Upload into…',
            hintText: widget.hint,
            border: const OutlineInputBorder(),
            prefixIcon: _previewFolder != null
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: CoverImage(
                        url: widget.client.coverUrl(_previewFolder!.id),
                        headers: widget.client.authHeaders,
                        cacheKey: _previewFolder!.coverCachePath,
                        fit: BoxFit.cover,
                        width: 30,
                        height: 42,
                      ),
                    ),
                  )
                : const Icon(Icons.folder_outlined),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 52, minHeight: 52),
            suffixIcon: ctrl.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    tooltip: 'Upload to library root',
                    onPressed: widget.enabled ? () => _clear(ctrl) : null,
                  )
                : null,
          ),
        );
      },
      optionsViewBuilder: (context, onOptionSelected, options) => Align(
        alignment: Alignment.topLeft,
        child: Material(
          elevation: 4,
          borderRadius: BorderRadius.circular(8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320, maxWidth: 560),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: options.length,
                itemBuilder: (context, i) {
                  final opt = options.elementAt(i);
                  final highlighted =
                      AutocompleteHighlightedOption.of(context) == i;
                  final hlColor = highlighted
                      ? Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withValues(alpha: 0.4)
                      : null;
                  return switch (opt) {
                    _NewFolder(:final path) => _NewFolderTile(
                        path: path,
                        color: hlColor,
                        onTap: path.isNotEmpty
                            ? () => onOptionSelected(opt)
                            : null,
                      ),
                    _ExistingFolder(:final folder) => _ExistingFolderTile(
                        folder: folder,
                        client: widget.client,
                        color: hlColor,
                        onTap: () => onOptionSelected(opt),
                      ),
                  };
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _NewFolderTile extends StatelessWidget {
  final String path;
  final Color? color;
  final VoidCallback? onTap;
  const _NewFolderTile(
      {required this.path, required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = path.isNotEmpty;
    return InkWell(
      onTap: onTap,
      child: Container(
        color: active ? color : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Icon(
              Icons.create_new_folder_outlined,
              size: 20,
              color: active ? cs.primary : cs.onSurface.withValues(alpha: 0.38),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: active
                  ? RichText(
                      text: TextSpan(
                        style: Theme.of(context).textTheme.bodyMedium,
                        children: [
                          TextSpan(
                              text: 'Create ',
                              style: TextStyle(color: cs.primary)),
                          TextSpan(
                              text: '"$path/"',
                              style:
                                  const TextStyle(fontWeight: FontWeight.w500)),
                        ],
                      ),
                    )
                  : Text(
                      'Type a path to create a new folder',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: cs.onSurface.withValues(alpha: 0.38)),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ExistingFolderTile extends StatelessWidget {
  final Media folder;
  final ApiClient client;
  final Color? color;
  final VoidCallback onTap;
  const _ExistingFolderTile(
      {required this.folder,
      required this.client,
      required this.color,
      required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Container(
        color: color,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              height: 62,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: CoverImage(
                  url: client.coverUrl(folder.id),
                  headers: client.authHeaders,
                  cacheKey: folder.coverCachePath,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    folder.displayTitle,
                    style: Theme.of(context).textTheme.bodyMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${folder.relativePath}/',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color:
                            Theme.of(context).colorScheme.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── System tab ────────────────────────────────────────────────────────────

class _SystemTab extends ConsumerWidget {
  final String sourceId;
  const _SystemTab({required this.sourceId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsState = ref.watch(_statsProvider(sourceId));

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Server Statistics',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 16),
          statsState.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => _ErrorText(e.toString()),
            data: (stats) => _StatsGrid(stats: stats),
          ),
          const SizedBox(height: 32),
          const Divider(),
          const SizedBox(height: 16),
          Text('Cache Management',
              style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'Clearing the cache forces all archives to be re-extracted on next access. '
            'This frees disk space but temporarily increases load.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 16),
          _ClearCacheButton(
            sourceId: sourceId,
            onCleared: () => ref.invalidate(_statsProvider(sourceId)),
          ),
        ],
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  final AdminStats stats;
  const _StatsGrid({required this.stats});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _StatCard(label: 'Users', value: '${stats.userCount}',
            icon: Icons.people_outline),
        _StatCard(label: 'Libraries', value: '${stats.libraryCount}',
            icon: Icons.library_books_outlined),
        _StatCard(label: 'Media Items', value: '${stats.mediaCount}',
            icon: Icons.collections_bookmark_outlined),
        _StatCard(label: 'Page Cache', value: stats.cacheSizeLabel,
            icon: Icons.storage_outlined),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _StatCard(
      {required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 160,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon,
                  size: 28,
                  color: Theme.of(context).colorScheme.primary),
              const SizedBox(height: 12),
              Text(value,
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(label,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color:
                          Theme.of(context).colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClearCacheButton extends ConsumerStatefulWidget {
  final String sourceId;
  final VoidCallback onCleared;
  const _ClearCacheButton({required this.sourceId, required this.onCleared});

  @override
  ConsumerState<_ClearCacheButton> createState() => _ClearCacheButtonState();
}

class _ClearCacheButtonState extends ConsumerState<_ClearCacheButton> {
  bool _clearing = false;

  Future<void> _clear() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Clear page cache?'),
        content: const Text(
            'All extracted pages will be deleted and re-generated on next access.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Clear cache')),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _clearing = true);
    try {
      final client = ref.read(_sourceClientProvider(widget.sourceId));
      final freed = await AdminApi(client).clearCache();
      widget.onCleared();
      if (mounted) {
        final mb = (freed / (1024 * 1024)).toStringAsFixed(1);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Cache cleared — $mb MB freed.')),
        );
      }
    } catch (e) {
      if (mounted) _showError(context, e);
    } finally {
      if (mounted) setState(() => _clearing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: _clearing ? null : _clear,
      style: OutlinedButton.styleFrom(
          foregroundColor: Theme.of(context).colorScheme.error,
          side: BorderSide(color: Theme.of(context).colorScheme.error)),
      icon: _clearing
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.delete_sweep_outlined),
      label: const Text('Clear Page Cache'),
    );
  }
}

// ── APIs tab ──────────────────────────────────────────────────────────────

class _ApisTab extends ConsumerStatefulWidget {
  final String sourceId;
  const _ApisTab({required this.sourceId});

  @override
  ConsumerState<_ApisTab> createState() => _ApisTabState();
}

class _ApisTabState extends ConsumerState<_ApisTab> {
  final _malCtrl = TextEditingController();
  final _cvCtrl = TextEditingController();
  bool _obscureMal = true;
  bool _obscureCv = true;
  bool _saving = false;
  bool _loading = true;
  bool _malKeySet = false;
  bool _cvKeySet = false;
  String? _error;
  String? _success;

  @override
  void initState() {
    super.initState();
    _loadConfig();
  }

  @override
  void dispose() {
    _malCtrl.dispose();
    _cvCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadConfig() async {
    try {
      final client = ref.read(_sourceClientProvider(widget.sourceId));
      final config = await MetadataApi(client).getConfig();
      if (mounted) {
        setState(() {
          _malKeySet = config.malKeySet;
          _cvKeySet = config.comicvineKeySet;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) { setState(() => _loading = false); }
    }
  }

  Future<void> _save() async {
    final mal = _malCtrl.text.trim();
    final cv = _cvCtrl.text.trim();
    if (mal.isEmpty && cv.isEmpty) {
      setState(() => _error = 'Enter at least one API key.');
      return;
    }
    setState(() { _saving = true; _error = null; _success = null; });
    try {
      final client = ref.read(_sourceClientProvider(widget.sourceId));
      await MetadataApi(client).saveConfig(
        malClientId: mal.isEmpty ? null : mal,
        comicvineApiKey: cv.isEmpty ? null : cv,
      );
      if (mounted) {
        setState(() {
          _saving = false;
          if (mal.isNotEmpty) { _malKeySet = true; _malCtrl.clear(); }
          if (cv.isNotEmpty) { _cvKeySet = true; _cvCtrl.clear(); }
          _success = 'API keys saved.';
        });
      }
    } catch (e) {
      if (mounted) setState(() { _saving = false; _error = _apiError(e); });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Metadata API Keys',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'API keys are stored securely on the server and only used for '
              'scraping manga metadata. AniList works without a key.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 24),
            if (_error != null) ...[
              _ErrorText(_error!),
              const SizedBox(height: 16),
            ],
            if (_success != null) ...[
              _SuccessText(_success!),
              const SizedBox(height: 16),
            ],

            // ── ComicVine ─────────────────────────────────────────────────
            Row(
              children: [
                const Icon(Icons.menu_book_outlined, size: 20),
                const SizedBox(width: 8),
                Text('ComicVine',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(width: 8),
                if (_cvKeySet)
                  const Chip(
                    label: Text('Key set'),
                    avatar: Icon(Icons.check_circle,
                        size: 14, color: Colors.green),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Used for comic metadata. Register at comicvine.gamespot.com/api to get an API key. '
              'Rate limit: 200 requests/resource/hour.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _cvCtrl,
              obscureText: _obscureCv,
              decoration: InputDecoration(
                labelText: _cvKeySet
                    ? 'New ComicVine API Key (leave blank to keep current)'
                    : 'ComicVine API Key',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                      _obscureCv ? Icons.visibility_off : Icons.visibility),
                  onPressed: () =>
                      setState(() => _obscureCv = !_obscureCv),
                ),
              ),
              onSubmitted: (_) => _save(),
            ),

            const SizedBox(height: 24),
            const Divider(),
            const SizedBox(height: 16),

            // ── MAL ──────────────────────────────────────────────────────
            Row(
              children: [
                const Icon(Icons.public, size: 20),
                const SizedBox(width: 8),
                Text('MyAnimeList',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(width: 8),
                if (_malKeySet)
                  const Chip(
                    label: Text('Key set'),
                    avatar: Icon(Icons.check_circle,
                        size: 14, color: Colors.green),
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Used for manga metadata. Register at myanimelist.net/apiconfig to obtain a Client ID.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _malCtrl,
              obscureText: _obscureMal,
              decoration: InputDecoration(
                labelText: _malKeySet
                    ? 'New MAL Client ID (leave blank to keep current)'
                    : 'MAL Client ID',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                      _obscureMal ? Icons.visibility_off : Icons.visibility),
                  onPressed: () =>
                      setState(() => _obscureMal = !_obscureMal),
                ),
              ),
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.save_outlined),
              label: const Text('Save API Keys'),
            ),

            const SizedBox(height: 32),
            const Divider(),
            const SizedBox(height: 16),

            // ── AniList ──────────────────────────────────────────────────
            Row(
              children: [
                const Icon(Icons.public, size: 20),
                const SizedBox(width: 8),
                Text('AniList',
                    style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(width: 8),
                const Chip(
                  label: Text('No key needed'),
                  avatar: Icon(Icons.check_circle,
                      size: 14, color: Colors.green),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'AniList public GraphQL API is available without authentication. '
              'Rekindle enforces a 30-request/minute rate limit to stay within AniList\'s burst limit.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared helpers ────────────────────────────────────────────────────────

List<Widget> _dialogActions(
  BuildContext context,
  bool saving,
  VoidCallback onSave, {
  String label = 'Add',
}) =>
    [
      TextButton(
          onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
      FilledButton(
        onPressed: saving ? null : onSave,
        child: saving
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2))
            : Text(label),
      ),
    ];

String _apiError(Object e) {
  if (e is DioException) {
    final msg = e.response?.data?['error'];
    if (msg is String) return msg;
    final status = e.response?.statusCode;
    if (status == 409) return 'Username already taken.';
    if (status == 403) return 'Forbidden.';
    if (status == 404) return 'Not found.';
  }
  return e.toString();
}

void _showError(BuildContext context, Object e) {
  ScaffoldMessenger.of(context)
      .showSnackBar(SnackBar(content: Text(_apiError(e))));
}

class _ErrorText extends StatelessWidget {
  final String message;
  const _ErrorText(this.message);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(message,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onErrorContainer)),
      );
}

class _SuccessText extends StatelessWidget {
  final String message;
  const _SuccessText(this.message);

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(message,
            style: TextStyle(
                color: Theme.of(context).colorScheme.onPrimaryContainer)),
      );
}
