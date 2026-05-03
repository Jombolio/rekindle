import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/download/download_state.dart';
import '../core/models/media.dart';
import '../providers/auth_provider.dart';
import '../providers/chapter_provider.dart';
import '../providers/download_provider.dart';
import '../providers/reader_provider.dart';
import 'widgets/cover_image.dart';
import 'widgets/download_button.dart';
import 'widgets/error_view.dart';
import 'widgets/manga_about_section.dart';
import 'widgets/marquee_text.dart';

// Fixed tile height — leading thumbnail is 68 px + 12 px vertical padding.
// Keeping this constant lets ListView skip O(n) layout on large lists.
const double _kTileHeight = 82.0;
const double _kHeaderHeight = 32.0;

class ChapterIndexScreen extends ConsumerWidget {
  final String folderId;
  final String folderTitle;
  final String? libraryType;

  const ChapterIndexScreen({
    super.key,
    required this.folderId,
    required this.folderTitle,
    this.libraryType,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chaptersAsync = ref.watch(chapterProvider(folderId));
    final client = ref.watch(apiClientProvider);
    // Resolved once here — avoids one authProvider watch per tile.
    final authState = ref.watch(authProvider).valueOrNull;
    final canDownload =
        authState is AuthAuthenticated && authState.canDownload;

    return Scaffold(
      appBar: AppBar(
        title: Text(folderTitle),
        actions: [
          if (canDownload)
            FolderDownloadButton(folderId: folderId, showConfirm: true),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(chapterProvider(folderId)),
          ),
        ],
      ),
      bottomNavigationBar: canDownload
          ? _DownloadProgressBar(folderId: folderId)
          : null,
      body: chaptersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
          message: e.toString(),
          onRetry: () => ref.invalidate(chapterProvider(folderId)),
        ),
        data: (items) {
          final subfolders = items.where((m) => m.isFolder).toList();
          final archives = items.where((m) => !m.isFolder).toList();

          final isManga = libraryType == 'manga';

          if (subfolders.isEmpty && archives.isEmpty) {
            return Column(
              children: [
                if (isManga) MangaAboutSection(mediaId: folderId),
                const Expanded(
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.folder_open_outlined, size: 64),
                        SizedBox(height: 16),
                        Text('No chapters found. Try scanning the library.'),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }

          final hasSubfolders = subfolders.isNotEmpty;
          final totalItems =
              (hasSubfolders ? subfolders.length + 1 : 0) + archives.length;

          Widget list = ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: totalItems,
            cacheExtent: _kTileHeight * 6,
            itemExtentBuilder: (i, _) {
              if (hasSubfolders && i == 0) return _kHeaderHeight;
              return _kTileHeight;
            },
            itemBuilder: (_, i) {
              if (hasSubfolders) {
                if (i == 0) {
                  return const _SectionHeader(label: 'Subfolders');
                }
                if (i <= subfolders.length) {
                  final folder = subfolders[i - 1];
                  return _SubfolderTile(
                    folder: folder,
                    coverUrl: client.coverUrl(folder.id),
                    authHeaders: client.authHeaders,
                    libraryType: libraryType,
                    canDownload: canDownload,
                  );
                }
                final archiveIndex = i - subfolders.length - 1;
                final chapter = archives[archiveIndex];
                return _ChapterTile(
                  chapter: chapter,
                  index: archiveIndex,
                  coverUrl: client.coverUrl(chapter.id),
                  authHeaders: client.authHeaders,
                  libraryType: libraryType,
                  canDownload: canDownload,
                );
              }
              final chapter = archives[i];
              return _ChapterTile(
                chapter: chapter,
                index: i,
                coverUrl: client.coverUrl(chapter.id),
                authHeaders: client.authHeaders,
                libraryType: libraryType,
                canDownload: canDownload,
              );
            },
          );

          if (!isManga) return list;

          return Column(
            children: [
              MangaAboutSection(mediaId: folderId),
              Expanded(child: list),
            ],
          );
        },
      ),
    );
  }
}

// ── Section header ───────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  const _SectionHeader({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              letterSpacing: 0.8,
            ),
      ),
    );
  }
}

// ── Subfolder tile ───────────────────────────────────────────────────────────

class _SubfolderTile extends StatelessWidget {
  final Media folder;
  final String coverUrl;
  final Map<String, String> authHeaders;
  final String? libraryType;
  final bool canDownload;

  const _SubfolderTile({
    required this.folder,
    required this.coverUrl,
    required this.authHeaders,
    required this.canDownload,
    this.libraryType,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: _kTileHeight,
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Stack(
          children: [
            SizedBox(
              width: 48,
              height: 68,
              child: CoverImage(
                url: coverUrl,
                headers: authHeaders,
                cacheKey: folder.coverCachePath ?? folder.id,
              ),
            ),
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Icon(Icons.folder,
                    size: 10,
                    color: Theme.of(context).colorScheme.onPrimary),
              ),
            ),
          ],
        ),
        title: MarqueeText(
          text: folder.displayTitle,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        trailing: canDownload
            ? SizedBox(
                width: 40,
                height: 40,
                child: FolderDownloadButton(folderId: folder.id),
              )
            : const Icon(Icons.chevron_right),
        onTap: () => context.push(
          '/series/${folder.id}',
          extra: <String, String?>{
            'title': folder.displayTitle,
            'libraryType': libraryType
          },
        ),
      ),
    );
  }
}

