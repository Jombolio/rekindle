import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/api/api_client.dart';
import '../core/api/libraries_api.dart';
import '../core/models/library.dart';
import '../core/models/server_source.dart';
import '../providers/auth_provider.dart';
import '../providers/library_provider.dart';
import '../providers/sources_provider.dart';
import 'widgets/error_view.dart';
import 'widgets/scan_progress_sheet.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sources = ref.watch(sourcesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rekindle'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            tooltip: 'Add Server',
            onPressed: () => context.push('/source/add'),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => context.push('/settings'),
          ),
        ],
      ),
      body: sources.isEmpty
          ? _EmptyState(onAdd: () => context.push('/source/add'))
          : ListView.builder(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: sources.length,
              itemBuilder: (_, i) => _SourceSection(source: sources[i]),
            ),
    );
  }
}

// ── Per-source section ──────────────────────────────────────────────────────

class _SourceSection extends ConsumerWidget {
  final ServerSource source;
  const _SourceSection({required this.source});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authAsync = ref.watch(sourceAuthProvider(source.id));
    final librariesState = ref.watch(sourceLibraryProvider(source.id));

    final auth = authAsync.valueOrNull;
    final isAdmin = auth is AuthAuthenticated && auth.isAdmin;
    final username = auth is AuthAuthenticated ? auth.username : null;

    Widget body;
    if (authAsync.isLoading) {
      body = const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    } else if (auth is! AuthAuthenticated) {
      body = _SignInPrompt(sourceId: source.id);
    } else {
      body = librariesState.when(
        loading: () => const Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Padding(
          padding: const EdgeInsets.all(16),
          child: ErrorView(
            message: e.toString(),
            onRetry: () =>
                ref.read(sourceLibraryProvider(source.id).notifier).refresh(),
          ),
        ),
        data: (libs) => libs.isEmpty
            ? _EmptyLibraries(
                isAdmin: isAdmin,
                onAdd: () => _showLibraryDialog(context, ref, source.id),
              )
            : _LibraryList(
                libraries: libs,
                sourceId: source.id,
                isAdmin: isAdmin,
                username: username,
                ref: ref,
              ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Source header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 8, 4),
          child: Row(
            children: [
              const Icon(Icons.dns_outlined, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  source.name,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              if (isAdmin)
                IconButton(
                  icon: const Icon(Icons.add, size: 20),
                  tooltip: 'Add Library',
                  visualDensity: VisualDensity.compact,
                  onPressed: () =>
                      _showLibraryDialog(context, ref, source.id),
                ),
              _SourceMenu(source: source, isAdmin: isAdmin),
            ],
          ),
        ),
        const Divider(height: 1, indent: 16, endIndent: 16),
        body,
      ],
    );
  }

  Future<void> _showLibraryDialog(
    BuildContext context,
    WidgetRef ref,
    String sourceId, [
    Library? existing,
  ]) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _LibraryDialog(
        ref: ref,
        sourceId: sourceId,
        existing: existing,
      ),
    );
  }
}

// ── Source menu (edit name / sign out / remove) ─────────────────────────────

