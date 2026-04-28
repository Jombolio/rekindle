import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/download/download_state.dart';
import '../core/models/media.dart';
import '../providers/auth_provider.dart';
import '../providers/download_provider.dart';
import '../providers/media_provider.dart';
import '../providers/reader_provider.dart';
import 'widgets/cover_image.dart';
import 'widgets/download_button.dart';
import 'widgets/error_view.dart';

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
    super.dispose();
  }

  void _openItem(BuildContext context, Media item) {
    if (item.isFolder) {
      context.push('/series/${item.id}',
          extra: <String, String?>{'title': item.displayTitle, 'libraryType': widget.libraryType});
    } else if (item.isImageBased) {
      context.push('/reader/${item.id}',
          extra: <String, dynamic>{'libraryType': widget.libraryType});
    } else {
      context.push('/epub/${item.id}', extra: item.displayTitle);
    }
  }

  void _onScroll() {
    if (_scrollCtrl.position.pixels >=
        _scrollCtrl.position.maxScrollExtent - 300) {
      ref
          .read(mediaListProvider(widget.libraryId).notifier)
          .fetchNext(widget.libraryId);
    }
  }

  @override
  Widget build(BuildContext context) {
    final client = ref.watch(apiClientProvider);
    final media = ref.watch(mediaListProvider(widget.libraryId));
    final authState = ref.watch(authProvider).valueOrNull;
    final canDownload =
        authState is AuthAuthenticated && authState.canDownload;

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.libraryName ?? 'Library'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref
                .read(mediaListProvider(widget.libraryId).notifier)
                .refresh(widget.libraryId),
          ),
        ],
      ),
      body: media.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
          message: e.toString(),
          onRetry: () => ref
              .read(mediaListProvider(widget.libraryId).notifier)
              .refresh(widget.libraryId),
        ),
        data: (items) {
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

          return LayoutBuilder(
            builder: (context, constraints) {
              final columns =
                  (constraints.maxWidth / 180).floor().clamp(2, 8);

              return GridView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.all(16),
                gridDelegate:
                    SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  childAspectRatio: 2 / 3,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: items.length,
                itemBuilder: (_, i) {
                  final item = items[i];
                  final downloadState =
                      ref.watch(downloadProvider(item.id));
                  final isOffline =
                      downloadState.status == DownloadStatus.complete;
                  final progress =
                      ref.watch(localProgressProvider(item.id)).valueOrNull;

                  return Column(
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
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            if (isOffline) const OfflineBadge(),
                            if (item.isFolder) const FolderBadge(),
                            ReadProgressBadge(progress: progress),
                            if (canDownload)
                              Positioned(
                                bottom: 4,
                                right: 4,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.55),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: SizedBox(
                                    width: 32,
                                    height: 32,
                                    child: item.isFolder
                                        ? FolderDownloadButton(folderId: item.id)
                                        : DownloadButton(media: item),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      GestureDetector(
                        onTap: () => _openItem(context, item),
                        child: Text(
                          item.displayTitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
