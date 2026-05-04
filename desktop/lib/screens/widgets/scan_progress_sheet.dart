import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/api/libraries_api.dart';
import '../../core/models/scan_progress.dart';

class ScanProgressSheet extends StatefulWidget {
  final String libraryId;
  final String libraryName;
  final LibrariesApi api;

  const ScanProgressSheet({
    super.key,
    required this.libraryId,
    required this.libraryName,
    required this.api,
  });

  @override
  State<ScanProgressSheet> createState() => _ScanProgressSheetState();
}

class _ScanProgressSheetState extends State<ScanProgressSheet> {
  Timer? _timer;
  ScanProgress _progress = const ScanProgress();

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(const Duration(milliseconds: 1500), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _poll() async {
    try {
      final p = await widget.api.getScanProgress(widget.libraryId);
      if (!mounted) return;
      setState(() => _progress = p);
      if (p.isComplete) _timer?.cancel();
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = _progress;
    final isDone = p.isComplete;
    final hasFileCount = p.filesTotal > 0;
    final hasCovers = p.coversQueued > 0;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isDone ? 'Scan complete' : 'Scanning library…',
                        style: theme.textTheme.titleMedium
                            ?.copyWith(fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.libraryName,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                if (isDone)
                  Icon(Icons.check_circle_outline,
                      color: Colors.green.shade600, size: 28)
                else
                  const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ),
              ],
            ),

            const SizedBox(height: 20),

            // ── File scan progress bar ───────────────────────────────────────
            _SectionLabel(label: 'Files', theme: theme),
            const SizedBox(height: 6),
            _ProgressBar(
              value: isDone
                  ? 1.0
                  : hasFileCount
                      ? p.scanProgress
                      : null,
            ),
            const SizedBox(height: 5),
            Text(
              _fileCountLabel(p, isDone),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),

            const SizedBox(height: 20),

            // ── Stats row ────────────────────────────────────────────────────
            Row(
              children: [
                _StatCell(
                  label: 'New archives',
                  value: p.added,
                  icon: Icons.archive_outlined,
                ),
                _StatCell(
                  label: 'New folders',
                  value: p.folders,
                  icon: Icons.folder_outlined,
                ),
                _StatCell(
                  label: 'Removed',
                  value: p.removed,
                  icon: Icons.delete_outline,
                  highlight: p.removed > 0,
                ),
              ],
            ),

            // ── Cover caching progress ───────────────────────────────────────
            if (hasCovers) ...[
              const SizedBox(height: 20),
              _SectionLabel(label: 'Cover cache', theme: theme),
              const SizedBox(height: 6),
              _ProgressBar(value: p.coverProgress),
              const SizedBox(height: 5),
              Text(
                '${p.coversGenerated} / ${p.coversQueued}',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],

            const SizedBox(height: 28),

            // ── Done button ──────────────────────────────────────────────────
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: isDone ? () => Navigator.of(context).pop() : null,
                child: Text(isDone ? 'Done' : 'Scanning…'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _fileCountLabel(ScanProgress p, bool isDone) {
    if (isDone && p.filesTotal > 0) return '${p.filesTotal} files processed';
    if (p.filesTotal > 0) return '${p.filesProcessed} / ${p.filesTotal} files';
    if (isDone) return 'No files found';
    return 'Discovering files…';
  }
}

// ── Helper widgets ────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String label;
  final ThemeData theme;
  const _SectionLabel({required this.label, required this.theme});

  @override
  Widget build(BuildContext context) => Text(
        label.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          letterSpacing: 0.8,
        ),
      );
}

class _ProgressBar extends StatelessWidget {
  final double? value;
  const _ProgressBar({this.value});

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(value: value, minHeight: 7),
      );
}

class _StatCell extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final bool highlight;

  const _StatCell({
    required this.label,
    required this.value,
    required this.icon,
    this.highlight = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = highlight
        ? Colors.orange.shade700
        : theme.colorScheme.onSurface;

    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 22, color: color),
          const SizedBox(height: 4),
          Text(
            '$value',
            style: theme.textTheme.titleLarge?.copyWith(
              color: color,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