class _SourceMenu extends ConsumerWidget {
  final ServerSource source;
  final bool isAdmin;
  const _SourceMenu({required this.source, required this.isAdmin});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      icon: const Icon(Icons.more_vert, size: 20),
      tooltip: 'Source options',
      onSelected: (action) => _onAction(context, ref, action),
      itemBuilder: (_) => [
        if (isAdmin)
          const PopupMenuItem(
            value: 'admin',
            child: ListTile(
              leading: Icon(Icons.admin_panel_settings_outlined),
              title: Text('Admin Panel'),
              contentPadding: EdgeInsets.zero,
              dense: true,
            ),
          ),
        const PopupMenuItem(value: 'refresh', child: Text('Refresh')),
        const PopupMenuItem(value: 'rename', child: Text('Rename')),
        if (source.token != null)
          const PopupMenuItem(value: 'signout', child: Text('Sign out'))
        else
          const PopupMenuItem(value: 'signin', child: Text('Sign in')),
        const PopupMenuItem(value: 'remove', child: Text('Remove')),
      ],
    );
  }

  Future<void> _onAction(
      BuildContext context, WidgetRef ref, String action) async {
    final notifier = ref.read(sourcesProvider.notifier);
    switch (action) {
      case 'admin':
        if (context.mounted) context.push('/admin/${source.id}');
      case 'refresh':
        ref.read(sourceLibraryProvider(source.id).notifier).refresh();
      case 'rename':
        await _showRenameDialog(context, ref);
      case 'signout':
        await notifier.clearToken(source.id);
      case 'signin':
        if (context.mounted) context.push('/source/add');
      case 'remove':
        final confirm = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Remove server?'),
            content: Text(
                'Remove "${source.name}" from Rekindle? Your data on the server is not affected.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Remove'),
              ),
            ],
          ),
        );
        if (confirm == true) await notifier.remove(source.id);
    }
  }

  Future<void> _showRenameDialog(BuildContext context, WidgetRef ref) async {
    final ctrl = TextEditingController(text: source.name);
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Rename server'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'Display name',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = ctrl.text.trim();
              if (name.isNotEmpty) {
                ref.read(sourcesProvider.notifier).updateName(source.id, name);
              }
              Navigator.pop(context);
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    ctrl.dispose();
  }
}

// ── Sign-in prompt for sources without a token ──────────────────────────────

class _SignInPrompt extends StatelessWidget {
  final String sourceId;
  const _SignInPrompt({required this.sourceId});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: Row(
        children: [
          Icon(Icons.lock_outline,
              size: 20,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Not signed in.',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ),
          TextButton(
            onPressed: () => context.push('/source/add'),
            child: const Text('Sign in'),
          ),
        ],
      ),
    );
  }
}

// ── Library list within a source section ────────────────────────────────────

class _LibraryList extends StatelessWidget {
  final List<Library> libraries;
  final String sourceId;
  final bool isAdmin;
  final String? username;
  final WidgetRef ref;

  const _LibraryList({
    required this.libraries,
    required this.sourceId,
    required this.isAdmin,
    required this.username,
    required this.ref,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: libraries.map((lib) {
        return ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          leading: CircleAvatar(child: Icon(_iconFor(lib.type))),
          title: Text(lib.name),
          subtitle: Text(
            username != null ? '${lib.typeLabel} · $username' : lib.typeLabel,
          ),
          trailing: isAdmin
              ? PopupMenuButton<String>(
                  onSelected: (action) => _onAction(context, action, lib),
                  itemBuilder: (_) => const [
                    PopupMenuItem(value: 'edit', child: Text('Edit')),
                    PopupMenuItem(value: 'scan', child: Text('Scan')),
                    PopupMenuItem(value: 'delete', child: Text('Delete')),
                  ],
                )
              : null,
          onTap: () {
            ref.read(activeSourceIdProvider.notifier).state = sourceId;
            context.push('/libraries/${lib.id}',
                extra: {'name': lib.name, 'type': lib.type});
          },
        );
      }).toList(),
    );
  }

  IconData _iconFor(String type) => switch (type) {
        'manga' => Icons.auto_stories,
        'book' => Icons.book,
        _ => Icons.collections_bookmark,
      };

  Future<void> _onAction(
      BuildContext context, String action, Library lib) async {
    final notifier = ref.read(sourceLibraryProvider(sourceId).notifier);
    if (action == 'edit') {
      await showDialog<void>(
        context: context,
        builder: (_) =>
            _LibraryDialog(ref: ref, sourceId: sourceId, existing: lib),
      );
    } else if (action == 'scan') {
      // Build a source-specific API client for polling scan progress.
      final sources = ref.read(sourcesProvider);
      final source = sources.where((s) => s.id == sourceId).firstOrNull;
      if (source == null) return;
      final api = LibrariesApi(ApiClient(baseUrl: source.baseUrl, token: source.token));

      await notifier.scan(lib.id);

      if (context.mounted) {
        await showModalBottomSheet<void>(
          context: context,
          isDismissible: false,
          enableDrag: false,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          builder: (_) => ScanProgressSheet(
            libraryId: lib.id,
            libraryName: lib.name,
            api: api,
          ),
        );
        // Refresh the library list so new/removed items are reflected.
        await notifier.refresh();
      }
    } else if (action == 'delete') {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Delete library?'),
          content: Text(
              'Remove "${lib.name}" from Rekindle? Media files will not be deleted.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Delete')),
          ],
        ),
      );
      if (confirm == true) await notifier.delete(lib.id);
    }
  }
}

