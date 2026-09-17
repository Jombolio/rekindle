import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../core/discord/discord_activity.dart';
import '../core/storage/prefs.dart';

class SettingsState {
  final ThemeMode themeMode;
  final String downloadDirectory; // empty = use platform default
  final DiscordPresenceSettings discord;

  /// Require a second input to leave the current chapter.
  final bool confirmChapterChange;

  /// How long an armed chapter-change confirmation stays open.
  final Duration chapterConfirmWindow;

  const SettingsState({
    required this.themeMode,
    required this.downloadDirectory,
    required this.confirmChapterChange,
    required this.chapterConfirmWindow,
    this.discord = const DiscordPresenceSettings(),
  });

  SettingsState copyWith({
    ThemeMode? themeMode,
    String? downloadDirectory,
    bool? confirmChapterChange,
    Duration? chapterConfirmWindow,
    DiscordPresenceSettings? discord,
  }) =>
      SettingsState(
        themeMode: themeMode ?? this.themeMode,
        downloadDirectory: downloadDirectory ?? this.downloadDirectory,
        confirmChapterChange: confirmChapterChange ?? this.confirmChapterChange,
        chapterConfirmWindow: chapterConfirmWindow ?? this.chapterConfirmWindow,
        discord: discord ?? this.discord,
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
    final prefs = Prefs.instance;
    return SettingsState(
      themeMode: mode,
      downloadDirectory: prefs.downloadDirectory,
      confirmChapterChange: prefs.confirmChapterChange,
      chapterConfirmWindow: Duration(
        milliseconds: _clampConfirmMs(prefs.chapterConfirmMs),
      ),
      discord: DiscordPresenceSettings(
        enabled: prefs.discordEnabled,
        titleMode: DiscordTitleMode.parse(prefs.discordTitleMode),
        showPage: prefs.discordShowPage,
        showElapsed: prefs.discordShowElapsed,
        showWhileBrowsing: prefs.discordShowWhileBrowsing,
      ),
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

  Future<void> setConfirmChapterChange({required bool confirm}) async {
    await Prefs.instance.setConfirmChapterChange(confirm: confirm);
    state = state.copyWith(confirmChapterChange: confirm);
  }

  Future<void> setChapterConfirmWindow(Duration window) async {
    final ms = _clampConfirmMs(window.inMilliseconds);
    await Prefs.instance.setChapterConfirmMs(ms);
    state = state.copyWith(chapterConfirmWindow: Duration(milliseconds: ms));
  }

  Future<void> setDiscordPresence(DiscordPresenceSettings discord) async {
    state = state.copyWith(discord: discord);
    await Prefs.instance.setDiscordPresence(
      enabled: discord.enabled,
      titleMode: discord.titleMode.name,
      showPage: discord.showPage,
      showElapsed: discord.showElapsed,
      showWhileBrowsing: discord.showWhileBrowsing,
    );
  }
}

int _clampConfirmMs(int ms) =>
    ms.clamp(kMinChapterConfirmMs, kMaxChapterConfirmMs);

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
  final dir = Directory(p.join(base.path, 'Rekindle'));
  await dir.create(recursive: true);
  return dir;
}

/// The human-readable default path shown as hint when no custom dir is set.
Future<String> defaultDownloadDirPath() async {
  final base = await _platformDownloadsBase();
  return p.join(base.path, 'Rekindle');
}

/// Returns the base directory for default downloads.
/// Windows and Android always use app-private Documents so no special
/// filesystem permissions are required.
Future<Directory> _platformDownloadsBase() async {
  if (Platform.isWindows || Platform.isAndroid) {
    return getApplicationDocumentsDirectory();
  }
  try {
    final dir = await getDownloadsDirectory();
    if (dir != null) return dir;
  } catch (_) {}
  return getApplicationDocumentsDirectory();
}
