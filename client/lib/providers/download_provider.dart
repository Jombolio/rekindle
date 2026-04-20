import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/download/download_manager.dart';
import '../core/download/download_state.dart';
import '../core/db/local_db_provider.dart';
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
    } on DioException catch (e) {
      if (e.type != DioExceptionType.cancel) rethrow;
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
