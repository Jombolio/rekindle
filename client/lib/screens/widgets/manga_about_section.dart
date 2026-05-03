import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_provider.dart';
import '../../providers/metadata_provider.dart';

/// Expandable "About" section shown at the top of a manga chapter list.
/// Admins see a "Scrape" button to pull metadata from MAL/AniList.
class MangaAboutSection extends ConsumerStatefulWidget {
  final String mediaId;

  const MangaAboutSection({super.key, required this.mediaId});

  @override
  ConsumerState<MangaAboutSection> createState() => _MangaAboutSectionState();
}

class _MangaAboutSectionState extends ConsumerState<MangaAboutSection> {
  bool _expanded = false;
  bool _scraping = false;

  Future<void> _scrape() async {
    setState(() => _scraping = true);
    try {
      await ref.read(scrapeMetadataProvider(widget.mediaId).future);
      ref.invalidate(mangaMetadataProvider(widget.mediaId));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Scrape failed: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _scraping = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final metaAsync = ref.watch(mangaMetadataProvider(widget.mediaId));
    final authState = ref.watch(authProvider).valueOrNull;
    final isAdmin = authState is AuthAuthenticated && authState.permissionLevel >= 4;
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return metaAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (meta) {
        final hasMeta = meta != null;

        if (!hasMeta && !isAdmin) return const SizedBox.shrink();

        return Card(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header row
              InkWell(
                onTap: hasMeta ? () => setState(() => _expanded = !_expanded) : null,
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 18, color: cs.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          hasMeta ? (meta.title ?? 'About') : 'No metadata',
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      if (isAdmin) ...[
                        if (_scraping)
                          const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        else
                          IconButton(
                            icon: const Icon(Icons.refresh),
                            tooltip: 'Scrape metadata',
                            iconSize: 18,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: _scrape,
                          ),
                        const SizedBox(width: 8),
                      ],
                      if (hasMeta)
                        Icon(
                          _expanded ? Icons.expand_less : Icons.expand_more,
                          color: cs.onSurfaceVariant,
                        ),
                    ],
                  ),
                ),
              ),

              // Expanded body
              if (hasMeta && _expanded)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Divider(height: 1),
                      const SizedBox(height: 12),

                      // Metadata chips row
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          if (meta.year != null)
                            _MetaChip(label: '${meta.year}', icon: Icons.calendar_today),
                          if (meta.score != null)
                            _MetaChip(
                              label: meta.score!.toStringAsFixed(1),
                              icon: Icons.star_outline,
                            ),
                          if (meta.status != null)
                            _MetaChip(
                              label: _formatStatus(meta.status!),
                              icon: Icons.circle_outlined,
                            ),
                          if (meta.source != null)
                            _MetaChip(
                              label: meta.source == 'mal' ? 'MAL' : 'AniList',
                              icon: Icons.public,
                            ),
                        ],
                      ),

                      // Genres
                      if (meta.genreList.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: meta.genreList
                              .map((g) => Chip(
                                    label: Text(g, style: theme.textTheme.labelSmall),
                                    padding: EdgeInsets.zero,
                                    visualDensity: VisualDensity.compact,
                                    backgroundColor: cs.surfaceContainerHighest,
                                  ))
                              .toList(),
                        ),
                      ],

                      // Synopsis
                      if (meta.synopsis != null && meta.synopsis!.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        _ExpandableSynopsis(synopsis: meta.synopsis!),
                      ],
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  String _formatStatus(String raw) {
    return raw
        .split('_')
        .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
        .join(' ');
  }
}

class _MetaChip extends StatelessWidget {
  final String label;
  final IconData icon;

  const _MetaChip({required this.label, required this.icon});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: cs.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: cs.onSurface)),
        ],
      ),
    );
  }
}

class _ExpandableSynopsis extends StatefulWidget {
  final String synopsis;
  const _ExpandableSynopsis({required this.synopsis});

  @override
  State<_ExpandableSynopsis> createState() => _ExpandableSynopsisState();
}

class _ExpandableSynopsisState extends State<_ExpandableSynopsis> {
  bool _showFull = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cleaned = widget.synopsis
        .replaceAll(RegExp(r'<[^>]*>'), '')  // strip any HTML tags
        .trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          cleaned,
          style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant),
          maxLines: _showFull ? null : 4,
          overflow: _showFull ? TextOverflow.visible : TextOverflow.fade,
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: () => setState(() => _showFull = !_showFull),
          child: Text(
            _showFull ? 'Show less' : 'Show more',
            style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.primary),
          ),
        ),
      ],
    );
  }
}
