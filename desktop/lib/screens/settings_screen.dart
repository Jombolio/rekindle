import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/update/update_service.dart';
import '../providers/settings_provider.dart';
import '../providers/update_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _dirCtrl;
  String _defaultDirHint = '';
  String? _appVersion;
  bool _checking = false;

  @override
  void initState() {
    super.initState();
    final current = ref.read(settingsProvider).downloadDirectory;
    _dirCtrl = TextEditingController(text: current);
    _loadDefaultHint();
    _loadVersion();
  }

  Future<void> _loadDefaultHint() async {
    final path = await defaultDownloadDirPath();
    if (mounted) setState(() => _defaultDirHint = path);
  }

  Future<void> _loadVersion() async {
    final v = await ref.read(updateServiceProvider).currentVersion();
    if (mounted) setState(() => _appVersion = v);
  }

  // ── Update check ──────────────────────────────────────────────────────────

  Future<void> _checkForUpdates() async {
    setState(() => _checking = true);
    final result = await ref.read(updateServiceProvider).check();
    if (!mounted) return;
    setState(() => _checking = false);

    switch (result.status) {
      case UpdateStatus.upToDate:
        _snack('You are on the latest version (${result.currentVersion}).');
      case UpdateStatus.error:
        _snack(result.error ?? 'Could not check for updates.');
      case UpdateStatus.updateAvailable:
        await _showUpdateDialog(result.release!, result.currentVersion);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _showUpdateDialog(ReleaseInfo release, String current) async {
    final service = ref.read(updateServiceProvider);
    final installer =
        Platform.isWindows ? service.windowsInstaller(release) : null;
    final canInstall = installer != null;
    final title = release.name.isNotEmpty
        ? release.name
        : 'Version ${release.version}';

    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Update available: $title'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'You have $current. The latest is ${release.version}.',
                style: Theme.of(ctx).textTheme.bodyMedium,
              ),
              if (release.notes.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Flexible(
                  child: SingleChildScrollView(
                    child: Text(
                      release.notes.trim(),
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Later'),
          ),
          TextButton(
            onPressed: () => service.openInBrowser(release.htmlUrl),
            child: const Text('View on GitHub'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              if (canInstall) {
                _downloadAndInstall(installer);
              } else {
                // Linux (or Windows with no installer asset): let the user grab
                // the download from the release page.
                service.openInBrowser(release.htmlUrl);
              }
            },
            child: Text(canInstall ? 'Download and install' : 'Open download'),
          ),
        ],
      ),
    );
  }

  Future<void> _downloadAndInstall(ReleaseAsset installer) async {
    final service = ref.read(updateServiceProvider);
    final progress = ValueNotifier<double>(0);

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Downloading update'),
        content: SizedBox(
          width: 360,
          child: ValueListenableBuilder<double>(
            valueListenable: progress,
            builder: (_, v, __) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: v > 0 ? v : null),
                const SizedBox(height: 12),
                Text('${(v * 100).toStringAsFixed(0)}%'),
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final path = await service.downloadAsset(
        installer,
        onProgress: (p) => progress.value = p,
      );
      if (!mounted) return;
      Navigator.of(context).pop(); // close the progress dialog
      // Launch the installer, then quit so it can replace the running files.
      // The Inno Setup installer closes and relaunches the app itself.
      await service.launchInstaller(path);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      exit(0);
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        _snack('Download failed: $e');
      }
      progress.dispose();
    }
  }

  @override
  void dispose() {
    _dirCtrl.dispose();
    super.dispose();
  }

  void _saveDownloadDir() {
    ref
        .read(settingsProvider.notifier)
        .setDownloadDirectory(_dirCtrl.text);
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // ── Appearance ──────────────────────────────────────────────────
          const _SectionHeader('Appearance'),
          Card(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Theme',
                        style: theme.textTheme.bodyLarge),
                  ),
                  SegmentedButton<ThemeMode>(
                    segments: const [
                      ButtonSegment(
                        value: ThemeMode.system,
                        icon: Icon(Icons.brightness_auto),
                        label: Text('System'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.light,
                        icon: Icon(Icons.light_mode),
                        label: Text('Light'),
                      ),
                      ButtonSegment(
                        value: ThemeMode.dark,
                        icon: Icon(Icons.dark_mode),
                        label: Text('Dark'),
                      ),
                    ],
                    selected: {settings.themeMode},
                    onSelectionChanged: (sel) =>
                        ref.read(settingsProvider.notifier).setThemeMode(sel.first),
                  ),
                ],
              ),
            ),
          ),

          if (!Platform.isAndroid) ...[
            const SizedBox(height: 24),

            // ── Downloads ─────────────────────────────────────────────────
            const _SectionHeader('Downloads'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Download directory',
                        style: theme.textTheme.bodyLarge),
                    const SizedBox(height: 4),
                    Text(
                      'Files are saved preserving the server\'s folder structure.',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _dirCtrl,
                            decoration: InputDecoration(
                              border: const OutlineInputBorder(),
                              hintText: _defaultDirHint.isNotEmpty
                                  ? _defaultDirHint
                                  : 'Loading default…',
                              hintStyle: TextStyle(
                                  color: theme.colorScheme.onSurfaceVariant),
                              prefixIcon: const Icon(Icons.folder_outlined),
                              suffixIcon: _dirCtrl.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear),
                                      tooltip: 'Reset to default',
                                      onPressed: () {
                                        _dirCtrl.clear();
                                        ref
                                            .read(settingsProvider.notifier)
                                            .setDownloadDirectory('');
                                      },
                                    )
                                  : null,
                            ),
                            onSubmitted: (_) => _saveDownloadDir(),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonal(
                          onPressed: _saveDownloadDir,
                          child: const Text('Save'),
                        ),
                      ],
                    ),
                    if (_defaultDirHint.isNotEmpty &&
                        _dirCtrl.text.isEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        'Default: $_defaultDirHint',
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
            ),

            const SizedBox(height: 24),

            // ── Updates ───────────────────────────────────────────────────
            const _SectionHeader('Updates'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Rekindle desktop',
                              style: theme.textTheme.bodyLarge),
                          const SizedBox(height: 4),
                          Text(
                            _appVersion != null
                                ? 'Version $_appVersion'
                                : 'Version …',
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.tonalIcon(
                      onPressed: _checking ? null : _checkForUpdates,
                      icon: _checking
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.system_update_alt),
                      label: Text(
                          _checking ? 'Checking…' : 'Check for updates'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.primary,
            ),
      ),
    );
  }
}