// ── Archive tile ─────────────────────────────────────────────────────────────

class _ChapterTile extends ConsumerWidget {
  final Media chapter;
  final int index;
  final String coverUrl;
  final Map<String, String> authHeaders;
  final String? libraryType;
  final bool canDownload;

  const _ChapterTile({
    required this.chapter,
    required this.index,
    required this.coverUrl,
    required this.authHeaders,
    required this.canDownload,
    this.libraryType,
  });

  void _open(BuildContext context) {
    if (chapter.isImageBased) {
      context.push('/reader/${chapter.id}',
          extra: <String, dynamic>{'libraryType': libraryType});
    } else {
      context.push('/epub/${chapter.id}', extra: chapter.title);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadState = ref.watch(downloadProvider(chapter.id));
    final isOffline = downloadState.status == DownloadStatus.complete;
    final progress =
        ref.watch(localProgressProvider(chapter.id)).valueOrNull;
    final theme = Theme.of(context);

    // Subtitle: show progress status first, then offline indicator.
    final completed = progress?.isCompleted ?? false;
    final inProgress = !(progress?.isCompleted ?? true) && (progress?.currentPage ?? 0) > 0;
    final subtitleParts = [
      if (completed) 'Read'
      else if (inProgress) 'In progress',
      if (isOffline) 'Downloaded',
    ];

    return SizedBox(
      height: _kTileHeight,
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        leading: Stack(
          children: [
            SizedBox(
              width: 48,
              height: 68,
              child: CoverImage(
                url: coverUrl,
                headers: authHeaders,
                cacheKey: chapter.coverCachePath ?? chapter.id,
              ),
            ),
            if (isOffline)
              Positioned(
                bottom: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: Colors.green.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(3),
                  ),
                  child: const Icon(Icons.offline_bolt,
                      size: 10, color: Colors.white),
                ),
              ),
            ReadProgressBadge(progress: progress),
          ],
        ),
        title: MarqueeText(
          text: chapter.title,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: completed
                ? theme.colorScheme.onSurface.withValues(alpha: 0.5)
                : null,
          ),
        ),
        subtitle: subtitleParts.isNotEmpty
            ? Text(
                subtitleParts.join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: completed
                      ? Colors.green.shade600
                      : inProgress
                          ? Colors.orange.shade700
                          : theme.colorScheme.onSurfaceVariant,
                ),
              )
            : null,
        trailing: canDownload
            ? SizedBox(
                width: 40,
                height: 40,
                child: DownloadButton(media: chapter),
              )
            : null,
        onTap: () => _open(context),
      ),
    );
  }
}

// ── Download progress bar ─────────────────────────────────────────────────────

/// Persistent bottom bar that appears while a folder download is in progress.
/// Slides in/out smoothly and shows determinate progress once transfer begins.
class _DownloadProgressBar extends ConsumerWidget {
  final String folderId;
  const _DownloadProgressBar({required this.folderId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dl = ref.watch(folderDownloadProvider(folderId));
    final scheme = Theme.of(context).colorScheme;

    final visible = dl.status == FolderDownloadStatus.fetching ||
        dl.status == FolderDownloadStatus.downloading ||
        dl.status == FolderDownloadStatus.failed;

    return AnimatedSize(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      child: visible ? _buildBar(context, ref, dl, scheme) : const SizedBox.shrink(),
    );
  }

  Widget _buildBar(
    BuildContext context,
    WidgetRef ref,
    FolderDownloadState dl,
    ColorScheme scheme,
  ) {
    final isError = dl.status == FolderDownloadStatus.failed;
    final isFetching = dl.status == FolderDownloadStatus.fetching;

    final String label;
    final double? progressValue;

    if (isFetching) {
      label = 'Preparing download…';
      progressValue = null; // indeterminate
    } else if (isError) {
      label = dl.error ?? 'Download failed';
      progressValue = 0;
    } else {
      label = 'Downloading ${dl.completed} / ${dl.total}';
      progressValue = dl.progress;
    }

    return Material(
      color: scheme.surfaceContainerHigh,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          LinearProgressIndicator(
            value: progressValue,
            minHeight: 3,
            color: isError ? scheme.error : scheme.primary,
            backgroundColor: scheme.surfaceContainerHighest,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 8, 6),
            child: Row(
              children: [
                Icon(
                  isError ? Icons.error_outline : Icons.download_outlined,
                  size: 16,
                  color: isError ? scheme.error : scheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: isError
                              ? scheme.error
                              : scheme.onSurfaceVariant,
                        ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (!isError)
                  TextButton(
                    onPressed: () => ref
                        .read(folderDownloadProvider(folderId).notifier)
                        .cancel(),
                    style: TextButton.styleFrom(
                      foregroundColor: scheme.error,
                      visualDensity: VisualDensity.compact,
                    ),
                    child: const Text('Cancel'),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
