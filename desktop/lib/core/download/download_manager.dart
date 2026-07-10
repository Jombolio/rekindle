import 'dart:io';
import 'dart:isolate';

import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../api/api_client.dart';
import '../utils/natural_sort.dart';
import 'download_state.dart';

typedef ProgressCallback = void Function(DownloadState state);

/// A completed download row, used to enumerate the local library offline.
class DownloadRecord {
  final String mediaId;
  final String title;
  final String format;
  final String? localPath;

  const DownloadRecord({
    required this.mediaId,
    required this.title,
    required this.format,
    this.localPath,
  });
}

class DownloadManager {
  final ApiClient _client;
  final Database _db;

  /// Base directory for user-visible downloads. If null, falls back to the
  /// platform documents directory under "Rekindle Downloads/".
  final Directory? downloadBaseDir;

  DownloadManager(this._client, this._db, {this.downloadBaseDir});

  /// Download the raw archive file for [mediaId] to device storage.
  ///
  /// [relativePath] mirrors the server directory structure, e.g.
  /// "Absolute Batman/Chapter1.cbz". When empty, falls back to a flat
  /// "<mediaId>.<format>" filename.
  Future<String> download({
    required String mediaId,
    required String format,
    required String title,
    required String relativePath,
    required ProgressCallback onProgress,
    CancelToken? cancelToken,
  }) async {
    final base = downloadBaseDir ?? await _defaultDownloadsDir();
    // relativePath is server-controlled — a hostile or compromised source could
    // smuggle ../ (or an absolute path) and write outside the downloads dir.
    final fallback = p.join(base.path, '$mediaId.$format');
    final candidate = relativePath.isNotEmpty
        ? p.normalize(p.join(base.path, relativePath))
        : fallback;
    final localPath = p.isWithin(base.path, candidate) ? candidate : fallback;

    // Ensure parent directories exist
    await File(localPath).parent.create(recursive: true);

    // Store path immediately so cancel/delete can clean it up even mid-download.
    await _upsertDownload(mediaId, format, title, DownloadStatus.downloading, 0, localPath);
    onProgress(const DownloadState(status: DownloadStatus.downloading));

    try {
      await _client.dio.download(
        'api/media/$mediaId/download',
        localPath,
        cancelToken: cancelToken,
        // Override the base receiveTimeout — large archives on slow connections
        // can legitimately take many minutes to transfer.
        options: Options(receiveTimeout: const Duration(hours: 2)),
        onReceiveProgress: (received, total) {
          if (total <= 0) return;
          onProgress(DownloadState(
            status: DownloadStatus.downloading,
            progress: received / total,
          ));
        },
      );
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.cancel) {
        // dio already removed the partial file (deleteOnError); drop the row
        // too or the item restores as a phantom "downloading" forever.
        await _db.delete('downloads', where: 'media_id = ?', whereArgs: [mediaId]);
        rethrow;
      }
      await _upsertDownload(mediaId, format, title, DownloadStatus.failed, 0, localPath);
      onProgress(DownloadState(
        status: DownloadStatus.failed,
        error: e.toString(),
      ));
      rethrow;
    }

    await _upsertDownload(mediaId, format, title, DownloadStatus.complete, 1.0, localPath);
    onProgress(DownloadState(
      status: DownloadStatus.complete,
      progress: 1.0,
      localPath: localPath,
    ));

    // Best-effort persistent cover fetch so the Downloads screen shows a
    // thumbnail while offline. Never blocks or fails the download.
    await downloadCover(mediaId);

