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
import 'widgets/read_aloud_settings.dart';
import 'widgets/reading_options.dart';
import 'widgets/update_flow.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  final String? category;
  const SettingsScreen({super.key, this.category});

  static const categories = [
    ('Appearance', 'Theme and file names', Icons.palette_outlined),
    (
      'Reader',
      'Chapter navigation and comic page turns',
      Icons.auto_stories_outlined
    ),
    ('Books', 'Typography, layout and reading tools', Icons.menu_book_outlined),
    ('Downloads', 'Where your files are saved', Icons.download_outlined),
    ('Discord', 'Reading activity and privacy', Icons.chat_bubble_outline),
    ('Updates', 'Version, updates and licences', Icons.system_update_alt),
  ];

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
    final result = await ref.read(updateServiceProvider).check(
        includePreReleases: ref.read(settingsProvider).receivePreReleases);
    if (!mounted) return;
    setState(() => _checking = false);

    switch (result.status) {
      case UpdateStatus.upToDate:
        _snack('You are on the latest version (${result.currentVersion}).'
            '${result.usedFallback ? ' Checked ${result.source}, as Gitea could not be reached.' : ''}');
      case UpdateStatus.error:
        _snack(result.error ?? 'Could not check for updates.');
      case UpdateStatus.updateAvailable:
        await UpdateFlow.offer(context, ref, result);
    }
  }

  void _snack(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  void dispose() {
    _dirCtrl.dispose();
    super.dispose();
  }

  void _saveDownloadDir() {
    ref.read(settingsProvider.notifier).setDownloadDirectory(_dirCtrl.text);
    FocusScope.of(context).unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final theme = Theme.of(context);

    if (widget.category == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Settings')),
        body: Center(
            child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 760),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            for (final (title, subtitle, icon) in SettingsScreen.categories)
              if (title != 'Discord' || DiscordIpcClient.isSupported)
                Card(
                    child: ListTile(
                  leading: Icon(icon),
                  title: Text(title),
                  subtitle: Text(subtitle),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () =>
                      Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => SettingsScreen(category: title),
                  )),
                )),
          ]),
        )),
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(widget.category!)),
      body: Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 760),
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: _categoryChildren([
                  // ── Appearance ──────────────────────────────────────────────────
                  const _SectionHeader('Appearance'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child:
                                Text('Theme', style: theme.textTheme.bodyLarge),
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
                            onSelectionChanged: (sel) => ref
                                .read(settingsProvider.notifier)
                                .setThemeMode(sel.first),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 8),
                  Card(
                    child: SwitchListTile(
                      title: const Text('Show file extensions'),
                      subtitle: const Text(
                          'Add ".cbz", ".epub" and so on after the names of archives.'),
                      value: settings.showFileExtensions,
                      onChanged: (v) => ref
                          .read(settingsProvider.notifier)
                          .setShowFileExtensions(show: v),
                    ),
                  ),
                  const SizedBox(height: 24),

                  // ── Reader ──────────────────────────────────────────────────────
                  const _SectionHeader('Reader'),
                  Card(
                      child: SwitchListTile(
                    title: const Text('Comic and manga page turns'),
                    subtitle: const Text(
                        'Turn pages like a book in paged mode. Turn off for sliding pages.'),
                    value: settings.comicPageTurns,
                    onChanged: (value) => ref
                        .read(settingsProvider.notifier)
                        .setComicPageTurns(value),
                  )),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text('Page turn speed',
                                    style: theme.textTheme.bodyLarge),
                              ),
                              Text(
                                _formatPageTurn(settings.pageTurn),
                                style: theme.textTheme.bodyMedium?.copyWith(
                                    color: theme.colorScheme.primary),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'How long a page takes to turn, in comics and in books.',
                            style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant),
                          ),
                          Slider(
                            // Left to right runs fast to slow, as the label says.
                            value: settings.pageTurn.inMilliseconds
                                .clamp(kMinPageTurnMs, kMaxPageTurnMs)
                                .toDouble(),
                            min: kMinPageTurnMs.toDouble(),
                            max: kMaxPageTurnMs.toDouble(),
                            // 100 ms steps across the range.
                            divisions: (kMaxPageTurnMs - kMinPageTurnMs) ~/ 100,
                            label: _formatPageTurn(settings.pageTurn),
                            onChanged: (v) => ref
                                .read(settingsProvider.notifier)
                                .setPageTurn(
                                    Duration(milliseconds: v.round())),
                          ),
                        ],
                      ),
                    ),
                  ),
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
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                              color: theme.colorScheme
                                                  .onSurfaceVariant),
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
                                  _formatConfirmWindow(
                                      settings.chapterConfirmWindow),
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
                              value: settings
                                  .chapterConfirmWindow.inMilliseconds
                                  .clamp(kMinChapterConfirmMs,
                                      kMaxChapterConfirmMs)
                                  .toDouble(),
                              min: kMinChapterConfirmMs.toDouble(),
                              max: kMaxChapterConfirmMs.toDouble(),
                              // 250 ms steps across the range.
                              divisions: (kMaxChapterConfirmMs -
                                      kMinChapterConfirmMs) ~/
                                  250,
                              label: _formatConfirmWindow(Duration(
                                  milliseconds: settings
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

                  // ── Books ──────────────────────────────────────────────────────
                  const SizedBox(height: 24),
                  const _SectionHeader('Books'),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // The same options as the reader's Aa panel.
                          const ReadingOptionsForm(),
                          const Divider(height: 32),
                          Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('Define selected words',
                                        style: theme.textTheme.bodyLarge),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Selecting a word shows its meaning. English only, '
                                      'and works offline.',
                                      style: theme.textTheme.bodySmall
                                          ?.copyWith(
                                              color: theme.colorScheme
                                                  .onSurfaceVariant),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 16),
                              Switch(
                                value: settings.defineOnSelect,
                                onChanged: (v) => ref
                                    .read(settingsProvider.notifier)
                                    .setDefineOnSelect(enabled: v),
                              ),
                            ],
                          ),
                          const Divider(height: 32),
                          const ReadAloudSettings(),
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
                                          color: theme
                                              .colorScheme.onSurfaceVariant),
                                      prefixIcon:
                                          const Icon(Icons.folder_outlined),
                                      suffixIcon: _dirCtrl.text.isNotEmpty
                                          ? IconButton(
                                              icon: const Icon(Icons.clear),
                                              tooltip: 'Reset to default',
                                              onPressed: () {
                                                _dirCtrl.clear();
                                                ref
                                                    .read(settingsProvider
                                                        .notifier)
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
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('Rekindle desktop',
                                          style: theme.textTheme.bodyLarge),
                                      const SizedBox(height: 4),
                                      Text(
                                        _appVersion != null
                                            ? 'Version $_appVersion'
                                            : 'Version …',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                                color: theme.colorScheme
                                                    .onSurfaceVariant),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                FilledButton.tonalIcon(
                                  onPressed:
                                      _checking ? null : _checkForUpdates,
                                  icon: _checking
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        )
                                      : const Icon(Icons.system_update_alt),
                                  label: Text(_checking
                                      ? 'Checking…'
                                      : 'Check for updates'),
                                ),
                              ],
                            ),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: TextButton(
                                // Includes the bundled reading fonts' licences.
                                onPressed: () => showLicensePage(
                                  context: context,
                                  applicationName: 'Rekindle',
                                  applicationVersion: _appVersion,
                                ),
                                child: const Text('Licences'),
                              ),
                            ),
                            const Divider(height: 24),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('Receive pre-releases',
                                          style: theme.textTheme.bodyLarge),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Also offer betas and release candidates when '
                                        'checking for updates. They may be less stable.',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                                color: theme.colorScheme
                                                    .onSurfaceVariant),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Switch(
                                  value: settings.receivePreReleases,
                                  onChanged: (v) => ref
                                      .read(settingsProvider.notifier)
                                      .setReceivePreReleases(receive: v),
                                ),
                              ],
                            ),
                            const Divider(height: 32),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text('Check for updates automatically',
                                          style: theme.textTheme.bodyLarge),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Look for a new version when Rekindle starts, '
                                        'at most once a day, and ask before installing.',
                                        style: theme.textTheme.bodySmall
                                            ?.copyWith(
                                                color: theme.colorScheme
                                                    .onSurfaceVariant),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Switch(
                                  value: settings.autoCheckUpdates,
                                  onChanged: (v) => ref
                                      .read(settingsProvider.notifier)
                                      .setAutoCheckUpdates(enabled: v),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ]),
              ))),
    );
  }

  List<Widget> _categoryChildren(List<Widget> children) {
    final result = <Widget>[];
    var selected = false;
    for (final child in children) {
      if (child is _SectionHeader) {
        selected = child.title == widget.category;
      } else if (selected) {
        result.add(child);
      }
    }
    return result;
  }
}

/// "750 ms" below a second, "1.5 s" above — the slider steps in 250 ms, so one
/// decimal is always enough.
/// A page turn as the reader picks it: how it feels, and how long it takes.
String _formatPageTurn(Duration d) {
  final ms = d.inMilliseconds;
  final feel = switch (ms) {
    <= 300 => 'Very fast',
    <= 500 => 'Fast',
    <= 800 => 'Standard',
    <= 1100 => 'Slow',
    _ => 'Very slow',
  };
  return '$feel · $ms ms';
}

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
            onChanged:
                available ? (v) => save(settings.copyWith(enabled: v)) : null,
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
