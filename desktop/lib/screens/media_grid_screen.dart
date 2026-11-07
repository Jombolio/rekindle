import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/models/media.dart';
import '../providers/settings_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/media_provider.dart';
import '../providers/progress_summary_provider.dart';
import 'widgets/read_mark_menu.dart';
import 'widgets/cover_image.dart';
import 'widgets/download_button.dart';
import 'widgets/error_view.dart';
import 'widgets/marquee_text.dart';
import 'widgets/progress_badges.dart';
import 'widgets/type_to_search.dart';

class MediaGridScreen extends ConsumerStatefulWidget {
  final String libraryId;
  final String? libraryName;
  final String? libraryType;

  const MediaGridScreen({
    super.key,
    required this.libraryId,
    this.libraryName,
    this.libraryType,
  });

  @override
  ConsumerState<MediaGridScreen> createState() => _MediaGridScreenState();
}

class _MediaGridScreenState extends ConsumerState<MediaGridScreen> {
  final _scrollCtrl = ScrollController();

  // ── Search ─────────────────────────────────────────────────────────────
  bool _searchActive = false;
  final _searchCtrl = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'Folder search');

  /// The search was opened by typing, so emptying it closes it again.
  bool _typedSearch = false;
  String _debouncedQuery = '';
  Timer? _debounce;

  // ── Pagination ──────────────────────────────────────────────────────────
  bool _fetchingMore = false;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref
          .read(mediaListProvider(widget.libraryId).notifier)
          .refreshIfStale(widget.libraryId);
    });
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_onScroll);
    _scrollCtrl.dispose();
    _searchCtrl.dispose();
    _searchFocus.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 300) {
      _triggerFetchMore();
    }
  }

  Future<void> _triggerFetchMore() async {
    if (_fetchingMore) return;
    final notifier = ref.read(mediaListProvider(widget.libraryId).notifier);
    if (!notifier.hasMore) return;
    setState(() => _fetchingMore = true);
    try {
      await notifier.fetchNext(widget.libraryId);
    } finally {
      if (mounted) setState(() => _fetchingMore = false);
    }
  }

  void _openItem(BuildContext context, Media item) {
    if (item.isFolder) {
      context.push('/series/${item.id}', extra: <String, String?>{
        'title': item.displayTitle,
        'libraryType': widget.libraryType,
      });
    } else if (item.isImageBased) {
      context.push('/reader/${item.id}',
          extra: <String, dynamic>{'libraryType': widget.libraryType});
    } else {
      context.push('/epub/${item.id}', extra: item.displayTitle);
    }
  }

  // ── Search helpers ──────────────────────────────────────────────────────

  void _openSearch() {
    setState(() {
      _searchActive = true;
      _typedSearch = false;
    });
    _focusSearch();
  }

  /// Typing on the grid: open the search holding what was typed, or add to it.
  void _onType(String text) {
    final value = _searchCtrl.value;
    final at =
        value.selection.isValid ? value.selection.end : value.text.length;
    final next = value.text.substring(0, at) + text + value.text.substring(at);
    _searchCtrl.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: at + text.length),
    );
    if (!_searchActive) {
      setState(() {
        _searchActive = true;
        _typedSearch = true;
      });
    }
    _onQueryChanged(next);
    _focusSearch();
  }

  void _focusSearch() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _searchActive) _searchFocus.requestFocus();
    });
  }

  void _closeSearch() {
    _debounce?.cancel();
    _searchCtrl.clear();
    setState(() {
      _searchActive = false;
      _typedSearch = false;
      _debouncedQuery = '';
    });
  }

  void _onQueryChanged(String q) {
    if (_typedSearch && q.isEmpty) {
      _closeSearch();
      return;
    }
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _debouncedQuery = q.trim());
    });
  }

  void _clearQuery() {
    if (_typedSearch) {
      _closeSearch();
      return;
    }
    _debounce?.cancel();
    _searchCtrl.clear();
    setState(() => _debouncedQuery = '');
  }

  // ── App bars ────────────────────────────────────────────────────────────

  PreferredSizeWidget _normalAppBar() {
    return AppBar(
      title: Text(widget.libraryName ?? 'Library'),
      actions: [
        IconButton(
          icon: const Icon(Icons.search),
          tooltip: 'Search folders',
          onPressed: _openSearch,
        ),
        IconButton(
          icon: const Icon(Icons.refresh),
          tooltip: 'Refresh',
          onPressed: () => ref
              .read(mediaListProvider(widget.libraryId).notifier)
              .refresh(widget.libraryId),
        ),
      ],
    );
  }

  PreferredSizeWidget _searchAppBar(BuildContext context) {
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        tooltip: 'Exit search',
        onPressed: _closeSearch,
      ),
      title: TextField(
        controller: _searchCtrl,
        focusNode: _searchFocus,
        autofocus: true,
        decoration: const InputDecoration(
          hintText: 'Search folders and directories…',
          border: InputBorder.none,
        ),
        style: Theme.of(context).textTheme.titleMedium,
        onChanged: _onQueryChanged,
      ),
      actions: [
        if (_searchCtrl.text.isNotEmpty)
          IconButton(
            icon: const Icon(Icons.clear),
            tooltip: 'Clear',
            onPressed: _clearQuery,
          ),
      ],
    );
  }

  // ── Bodies ──────────────────────────────────────────────────────────────

  Widget _searchBody(BuildContext context) {
    final client = ref.watch(apiClientProvider);

    if (_debouncedQuery.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.folder_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text(
              'Type to search folders and directories',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      );
    }

    final results = ref.watch(folderSearchProvider(
      (libraryId: widget.libraryId, query: _debouncedQuery),
    ));

    return results.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (folders) {
        if (folders.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.search_off,
                    size: 56,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(height: 16),
                Text(
                  'No folders matching "$_debouncedQuery"',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: folders.length,
          itemBuilder: (_, i) {
            final folder = folders[i];
            return ListTile(
              leading: SizedBox(
                width: 44,
                height: 62,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: CoverImage(
                    url: client.coverUrl(folder.id),
                    headers: client.authHeaders,
                    cacheKey: folder.coverCachePath ?? folder.id,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              title: Text(
                folder.displayTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(
                '${folder.relativePath}/',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              onTap: () => context.push(
                '/series/${folder.id}',
                extra: <String, String?>{
                  'title': folder.displayTitle,
                  'libraryType': widget.libraryType,
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _gridBody(BuildContext context, List<Media> items) {
    final client = ref.watch(apiClientProvider);
    final hasMore =
        ref.read(mediaListProvider(widget.libraryId).notifier).hasMore;

    if (items.isEmpty) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 72),
            SizedBox(height: 16),
            Text('No media found. Try scanning the library.'),
          ],
        ),
      );
    }

    final ids = [for (final m in items) m.id];
    final showExtensions =
        ref.watch(settingsProvider.select((s) => s.showFileExtensions));

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = (constraints.maxWidth / 180).floor().clamp(2, 8);
        return Stack(
          children: [
            GridView.builder(
              controller: _scrollCtrl,
              padding: EdgeInsets.fromLTRB(
                  16, 16, 16, (_fetchingMore || hasMore) ? 56 : 16),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                childAspectRatio: 2 / 3,
                crossAxisSpacing: 12,
                mainAxisSpacing: 12,
              ),
              itemCount: items.length,
              itemBuilder: (_, i) {
                final item = items[i];
                final summary = watchProgressSummary(
                    ref, item, summaryChunkKey(ids, i, kGridSummaryChunk));

                return ReadMarkMenuArea(
                  media: item,
                  summary: summary,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            GestureDetector(
                              onTap: () => _openItem(context, item),
                              child: CoverImage(
                                url: client.coverUrl(item.id),
                                headers: client.authHeaders,
                                cacheKey: item.coverCachePath ?? item.id,
                              ),
                            ),
                            ReadProgressRing(summary: summary),
                            NewChaptersBadge(count: summary?.newCount ?? 0),
                            DownloadStatusBadge(
                              mediaId: item.id,
                              isFolder: item.isFolder,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      GestureDetector(
                        onTap: () => _openItem(context, item),
                        child: MarqueeText(
                          text: item.label(showExtension: showExtensions),
                          style: Theme.of(context).textTheme.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),

            // Bottom progress bar — visible while the next page is loading.
            if (_fetchingMore)
              const Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: LinearProgressIndicator(),
              ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return TypeToSearch(
      enabled: ref.watch(settingsProvider.select((s) => s.typeToSearch)),
      active: _searchActive,
      onType: _onType,
      onEscape: _closeSearch,
      child: _buildScreen(context),
    );
  }

  Widget _buildScreen(BuildContext context) {
    if (_searchActive) {
      return Scaffold(
        appBar: _searchAppBar(context),
        body: _searchBody(context),
      );
    }

    final media = ref.watch(mediaListProvider(widget.libraryId));
    return Scaffold(
      appBar: _normalAppBar(),
      body: media.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
          message: e.toString(),
          onRetry: () => ref
              .read(mediaListProvider(widget.libraryId).notifier)
              .refresh(widget.libraryId),
        ),
        data: (items) => _gridBody(context, items),
      ),
    );
  }
}
