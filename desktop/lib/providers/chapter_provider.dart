import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/media_api.dart';
import '../core/models/media.dart';
import 'auth_provider.dart';

final chapterProvider =
    FutureProvider.family<List<Media>, String>((ref, folderId) async {
  final client = ref.watch(apiClientProvider);
  return MediaApi(client).getChapters(folderId);
});
