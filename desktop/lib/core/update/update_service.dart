import 'dart:io';

import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Checks GitHub Releases for a newer desktop client and applies the update.
///
/// Detection reads the public Releases API directly (no auth, no manifest), so
/// it tracks the repo's GitHub releases with nothing extra to host. Applying is
/// platform-specific: Windows downloads and launches the Inno Setup installer;
/// Linux opens the release download for the user to replace the bundle.
class UpdateService {
  static const _repo = 'Jombolio/rekindle';
  static const _latestApi =
      'https://api.github.com/repos/$_repo/releases/latest';

  final Dio _dio;

  UpdateService({Dio? dio})
      : _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              headers: {'Accept': 'application/vnd.github+json'},
            ));

  /// Checks for a newer release. Never throws; failures return an error result.
  Future<UpdateCheckResult> check() async {
    final current = await currentVersion();
    try {
      final resp = await _dio.get<Map<String, dynamic>>(_latestApi);
      final data = resp.data;
      if (data == null) {
        return UpdateCheckResult.error(current, 'Empty response from GitHub.');
      }
      final release = ReleaseInfo.fromJson(data);
      if (release.version == null) {
        return UpdateCheckResult.error(
            current, 'Could not read the latest version.');
      }
      final isNewer = _isNewer(release.version!, current);
      return UpdateCheckResult(
        status: isNewer ? UpdateStatus.updateAvailable : UpdateStatus.upToDate,
        currentVersion: current,
        release: release,
      );
    } on DioException catch (e) {
      return UpdateCheckResult.error(current, _friendlyDioError(e));
    } catch (e) {
      return UpdateCheckResult.error(current, e.toString());
    }
  }

  /// Downloads [asset] to a temp file and returns its path.
  Future<String> downloadAsset(
    ReleaseAsset asset, {
    void Function(double progress)? onProgress,
  }) async {
    final dir = await Directory.systemTemp.createTemp('rekindle_update_');
    final dest = '${dir.path}/${asset.name}';
    await _dio.download(
      asset.downloadUrl,
      dest,
      options: Options(headers: {'Accept': 'application/octet-stream'}),
      onReceiveProgress: (received, total) {
        if (total > 0) onProgress?.call(received / total);
      },
    );
    return dest;
  }

  /// Launches the downloaded Windows installer detached and returns. The caller
  /// should exit the app so the installer can replace files.
  Future<void> launchInstaller(String path) async {
    if (Platform.isWindows) {
      // The installer's manifest requires elevation (PrivilegesRequired=admin),
      // so CreateProcess — what Process.start uses — fails with
      // ERROR_ELEVATION_REQUIRED. cmd's `start` goes through ShellExecute,
      // which shows the UAC prompt instead.
      await Process.start(
        'cmd',
        ['/c', 'start', '', path],
        mode: ProcessStartMode.detached,
      );
    } else {
      await Process.start(path, const [], mode: ProcessStartMode.detached);
    }
  }

  /// Opens [url] in the user's default browser. Best-effort; never throws.
  Future<void> openInBrowser(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {
      // Nothing more we can do; the dialog also shows the URL.
    }
  }

  /// The Windows installer asset for this release, if present.
  ReleaseAsset? windowsInstaller(ReleaseInfo release) {
    for (final a in release.assets) {
      final n = a.name.toLowerCase();
      if (n.endsWith('setup.exe')) return a;
    }
    return null;
  }

  /// The running app's version, e.g. "1.2.1". Falls back to "0.0.0".
  Future<String> currentVersion() async {
    try {
      final info = await PackageInfo.fromPlatform();
      return info.version;
    } catch (_) {
      return '0.0.0';
    }
  }

  static String _friendlyDioError(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.connectionError) {
      return 'Could not reach GitHub. Check your internet connection.';
    }
    final code = e.response?.statusCode;
    if (code == 403) return 'GitHub rate limit reached. Try again later.';
    if (code == 404) return 'No published release was found.';
    return 'Update check failed${code != null ? ' (HTTP $code)' : ''}.';
  }

  /// Returns true when [candidate] is a strictly higher semver than [current].
  /// Parsing is lenient; unparseable inputs compare as 0.0.0.
  static bool _isNewer(String candidate, String current) {
    final a = _parseVersion(candidate);
    final b = _parseVersion(current);
    for (var i = 0; i < 3; i++) {
      if (a[i] != b[i]) return a[i] > b[i];
    }
    return false;
  }

  static List<int> _parseVersion(String raw) {
    final match = RegExp(r'(\d+)\.(\d+)\.(\d+)').firstMatch(raw);
    if (match == null) return [0, 0, 0];
    return [
      int.tryParse(match.group(1)!) ?? 0,
      int.tryParse(match.group(2)!) ?? 0,
      int.tryParse(match.group(3)!) ?? 0,
    ];
  }
}

enum UpdateStatus { upToDate, updateAvailable, error }

class UpdateCheckResult {
  final UpdateStatus status;
  final String currentVersion;
  final ReleaseInfo? release;
  final String? error;

  const UpdateCheckResult({
    required this.status,
    required this.currentVersion,
    this.release,
    this.error,
  });

  factory UpdateCheckResult.error(String current, String message) =>
      UpdateCheckResult(
        status: UpdateStatus.error,
        currentVersion: current,
        error: message,
      );
}

class ReleaseInfo {
  /// Normalized "X.Y.Z", or null when no version could be parsed.
  final String? version;
  final String tagName;
  final String name;
  final String notes;
  final String htmlUrl;
  final List<ReleaseAsset> assets;

  const ReleaseInfo({
    required this.version,
    required this.tagName,
    required this.name,
    required this.notes,
    required this.htmlUrl,
    required this.assets,
  });

  factory ReleaseInfo.fromJson(Map<String, dynamic> j) {
    final tag = (j['tag_name'] as String?) ?? '';
    final name = (j['name'] as String?) ?? '';
    // Prefer the tag, fall back to the release name ("Rekindle vX.Y.Z").
    final version = _extract(tag) ?? _extract(name);
    final assets = (j['assets'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(ReleaseAsset.fromJson)
        .toList();
    return ReleaseInfo(
      version: version,
      tagName: tag,
      name: name,
      notes: (j['body'] as String?) ?? '',
      htmlUrl: (j['html_url'] as String?) ?? '',
      assets: assets,
    );
  }

  static String? _extract(String raw) {
    final m = RegExp(r'(\d+\.\d+\.\d+)').firstMatch(raw);
    return m?.group(1);
  }
}

class ReleaseAsset {
  final String name;
  final String downloadUrl;
  final int size;

  const ReleaseAsset({
    required this.name,
    required this.downloadUrl,
    required this.size,
  });

  factory ReleaseAsset.fromJson(Map<String, dynamic> j) => ReleaseAsset(
        name: (j['name'] as String?) ?? '',
        downloadUrl: (j['browser_download_url'] as String?) ?? '',
        size: (j['size'] as int?) ?? 0,
      );
}
