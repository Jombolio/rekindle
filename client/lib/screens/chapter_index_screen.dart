import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/download/download_state.dart';
import '../core/models/media.dart';
import '../providers/auth_provider.dart';
import '../providers/chapter_provider.dart';
import '../providers/download_provider.dart';
import 'widgets/cover_image.dart';
import 'widgets/download_button.dart';
import 'widgets/error_view.dart';

class ChapterIndexScreen extends ConsumerWidget {
  final String folderId;
  final String folderTitle;

  const ChapterIndexScreen({
    super.key,
    required this.folderId,
    required this.folderTitle,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chaptersAsync = ref.watch(chapterProvider(folderId));
    final client = ref.watch(apiClientProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(folderTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(chapterProvider(folderId)),
          ),
        ],
      ),
      body: chaptersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
          message: e.toString(),
          onRetry: () => ref.invalidate(chapterProvider(folderId)),
        ),
        data: (items) {
          final subfolders = items.where((m) => m.isFolder).toList();
          final archives = items.where((m) => !m.isFolder).toList();

          if (subfolders.isEmpty && archives.isEmpty) {
            return const Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.folder_open_outlined, size: 64),
                  SizedBox(height: 16),
                  Text('No chapters found. Try scanning the library.'),
                ],
              ),
            );
          }

          final totalItems =
              (subfolders.isNotEmpty ? subfolders.length + 1 : 0) +
              archives.length;

          return ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: totalItems,
            itemBuilder: (_, i) {
              if (subfolders.isNotEmpty) {
                if (i == 0) {
                  return const _SectionHeader(label: 'Subfolders');
                }
                if (i <= subfolders.length) {
                  return _SubfolderTile(
                    folder: subfolders[i - 1],
                    coverUrl: client.coverUrl(subfolders[i - 1].id),
                    authHeaders: client.authHeaders,
                  );
                }
                final archiveIndex = i - subfolders.length - 1;
                return _ChapterTile(
                  chapter: archives[archiveIndex],
                  index: archiveIndex,
                  coverUrl: client.coverUrl(archives[archiveIndex].id),
                  authHeaders: client.authHeaders,
                );
              }
              return _ChapterTile(
                chapter: archives[i],
                index: i,
                coverUrl: client.coverUrl(archives[i].id),
                authHeaders: client.authHeaders,
              );
            },
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

  const _SubfolderTile({
    required this.folder,
    required this.coverUrl,
    required this.authHeaders,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      leading: Stack(
        children: [
          SizedBox(
            width: 48,
            height: 68,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: CoverImage(
                url: coverUrl,
                headers: authHeaders,
                borderRadius: BorderRadius.zero,
              ),
            ),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.85),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Icon(Icons.folder,
                  size: 10,
                  color: Theme.of(context).colorScheme.onPrimary),
            ),
          ),
        ],
      ),
      title: Text(
        folder.displayTitle,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => context.push(
        '/series/${folder.id}',
        extra: <String, String?>{'title': folder.displayTitle},
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

  const _ChapterTile({
    required this.chapter,
    required this.index,
    required this.coverUrl,
    required this.authHeaders,
  });

  void _open(BuildContext context) {
    if (chapter.isImageBased) {
      context.push('/reader/${chapter.id}');
    } else {
      context.push('/epub/${chapter.id}', extra: chapter.title);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final downloadState = ref.watch(downloadProvider(chapter.id));
    final isOffline = downloadState.status == DownloadStatus.complete;
    final theme = Theme.of(context);
    final authState = ref.watch(authProvider).valueOrNull;
    final canDownload =
        authState is AuthAuthenticated && authState.canDownload;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      leading: Stack(
        children: [
          SizedBox(
            width: 48,
            height: 68,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: CoverImage(
                url: coverUrl,
                headers: authHeaders,
                borderRadius: BorderRadius.zero,
              ),
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
        ],
      ),
      title: Text(
        chapter.title,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyMedium,
      ),
      subtitle: isOffline
          ? Text('Downloaded',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: Colors.green.shade700))
          : null,
      trailing: canDownload
          ? SizedBox(
              width: 40,
              height: 40,
              child: DownloadButton(media: chapter),
            )
          : null,
      onTap: () => _open(context),
    );
  }
}
