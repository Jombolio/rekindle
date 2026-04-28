import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/media_api.dart';
import '../core/download/download_manager.dart';
import '../core/download/download_state.dart';
import '../core/db/local_db_provider.dart';
import '../core/models/media.dart';
import 'auth_provider.dart';
import 'settings_provider.dart';

class DownloadNotifier extends FamilyNotifier<DownloadState, String> {
  CancelToken? _cancelToken;

  @override
  DownloadState build(String mediaId) {
    ref.onDispose(() => _cancelToken?.cancel('disposed'));
    _restore(mediaId);
    return const DownloadState.idle();
  }

  Future<void> _restore(String mediaId) async {
    final manager = await _manager();
    final restored = await manager.restore(mediaId);
    state = restored;
  }

  Future<void> download({
    required String mediaId,
    required String format,
    required String title,
    required String relativePath,
  }) async {
    if (state.status == DownloadStatus.downloading ||
        state.status == DownloadStatus.extracting) return;

    _cancelToken = CancelToken();
    final manager = await _manager();

    try {
      final path = await manager.download(
        mediaId: mediaId,
        format: format,
        title: title,
        relativePath: relativePath,
        onProgress: (s) => state = s,
        cancelToken: _cancelToken,
      );

      await manager.extractPages(
        mediaId: mediaId,
        localPath: path,
        onProgress: (s) => state = s,
      );

      // Force any open reader to switch from NetworkImage to local FileImage.
      ref.invalidate(extractedPagesProvider(mediaId));
    } on DioException catch (_) {
      // Cancel: state already idle (set by cancel()).
      // Network error: state already set to failed by manager.
    } catch (e) {
      state = DownloadState(status: DownloadStatus.failed, error: e.toString());
    }
  }

  Future<void> delete(String mediaId) async {
    final manager = await _manager();
    await manager.delete(mediaId);
    state = const DownloadState.idle();
  }

  void cancel() {
    _cancelToken?.cancel('user');
    state = const DownloadState.idle();
    _manager().then((m) => m.delete(arg));
  }

  Future<DownloadManager> _manager() async {
    final client = ref.read(apiClientProvider);
    final db = ref.read(localDbProvider);
    final downloadDir = await resolveDownloadDir();
    return DownloadManager(client, db, downloadBaseDir: downloadDir);
  }
}

final downloadProvider =
    NotifierProviderFamily<DownloadNotifier, DownloadState, String>(
  DownloadNotifier.new,
);

/// Loads the extracted page paths for [mediaId], or null if not extracted.
final extractedPagesProvider =
    FutureProvider.family<List<String>?, String>((ref, mediaId) async {
  final client = ref.read(apiClientProvider);
  final db = ref.read(localDbProvider);
  final downloadDir = await resolveDownloadDir();
  return DownloadManager(client, db, downloadBaseDir: downloadDir)
      .loadExtractedPages(mediaId);
});

// ---------------------------------------------------------------------------
// Folder download — downloads all archives in a directory tree sequentially
// ---------------------------------------------------------------------------

enum FolderDownloadStatus { idle, fetching, downloading, complete, failed }

class FolderDownloadState {
  final FolderDownloadStatus status;
  final int total;
  final int completed;
  final String? error;

  const FolderDownloadState({
    this.status = FolderDownloadStatus.idle,
    this.total = 0,
    this.completed = 0,
    this.error,
  });

  const FolderDownloadState.idle()
      : status = FolderDownloadStatus.idle,
        total = 0,
        completed = 0,
        error = null;

  double get progress => total == 0 ? 0 : completed / total;
}

class FolderDownloadNotifier
    extends FamilyNotifier<FolderDownloadState, String> {
  CancelToken? _cancelToken;
  bool _cancelled = false;

  @override
  FolderDownloadState build(String folderId) {
    ref.onDispose(() => _cancelToken?.cancel('disposed'));
    return const FolderDownloadState.idle();
  }

  Future<void> downloadFolder(String folderId) async {
    if (state.status == FolderDownloadStatus.fetching ||
        state.status == FolderDownloadStatus.downloading) return;

    _cancelled = false;
    state = const FolderDownloadState(status: FolderDownloadStatus.fetching);

    final client = ref.read(apiClientProvider);
    final api = MediaApi(client);

    final archives = <Media>[];
    try {
      await _collectArchives(api, folderId, archives);
    } catch (e) {
      state = FolderDownloadState(
          status: FolderDownloadStatus.failed, error: e.toString());
      return;
    }

    if (_cancelled || archives.isEmpty) {
      state = const FolderDownloadState.idle();
      return;
    }

    state = FolderDownloadState(
      status: FolderDownloadStatus.downloading,
      total: archives.length,
      completed: 0,
    );

    final manager = await _manager();

    for (int i = 0; i < archives.length; i++) {
      if (_cancelled) break;

      final archive = archives[i];
      _cancelToken = CancelToken();

      try {
        final path = await manager.download(
          mediaId: archive.id,
          format: archive.format,
          title: archive.displayTitle,
          relativePath: archive.relativePath,
          onProgress: (_) {},
          cancelToken: _cancelToken,
        );

        if (!_cancelled) {
          await manager.extractPages(
            mediaId: archive.id,
            localPath: path,
            onProgress: (_) {},
          );
          ref.invalidate(extractedPagesProvider(archive.id));
        }
      } on DioException catch (_) {
        if (_cancelled) break;
        // Skip failed items; continue to the next
      } catch (_) {
        if (_cancelled) break;
      }

      if (!_cancelled) {
        state = FolderDownloadState(
          status: FolderDownloadStatus.downloading,
          total: archives.length,
          completed: i + 1,
        );
      }
    }

    state = _cancelled
        ? const FolderDownloadState.idle()
        : FolderDownloadState(
            status: FolderDownloadStatus.complete,
            total: archives.length,
            completed: archives.length,
          );
  }

  void cancel() {
    _cancelled = true;
    _cancelToken?.cancel('user');
    state = const FolderDownloadState.idle();
  }

  Future<void> _collectArchives(
      MediaApi api, String folderId, List<Media> archives) async {
    final items = await api.getChapters(folderId);
    for (final item in items) {
      if (item.isFolder) {
        await _collectArchives(api, item.id, archives);
      } else {
        archives.add(item);
      }
    }
  }

  Future<DownloadManager> _manager() async {
    final client = ref.read(apiClientProvider);
    final db = ref.read(localDbProvider);
    final downloadDir = await resolveDownloadDir();
    return DownloadManager(client, db, downloadBaseDir: downloadDir);
  }
}

final folderDownloadProvider = NotifierProviderFamily<FolderDownloadNotifier,
    FolderDownloadState, String>(
  FolderDownloadNotifier.new,
);
