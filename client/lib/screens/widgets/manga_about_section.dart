import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/metadata_api.dart';
import '../../core/models/manga_metadata.dart';
import '../../core/models/scrape_result.dart';
import '../../providers/auth_provider.dart';
import '../../providers/metadata_provider.dart';

/// Expandable "About" section shown at the top of a manga/comic chapter list.
/// Admins see a refresh button that scrapes metadata and handles three outcomes:
///   created   → refreshes and shows a snackbar
///   no_change → snackbar only, no write
///   conflict  → diff dialog before committing
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
      final client = ref.read(apiClientProvider);
      final result = await MetadataApi(client).scrape(widget.mediaId);

      if (!mounted) return;

      switch (result.status) {
        case ScrapeStatus.created:
          ref.invalidate(mangaMetadataProvider(widget.mediaId));
          _showSnackBar('Metadata updated.');

        case ScrapeStatus.noChange:
          _showSnackBar('Metadata is already up to date.');

        case ScrapeStatus.conflict:
          final useNew = await showDialog<bool>(
            context: context,
            barrierDismissible: false,
            builder: (_) => _ConflictDialog(
              proposed: result.data,
              existing: result.existing!,
            ),
          );
          if (useNew == true && mounted) {
            await MetadataApi(client).commit(widget.mediaId, result.data);
            ref.invalidate(mangaMetadataProvider(widget.mediaId));
            _showSnackBar('Metadata updated.');
          }
      }
    } catch (e) {
      if (mounted) _showSnackBar('Scrape failed: $e', isError: true);
    } finally {
      if (mounted) setState(() => _scraping = false);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(message),
      backgroundColor: isError ? Colors.red : null,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final metaAsync = ref.watch(mangaMetadataProvider(widget.mediaId));
    final authState = ref.watch(authProvider).valueOrNull;
    final isAdmin   = authState is AuthAuthenticated && authState.permissionLevel >= 4;
    final theme     = Theme.of(context);
    final cs        = theme.colorScheme;

    return metaAsync.when(
      loading: () => const SizedBox.shrink(),
      error:   (_, __) => const SizedBox.shrink(),
      data: (meta) {
        final hasMeta = meta != null;
        if (!hasMeta && !isAdmin) return const SizedBox.shrink();

        return Card(
          margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Header ──────────────────────────────────────────────────
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
                            width: 20, height: 20,
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

              // ── Body ─────────────────────────────────────────────────────
              if (hasMeta && _expanded)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Divider(height: 1),
                      const SizedBox(height: 12),
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
                              label: _sourceLabel(meta.source!),
                              icon: Icons.public,
                            ),
                        ],
                      ),
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

  static String _formatStatus(String raw) => raw
      .split('_')
      .map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1).toLowerCase()}')
      .join(' ');

  static String _sourceLabel(String source) => switch (source) {
    'mal'       => 'MAL',
    'anilist'   => 'AniList',
    'comicvine' => 'ComicVine',
    _           => source,
  };
}

// ── Conflict dialog ───────────────────────────────────────────────────────────

class _ConflictDialog extends StatelessWidget {
  final MangaMetadata proposed;
  final MangaMetadata existing;

  const _ConflictDialog({required this.proposed, required this.existing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs    = theme.colorScheme;
    final diffs = _buildDiffs();

    return AlertDialog(
      title: const Text('Metadata conflict'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The scraped data differs from what is stored. '
              'Review the changes below and choose which version to keep.',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 16),
            // Column headers
            Row(children: [
              const SizedBox(width: 88),
              Expanded(
                child: Text('Stored',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: cs.onSurfaceVariant)),
              ),
              Expanded(
                child: Text('New',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: cs.primary)),
              ),
            ]),
            const Divider(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: SingleChildScrollView(
                child: Column(
                  children: diffs.map((d) => _DiffRow(diff: d)).toList(),
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Keep existing'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Use new data'),
        ),
      ],
    );
  }

  List<_Diff> _buildDiffs() {
    final diffs = <_Diff>[];
    void add(String field, String? oldVal, String? newVal) {
      if (oldVal != newVal) diffs.add(_Diff(field, oldVal, newVal));
    }

    add('Title',   existing.title,  proposed.title);
    add('Year',    existing.year?.toString(),  proposed.year?.toString());
    add('Status',  existing.status, proposed.status);
    add('Score',   existing.score?.toStringAsFixed(1), proposed.score?.toStringAsFixed(1));
    add('Genres',  existing.genres, proposed.genres);
    add('Source',  existing.source, proposed.source);
    // Truncate synopsis for readability
    final oldSyn = _truncate(existing.synopsis);
    final newSyn = _truncate(proposed.synopsis);
    if (oldSyn != newSyn) diffs.add(_Diff('Synopsis', oldSyn, newSyn));

    return diffs;
  }

  static String? _truncate(String? s, [int max = 120]) {
    if (s == null) return null;
    final cleaned = s.replaceAll(RegExp(r'<[^>]*>'), '').trim();
    return cleaned.length <= max ? cleaned : '${cleaned.substring(0, max)}…';
  }
}

class _Diff {
  final String field;
  final String? oldVal;
  final String? newVal;
  const _Diff(this.field, this.oldVal, this.newVal);
}

class _DiffRow extends StatelessWidget {
  final _Diff diff;
  const _DiffRow({required this.diff});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs    = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(diff.field,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: cs.onSurfaceVariant)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              diff.oldVal ?? '—',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface.withValues(alpha: 0.55),
                decoration: TextDecoration.lineThrough,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              diff.newVal ?? '—',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.primary, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shared sub-widgets ────────────────────────────────────────────────────────

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
    final theme   = Theme.of(context);
    final cleaned = widget.synopsis
        .replaceAll(RegExp(r'<[^>]*>'), '')
        .trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          cleaned,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          maxLines: _showFull ? null : 4,
          overflow: _showFull ? TextOverflow.visible : TextOverflow.fade,
        ),
        const SizedBox(height: 4),
        GestureDetector(
          onTap: () => setState(() => _showFull = !_showFull),
          child: Text(
            _showFull ? 'Show less' : 'Show more',
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.primary),
          ),
        ),
      ],
    );
  }
}
