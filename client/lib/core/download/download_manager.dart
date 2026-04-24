import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:dio/dio.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../api/api_client.dart';
import '../utils/natural_sort.dart';
import 'download_state.dart';

typedef ProgressCallback = void Function(DownloadState state);

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
    final localPath = relativePath.isNotEmpty
        ? '${base.path}/$relativePath'
        : '${base.path}/$mediaId.$format';

    // Ensure parent directories exist
    await File(localPath).parent.create(recursive: true);

    await _upsertDownload(mediaId, format, title, DownloadStatus.downloading, 0, null);
    onProgress(DownloadState(status: DownloadStatus.downloading));

    try {
      await _client.dio.download(
        'api/media/$mediaId/download',
        localPath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total <= 0) return;
          onProgress(DownloadState(
            status: DownloadStatus.downloading,
            progress: received / total,
          ));
        },
      );
    } catch (e) {
      await _upsertDownload(mediaId, format, title, DownloadStatus.failed, 0, null);
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
    if (manifest.existsSync()) {
      return extractDir.path;
    }

    final bytes = File(localPath).readAsBytesSync();
    final archive = ZipDecoder().decodeBytes(bytes);

    final imageExtensions = {'.jpg', '.jpeg', '.png', '.webp', '.gif', '.bmp'};
    final imageEntries = archive.files
        .where((f) =>
            !f.isFile == false &&
            imageExtensions.contains(_ext(f.name).toLowerCase()))
        .toList()
      ..sort((a, b) => naturalCompare(a.name, b.name));

    final pageNames = <String>[];
    for (var i = 0; i < imageEntries.length; i++) {
      final entry = imageEntries[i];
      final ext = _ext(entry.name).toLowerCase();
      final pageName = '${i.toString().padLeft(5, '0')}$ext';
      final pageFile = File('${extractDir.path}/$pageName');
      pageFile.writeAsBytesSync(entry.content as List<int>);
      pageNames.add(pageName);
    }

    manifest.writeAsStringSync(pageNames.join('\n'));

    onProgress(DownloadState(
      status: DownloadStatus.complete,
      progress: 1.0,
      localPath: localPath,
      extractedDir: extractDir.path,
    ));

    return extractDir.path;
  }

  /// Loads previously extracted page paths, or null if not extracted yet.
  Future<List<String>?> loadExtractedPages(String mediaId) async {
    final dir = await _extractedDir(mediaId);
    final manifest = File('${dir.path}/manifest.txt');
    if (!manifest.existsSync()) return null;
    return manifest
        .readAsStringSync()
        .trim()
        .split('\n')
        .map((name) => '${dir.path}/$name')
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

    return DownloadState(status: status);
  }

  Future<void> delete(String mediaId) async {
    final path = await localPath(mediaId);
    if (path != null) {
      final file = File(path);
      if (file.existsSync()) file.deleteSync();
    }

    final extractDir = await _extractedDir(mediaId);
    if (extractDir.existsSync()) extractDir.deleteSync(recursive: true);

    await _db.delete('downloads', where: 'media_id = ?', whereArgs: [mediaId]);
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
    final base = await getApplicationCacheDirectory();
    final dir = Directory('${base.path}/rekindle/extracted/$mediaId');
    await dir.create(recursive: true);
    return dir;
  }

  static String _ext(String filename) {
    final dot = filename.lastIndexOf('.');
    return dot == -1 ? '' : filename.substring(dot);
  }
}
