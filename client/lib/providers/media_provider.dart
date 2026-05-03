import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/media_api.dart';
import '../core/models/media.dart';
import 'auth_provider.dart';

// ---------------------------------------------------------------------------
// Paginated media list per library
// ---------------------------------------------------------------------------

class MediaListNotifier extends FamilyAsyncNotifier<List<Media>, String> {
  final List<Media> _items = [];
  int _page = 1;
  bool _hasMore = true;
  bool _loading = false;
  DateTime? _lastRefresh;

  static const _rateLimitSeconds = 5;

  @override
  Future<List<Media>> build(String libraryId) async {
    _items.clear();
    _page = 1;
    _hasMore = true;
    _lastRefresh = DateTime.now();
    return _fetchPage(libraryId);
  }

  bool get hasMore => _hasMore;

  Future<List<Media>> _fetchPage(String libraryId) async {
    if (_loading) return _items;
    _loading = true;
    try {
      final client = ref.read(apiClientProvider);
      final result = await MediaApi(client)
          .getPaged(libraryId: libraryId, page: _page, pageSize: 24);
      _items.addAll(result.items);
      _hasMore = result.hasMore;
      _page++;
      return List.unmodifiable(_items);
    } finally {
      _loading = false;
    }
  }

  Future<void> fetchNext(String libraryId) async {
    if (!_hasMore || _loading) return;
    state = await AsyncValue.guard(() => _fetchPage(libraryId));
  }

  Future<void> refresh(String libraryId) async {
    _items.clear();
    _page = 1;
    _hasMore = true;
    _lastRefresh = DateTime.now();
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => _fetchPage(libraryId));
  }

  /// Refreshes only if more than [_rateLimitSeconds] have elapsed since the
  /// last refresh. Called automatically when entering the library screen.
  Future<void> refreshIfStale(String libraryId) async {
    final last = _lastRefresh;
    if (last != null &&
        DateTime.now().difference(last).inSeconds < _rateLimitSeconds) {
      return;
    }
    await refresh(libraryId);
  }
}

final mediaListProvider =
    AsyncNotifierProviderFamily<MediaListNotifier, List<Media>, String>(
  MediaListNotifier.new,
);

// ---------------------------------------------------------------------------
// Folder search
// ---------------------------------------------------------------------------

/// Returns all [Media] items with mediaType == "folder" whose title contains
/// [query] at any depth inside [libraryId]. Empty query returns nothing.
final folderSearchProvider = FutureProvider.autoDispose
    .family<List<Media>, ({String libraryId, String query})>(
  (ref, args) async {
    if (args.query.isEmpty) return [];
    final client = ref.read(apiClientProvider);
    return MediaApi(client).searchFolders(
      libraryId: args.libraryId,
      query: args.query,
    );
  },
);

// ---------------------------------------------------------------------------
// Single media item
// ---------------------------------------------------------------------------

final mediaDetailProvider = FutureProvider.family<Media, String>((ref, mediaId) async {
  final client = ref.read(apiClientProvider);
  return MediaApi(client).getById(mediaId);
});

// ---------------------------------------------------------------------------
// Sibling archives (other chapters under the same parent folder)
// ---------------------------------------------------------------------------

/// Returns all archive siblings of [mediaId] sorted as the server provides
/// (natural order by file path). Empty list if the item has no parent.
final siblingArchivesProvider = FutureProvider.family<List<Media>, String>((ref, mediaId) async {
  final media = await ref.watch(mediaDetailProvider(mediaId).future);
  if (media.parentId == null) return [];
  final client = ref.read(apiClientProvider);
  final all = await MediaApi(client).getChapters(media.parentId!);
  return all.where((m) => !m.isFolder).toList();
});
