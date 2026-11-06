import 'dart:typed_data';

import 'package:dio/dio.dart';

import '../models/media.dart';
import '../models/paged_response.dart';
import '../models/progress_summary.dart';
import '../models/reading_progress.dart';
import 'api_client.dart';

class MediaApi {
  const MediaApi(this._client);
  final ApiClient _client;

  Future<PagedResponse<Media>> getPaged({
    required String libraryId,
    int page = 1,
    int pageSize = 50,
  }) async {
    final resp = await _client.dio.get('api/media', queryParameters: {
      'libraryId': libraryId,
      'page': page,
      'pageSize': pageSize,
    });
    final data = resp.data as Map<String, dynamic>;
    final items = (data['items'] as List<dynamic>)
        .map((e) => Media.fromJson(e as Map<String, dynamic>))
        .toList();
    return PagedResponse<Media>(
      items: items,
      total: data['total'] as int,
      page: data['page'] as int,
      pageSize: data['pageSize'] as int,
      totalPages: data['totalPages'] as int,
    );
  }

  Future<Media> getById(String mediaId) async {
    final resp = await _client.dio.get('api/media/$mediaId');
    return Media.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<ReadingProgress> getProgress(String mediaId) async {
    final resp = await _client.dio.get('api/media/$mediaId/progress');
    return ReadingProgress.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<({int count, List<bool> spreads})> getPageCount(String mediaId) async {
    final resp = await _client.dio.get('api/media/$mediaId/pagecount');
    final data = resp.data as Map<String, dynamic>;
    final count = data['pageCount'] as int;
    final spreads = (data['spreads'] as List<dynamic>? ?? [])
        .map((e) => e as bool)
        .toList();
    return (count: count, spreads: spreads);
  }

  /// A book's title and chapters, for reading it a chapter at a time.
  Future<({String title, List<({String title, String path})> chapters})>
      getBookManifest(String mediaId) async {
    final resp = await _client.dio.get('api/media/$mediaId/book/manifest');
    final data = resp.data as Map<String, dynamic>;
    return (
      title: (data['title'] ?? '') as String,
      chapters: [
        for (final c in data['chapters'] as List<dynamic>)
          (
            title: (c['title'] ?? '') as String,
            path: c['path'] as String,
          ),
      ],
    );
  }

  /// One file from inside a book, by its path in the EPUB.
  Future<Uint8List> getBookContent(String mediaId, String path) async {
    final resp = await _client.dio.get<List<int>>(
      'api/media/$mediaId/book/content/${_encodePath(path)}',
      options: Options(responseType: ResponseType.bytes),
    );
    return Uint8List.fromList(resp.data!);
  }

  String bookContentUrl(String mediaId, String path) {
    final base = _client.baseUrl.endsWith('/')
        ? _client.baseUrl
        : '${_client.baseUrl}/';
    return '${base}api/media/$mediaId/book/content/${_encodePath(path)}';
  }

  static String _encodePath(String path) =>
      path.split('/').map(Uri.encodeComponent).join('/');

  /// Returns all folder-type items in [libraryId] whose title contains [query].
  /// Archives and individual chapters are never included.
  Future<List<Media>> searchFolders({
    required String libraryId,
    required String query,
  }) async {
    final resp = await _client.dio.get(
      'api/media/search',
      queryParameters: {'libraryId': libraryId, 'q': query},
    );
    return (resp.data as List<dynamic>)
        .map((e) => Media.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Reading state for each of [mediaIds], keyed by media id. Ids the server
  /// doesn't know are absent from the result.
  Future<Map<String, ProgressSummary>> getProgressSummaries(
      List<String> mediaIds) async {
    if (mediaIds.isEmpty) return const {};
    final resp = await _client.dio
        .post('api/media/progress-summary', data: {'ids': mediaIds});
    final summaries = (resp.data as List<dynamic>)
        .map((e) => ProgressSummary.fromJson(e as Map<String, dynamic>));
    return {for (final s in summaries) s.mediaId: s};
  }

  /// Marks a chapter, or every chapter in a series, as read for this user.
  /// Their reading progress is left as it is.
  Future<void> markRead(String mediaId) =>
      _client.dio.put('api/media/$mediaId/read-mark');

  /// Removes the read mark from a chapter, or every chapter in a series.
  Future<void> unmarkRead(String mediaId) =>
      _client.dio.delete('api/media/$mediaId/read-mark');

  /// Leaves an archive, or everything in a folder, out of the series' progress.
  /// Its own progress is kept.
  Future<void> ignoreTracking(String mediaId) =>
      _client.dio.put('api/media/$mediaId/tracking-ignore');

  /// Counts an archive, or everything in a folder, in the series' progress again.
  Future<void> trackAgain(String mediaId) =>
      _client.dio.delete('api/media/$mediaId/tracking-ignore');

  Future<List<Media>> getChapters(String folderId) async {
    final resp = await _client.dio.get('api/media/$folderId/chapters');
    return (resp.data as List<dynamic>)
        .map((e) => Media.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// [lastReadAtMillis] is the client-side time of the write (epoch ms). The
  /// server uses it to order offline-queued writes correctly; without it a
  /// stale flush would be stamped with its arrival time and win over newer
  /// progress from another device.
  Future<void> saveProgress(
    String mediaId, {
    required int currentPage,
    required bool isCompleted,
    int? lastReadAtMillis,
    double? positionFraction,
  }) =>
      _client.dio.post('api/media/$mediaId/progress', data: {
        'currentPage': currentPage,
        'isCompleted': isCompleted,
        if (positionFraction != null) 'positionFraction': positionFraction,
        if (lastReadAtMillis != null)
          'lastReadAt':
              DateTime.fromMillisecondsSinceEpoch(lastReadAtMillis, isUtc: true)
                  .toIso8601String(),
      });
}
