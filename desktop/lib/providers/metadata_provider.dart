import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/metadata_api.dart';
import '../core/models/manga_metadata.dart';
import 'auth_provider.dart';

final mangaMetadataProvider =
    FutureProvider.autoDispose.family<MangaMetadata?, String>((ref, mediaId) async {
  final client = ref.watch(apiClientProvider);
  return MetadataApi(client).getMetadata(mediaId);
});

final metadataConfigProvider = FutureProvider.autoDispose<({bool malKeySet, bool comicvineKeySet})>((ref) async {
  final client = ref.watch(apiClientProvider);
  return MetadataApi(client).getConfig();
});
