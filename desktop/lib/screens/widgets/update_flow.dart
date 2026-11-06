import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../core/storage/prefs.dart';
import '../../core/update/app_updater.dart';
import '../../core/update/install_kind.dart';
import '../../core/update/update_service.dart';
import '../../providers/update_provider.dart';
import 'release_notes.dart';

enum _Choice { later, skip, install, download }

/// The "Update available" dialog and what follows it, shared by the Settings
/// button and the startup check. Installs in-app where the install allows it
/// (Windows, AppImage, portable zips) and restarts; otherwise downloads the
/// right file or explains how this install updates. Never sends the user to a
/// release page.
class UpdateFlow {
  static Future<void> offer(
    BuildContext context,
    WidgetRef ref,
    UpdateCheckResult result, {
    bool automatic = false,
  }) async {
    final release = result.release;
    if (release == null) return;
    final target = detectInstall();

    final choice = await showDialog<_Choice>(
      context: context,
      builder: (ctx) => _UpdateDialog(
        release: release,
        current: result.currentVersion,
        target: target,
        automatic: automatic,
      ),
    );
    if (!context.mounted) return;

    switch (choice) {
      case _Choice.install:
        await _install(context, ref, release, target);
      case _Choice.download:
        await _downloadForManualInstall(context, ref, release, target);
      case _Choice.skip:
        await Prefs.instance.setSkippedUpdateVersion(release.version!);
      case _Choice.later || null:
        break;
    }
  }

  static Future<void> _install(BuildContext context, WidgetRef ref,
      ReleaseInfo release, InstallTarget target) async {
    final updater = AppUpdater(ref.read(updateServiceProvider));
    final path = await _withProgress(
        context,
        'Downloading update',
        (onProgress) =>
            updater.download(release, target, onProgress: onProgress));
    if (path == null || !context.mounted) return;

    final installed = await _withProgress(context, 'Installing update', (_) async {
      await updater.install(path, target);
      return true;
    });
    if (installed == true) {
      // The new version has been started (or the installer is running); give
      // it a moment to launch before this one exits.
      await Future<void>.delayed(const Duration(milliseconds: 400));
      exit(0);
    }
  }

  /// Flatpak: download and verify the bundle into Downloads, then show the
  /// one command that installs it.
  static Future<void> _downloadForManualInstall(BuildContext context,
      WidgetRef ref, ReleaseInfo release, InstallTarget target) async {
    final updater = AppUpdater(ref.read(updateServiceProvider));
    final saved = await _withProgress(context, 'Downloading update',
        (onProgress) async {
      final tmp =
          await updater.download(release, target, onProgress: onProgress);
      final dir = await getDownloadsDirectory() ??
          Directory(Platform.environment['HOME'] ?? Directory.systemTemp.path);
      final dest = p.join(dir.path, target.kind.assetName!);
      await File(tmp).copy(dest);
      return dest;
    });
    if (saved == null || !context.mounted) return;

    final command = 'flatpak install --user "$saved"';
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Update downloaded'),
        content: SizedBox(
          width: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Close Rekindle, then run this in a terminal to '
                  'install it:'),
              const SizedBox(height: 12),
              SelectableText(command,
                  style: const TextStyle(fontFamily: 'monospace')),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: command)),
            child: const Text('Copy command'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  /// Runs [work] behind a progress dialog. Returns its result, or null after
  /// showing what went wrong.
  static Future<T?> _withProgress<T>(
    BuildContext context,
    String title,
    Future<T> Function(void Function(double) onProgress) work,
  ) async {
    final progress = ValueNotifier<double>(0);
    final nav = Navigator.of(context, rootNavigator: true);
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: SizedBox(
          width: 360,
          child: ValueListenableBuilder<double>(
            valueListenable: progress,
            builder: (_, v, __) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(value: v > 0 ? v : null),
                if (v > 0) ...[
                  const SizedBox(height: 12),
                  Text('${(v * 100).toStringAsFixed(0)}%'),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    try {
      final result = await work((v) => progress.value = v);
      nav.pop();
      return result;
    } catch (e) {
      nav.pop();
      if (nav.mounted) {
        await showDialog<void>(
          context: nav.context,
          builder: (ctx) => AlertDialog(
            title: const Text('Update failed'),
            content: Text('$e\n\nNothing was changed.'),
            actions: [
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      return null;
    } finally {
      progress.dispose();
    }
  }
}

class _UpdateDialog extends StatelessWidget {
  const _UpdateDialog({
    required this.release,
    required this.current,
    required this.target,
    required this.automatic,
  });

  final ReleaseInfo release;
  final String current;
  final InstallTarget target;
  final bool automatic;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pre = release.semVersion?.isPreRelease == true ? ' (pre-release)' : '';
    final how = switch (target.kind) {
      _ when target.kind.installsInApp =>
        'Rekindle will download it, install it and restart. Your settings, '
            'servers and downloads are kept.',
      InstallKind.flatpak =>
        "A Flatpak can't update itself. Rekindle can download the new bundle "
            'to your Downloads folder and show the command that installs it.',
      InstallKind.packageManaged =>
        'This copy is managed by your package manager. Update it there, '
            'e.g. yay -Syu rekindle-bin on Arch.',
      InstallKind.readOnlyFolder =>
        "Rekindle can't write to the folder it's in, so it can't update itself. "
            'Download this version from the release page, or move this copy to '
            'a folder you can write to.',
      _ => "This is a development build, so it isn't updated in place.",
    };

    return AlertDialog(
      title: Text('Update available: ${release.version}'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('You have $current. The newest is ${release.version}$pre.',
                style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            Text(how, style: theme.textTheme.bodySmall),
            if (release.notes.trim().isNotEmpty) ...[
              const Divider(height: 24),
              Flexible(
                child: SingleChildScrollView(
                  child: ReleaseNotes(release.notes,
                      textStyle: theme.textTheme.bodySmall),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (automatic)
          TextButton(
            onPressed: () => Navigator.of(context).pop(_Choice.skip),
            child: const Text('Skip this version'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(_Choice.later),
          child: Text(target.kind.installsInApp ||
                  target.kind == InstallKind.flatpak
              ? 'Later'
              : 'OK'),
        ),
        if (target.kind.installsInApp)
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_Choice.install),
            child: const Text('Update now'),
          )
        else if (target.kind == InstallKind.flatpak)
          FilledButton(
            onPressed: () => Navigator.of(context).pop(_Choice.download),
            child: const Text('Download'),
          ),
      ],
    );
  }
}
