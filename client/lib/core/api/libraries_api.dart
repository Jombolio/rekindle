import '../models/library.dart';
import 'api_client.dart';

class LibrariesApi {
  const LibrariesApi(this._client);
  final ApiClient _client;

  Future<List<Library>> getAll() async {
    final resp = await _client.dio.get('api/libraries');
    final list = resp.data as List<dynamic>;
    return list.map((e) => Library.fromJson(e as Map<String, dynamic>)).toList();
  }

  Future<Library> getById(String libraryId) async {
    final resp = await _client.dio.get('api/libraries/$libraryId');
    return Library.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<Library> create({
    required String name,
    required String rootPath,
    required String type,
  }) async {
    final resp = await _client.dio.post('api/libraries', data: {
      'name': name,
      'rootPath': rootPath,
      'type': type,
    });
    return Library.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<Library> update(
    String libraryId, {
    required String name,
    required String rootPath,
    required String type,
  }) async {
    final resp = await _client.dio.put('api/libraries/$libraryId', data: {
      'name': name,
      'rootPath': rootPath,
      'type': type,
    });
    return Library.fromJson(resp.data as Map<String, dynamic>);
  }

  Future<void> scan(String libraryId) =>
      _client.dio.post('api/libraries/$libraryId/scan');

  Future<void> delete(String libraryId) =>
      _client.dio.delete('api/libraries/$libraryId');
}
