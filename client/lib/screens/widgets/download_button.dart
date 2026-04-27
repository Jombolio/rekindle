import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/download/download_state.dart';
import '../../core/models/media.dart';
import '../../providers/download_provider.dart';

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
