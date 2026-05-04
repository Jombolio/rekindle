import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/api_client.dart';
import '../core/api/libraries_api.dart';
import '../core/models/library.dart';
import 'sources_provider.dart';

class SourceLibraryNotifier
    extends FamilyAsyncNotifier<List<Library>, String> {
  @override
  Future<List<Library>> build(String sourceId) => _fetch(sourceId);

  Future<List<Library>> _fetch(String sourceId) async {
    final sources = ref.read(sourcesProvider);
    final source = sources.where((s) => s.id == sourceId).firstOrNull;
    if (source == null) return [];
    final client = ApiClient(baseUrl: source.baseUrl, token: source.token);
    return LibrariesApi(client).getAll();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _fetch(arg));
  }

  Future<void> scan(String libraryId) async {
    final client = _client();
    if (client == null) return;
    await LibrariesApi(client).scan(libraryId);
  }

  Future<void> create({
    required String name,
    required String rootPath,
    required String type,
  }) async {
    final client = _client();
    if (client == null) return;
    await LibrariesApi(client).create(name: name, rootPath: rootPath, type: type);
    await refresh();
  }

  Future<void> updateLibrary(
    String libraryId, {
    required String name,
    required String rootPath,
    required String type,
  }) async {
    final client = _client();
    if (client == null) return;
    await LibrariesApi(client)
        .update(libraryId, name: name, rootPath: rootPath, type: type);
    await refresh();
  }

  Future<void> delete(String libraryId) async {
    final client = _client();
    if (client == null) return;
    await LibrariesApi(client).delete(libraryId);
    await refresh();
  }

  ApiClient? _client() {
    final sources = ref.read(sourcesProvider);
    final source = sources.where((s) => s.id == arg).firstOrNull;
    if (source == null) return null;
    return ApiClient(baseUrl: source.baseUrl, token: source.token);
  }
}

final sourceLibraryProvider = AsyncNotifierProviderFamily<
    SourceLibraryNotifier, List<Library>, String>(
  SourceLibraryNotifier.new,
);
