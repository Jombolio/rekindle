import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/read_aloud/voices.dart';
import '../../providers/read_aloud_provider.dart';

/// The Read aloud setting: downloading the voice, and choosing one.
class ReadAloudSettings extends ConsumerWidget {
  const ReadAloudSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final pack = ref.watch(voicePackProvider);
    final notifier = ref.read(voicePackProvider.notifier);
    final voice = ref.watch(readAloudVoiceProvider);
    final muted = theme.textTheme.bodySmall
        ?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    final String detail;
    final Widget action;
    if (pack.checking) {
      detail = 'Checking for the voice…';
      action = const SizedBox.shrink();
    } else if (pack.downloading) {
      detail = 'Downloading the voice… '
          '${(pack.progress! * 100).round()}%';
      action = TextButton(onPressed: notifier.cancel, child: const Text('Cancel'));
    } else if (pack.installed) {
      detail = 'Reads books aloud on this computer, with a natural voice. '
          'Press play in a book\'s top bar.';
      action = TextButton(
        onPressed: () => _confirmDelete(context, notifier),
        child: const Text('Remove voice'),
      );
    } else {
      detail = 'Reads books aloud on this computer, with a natural voice. '
          'The voice is a one-off download of about '
          '${VoiceStore.approximateBytes ~/ (1024 * 1024)} MB, and then works '
          'offline.';
      action = FilledButton.tonal(
          onPressed: notifier.download, child: const Text('Download'));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Read aloud', style: theme.textTheme.bodyLarge),
                  const SizedBox(height: 4),
                  Text(detail, style: muted),
                ],
              ),
            ),
            const SizedBox(width: 16),
            action,
          ],
        ),
        if (pack.downloading) ...[
          const SizedBox(height: 12),
          LinearProgressIndicator(value: pack.progress),
        ],
        if (pack.error != null) ...[
          const SizedBox(height: 8),
          Text(pack.error!,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.error)),
        ],
        if (pack.installed) ...[
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: Text('Voice', style: theme.textTheme.bodyMedium)),
              DropdownButton<String>(
                value: voice.id,
                items: [
                  for (final v in kokoroVoices)
                    DropdownMenuItem(value: v.id, child: Text(v.label)),
                ],
                onChanged: (id) {
                  if (id != null) {
                    ref
                        .read(readAloudVoiceProvider.notifier)
                        .select(voiceById(id));
                  }
                },
              ),
            ],
          ),
        ],
      ],
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, VoicePackNotifier notifier) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove the voice?'),
        content: const Text(
            'Books can\'t be read aloud until it is downloaded again.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Keep')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Remove')),
        ],
      ),
    );
    if (yes == true) await notifier.delete();
  }
}