// ── Empty state views ────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyState({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.dns_outlined,
              size: 72,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text('No servers added yet',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text('Add a Rekindle server to get started.',
              style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onAdd,
            icon: const Icon(Icons.add),
            label: const Text('Add Server'),
          ),
        ],
      ),
    );
  }
}

class _EmptyLibraries extends StatelessWidget {
  final bool isAdmin;
  final VoidCallback onAdd;
  const _EmptyLibraries({required this.isAdmin, required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Row(
        children: [
          Icon(Icons.library_books_outlined,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(
            child: Text('No libraries',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          if (isAdmin)
            TextButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add'),
            ),
        ],
      ),
    );
  }
}

// ── Library dialog (add / edit) ──────────────────────────────────────────────

class _LibraryDialog extends StatefulWidget {
  final WidgetRef ref;
  final String sourceId;
  final Library? existing;

  const _LibraryDialog({
    required this.ref,
    required this.sourceId,
    this.existing,
  });

  @override
  State<_LibraryDialog> createState() => _LibraryDialogState();
}

class _LibraryDialogState extends State<_LibraryDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _pathCtrl;
  late String _type;
  bool _saving = false;
  String? _error;

  bool get _isEditing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _pathCtrl = TextEditingController(text: widget.existing?.rootPath ?? '');
    _type = widget.existing?.type ?? 'comic';
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _pathCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_nameCtrl.text.trim().isEmpty || _pathCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Name and path are required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final notifier =
          widget.ref.read(sourceLibraryProvider(widget.sourceId).notifier);
      if (_isEditing) {
        await notifier.updateLibrary(
          widget.existing!.id,
          name: _nameCtrl.text.trim(),
          rootPath: _pathCtrl.text.trim(),
          type: _type,
        );
      } else {
        await notifier.create(
          name: _nameCtrl.text.trim(),
          rootPath: _pathCtrl.text.trim(),
          type: _type,
        );
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      setState(() {
        _saving = false;
        _error = _errorMessage(e);
      });
    }
  }

  static String _errorMessage(Object e) {
    if (e is DioException) {
      final msg = e.response?.data?['error'];
      if (msg is String) return msg;
    }
    return e.toString();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(_isEditing ? 'Edit Library' : 'Add Library'),
      content: SizedBox(
        width: 400,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_error != null) ...[
              Text(_error!,
                  style: TextStyle(
                      color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 12),
            ],
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                  labelText: 'Library Name', border: OutlineInputBorder()),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _pathCtrl,
              decoration: const InputDecoration(
                  labelText: 'Path on server',
                  hintText: '/media/comics',
                  border: OutlineInputBorder()),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _type,
              decoration: const InputDecoration(
                  labelText: 'Type', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'comic', child: Text('Comics')),
                DropdownMenuItem(value: 'manga', child: Text('Manga')),
                DropdownMenuItem(value: 'book', child: Text('Books')),
              ],
              onChanged: (v) => setState(() => _type = v!),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : Text(_isEditing ? 'Save' : 'Add'),
        ),
      ],
    );
  }
}
