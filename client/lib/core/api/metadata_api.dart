import '../models/manga_metadata.dart';
import '../models/scrape_result.dart';
import 'api_client.dart';

class MetadataApi {
  const MetadataApi(this._client);
  final ApiClient _client;

  Future<MangaMetadata?> getMetadata(String mediaId) async {
    try {
      final resp = await _client.dio.get('api/metadata/$mediaId');
      return MangaMetadata.fromJson(resp.data as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<ScrapeResult> scrape(String mediaId) async {
    final resp = await _client.dio.post('api/metadata/$mediaId/scrape');
    return ScrapeResult.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<MangaMetadata> commit(String mediaId, MangaMetadata metadata) async {
    final resp = await _client.dio.post(
      'api/metadata/$mediaId/commit',
      data: {
        'mediaId':     metadata.mediaId,
        'title':       metadata.title,
        'synopsis':    metadata.synopsis,
        'genres':      metadata.genres,
        'score':       metadata.score,
        'status':      metadata.status,
        'year':        metadata.year,
        'malId':       metadata.malId,
        'anilistId':   metadata.anilistId,
        'comicvineId': metadata.comicvineId,
        'source':      metadata.source,
      },
    );
    return MangaMetadata.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<({bool malKeySet, bool comicvineKeySet})> getConfig() async {
    final resp = await _client.dio.get('api/admin/metadata/config');
    final data = resp.data as Map<String, dynamic>;
    return (
      malKeySet: data['malClientIdSet'] as bool? ?? false,
      comicvineKeySet: data['comicvineApiKeySet'] as bool? ?? false,
    );
  }

  Future<void> saveConfig({String? malClientId, String? comicvineApiKey}) =>
      _client.dio.put('api/admin/metadata/config', data: {
        if (malClientId != null) 'malClientId': malClientId,
        if (comicvineApiKey != null) 'comicvineApiKey': comicvineApiKey,
      });
}
