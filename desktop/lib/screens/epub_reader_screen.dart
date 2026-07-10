import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:sqflite/sqflite.dart';

import '../core/api/api_client.dart';
import '../core/api/media_api.dart';
import '../core/db/local_db_provider.dart';
import '../core/download/download_manager.dart';
import '../core/epub/epub_parser.dart';
import '../core/models/reading_progress.dart';
import '../providers/auth_provider.dart';
import '../providers/reader_provider.dart';
import '../providers/settings_provider.dart';

enum _Theme { light, dark, sepia }

class EpubReaderScreen extends ConsumerStatefulWidget {
  final String mediaId;
  final String title;

  const EpubReaderScreen({
    super.key,
    required this.mediaId,
    required this.title,
  });

  @override
  ConsumerState<EpubReaderScreen> createState() => _EpubReaderScreenState();
}

class _EpubReaderScreenState extends ConsumerState<EpubReaderScreen> {
  EpubBook? _book;
  int _chapterIndex = 0;
  double _fontSize = 16;
  _Theme _theme = _Theme.light;
  bool _showControls = true;
  bool _notDownloaded = false;
  String? _loadError;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _loadEpub();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    // Reset reader state so re-opening restarts a finished book at chapter 0.
    ref.invalidate(readerProvider((widget.mediaId, null)));
    super.dispose();
  }

  Future<void> _loadEpub() async {
    // Resolve the downloaded file from the local DB (not the in-memory
    // download provider, which may still be restoring on a cold offline start).
    final client = ref.read(apiClientProvider);
    final db = ref.read(localDbProvider);
    final dir = await resolveDownloadDir();
    final localPath = await DownloadManager(client, db, downloadBaseDir: dir)
        .localPath(widget.mediaId);
    if (localPath == null) {
      if (mounted) setState(() => _notDownloaded = true);
      return;
    }

    final bytes = await File(localPath).readAsBytes();
    if (!mounted) return;

    final EpubBook book;
    try {
      book = await Isolate.run(() => EpubParser.parse(bytes));
    } catch (_) {
      // A malformed EPUB would otherwise throw out of here and leave the
      // reader on an endless spinner.
      if (mounted) {
        setState(() => _loadError = "This book couldn't be opened.");
      }
      return;
    }
    if (book.chapters.isEmpty) {
      if (mounted) {
        setState(() => _loadError = 'This EPUB has no readable chapters.');
      }
      return;
    }

    // Resolve the saved chapter directly. Reading it from the reader provider
    // synchronously would return 0, because that first access only KICKS OFF
    // the provider's async init — the restored value isn't there yet.
    final savedChapter = await _savedChapter(client, db);
    if (!mounted) return;

    setState(() {
      _book = book;
      _chapterIndex = savedChapter.clamp(0, book.chapters.length - 1);
    });

    ref
        .read(readerProvider((widget.mediaId, null)).notifier)
        .setTotalPages(book.chapters.length);
  }

  /// The saved chapter index, preferring server progress when reachable and
  /// falling back to the local queue. Completed books restart at chapter 0.
  Future<int> _savedChapter(ApiClient client, Database db) async {
    ReadingProgress? progress;
    try {
      progress = await MediaApi(client).getProgress(widget.mediaId);
    } catch (_) {
      // Offline — fall back to the local queue below.
    }
    if (progress == null) {
      final rows = await db.query(
        'progress_queue',
        columns: ['current_page', 'is_completed'],
        where: 'media_id = ?',
        whereArgs: [widget.mediaId],
      );
      if (rows.isNotEmpty) {
        final completed = (rows.first['is_completed'] as int) == 1;
        return completed ? 0 : rows.first['current_page'] as int;
      }
      return 0;
    }
    return progress.isCompleted ? 0 : progress.currentPage;
  }

  void _prevChapter() {
    if (_chapterIndex > 0) {
      setState(() => _chapterIndex--);
      _saveChapter();
    }
  }

  void _nextChapter() {
    final book = _book;
    if (book == null) return;
    if (_chapterIndex < book.chapters.length - 1) {
      setState(() => _chapterIndex++);
      _saveChapter();
    }
  }

  void _saveChapter() {
    ref
        .read(readerProvider((widget.mediaId, null)).notifier)
        .goToPage(_chapterIndex, widget.mediaId);
  }

  Color get _bgColor => switch (_theme) {
        _Theme.light => Colors.white,
        _Theme.dark => const Color(0xFF1A1A1A),
        _Theme.sepia => const Color(0xFFF5ECD7),
      };

  Color get _fgColor => switch (_theme) {
        _Theme.light => Colors.black87,
        _Theme.dark => const Color(0xFFE0E0E0),
        _Theme.sepia => const Color(0xFF3B2C1A),
      };

  @override
  Widget build(BuildContext context) {
    final book = _book;

    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
              event.logicalKey == LogicalKeyboardKey.keyD) { _nextChapter(); }
          if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
              event.logicalKey == LogicalKeyboardKey.keyA) { _prevChapter(); }
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.of(context).pop();
          }
        }
      },
      child: Scaffold(
        backgroundColor: _bgColor,
        body: book == null
            ? (_notDownloaded
                ? _OfflineUnavailable(fgColor: _fgColor)
                : _loadError != null
                    ? _EpubLoadError(message: _loadError!, fgColor: _fgColor)
                    : const Center(child: CircularProgressIndicator()))
            : Stack(
                children: [
                  GestureDetector(
                    onTap: () =>
                        setState(() => _showControls = !_showControls),
                    child: SingleChildScrollView(
                      padding:
                          const EdgeInsets.fromLTRB(24, 80, 24, 100),
                      child: HtmlWidget(
                        book.chapters[_chapterIndex].html,
                        textStyle: TextStyle(
                          fontSize: _fontSize,
                          color: _fgColor,
                          height: 1.6,
                        ),
                      ),
                    ),
                  ),

                  if (_showControls) ...[
                    // Top bar
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        color: _bgColor.withValues(alpha: 0.95),
                        child: SafeArea(
                          bottom: false,
                          child: Row(
                            children: [
                              IconButton(
                                icon:
                                    Icon(Icons.arrow_back, color: _fgColor),
                                onPressed: () =>
                                    Navigator.of(context).pop(),
                              ),
                              Expanded(
                                child: Text(
                                  book.chapters[_chapterIndex].title,
                                  style: TextStyle(
                                    color: _fgColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.palette, color: _fgColor),
                                tooltip: 'Cycle theme',
                                onPressed: () => setState(() {
                                  _theme = _Theme.values[
                                      (_theme.index + 1) %
                                          _Theme.values.length];
                                }),
                              ),
                              IconButton(
                                icon: Icon(Icons.text_decrease,
                                    color: _fgColor),
                                onPressed: () => setState(() =>
                                    _fontSize =
                                        (_fontSize - 1).clamp(10, 32)),
                              ),
                              IconButton(
                                icon: Icon(Icons.text_increase,
                                    color: _fgColor),
                                onPressed: () => setState(() =>
                                    _fontSize =
                                        (_fontSize + 1).clamp(10, 32)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    // Bottom chapter nav
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        color: _bgColor.withValues(alpha: 0.95),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: SafeArea(
                          top: false,
                          child: Row(
                            children: [
                              IconButton(
                                icon: Icon(Icons.chevron_left,
                                    color: _fgColor),
                                onPressed: _chapterIndex > 0
                                    ? _prevChapter
                                    : null,
                              ),
                              Expanded(
                                child: Text(
                                  'Chapter ${_chapterIndex + 1}'
                                  ' / ${book.chapters.length}',
                                  style: TextStyle(color: _fgColor),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.chevron_right,
                                    color: _fgColor),
                                onPressed: _chapterIndex <
                                        book.chapters.length - 1
                                    ? _nextChapter
                                    : null,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

/// Shown when a downloaded EPUB can't be parsed (corrupt / no chapters).
class _EpubLoadError extends StatelessWidget {
  final String message;
  final Color fgColor;
  const _EpubLoadError({required this.message, required this.fgColor});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline,
                size: 64, color: fgColor.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: TextStyle(color: fgColor.withValues(alpha: 0.8)),
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown when an EPUB is opened but hasn't been downloaded and the server is
/// unreachable — mirrors the comic reader's offline message.
class _OfflineUnavailable extends StatelessWidget {
  final Color fgColor;
  const _OfflineUnavailable({required this.fgColor});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off, size: 64, color: fgColor.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            Text(
              "This book isn't available offline yet.",
              textAlign: TextAlign.center,
              style: TextStyle(color: fgColor.withValues(alpha: 0.8)),
            ),
            const SizedBox(height: 6),
            Text(
              'Connect to your server to download it for offline reading.',
              textAlign: TextAlign.center,
              style:
                  TextStyle(color: fgColor.withValues(alpha: 0.5), fontSize: 12),
            ),
            const SizedBox(height: 20),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }
}