    return localPath;
  }

  /// Extract a downloaded CBZ/CBR archive to a per-media cache directory.
  /// Returns the extracted directory path.
  Future<String> extractPages({
    required String mediaId,
    required String localPath,
    required ProgressCallback onProgress,
  }) async {
    onProgress(DownloadState(
      status: DownloadStatus.extracting,
      progress: 1.0,
      localPath: localPath,
    ));

    final extractDir = await _extractedDir(mediaId);

    final manifest = File('${extractDir.path}/manifest.txt');
    if (!manifest.existsSync()) {
      final extractDirPath = extractDir.path;
      await Isolate.run(() => _extractArchive(localPath, extractDirPath));
    }

    onProgress(DownloadState(
      status: DownloadStatus.complete,
      progress: 1.0,
      localPath: localPath,
      extractedDir: extractDir.path,
    ));

    return extractDir.path;
  }

  /// Runs in a background isolate — no instance state allowed.
  static void _extractArchive(String archivePath, String extractDirPath) {
    final bytes = File(archivePath).readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);

    const imageExtensions = {'.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp'};
    final imageEntries = archive.files
        .where((f) => f.isFile && imageExtensions.contains(_ext(f.name).toLowerCase()))
        .toList()
      ..sort((a, b) => naturalCompare(a.name, b.name));

    final pageNames = <String>[];
    for (var i = 0; i < imageEntries.length; i++) {
      final entry = imageEntries[i];
      final ext = _ext(entry.name).toLowerCase();
      final pageName = '${i.toString().padLeft(5, '0')}$ext';
      File('$extractDirPath/$pageName').writeAsBytesSync(entry.content as List<int>);
      pageNames.add(pageName);
    }

    // Only write a manifest when extraction produced pages, so an imageless
    // archive isn't cached as a permanent empty result. Temp + rename so a
    // crash mid-write can't leave a truncated manifest that gets trusted.
    if (pageNames.isNotEmpty) {
      final tmp = File('$extractDirPath/manifest.txt.tmp');
      tmp.writeAsStringSync(pageNames.join('\n'));
      tmp.renameSync('$extractDirPath/manifest.txt');
    }
  }

  /// Loads previously extracted page paths, or null if not extracted yet.
  Future<List<String>?> loadExtractedPages(String mediaId) async {
    final dir = await _extractedDir(mediaId);
    final manifest = File('${dir.path}/manifest.txt');
    if (!manifest.existsSync()) return null;
    final names = manifest
        .readAsStringSync()
        .trim()
        .split('\n')
        .where((name) => name.isNotEmpty)
        .toList();
    // An empty manifest would otherwise parse to one bogus '' page path.
    if (names.isEmpty) return null;
    return names.map((name) => '${dir.path}/$name').toList();
  }

  /// Ensures a downloaded ZIP-container comic (CBZ) is extracted to local page
  /// files, extracting on demand if needed, and returns the page paths.
  ///
  /// Returns null when the item is not a completed download, or is a format we
  /// cannot decode on-device offline (CBR/PDF need a decoder we don't bundle;
  /// EPUB is rendered by its own reader). This is the offline-first source of
  /// truth for the reader's page count.
  Future<List<String>?> ensureExtractedPages(String mediaId) async {
    final rows = await _db.query(
      'downloads',
      columns: ['local_path', 'status', 'format'],
      where: 'media_id = ?',
      whereArgs: [mediaId],
    );
    if (rows.isEmpty || rows.first['status'] != 'complete') return null;

    final fmt = (rows.first['format'] as String? ?? '').toLowerCase();
    if (fmt != 'cbz' && fmt != 'zip') return null;

    final existing = await loadExtractedPages(mediaId);
    if (existing != null) return existing;

    final path = rows.first['local_path'] as String?;
    if (path == null) return null;
    try {
      await extractPages(mediaId: mediaId, localPath: path, onProgress: (_) {});
    } catch (_) {
      return null;
    }
    return loadExtractedPages(mediaId);
  }

  /// Lists every completed download for offline browsing (local DB only).
  Future<List<DownloadRecord>> listCompleted() async {
    final rows = await _db.query(
      'downloads',
      where: 'status = ?',
      whereArgs: [DownloadStatus.complete.name],
      orderBy: 'title COLLATE NOCASE',
    );
    return rows
        .map((r) => DownloadRecord(
              mediaId: r['media_id'] as String,
              title: r['title'] as String,
              format: r['format'] as String,
              localPath: r['local_path'] as String?,
            ))
        .toList();
  }

  /// Returns the local file path if this media has been downloaded.
  Future<String?> localPath(String mediaId) async {
    final rows = await _db.query(
      'downloads',
      columns: ['local_path', 'status'],
      where: 'media_id = ?',
      whereArgs: [mediaId],
    );
    if (rows.isEmpty) return null;
    if (rows.first['status'] != 'complete') return null;
    return rows.first['local_path'] as String?;
  }

  /// Restores [DownloadState] from the local DB on app restart.
  Future<DownloadState> restore(String mediaId) async {
    final rows = await _db.query(
      'downloads',
      where: 'media_id = ?',
      whereArgs: [mediaId],
    );
    if (rows.isEmpty) return const DownloadState.idle();

    final row = rows.first;
    final status = DownloadStatus.values.byName(row['status'] as String);
    final path = row['local_path'] as String?;

    if (status == DownloadStatus.complete && path != null) {
      final extractDir = await _extractedDir(mediaId);
      final extracted = File('${extractDir.path}/manifest.txt').existsSync()
          ? extractDir.path
          : null;
      return DownloadState(
        status: DownloadStatus.complete,
        progress: 1.0,
        localPath: path,
        extractedDir: extracted,
      );
    }

    if (status == DownloadStatus.downloading ||
        status == DownloadStatus.extracting) {
      // An in-progress row on restore can only be a leftover from a killed
      // process — report FAILED so the item can be retried instead of showing
      // a phantom spinner forever.
      return const DownloadState(status: DownloadStatus.failed);
    }

    return DownloadState(status: status);
  }

  Future<void> delete(String mediaId) async {
    final rows = await _db.query(
      'downloads',
      columns: ['local_path'],
      where: 'media_id = ?',
      whereArgs: [mediaId],
    );
    if (rows.isNotEmpty) {
      final path = rows.first['local_path'] as String?;
      if (path != null) {
        // Guarded: on Windows deleting a file that an in-flight transfer still
        // has open throws; the DB row removal below must still happen.
        try {
          final file = File(path);
          if (file.existsSync()) file.deleteSync();
        } catch (_) {}
      }
    }

    final extractDir = await _extractedDir(mediaId);
    try {
      if (extractDir.existsSync()) extractDir.deleteSync(recursive: true);
    } catch (_) {}

    try {
      final cover = File(await _coverFilePath(mediaId));
      if (cover.existsSync()) cover.deleteSync();
    } catch (_) {}

    await _db.delete('downloads', where: 'media_id = ?', whereArgs: [mediaId]);
  }

  /// Removes every download from this device: files, extracted pages, covers,
  /// and all DB rows (including folder-download aggregates). Used by purge-all.
  Future<void> deleteAll() async {
    final rows = await _db.query('downloads', columns: ['media_id']);
    for (final r in rows) {
      await delete(r['media_id'] as String);
    }
    await _db.delete('folder_downloads');
  }

  // ── Folder-level persistence ───────────────────────────────────────────

  /// Returns the persisted [FolderDownloadState] for [folderId], or null if
  /// the folder has never been fully downloaded.
  Future<FolderDownloadState?> restoreFolder(String folderId) async {
    final rows = await _db.query(
      'folder_downloads',
      where: 'folder_id = ?',
      whereArgs: [folderId],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    final status =
        FolderDownloadStatus.values.byName(row['status'] as String);
    return FolderDownloadState(
      status: status,
      total: row['total'] as int,
      completed: row['completed'] as int,
    );
  }

  /// Persists a completed folder download so the UI survives app restarts.
  Future<void> saveFolderComplete(
      String folderId, int total, int completed) async {
    await _db.insert(
      'folder_downloads',
      {
        'folder_id': folderId,
        'status': FolderDownloadStatus.complete.name,
        'total': total,
        'completed': completed,
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  /// Returns the subset of [mediaIds] that are already fully downloaded.
  Future<Set<String>> completedMediaIds(Iterable<String> mediaIds) async {
    final ids = mediaIds.toSet();
    if (ids.isEmpty) return {};
    final rows = await _db.query(
      'downloads',
      columns: ['media_id'],
      where: 'status = ?',
      whereArgs: [DownloadStatus.complete.name],
    );
    final allComplete = rows.map((r) => r['media_id'] as String).toSet();
    return allComplete.intersection(ids);
  }

  // ── Private helpers ────────────────────────────────────────────────────

  Future<void> _upsertDownload(
    String mediaId,
    String format,
    String title,
    DownloadStatus status,
    double progress,
    String? path,
  ) =>
      _db.insert(
        'downloads',
        {
          'media_id': mediaId,
          'status': status.name,
          'progress': progress,
          'local_path': path,
          'format': format,
          'title': title,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  static Future<Directory> _defaultDownloadsDir() async {
    Directory? base;
    try {
      base = await getDownloadsDirectory();
    } catch (_) {}
    base ??= await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(base.path, 'Rekindle Downloads'));
    await dir.create(recursive: true);
    return dir;
  }

  Future<Directory> _extractedDir(String mediaId) async {
    // Persistent (support dir, NOT cache) so decoded pages survive OS cache
    // eviction and stay readable offline. Removed only by delete()/deleteAll().
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/rekindle/extracted/$mediaId');
    await dir.create(recursive: true);
    return dir;
  }

  // ── Covers ─────────────────────────────────────────────────────────────

  Future<Directory> _coversDir() async {
    final base = await getApplicationSupportDirectory();
    final dir = Directory('${base.path}/rekindle/covers');
    await dir.create(recursive: true);
    return dir;
  }

  Future<String> _coverFilePath(String mediaId) async =>
      '${(await _coversDir()).path}/$mediaId.jpg';

  /// Returns the persistent local cover path if one has been downloaded.
  Future<String?> localCoverPath(String mediaId) async {
    final path = await _coverFilePath(mediaId);
    return File(path).existsSync() ? path : null;
  }

  /// Best-effort persistent cover download. Skips if already present; swallows
  /// all errors (offline / no cover) so callers can await it unconditionally.
  Future<void> downloadCover(String mediaId) async {
    try {
      final dest = await _coverFilePath(mediaId);
      if (File(dest).existsSync()) return;
      final tmp = '$dest.tmp';
      await _client.dio.download('api/media/$mediaId/cover', tmp);
      await File(tmp).rename(dest);
    } catch (_) {
      // Offline or the server has no cover — leave it to the network fallback.
    }
  }

  static String _ext(String filename) {
    final dot = filename.lastIndexOf('.');
    return dot == -1 ? '' : filename.substring(dot);
  }
}
