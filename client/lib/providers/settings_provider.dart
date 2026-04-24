import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/storage/prefs.dart';

class SettingsState {
  final ThemeMode themeMode;
  final String downloadDirectory; // empty = use platform default

  const SettingsState({
    required this.themeMode,
    required this.downloadDirectory,
  });

  SettingsState copyWith({ThemeMode? themeMode, String? downloadDirectory}) =>
      SettingsState(
        themeMode: themeMode ?? this.themeMode,
        downloadDirectory: downloadDirectory ?? this.downloadDirectory,
      );
}

class SettingsNotifier extends Notifier<SettingsState> {
  @override
  SettingsState build() {
    final saved = Prefs.instance.themeMode;
    final mode = switch (saved) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    return SettingsState(
      themeMode: mode,
      downloadDirectory: Prefs.instance.downloadDirectory,
    );
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    await Prefs.instance.setThemeMode(mode.name);
    state = state.copyWith(themeMode: mode);
  }

  Future<void> setDownloadDirectory(String path) async {
    await Prefs.instance.setDownloadDirectory(path.trim());
    state = state.copyWith(downloadDirectory: path.trim());
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, SettingsState>(
  SettingsNotifier.new,
);

/// Resolves the effective download base directory: user's pref or platform default.
Future<Directory> resolveDownloadDir() async {
  final custom = Prefs.instance.downloadDirectory;
  if (custom.isNotEmpty) {
    final dir = Directory(custom);
    await dir.create(recursive: true);
    return dir;
  }

  final base = await _platformDownloadsBase();
  final dir = Directory(p.join(base.path, 'Rekindle Downloads'));
  await dir.create(recursive: true);
  return dir;
}

/// The human-readable default path shown as hint when no custom dir is set.
Future<String> defaultDownloadDirPath() async {
  final base = await _platformDownloadsBase();
  return p.join(base.path, 'Rekindle Downloads');
}

/// Returns the platform Downloads folder (Windows/macOS), falling back to
/// Documents on platforms where a dedicated Downloads folder doesn't exist.
Future<Directory> _platformDownloadsBase() async {
  try {
    final dir = await getDownloadsDirectory();
    if (dir != null) return dir;
  } catch (_) {}
  return getApplicationDocumentsDirectory();
}
