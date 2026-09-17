import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/discord/discord_activity.dart';
import '../core/discord/discord_ipc.dart';
import '../core/storage/prefs.dart';
import '../core/update/update_service.dart';
import '../providers/discord_presence_provider.dart';
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

    // Capture the root navigator up front so the progress dialog can be closed
    // even if the screen unmounts mid-download.
    final rootNav = Navigator.of(context, rootNavigator: true);

    String? path;
    Object? downloadError;
    try {
      path = await service.downloadAsset(
        installer,
        onProgress: (p) => progress.value = p,
      );
    } catch (e) {
      downloadError = e;
    }

    // Close the progress dialog exactly once, mounted or not.
    rootNav.pop();
    progress.dispose();
    if (!mounted) return;

    if (path == null) {
      _snack('Download failed: $downloadError');
      return;
    }

    // Launch the installer and quit so it can replace the running files (the
    // Inno Setup installer closes and relaunches the app itself). Kept out of
    // the dialog-pop path so a launch failure cannot double-pop the navigator.
    try {
      await service.launchInstaller(path);
      await Future<void>.delayed(const Duration(milliseconds: 400));
      exit(0);
    } catch (e) {
      if (mounted) _snack('Could not start the installer: $e');
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

          const SizedBox(height: 24),

          // ── Reader ──────────────────────────────────────────────────────
          const _SectionHeader('Reader'),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Confirm chapter change',
                                style: theme.textTheme.bodyLarge),
                            const SizedBox(height: 4),
                            Text(
                              'Turning past the last or first page needs a '
                              'second press, so a stray input cannot leave the '
                              'chapter by itself.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 16),
                      Switch(
                        value: settings.confirmChapterChange,
                        onChanged: (v) => ref
                            .read(settingsProvider.notifier)
                            .setConfirmChapterChange(confirm: v),
                      ),
                    ],
                  ),
                  if (settings.confirmChapterChange) ...[
                    const Divider(height: 32),
                    Row(
                      children: [
                        Expanded(
                          child: Text('Confirmation window',
                              style: theme.textTheme.bodyLarge),
                        ),
                        Text(
                          _formatConfirmWindow(settings.chapterConfirmWindow),
                          style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.primary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'How long the second press stays accepted.',
                      style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant),
                    ),
                    Slider(
                      value: settings.chapterConfirmWindow.inMilliseconds
                          .clamp(kMinChapterConfirmMs, kMaxChapterConfirmMs)
                          .toDouble(),
                      min: kMinChapterConfirmMs.toDouble(),
                      max: kMaxChapterConfirmMs.toDouble(),
                      // 250 ms steps across the range.
                      divisions:
                          (kMaxChapterConfirmMs - kMinChapterConfirmMs) ~/ 250,
                      label: _formatConfirmWindow(
                          Duration(milliseconds: settings
                              .chapterConfirmWindow.inMilliseconds)),
                      onChanged: (v) => ref
                          .read(settingsProvider.notifier)
                          .setChapterConfirmWindow(
                              Duration(milliseconds: v.round())),
                    ),
                  ],
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

            if (DiscordIpcClient.isSupported) ...[
              const SizedBox(height: 24),

              // ── Discord ───────────────────────────────────────────────────
              const _SectionHeader('Discord'),
              _DiscordPresenceCard(settings: settings.discord),
            ],

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

/// "750 ms" below a second, "1.5 s" above — the slider steps in 250 ms, so one
/// decimal is always enough.
String _formatConfirmWindow(Duration d) {
  final ms = d.inMilliseconds;
  if (ms < 1000) return '$ms ms';
  final seconds = ms / 1000;
  final text = seconds == seconds.roundToDouble()
      ? seconds.toStringAsFixed(0)
      : seconds.toStringAsFixed(1);
  return '$text s';
}

class _DiscordPresenceCard extends ConsumerWidget {
  final DiscordPresenceSettings settings;
  const _DiscordPresenceCard({required this.settings});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);
    final available = discordPresenceAvailable;
    final active = available && settings.enabled;

    void save(DiscordPresenceSettings next) =>
        ref.read(settingsProvider.notifier).setDiscordPresence(next);

    Widget option({
      required String title,
      required String subtitle,
      required bool value,
      required DiscordPresenceSettings Function(bool) apply,
    }) =>
        SwitchListTile(
          title: Text(title),
          subtitle: Text(subtitle),
          value: value,
          onChanged: active ? (v) => save(apply(v)) : null,
        );

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SwitchListTile(
            title: const Text('Share reading status'),
            subtitle: Text(available
                ? 'Show what you are reading on your Discord profile. '
                    'Requires the Discord desktop app to be running.'
                : 'Discord status is not configured in this build.'),
            value: active,
            onChanged: available
                ? (v) => save(settings.copyWith(enabled: v))
                : null,
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Title shown', style: theme.textTheme.bodyLarge),
                const SizedBox(height: 4),
                Text(
                  'Which name to share for the item you have open.',
                  style: muted,
                ),
                const SizedBox(height: 12),
                SegmentedButton<DiscordTitleMode>(
                  segments: const [
                    ButtonSegment(
                      value: DiscordTitleMode.folderAndFile,
                      label: Text('Folder & file'),
                    ),
                    ButtonSegment(
                      value: DiscordTitleMode.folder,
                      label: Text('Folder'),
                    ),
                    ButtonSegment(
                      value: DiscordTitleMode.file,
                      label: Text('File'),
                    ),
                    ButtonSegment(
                      value: DiscordTitleMode.hidden,
                      icon: Icon(Icons.visibility_off_outlined),
                      label: Text('Hidden'),
                    ),
                  ],
                  selected: {settings.titleMode},
                  onSelectionChanged: active
                      ? (sel) => save(settings.copyWith(titleMode: sel.first))
                      : null,
                ),
              ],
            ),
          ),
          option(
            title: 'Show page',
            subtitle: 'e.g. "Page 12 of 200", or the chapter for EPUBs.',
            value: settings.showPage,
            apply: (v) => settings.copyWith(showPage: v),
          ),
          option(
            title: 'Show time elapsed',
            subtitle: 'How long you have been reading the current series.',
            value: settings.showElapsed,
            apply: (v) => settings.copyWith(showElapsed: v),
          ),
          option(
            title: 'Show while browsing',
            subtitle: 'Keep a "Browsing the library" status when no reader '
                'is open.',
            value: settings.showWhileBrowsing,
            apply: (v) => settings.copyWith(showWhileBrowsing: v),
          ),
          if (active)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              child: _DiscordPreview(settings: settings),
            ),
        ],
      ),
    );
  }
}

/// A sample of the status using the current options.
class _DiscordPreview extends StatelessWidget {
  final DiscordPresenceSettings settings;
  const _DiscordPreview({required this.settings});

  static const _sample = NowReading(
    mediaId: 'preview',
    kind: ReadingKind.comic,
    folderName: 'Absolute Batman',
    fileName: 'Absolute Batman 001',
    position: 11,
    total: 32,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final activity = buildDiscordActivity(
      settings: settings,
      reading: _sample,
      startedAtMillis: settings.showElapsed ? 0 : null,
    );
    if (activity == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('PREVIEW',
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 6),
          Text('Playing Rekindle',
              style: theme.textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600)),
          Text(activity['details'] as String),
          if (activity['state'] != null) Text(activity['state'] as String),
          if (activity['timestamps'] != null)
            Text('12:34 elapsed',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
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
