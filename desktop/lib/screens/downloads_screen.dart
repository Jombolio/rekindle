import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers/auth_provider.dart';
import '../providers/download_provider.dart';
import '../providers/downloads_library_provider.dart';
import 'widgets/cover_image.dart';

/// Offline library of downloaded content. Reads the local DB only, so it opens
/// and works with the server unreachable. Two levels: series folders → the
/// chapters within a folder.
class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  /// Series folder the user has drilled into, or null at the top level.
  String? _openSeries;

  @override
  Widget build(BuildContext context) {
    final libraryAsync = ref.watch(downloadsLibraryProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            if (_openSeries != null) {
              setState(() => _openSeries = null);
            } else {
              context.pop();
            }
          },
        ),
        title: Text(_openSeries ?? 'Downloads'),
        actions: [
          if (_openSeries == null)
            libraryAsync.maybeWhen(
              data: (series) => series.isEmpty
                  ? const SizedBox.shrink()
                  : IconButton(
                      icon: const Icon(Icons.delete_sweep_outlined),
                      tooltip: 'Delete all downloads',
                      onPressed: () => _confirmPurgeAll(context, series),
                    ),
              orElse: () => const SizedBox.shrink(),
            ),
        ],
      ),
      body: libraryAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Could not read downloads.\n$e')),
        data: (series) {
          if (series.isEmpty) return const _EmptyDownloads();

          if (_openSeries == null) {
            return _FolderGrid(
              series: series,
              onOpen: (name) => setState(() => _openSeries = name),
            );
          }

          // Drilled into a folder — find it. If it vanished (last item deleted),
          // fall back to the folder list.
          final matches = series.where((s) => s.series == _openSeries);
          final folder = matches.isEmpty ? null : matches.first;
          if (folder == null) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _openSeries = null);
            });
            return const _EmptyDownloads();
          }

          return _ChapterGrid(
            items: folder.items,
            onDelete: (item) => _confirmDelete(context, item),
          );
        },
      ),
    );
  }

  Future<void> _confirmDelete(
      BuildContext context, DownloadedItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete download?'),
        content:
            Text('"${item.title}" will be removed from this device. It stays '
                'on the server.'),
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
    if (confirmed != true) return;
    await ref.read(downloadProvider(item.mediaId).notifier).delete(item.mediaId);
    ref.invalidate(downloadsLibraryProvider);
  }

  Future<void> _confirmPurgeAll(
      BuildContext context, List<DownloadedSeries> series) async {
    final count =
        series.fold<int>(0, (sum, s) => sum + s.items.length);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete all downloads?'),
        content: Text(
            'All $count downloaded ${count == 1 ? 'item' : 'items'} will be '
            'removed from this device. They stay on the server.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child:
                const Text('Delete all', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed == true) await purgeAllDownloads(ref);
  }
}

// ── Folder (series) grid ─────────────────────────────────────────────────────

class _FolderGrid extends StatelessWidget {
  final List<DownloadedSeries> series;
  final void Function(String series) onOpen;

  const _FolderGrid({required this.series, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        childAspectRatio: 0.58,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: series.length,
      itemBuilder: (context, i) {
        final folder = series[i];
        final count = folder.items.length;
        return _CoverTile(
          mediaId: folder.representative.mediaId,
          title: folder.series,
          subtitle: '$count ${count == 1 ? 'item' : 'items'}',
          badge: count > 1 ? const _FolderBadge() : null,
          onTap: () => onOpen(folder.series),
        );
      },
    );
  }
}

// ── Chapter grid (within a folder) ───────────────────────────────────────────

class _ChapterGrid extends StatelessWidget {
  final List<DownloadedItem> items;
  final void Function(DownloadedItem item) onDelete;

  const _ChapterGrid({required this.items, required this.onDelete});

  void _open(BuildContext context, DownloadedItem item) {
    if (item.isEpub) {
      context.push('/epub/${item.mediaId}', extra: item.title);
    } else {
      context.push('/reader/${item.mediaId}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 180,
        childAspectRatio: 0.58,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        return _CoverTile(
          mediaId: item.mediaId,
          title: item.title,
          subtitle: item.format.toUpperCase(),
          onTap: () => _open(context, item),
          onLongPress: () => onDelete(item),
          onSecondaryTap: () => onDelete(item),
        );
      },
    );
  }
}

// ── Cover tile (shared) ──────────────────────────────────────────────────────

class _CoverTile extends StatelessWidget {
  final String mediaId;
  final String title;
  final String subtitle;
  final Widget? badge;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onSecondaryTap;

  const _CoverTile({
    required this.mediaId,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.badge,
    this.onLongPress,
    this.onSecondaryTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      onSecondaryTap: onSecondaryTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _DownloadCover(mediaId: mediaId),
                  if (badge != null) badge!,
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          Text(
            subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }
}

/// Renders a downloaded item's cover: the persistent local file if present,
/// otherwise the server cover (which shows a placeholder when offline).
class _DownloadCover extends ConsumerWidget {
  final String mediaId;
  const _DownloadCover({required this.mediaId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final coverAsync = ref.watch(downloadedCoverProvider(mediaId));
    final client = ref.watch(apiClientProvider);

    final placeholder = Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Center(child: Icon(Icons.menu_book_outlined, size: 36)),
    );

    return coverAsync.when(
      loading: () => placeholder,
      error: (_, __) => placeholder,
      data: (path) {
        if (path != null) {
          return Image.file(
            File(path),
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => placeholder,
          );
        }
        // No local cover — fall back to the network (placeholder when offline).
        return CoverImage(
          url: client.coverUrl(mediaId),
          headers: client.authHeaders,
          fit: BoxFit.cover,
        );
      },
    );
  }
}

// ── Small pieces ─────────────────────────────────────────────────────────────

class _FolderBadge extends StatelessWidget {
  const _FolderBadge();

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

class _EmptyDownloads extends StatelessWidget {
  const _EmptyDownloads();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.download_done_outlined,
              size: 72, color: Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(height: 16),
          Text('No downloads yet',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text('Downloaded items appear here and open offline.',
              style: Theme.of(context).textTheme.bodyMedium),
        ],
      ),
    );
  }
}
