import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/settings_provider.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  late final TextEditingController _dirCtrl;
  String _defaultDirHint = '';

  @override
  void initState() {
    super.initState();
    final current = ref.read(settingsProvider).downloadDirectory;
    _dirCtrl = TextEditingController(text: current);
    _loadDefaultHint();
  }

  Future<void> _loadDefaultHint() async {
    final path = await defaultDownloadDirPath();
    if (mounted) setState(() => _defaultDirHint = path);
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
          _SectionHeader('Appearance'),
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

          // ── Downloads ───────────────────────────────────────────────────
          _SectionHeader('Downloads'),
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
