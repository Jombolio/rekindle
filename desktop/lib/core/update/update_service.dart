import 'dart:io';

import 'package:dio/dio.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'semver.dart';

/// Checks the project's releases for a newer desktop client and applies the
/// update.
///
/// Releases come from Gitea, with GitHub as a fallback used only when Gitea
/// can't be reached, the same order as the server's --update. Detection reads
/// the public release list (no auth, no manifest) and picks the highest
/// version, optionally including pre-releases. Applying is platform-specific:
/// Windows downloads and launches the Inno Setup installer; Linux opens the
/// release download for the user to replace the bundle.
class UpdateService {
  /// Release lists to try, in order. Gitea and GitHub return the fields
  /// [ReleaseInfo] reads under the same names.
  static const sources = <UpdateSource>[
    UpdateSource('Gitea',
        'https://git.jombo.uk/api/v1/repos/Jombo/rekindle/releases?limit=50'),
    UpdateSource('GitHub',
        'https://api.github.com/repos/Jombolio/rekindle/releases?per_page=50'),
  ];

  final Dio _dio;
  final List<UpdateSource> _sources;

  UpdateService({Dio? dio, List<UpdateSource> sources = sources})
      : _sources = sources,
        _dio = dio ??
            Dio(BaseOptions(
              connectTimeout: const Duration(seconds: 15),
              receiveTimeout: const Duration(seconds: 30),
              headers: {'Accept': 'application/json'},
            ));

  /// Checks for a newer release. With [includePreReleases], betas and release
  /// candidates count too. Never throws; failures return an error result.
  ///
  /// The next source is tried only when one can't be reached or answers with
  /// something unreadable; a source with nothing newer is an answer.
  Future<UpdateCheckResult> check({bool includePreReleases = false}) async {
    final current = await currentVersion();
    final failures = <String>[];

    for (final source in _sources) {
      final List<ReleaseInfo> releases;
      try {
        final resp = await _dio.get<List<dynamic>>(source.releasesApi);
        releases = (resp.data ?? const [])
            .whereType<Map<String, dynamic>>()
            .map(ReleaseInfo.fromJson)
            .toList();
      } on DioException catch (e) {
        failures.add('${source.name}: ${_friendlyDioError(e)}');
        continue;
      } catch (e) {
        // An unreadable answer (e.g. a maintenance page instead of JSON).
        failures.add('${source.name}: unexpected response');
        continue;
      }

      final newest =
          selectNewest(releases, includePreReleases: includePreReleases);
      return UpdateCheckResult(
        status: newest != null && isNewer(newest.version!, current)
            ? UpdateStatus.updateAvailable
            : UpdateStatus.upToDate,
        currentVersion: current,
        release: newest,
        source: source.name,
        usedFallback: failures.isNotEmpty,
      );
    }

    return UpdateCheckResult.error(current,
        'Could not check for updates (${failures.join('; ')}). Check your internet connection.');
  }

  /// The highest-versioned published release, or null if there is none. Picks
  /// by version rather than date, so a late patch to an old line can't hide a
  /// newer release. Drafts and unversioned tags are always skipped; without
  /// [includePreReleases], so are pre-releases, flagged or by version.
  static ReleaseInfo? selectNewest(Iterable<ReleaseInfo> releases,
      {required bool includePreReleases}) {
    ReleaseInfo? best;
    for (final r in releases) {
      final v = r.semVersion;
      if (r.isDraft || v == null) continue;
      if (!includePreReleases && (r.isPreRelease || v.isPreRelease)) continue;
      if (best == null || v > best.semVersion!) best = r;
    }
    return best;
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

  /// A short reason for one source's failure, e.g. "unreachable".
  static String _friendlyDioError(DioException e) => switch (e.type) {
        DioExceptionType.connectionTimeout ||
        DioExceptionType.receiveTimeout ||
        DioExceptionType.sendTimeout =>
          'timed out',
        DioExceptionType.connectionError => 'unreachable',
        _ => e.response?.statusCode != null
            ? 'HTTP ${e.response!.statusCode}'
            : 'request failed',
      };

  /// True when [candidate] is a strictly higher semver than [current], so a
  /// pre-release user is never "updated" back to an older stable release.
  /// An unparseable [current] counts as 0.0.0, so any release is newer.
  static bool isNewer(String candidate, String current) {
    final a = SemVersion.tryParse(candidate);
    if (a == null) return false;
    final b = SemVersion.tryParse(current) ?? const SemVersion(0, 0, 0);
    return a > b;
  }
}

enum UpdateStatus { upToDate, updateAvailable, error }

/// A release list to check, e.g. Gitea's or GitHub's.
class UpdateSource {
  final String name;
  final String releasesApi;

  const UpdateSource(this.name, this.releasesApi);
}

class UpdateCheckResult {
  final UpdateStatus status;
  final String currentVersion;

  /// The newest eligible release, or null when the source has none.
  final ReleaseInfo? release;
  final String? error;

  /// Which source answered, e.g. "Gitea".
  final String? source;

  /// True when an earlier source couldn't be reached.
  final bool usedFallback;

  const UpdateCheckResult({
    required this.status,
    required this.currentVersion,
    this.release,
    this.error,
    this.source,
    this.usedFallback = false,
  });

  factory UpdateCheckResult.error(String current, String message) =>
      UpdateCheckResult(
        status: UpdateStatus.error,
        currentVersion: current,
        error: message,
      );
}

class ReleaseInfo {
  /// The parsed version, or null when neither tag nor name holds one.
  final SemVersion? semVersion;
  final String tagName;
  final String name;
  final String notes;
  final String htmlUrl;
  final bool isPreRelease;
  final bool isDraft;
  final List<ReleaseAsset> assets;

  const ReleaseInfo({
    required this.semVersion,
    required this.tagName,
    required this.name,
    required this.notes,
    required this.htmlUrl,
    required this.assets,
    this.isPreRelease = false,
    this.isDraft = false,
  });

  /// Normalized "X.Y.Z" or "X.Y.Z-pre", or null when no version was found.
  String? get version => semVersion?.toString();

  factory ReleaseInfo.fromJson(Map<String, dynamic> j) {
    final tag = (j['tag_name'] as String?) ?? '';
    final name = (j['name'] as String?) ?? '';
    final assets = (j['assets'] as List<dynamic>? ?? [])
        .whereType<Map<String, dynamic>>()
        .map(ReleaseAsset.fromJson)
        .toList();
    return ReleaseInfo(
      // Prefer the tag ("v1.5.0-beta.1"), fall back to the release name.
      semVersion: SemVersion.tryParse(tag) ?? _fromName(name),
      tagName: tag,
      name: name,
      notes: (j['body'] as String?) ?? '',
      htmlUrl: (j['html_url'] as String?) ?? '',
      isPreRelease: (j['prerelease'] as bool?) ?? false,
      isDraft: (j['draft'] as bool?) ?? false,
      assets: assets,
    );
  }

  /// "Rekindle v1.5.0-beta.1" → 1.5.0-beta.1.
  static SemVersion? _fromName(String name) {
    final m = RegExp(r'v?\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?').firstMatch(name);
    return SemVersion.tryParse(m?.group(0));
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
