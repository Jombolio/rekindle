import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/server_source.dart';

/// Bounds for the chapter-change confirmation window. The screen clamps the
/// slider to these and the reader clamps whatever it reads back, so a value
/// written by an older build can never produce an unusable window.
const int kMinChapterConfirmMs = 250;
const int kMaxChapterConfirmMs = 5000;
const int kDefaultChapterConfirmMs = 2000;

/// Thin wrapper around SharedPreferences for typed, named access.
class Prefs {
  Prefs._(this._prefs);

  static late Prefs instance;
  final SharedPreferences _prefs;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    instance = Prefs._(prefs);
  }

  // Multi-source list — auto-migrates from legacy single-server prefs on first read.
  List<ServerSource> get sources {
    final raw = _prefs.getString('sources');
    if (raw != null) {
      try {
        final list = jsonDecode(raw) as List<dynamic>;
        return list
            .map((e) => ServerSource.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        return [];
      }
    }
    // Migrate from legacy single-server prefs.
    final url = _prefs.getString('server_url') ?? '';
    if (url.isEmpty) return [];
    return [
      ServerSource(
        id: 'legacy',
        name: 'Default',
        baseUrl: url,
        token: _prefs.getString('jwt_token'),
      )
    ];
  }

  Future<void> setSources(List<ServerSource> sources) => _prefs.setString(
        'sources',
        jsonEncode(sources.map((s) => s.toJson()).toList()),
      );

  // Legacy single-server prefs — kept for migration path only.
  String get serverUrl => _prefs.getString('server_url') ?? '';
  Future<void> setServerUrl(String url) => _prefs.setString('server_url', url);

  String? get token => _prefs.getString('jwt_token');
  Future<void> setToken(String token) => _prefs.setString('jwt_token', token);
  Future<void> clearToken() => _prefs.remove('jwt_token');

  // Per-series reading direction (key = series name or mediaId)
  bool isRtl(String key) => _prefs.getBool('rtl_$key') ?? false;

  /// Returns null when the user has never explicitly set a direction for [key].
  bool? isRtlExplicit(String key) => _prefs.getBool('rtl_$key');
  Future<void> setRtl(String key, {required bool rtl}) =>
      _prefs.setBool('rtl_$key', rtl);

  // Appearance — 'system' | 'light' | 'dark'
  String get themeMode => _prefs.getString('theme_mode') ?? 'system';
  Future<void> setThemeMode(String mode) =>
      _prefs.setString('theme_mode', mode);

  // Download directory — empty string means use the platform default
  String get downloadDirectory => _prefs.getString('download_directory') ?? '';
  Future<void> setDownloadDirectory(String path) =>
      _prefs.setString('download_directory', path);

  // Double-page spread mode (per-media)
  bool? isDoublePageExplicit(String key) => _prefs.getBool('double_page_$key');
  bool isDoublePage(String key) => isDoublePageExplicit(key) ?? false;
  Future<void> setDoublePage(String key, {required bool doublePage}) =>
      _prefs.setBool('double_page_$key', doublePage);

  // Vertical scroll mode (per-media)
  bool? isScrollModeExplicit(String key) => _prefs.getBool('scroll_mode_$key');
  bool isScrollMode(String key) => isScrollModeExplicit(key) ?? false;
  Future<void> setScrollMode(String key, {required bool scrollMode}) =>
      _prefs.setBool('scroll_mode_$key', scrollMode);

  // Chapter-change confirmation (global).
  // A chapter change sits one input past the last page, so a stray tap at the
  // boundary jumps out of the archive. When on, the first attempt only arms;
  // a second within the window commits it.
  bool get confirmChapterChange =>
      _prefs.getBool('confirm_chapter_change') ?? true;
  Future<void> setConfirmChapterChange({required bool confirm}) =>
      _prefs.setBool('confirm_chapter_change', confirm);

  // How long the armed confirmation stays open, in milliseconds (global).
  int get chapterConfirmMs =>
      _prefs.getInt('chapter_confirm_ms') ?? kDefaultChapterConfirmMs;
  Future<void> setChapterConfirmMs(int ms) =>
      _prefs.setInt('chapter_confirm_ms', ms);

  // Whether selecting a word in a book shows its definition.
  bool get defineOnSelect => _prefs.getBool('define_on_select') ?? true;

  // Whether archive names show their file extension (".cbz"). Off by default.
  bool get comicPageTurns => _prefs.getBool('comic_page_turns') ?? true;
  Future<void> setComicPageTurns(bool enabled) =>
      _prefs.setBool('comic_page_turns', enabled);

  bool get showFileExtensions =>
      _prefs.getBool('show_file_extensions') ?? false;
  Future<void> setShowFileExtensions({required bool show}) =>
      _prefs.setBool('show_file_extensions', show);
  Future<void> setDefineOnSelect({required bool enabled}) =>
      _prefs.setBool('define_on_select', enabled);

  // The font and text size books open with.
  String? get bookFont => _prefs.getString('book_font');
  Future<void> setBookFont(String font) => _prefs.setString('book_font', font);
  double? get bookFontSize => _prefs.getDouble('book_font_size');
  Future<void> setBookFontSize(double size) =>
      _prefs.setDouble('book_font_size', size);

  // The theme books open in.
  String? get bookTheme => _prefs.getString('book_theme');
  Future<void> setBookTheme(String theme) =>
      _prefs.setString('book_theme', theme);

  // Book layout and readability options, as JSON (see ReadingStyle).
  String? get readingStyle => _prefs.getString('reading_style');
  Future<void> setReadingStyle(String json) =>
      _prefs.setString('reading_style', json);

  // Whether "Check for updates" offers pre-releases (betas, release
  // candidates) as well as stable releases. Off by default.
  bool get receivePreReleases =>
      _prefs.getBool('receive_pre_releases') ?? false;
  Future<void> setReceivePreReleases({required bool receive}) =>
      _prefs.setBool('receive_pre_releases', receive);

  // Check for updates when the app starts (at most once a day). On by default.
  bool get autoCheckUpdates => _prefs.getBool('auto_check_updates') ?? true;
  Future<void> setAutoCheckUpdates({required bool enabled}) =>
      _prefs.setBool('auto_check_updates', enabled);

  // When the last automatic check ran, so it runs at most once a day.
  DateTime? get lastUpdateCheck {
    final ms = _prefs.getInt('last_update_check');
    return ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  Future<void> setLastUpdateCheck(DateTime when) =>
      _prefs.setInt('last_update_check', when.millisecondsSinceEpoch);

  // A version the user chose to skip: the automatic check won't offer it
  // again (a manual check still does).
  String? get skippedUpdateVersion =>
      _prefs.getString('skipped_update_version');
  Future<void> setSkippedUpdateVersion(String version) =>
      _prefs.setString('skipped_update_version', version);

  // Double-page spine gap in logical pixels (global)
  double get doublePageGap => _prefs.getDouble('double_page_gap') ?? 0.0;
  Future<void> setDoublePageGap(double gap) =>
      _prefs.setDouble('double_page_gap', gap);

  // Discord Rich Presence (global)
  bool get discordEnabled => _prefs.getBool('discord_enabled') ?? false;
  String? get discordTitleMode => _prefs.getString('discord_title_mode');
  bool get discordShowPage => _prefs.getBool('discord_show_page') ?? true;
  bool get discordShowElapsed => _prefs.getBool('discord_show_elapsed') ?? true;
  bool get discordShowWhileBrowsing =>
      _prefs.getBool('discord_show_browsing') ?? false;

  Future<void> setDiscordPresence({
    required bool enabled,
    required String titleMode,
    required bool showPage,
    required bool showElapsed,
    required bool showWhileBrowsing,
  }) async {
    await _prefs.setBool('discord_enabled', enabled);
    await _prefs.setString('discord_title_mode', titleMode);
    await _prefs.setBool('discord_show_page', showPage);
    await _prefs.setBool('discord_show_elapsed', showElapsed);
    await _prefs.setBool('discord_show_browsing', showWhileBrowsing);
  }

  // Cached auth — used as a fallback when the server is unreachable on restart.
  ({String username, int permissionLevel})? cachedAuth(String sourceId) {
    final username = _prefs.getString('cached_username_$sourceId');
    if (username == null) return null;
    final level = _prefs.getInt('cached_permission_$sourceId') ?? 2;
    return (username: username, permissionLevel: level);
  }

  Future<void> setCachedAuth(
      String sourceId, String username, int permissionLevel) async {
    await _prefs.setString('cached_username_$sourceId', username);
    await _prefs.setInt('cached_permission_$sourceId', permissionLevel);
  }

  Future<void> clearCachedAuth(String sourceId) async {
    await _prefs.remove('cached_username_$sourceId');
    await _prefs.remove('cached_permission_$sourceId');
  }
}
