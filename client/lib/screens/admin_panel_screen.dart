import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/admin_api.dart';
import '../core/api/api_client.dart';
import '../core/api/libraries_api.dart';
import '../core/models/library.dart';
import '../providers/sources_provider.dart';

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
              Tab(icon: Icon(Icons.upload_file_outlined), text: 'Upload'),
              Tab(icon: Icon(Icons.monitor_heart_outlined), text: 'System'),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _UsersTab(sourceId: sourceId),
            _UploadTab(sourceId: sourceId),
            _SystemTab(sourceId: sourceId),
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
              value: _level,
              decoration: const InputDecoration(
                  labelText: 'Permission level', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 1, child: Text('1 — Read-only')),
                DropdownMenuItem(value: 2, child: Text('2 — Download')),
                DropdownMenuItem(value: 3, child: Text('3 — Manage Media')),
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
              value: _level,
              decoration: const InputDecoration(
                  labelText: 'Permission level', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 1, child: Text('1 — Read-only')),
                DropdownMenuItem(value: 2, child: Text('2 — Download')),
                DropdownMenuItem(value: 3, child: Text('3 — Manage Media')),
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

// ── Upload tab ────────────────────────────────────────────────────────────

class _UploadTab extends ConsumerStatefulWidget {
  final String sourceId;
  const _UploadTab({required this.sourceId});

  @override
  ConsumerState<_UploadTab> createState() => _UploadTabState();
}

class _UploadTabState extends ConsumerState<_UploadTab> {
  Library? _selectedLibrary;
  String? _filePath;
  String? _fileName;
  double? _progress;
  String? _error;
  String? _success;
  bool _uploading = false;

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['cbz', 'cbr', 'pdf', 'epub', 'mobi'],
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
            librariesState.when(
              loading: () => const CircularProgressIndicator(),
              error: (e, _) => _ErrorText(e.toString()),
              data: (libs) => DropdownButtonFormField<Library>(
                value: _selectedLibrary,
                decoration: const InputDecoration(
                    labelText: 'Target Library',
                    border: OutlineInputBorder()),
                items: libs
                    .map((l) => DropdownMenuItem(value: l, child: Text(l.name)))
                    .toList(),
                onChanged: (v) => setState(() => _selectedLibrary = v),
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _uploading ? null : _pickFile,
              icon: const Icon(Icons.folder_open_outlined),
              label: Text(_fileName ?? 'Choose file…'),
            ),
            if (_fileName != null) ...[
              const SizedBox(height: 8),
              Text(_fileName!,
                  style: Theme.of(context).textTheme.bodySmall,
                  overflow: TextOverflow.ellipsis),
            ],
            const SizedBox(height: 24),
            if (_progress != null) ...[
              LinearProgressIndicator(value: _progress),
              const SizedBox(height: 8),
              Text('${((_progress ?? 0) * 100).toStringAsFixed(1)}%',
                  textAlign: TextAlign.center),
              const SizedBox(height: 16),
            ],
            FilledButton.icon(
              onPressed: (_uploading ||
                      _selectedLibrary == null ||
                      _filePath == null)
                  ? null
                  : _upload,
              icon: _uploading
                  ? const SizedBox(
                      width: 18,
                      height: 18,
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
          SnackBar(content: Text('Cache cleared — ${mb} MB freed.')),
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
