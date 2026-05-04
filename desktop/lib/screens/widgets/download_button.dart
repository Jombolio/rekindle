import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/download/download_state.dart';
import '../../core/models/media.dart';
import '../../core/models/reading_progress.dart';
import '../../providers/download_provider.dart';

/// Download button for folder/series items — downloads all contained archives
/// sequentially, including nested subdirectory contents.
///
/// Set [showConfirm] to true (e.g. in an AppBar) to prompt the user before
/// starting the bulk download.
class FolderDownloadButton extends ConsumerWidget {
  final String folderId;
  final bool showConfirm;

  const FolderDownloadButton({
    super.key,
    required this.folderId,
    this.showConfirm = false,
  });

  Future<void> _handlePress(BuildContext context, WidgetRef ref) async {
    if (showConfirm) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Download all chapters?'),
          content: const Text(
            'All chapters in this series will be downloaded for offline reading. This may use significant storage.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Download'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    ref.read(folderDownloadProvider(folderId).notifier).downloadFolder(folderId);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(folderDownloadProvider(folderId));
    final iconColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : Colors.black;

    return switch (state.status) {
      FolderDownloadStatus.idle || FolderDownloadStatus.failed => IconButton(
          icon: Icon(
            state.status == FolderDownloadStatus.failed
                ? Icons.error_outline
                : Icons.download_outlined,
            color: state.status == FolderDownloadStatus.failed
                ? Colors.red
                : iconColor,
          ),
          tooltip: state.status == FolderDownloadStatus.failed
              ? 'Download failed — retry'
              : 'Download all for offline',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: () => _handlePress(context, ref),
        ),

      FolderDownloadStatus.fetching => const SizedBox(
          width: 40,
          height: 40,
          child: Padding(
            padding: EdgeInsets.all(10),
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),

      FolderDownloadStatus.downloading => SizedBox(
          width: 40,
          height: 40,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: state.progress > 0 ? state.progress : null,
                strokeWidth: 2,
              ),
              GestureDetector(
                onTap: () =>
                    ref.read(folderDownloadProvider(folderId).notifier).cancel(),
                child: const Icon(Icons.close, size: 14),
              ),
            ],
          ),
        ),

      FolderDownloadStatus.complete => const IconButton(
          icon: Icon(Icons.download_done, color: Colors.green),
          tooltip: 'All chapters downloaded',
          padding: EdgeInsets.zero,
          constraints: BoxConstraints(),
          onPressed: null,
        ),
    };
  }
}

class DownloadButton extends ConsumerWidget {
  final Media media;

  const DownloadButton({super.key, required this.media});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Folder entries span multiple files — individual download not supported.
    if (media.isFolder) return const SizedBox.shrink();

    final state = ref.watch(downloadProvider(media.id));

    final iconColor = Theme.of(context).brightness == Brightness.dark
        ? Colors.white
        : Colors.black;

    return switch (state.status) {
      DownloadStatus.idle || DownloadStatus.failed => IconButton(
          icon: Icon(
            state.status == DownloadStatus.failed
                ? Icons.error_outline
                : Icons.download_outlined,
            color: state.status == DownloadStatus.failed
                ? Colors.red
                : iconColor,
          ),
          tooltip: state.status == DownloadStatus.failed
              ? 'Download failed — retry'
              : 'Download for offline',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: () => ref
              .read(downloadProvider(media.id).notifier)
              .download(
                mediaId: media.id,
                format: media.format,
                title: media.displayTitle,
                relativePath: media.relativePath,
              ),
        ),

      DownloadStatus.downloading => SizedBox(
          width: 40,
          height: 40,
          child: Stack(
            alignment: Alignment.center,
            children: [
              CircularProgressIndicator(
                value: state.progress > 0 ? state.progress : null,
                strokeWidth: 2,
              ),
              GestureDetector(
                onTap: () =>
                    ref.read(downloadProvider(media.id).notifier).cancel(),
                child: const Icon(Icons.close, size: 16),
              ),
            ],
          ),
        ),

      DownloadStatus.extracting => const SizedBox(
          width: 40,
          height: 40,
          child: Padding(
            padding: EdgeInsets.all(8),
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),

      DownloadStatus.complete => IconButton(
          icon: const Icon(Icons.download_done, color: Colors.green),
          tooltip: 'Downloaded — tap to delete',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          onPressed: () => _confirmDelete(context, ref),
        ),
    };
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete download?'),
        content: Text(
            '"${media.displayTitle}" will be removed from this device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(downloadProvider(media.id).notifier).delete(media.id);
    }
  }
}

/// Stacked-pages icon overlaid on folder-type media covers.
class FolderBadge extends StatelessWidget {
  const FolderBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      bottom: 4,
      left: 4,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.library_books, size: 12, color: Colors.white),
            SizedBox(width: 3),
            Text('Series',
                style: TextStyle(color: Colors.white, fontSize: 10)),
          ],
        ),
      ),
    );
  }
}

/// Progress badge overlaid on a cover — ✓ for completed, … for in-progress.
/// Returns an empty box when there is no progress or the item was never opened.
class ReadProgressBadge extends StatelessWidget {
  final ReadingProgress? progress;
  const ReadProgressBadge({super.key, required this.progress});

  @override
  Widget build(BuildContext context) {
    final p = progress;
    if (p == null) return const SizedBox.shrink();

    final completed = p.isCompleted;
    final inProgress = !completed && p.currentPage > 0;
    if (!completed && !inProgress) return const SizedBox.shrink();

    return Positioned(
      top: 4,
      left: 4,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: (completed ? Colors.green : Colors.orange)
              .withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Icon(
          completed ? Icons.check : Icons.more_horiz,
          size: 14,
          color: Colors.white,
        ),
      ),
    );
  }
}

/// Small offline-available badge overlaid on a cover image.
class OfflineBadge extends StatelessWidget {
  const OfflineBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 4,
      right: 4,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Icon(Icons.offline_bolt,
            size: 14, color: Colors.white),
      ),
    );
  }
}

/// Non-interactive download status badge for grid covers.
///
/// Three visible states:
///  - ALL  (green)  — everything in this item is available offline.
///  - MIXED (amber) — partially downloaded (download in progress or some
///                    chapters available, others not).
///  - null          — nothing downloaded; badge is not shown.
class DownloadStatusBadge extends ConsumerWidget {
  final String mediaId;
  final bool isFolder;

  const DownloadStatusBadge({
    super.key,
    required this.mediaId,
    required this.isFolder,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final Color? badgeColor;

    if (isFolder) {
      final state = ref.watch(folderDownloadProvider(mediaId));
      badgeColor = switch (state.status) {
        FolderDownloadStatus.complete  => Colors.green,
        FolderDownloadStatus.fetching ||
        FolderDownloadStatus.downloading => Colors.orange,
        _ => null,
      };
    } else {
      final state = ref.watch(downloadProvider(mediaId));
      badgeColor = switch (state.status) {
        DownloadStatus.complete   => Colors.green,
        DownloadStatus.downloading ||
        DownloadStatus.extracting => Colors.orange,
        _ => null,
      };
    }

    if (badgeColor == null) return const SizedBox.shrink();

    return Positioned(
      bottom: 4,
      right: 4,
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: badgeColor.withValues(alpha: 0.85),
          borderRadius: BorderRadius.circular(4),
        ),
        child: const Icon(Icons.offline_bolt, size: 14, color: Colors.white),
      ),
    );
  }
}
