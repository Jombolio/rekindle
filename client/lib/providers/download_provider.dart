import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/media_api.dart';
import '../core/download/download_manager.dart';
import '../core/download/download_queue.dart';
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

    // Immediately enter downloading state so the UI responds and double-taps
    // are blocked, even while this task waits its turn in the queue.
    _cancelToken = CancelToken();
    state = const DownloadState(status: DownloadStatus.downloading);

    final manager = await _manager();
    final queue = ref.read(downloadQueueProvider);

    try {
      final path = await queue.enqueue(() => manager.download(
            mediaId: mediaId,
            format: format,
            title: title,
            relativePath: relativePath,
            onProgress: (s) => state = s,
            cancelToken: _cancelToken,
          ));

      // manager.download() already set state to complete with localPath.
      // Run extraction in the background so the button shows the checkmark
      // immediately instead of blocking on CBZ decompression.
      manager
          .extractPages(mediaId: mediaId, localPath: path, onProgress: (_) {})
          .then((_) => ref.invalidate(extractedPagesProvider(mediaId)))
          .catchError((_) {});
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
// Folder download — downloads all archives in a directory tree, skipping any
// that are already fully downloaded.
// ---------------------------------------------------------------------------

/// Thrown inside a queued task when the folder download was cancelled while
/// the task was waiting in the queue (before the HTTP request started).
class _QueueCancelled implements Exception {
  const _QueueCancelled();
}

class FolderDownloadNotifier
    extends FamilyNotifier<FolderDownloadState, String> {
  // One token per active HTTP transfer; replaced with a set so all concurrent
  // transfers can be cancelled at once.
  final _activeTokens = <CancelToken>{};
  bool _cancelled = false;

  @override
  FolderDownloadState build(String folderId) {
    ref.onDispose(() {
      _cancelled = true;
      for (final t in _activeTokens) {
        t.cancel('disposed');
      }
    });
    _restore(folderId);
    return const FolderDownloadState.idle();
  }

  Future<void> _restore(String folderId) async {
    final manager = await _manager();
    final saved = await manager.restoreFolder(folderId);
    if (saved != null) state = saved;
  }

  Future<void> downloadFolder(String folderId) async {
    if (state.status == FolderDownloadStatus.fetching ||
        state.status == FolderDownloadStatus.downloading) return;

    _cancelled = false;
    state = const FolderDownloadState(status: FolderDownloadStatus.fetching);

    final client = ref.read(apiClientProvider);
    final api = MediaApi(client);

    // folderArchiveIds maps every visited folder → set of all archive IDs
    // under it (direct + nested). Used to persist per-subfolder states.
    final folderArchiveIds = <String, Set<String>>{};
    final archives = <Media>[];
    try {
      await _collectArchives(api, folderId, archives, folderArchiveIds);
    } catch (e) {
      state = FolderDownloadState(
          status: FolderDownloadStatus.failed, error: e.toString());
      return;
    }

    if (_cancelled || archives.isEmpty) {
      state = const FolderDownloadState.idle();
      return;
    }

    final manager = await _manager();

    // Determine which archives still need downloading.
    final alreadyDone =
        await manager.completedMediaIds(archives.map((a) => a.id));
    final toDownload =
        archives.where((a) => !alreadyDone.contains(a.id)).toList();

    // Everything already downloaded — mark all folders complete and return.
    if (toDownload.isEmpty) {
      final total = archives.length;
      state = FolderDownloadState(
        status: FolderDownloadStatus.complete,
        total: total,
        completed: total,
      );
      for (final entry in folderArchiveIds.entries) {
        await manager.saveFolderComplete(
            entry.key, entry.value.length, entry.value.length);
      }
      return;
    }

    state = FolderDownloadState(
      status: FolderDownloadStatus.downloading,
      total: toDownload.length,
      completed: 0,
    );

    final queue = ref.read(downloadQueueProvider);
    final successfulIds = <String>{};
    // Dart's event loop is single-threaded so plain int is safe here.
    var completedCount = 0;

    // Pre-submit every archive to the queue at once.  The queue's concurrency
    // cap (3) controls how many transfers actually run simultaneously, so
    // subsequent slots open immediately as each one finishes — no loop stall.
    await Future.wait<void>(
      toDownload.map((archive) async {
        if (_cancelled) return;

        String? path;
        try {
          path = await queue.enqueue(() async {
            if (_cancelled) throw const _QueueCancelled();
            final token = CancelToken();
            _activeTokens.add(token);
            try {
              return await manager.download(
                mediaId: archive.id,
                format: archive.format,
                title: archive.displayTitle,
                relativePath: archive.relativePath,
                onProgress: (_) {},
                cancelToken: token,
              );
            } finally {
              _activeTokens.remove(token);
            }
          });
        } on _QueueCancelled {
          return;
        } on DioException catch (_) {
          if (_cancelled) return;
          // Skip failed item; other downloads continue.
        } catch (_) {
          if (_cancelled) return;
        }

        if (!_cancelled && path != null) {
          successfulIds.add(archive.id);

          // Notify the individual chapter tile so it shows "Downloaded" immediately.
          ref.invalidate(downloadProvider(archive.id));

          // Extraction runs in an isolate — fire async so the next queued
          // download starts without waiting for decompression to finish.
          final archiveId = archive.id;
          manager
              .extractPages(
                  mediaId: archiveId, localPath: path, onProgress: (_) {})
              .then((_) => ref.invalidate(extractedPagesProvider(archiveId)))
              .catchError((_) {});
        }

        completedCount++;
        if (!_cancelled) {
          state = FolderDownloadState(
            status: FolderDownloadStatus.downloading,
            total: toDownload.length,
            completed: completedCount,
          );
        }
      }),
      eagerError: false,
    );

    if (!_cancelled) {
      final grandTotal = archives.length;
      state = FolderDownloadState(
        status: FolderDownloadStatus.complete,
        total: grandTotal,
        completed: grandTotal,
      );

      // Persist completion state for every folder in the tree whose archives
      // were all either already downloaded or just downloaded successfully.
      final allDone = alreadyDone.union(successfulIds);
      for (final entry in folderArchiveIds.entries) {
        if (entry.value.every((id) => allDone.contains(id))) {
          await manager.saveFolderComplete(
              entry.key, entry.value.length, entry.value.length);
        }
      }
    } else {
      state = const FolderDownloadState.idle();
    }
  }

  void cancel() {
    _cancelled = true;
    for (final t in _activeTokens) {
      t.cancel('user');
    }
    _activeTokens.clear();
    state = const FolderDownloadState.idle();
  }

  /// Recursively collects all leaf archives under [folderId].
  ///
  /// Subfolder API calls at the same depth are issued in parallel.
  /// Returns the set of all archive IDs found under [folderId] (used to
  /// populate [folderArchiveIds] for later per-subfolder persistence).
  Future<Set<String>> _collectArchives(
    MediaApi api,
    String folderId,
    List<Media> allArchives,
    Map<String, Set<String>> folderArchiveIds,
  ) async {
    final items = await api.getChapters(folderId);

    final subfolders = <Media>[];
    final directIds = <String>{};
    for (final item in items) {
      if (item.isFolder) {
        subfolders.add(item);
      } else {
        allArchives.add(item);
        directIds.add(item.id);
      }
    }

    // Fetch all subfolders at this level in parallel.
    final subResults = await Future.wait(
      subfolders.map(
          (sf) => _collectArchives(api, sf.id, allArchives, folderArchiveIds)),
    );

    final allIds = Set<String>.from(directIds);
    for (final ids in subResults) {
      allIds.addAll(ids);
    }
    folderArchiveIds[folderId] = allIds;
    return allIds;
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
