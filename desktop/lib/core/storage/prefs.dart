import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/server_source.dart';

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

  // Double-page spine gap in logical pixels (global)
  double get doublePageGap => _prefs.getDouble('double_page_gap') ?? 0.0;
  Future<void> setDoublePageGap(double gap) =>
      _prefs.setDouble('double_page_gap', gap);

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
