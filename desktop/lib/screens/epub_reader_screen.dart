import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:sqflite/sqflite.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api/api_client.dart';
import '../core/api/media_api.dart';
import '../core/db/local_db_provider.dart';
import '../core/download/download_manager.dart';
import '../core/epub/epub_parser.dart';
import '../core/models/reading_progress.dart';
import '../providers/auth_provider.dart';
import '../providers/discord_presence_provider.dart';
import '../providers/reader_provider.dart';
import '../providers/settings_provider.dart';

enum _Theme { light, dark, sepia }

/// URL scheme for paths inside the open book.
const _bookScheme = 'rekindle-book';

/// How long a restored position keeps being re-applied while a chapter lays out.
const _restoreWindow = Duration(seconds: 2);

/// How long a chapter gets to lay out before "nothing to scroll" means it's
/// short. Large chapters build asynchronously, so this errs on the long side.
const _shortChapterDelay = Duration(seconds: 5);

/// A book is finished once the reader is at the end of its last chapter. Merely
/// opening the last chapter doesn't count, and neither does being a little short
/// of the very bottom, which scrolling doesn't always reach.
bool isBookFinished({
  required int chapter,
  required int chapterCount,
  required double fraction,
}) =>
    chapter >= chapterCount - 1 && fraction >= 0.97;

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
  final ScrollController _scroll = ScrollController();
  double? _pendingFraction;
  DateTime _restoreDeadline = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _shortChapterTimer;

  @override
  void initState() {
    super.initState();
    ref.read(nowReadingProvider.notifier).open(
          widget.mediaId,
          libraryType: 'book',
          fallbackTitle: widget.title,
          countsChapters: true,
        );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _loadEpub();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _shortChapterTimer?.cancel();
    // A last save for scrolling still under way as the reader closes.
    if (_book != null && _activeRestore == null && _scroll.hasClients) {
      _savePosition(_currentFraction);
    }
    _scroll.dispose();
    ref.read(nowReadingProvider.notifier).close(widget.mediaId);
    // Reset reader state so re-opening restarts a finished book at chapter 0.
    ref.invalidate(readerProvider((widget.mediaId, null)));
    // Refresh the chapter/grid badges: the list screen underneath stays mounted,
    // so localProgressProvider never auto-disposes and would keep showing the
    // pre-open progress.
    ref.invalidate(localProgressProvider(widget.mediaId));
    super.dispose();
  }

  Future<void> _loadEpub() async {
    final client = ref.read(apiClientProvider);
    final db = ref.read(localDbProvider);

    final EpubBook book;
    try {
      final bytes = await _readBookBytes(client, db);
      if (bytes == null || !mounted) return;
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

    // Resolve the saved position directly. Reading it from the reader provider
    // synchronously would return 0, because that first access only KICKS OFF
    // the provider's async init — the restored value isn't there yet.
    final saved = await _savedPosition(client, db);
    if (!mounted) return;

    final chapter = saved.chapter.clamp(0, book.chapters.length - 1);
    setState(() {
      _book = book;
      _chapterIndex = chapter;
    });

    ref.read(readerProvider((widget.mediaId, null)).notifier).openBook(
          chapterCount: book.chapters.length,
          chapter: chapter,
          fraction: saved.fraction,
        );
    _restorePosition(saved.fraction ?? 0);
    _scheduleShortChapterCheck();
    _reportChapter();
  }

  /// The book's bytes: the downloaded copy when there is a usable one, otherwise
  /// from the server. Returns null, with the screen updated, if neither works.
  Future<Uint8List?> _readBookBytes(ApiClient client, Database db) async {
    // Resolve the downloaded file from the local DB (not the in-memory
    // download provider, which may still be restoring on a cold offline start).
    final dir = await resolveDownloadDir();
    final localPath = await DownloadManager(client, db, downloadBaseDir: dir)
        .localPath(widget.mediaId);
    if (localPath != null && await EpubParser.isEpubFile(localPath)) {
      return File(localPath).readAsBytes();
    }

    try {
      return await MediaApi(client).getBookBytes(widget.mediaId);
    } on DioException catch (e) {
      if (!mounted) return null;
      final reason = _serverReason(e);
      setState(() {
        if (reason != null) {
          _loadError = reason;
        } else if (e.response == null) {
          _notDownloaded = true;
        } else {
          _loadError = "This book couldn't be opened.";
        }
      });
      return null;
    }
  }

  /// Why the server can't provide this book: a read-only account, or a reason it
  /// gave itself, such as a DRM-protected MOBI.
  String? _serverReason(DioException e) {
    if (e.response?.statusCode == 403) {
      return "Your account doesn't have permission to open this book.";
    }
    final data = e.response?.data;
    if (e.response?.statusCode != 422 || data is! List<int>) return null;
    try {
      final json = jsonDecode(utf8.decode(data));
      return json is Map ? json['error'] as String? : null;
    } catch (_) {
      return null;
    }
  }

  /// The saved position. Unsynced local progress wins (it's newer than anything
  /// the server has — same rule as the comic reader); otherwise the server value,
  /// then the synced local row. Completed books restart at the beginning.
  Future<({int chapter, double? fraction})> _savedPosition(
      ApiClient client, Database db) async {
    ({int chapter, double? fraction}) position(
            int chapter, bool completed, double? fraction) =>
        completed
            ? (chapter: 0, fraction: null)
            : (chapter: chapter, fraction: fraction);

    final rows = await db.query(
      'progress_queue',
      columns: ['current_page', 'is_completed', 'synced', 'position_fraction'],
      where: 'media_id = ?',
      whereArgs: [widget.mediaId],
    );
    ({int chapter, double? fraction})? local;
    var localSynced = true;
    if (rows.isNotEmpty) {
      local = position(
        rows.first['current_page'] as int,
        (rows.first['is_completed'] as int) == 1,
        (rows.first['position_fraction'] as num?)?.toDouble(),
      );
      localSynced = (rows.first['synced'] as int? ?? 0) == 1;
    }
    if (local != null && !localSynced) return local;

    ReadingProgress? progress;
    try {
      progress = await MediaApi(client).getProgress(widget.mediaId);
    } catch (_) {
      // Offline — fall back to the local queue below.
    }
    if (progress != null) {
      return position(
        progress.currentPage,
        progress.isCompleted,
        progress.positionFraction,
      );
    }
    return local ?? (chapter: 0, fraction: null);
  }

  void _prevChapter() {
    if (_chapterIndex > 0) _goToChapter(_chapterIndex - 1);
  }

  void _nextChapter() {
    final book = _book;
    if (book == null) return;
    if (_chapterIndex < book.chapters.length - 1) {
      _goToChapter(_chapterIndex + 1);
    }
  }

  void _goToChapter(int index) {
    setState(() => _chapterIndex = index);
    _restorePosition(0);
    _savePosition(0);
    _scheduleShortChapterCheck();
    _reportChapter();
  }

  // ── Position within a chapter ────────────────────────────────────────────

  /// Scrolls to [fraction] of the chapter. The chapter's height keeps changing
  /// while it builds and its images load, so the target is held and re-applied
  /// as the height changes, until the reader scrolls or it has settled.
  void _restorePosition(double fraction) {
    _pendingFraction = fraction;
    _restoreDeadline = DateTime.now().add(_restoreWindow);
    WidgetsBinding.instance.addPostFrameCallback((_) => _applyPendingPosition());
  }

  void _applyPendingPosition() {
    final fraction = _activeRestore;
    if (fraction == null || !mounted || !_scroll.hasClients) return;
    final target = fraction * _scroll.position.maxScrollExtent;
    if ((_scroll.position.pixels - target).abs() > 1) _scroll.jumpTo(target);
  }

  void _cancelRestore() => _pendingFraction = null;

  /// The fraction still being restored, if the restore hasn't settled yet.
  double? get _activeRestore {
    if (DateTime.now().isAfter(_restoreDeadline)) _pendingFraction = null;
    return _pendingFraction;
  }

  /// Where the view is now, as a fraction of the chapter.
  double get _currentFraction {
    final pending = _activeRestore;
    if (pending != null || !_scroll.hasClients) return pending ?? 0;
    final max = _scroll.position.maxScrollExtent;
    return max <= 0 ? 0 : (_scroll.position.pixels / max).clamp(0.0, 1.0);
  }

  bool _onScrollNotification(Notification notification) {
    if (notification is ScrollMetricsNotification) {
      WidgetsBinding.instance
          .addPostFrameCallback((_) => _applyPendingPosition());
    } else if (notification is ScrollEndNotification &&
        _activeRestore == null) {
      _savePosition(_currentFraction);
    }
    return false;
  }

  void _savePosition(double fraction) {
    final book = _book;
    if (book == null) return;
    ref.read(readerProvider((widget.mediaId, null)).notifier).setBookPosition(
          widget.mediaId,
          chapter: _chapterIndex,
          fraction: fraction,
          completed: isBookFinished(
            chapter: _chapterIndex,
            chapterCount: book.chapters.length,
            fraction: fraction,
          ),
        );
  }

  /// A chapter too short to scroll never produces a scroll to save from, so once
  /// it has had time to lay out, count it as read to its end. Otherwise a book
  /// ending in a short afterword could never be finished.
  void _scheduleShortChapterCheck() {
    _shortChapterTimer?.cancel();
    _shortChapterTimer = Timer(_shortChapterDelay, () {
      if (!mounted || !_scroll.hasClients) return;
      if (_scroll.position.maxScrollExtent <= 0) _savePosition(1);
    });
  }

  /// Changes something that reflows the chapter, keeping the reader's place.
  void _reflow(VoidCallback change) {
    final fraction = _currentFraction;
    setState(change);
    _restorePosition(fraction);
  }

  void _onTapLink(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (uri.scheme == 'http' || uri.scheme == 'https') {
      launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }
    final book = _book;
    if (book == null || uri.scheme != _bookScheme) return;
    final target = book.chapterIndexOf(Uri.decodeFull(uri.path));
    if (target != null && target != _chapterIndex) _goToChapter(target);
  }

  void _reportChapter() {
    final book = _book;
    if (book == null) return;
    ref
        .read(nowReadingProvider.notifier)
        .updatePosition(widget.mediaId, _chapterIndex, book.chapters.length);
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
                    // Any direct input means the reader has taken over from a
                    // pending restore.
                    child: Listener(
                      onPointerDown: (_) => _cancelRestore(),
                      onPointerSignal: (_) => _cancelRestore(),
                      child: NotificationListener<Notification>(
                        onNotification: _onScrollNotification,
                        child: SingleChildScrollView(
                          controller: _scroll,
                          padding:
                              const EdgeInsets.fromLTRB(24, 80, 24, 100),
                          child: BookChapterView(
                            book: book,
                            chapter: book.chapters[_chapterIndex],
                            textStyle: TextStyle(
                              fontSize: _fontSize,
                              color: _fgColor,
                              height: 1.6,
                            ),
                            onTapLink: _onTapLink,
                          ),
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
                                onPressed: () => _reflow(() {
                                  _theme = _Theme.values[
                                      (_theme.index + 1) %
                                          _Theme.values.length];
                                }),
                              ),
                              IconButton(
                                icon: Icon(Icons.text_decrease,
                                    color: _fgColor),
                                onPressed: () => _reflow(() =>
                                    _fontSize =
                                        (_fontSize - 1).clamp(10, 32)),
                              ),
                              IconButton(
                                icon: Icon(Icons.text_increase,
                                    color: _fgColor),
                                onPressed: () => _reflow(() =>
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

/// One chapter, with its images and links resolved against the book.
@visibleForTesting
class BookChapterView extends StatelessWidget {
  final EpubBook book;
  final EpubChapter chapter;
  final TextStyle textStyle;
  final void Function(String url) onTapLink;

  const BookChapterView({
    super.key,
    required this.book,
    required this.chapter,
    required this.textStyle,
    required this.onTapLink,
  });

  @override
  Widget build(BuildContext context) {
    return HtmlWidget(
      chapter.html,
      baseUrl: Uri(scheme: _bookScheme, host: 'book', path: '/${chapter.path}'),
      factoryBuilder: () => _BookWidgetFactory(book),
      textStyle: textStyle,
      customStylesBuilder: (element) {
        final styles = chapter.styles.stylesFor(
          element.localName ?? '',
          element.classes,
        );
        return styles.isEmpty ? null : styles;
      },
      onTapUrl: (url) {
        onTapLink(url);
        return true;
      },
    );
  }
}

/// Serves images from inside the book. Anything else a book asks for is refused,
/// so opening one can't make network requests.
class _BookWidgetFactory extends WidgetFactory {
  final EpubBook book;
  _BookWidgetFactory(this.book);

  @override
  ImageProvider<Object>? imageProviderFromNetwork(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != _bookScheme) return null;
    final bytes = book.imageAt(Uri.decodeFull(uri.path));
    return bytes == null ? null : MemoryImage(bytes);
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
