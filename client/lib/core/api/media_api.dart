import '../models/media.dart';
import '../models/paged_response.dart';
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

  Future<List<Media>> getChapters(String folderId) async {
    final resp = await _client.dio.get('api/media/$folderId/chapters');
    return (resp.data as List<dynamic>)
        .map((e) => Media.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveProgress(
    String mediaId, {
    required int currentPage,
    required bool isCompleted,
  }) =>
      _client.dio.post('api/media/$mediaId/progress', data: {
        'currentPage': currentPage,
        'isCompleted': isCompleted,
      });
}
