import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:ui' as ui;

import 'package:csslib/visitor.dart' as css;
import 'package:dio/dio.dart';
import 'package:flutter/gestures.dart'
    show PointerScrollEvent, PointerSignalEvent;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show SelectedContent;
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:sqflite/sqflite.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/api/api_client.dart';
import '../core/api/media_api.dart';
import '../core/db/local_db_provider.dart';
import '../core/download/download_manager.dart';
import '../core/dictionary/word_forms.dart';
import '../core/dictionary/wordnet_dictionary.dart';
import '../core/epub/book_styles.dart';
import '../core/epub/book_theme.dart';
import '../core/epub/reading_style.dart';
import '../core/epub/epub_parser.dart';
import '../core/epub/reader_book.dart';
import '../core/epub/remote_book.dart';
import '../core/models/reading_progress.dart';
import '../providers/auth_provider.dart';
import '../providers/discord_presence_provider.dart';
import '../providers/reader_provider.dart';
import '../providers/settings_provider.dart';
import 'widgets/definition_popup.dart';
import 'book/continuous_book_view.dart';
import 'book/paged_chapter_view.dart';
import 'widgets/page_tap_detector.dart';
import 'widgets/reading_options.dart';

/// URL scheme for paths inside the open book.
const _bookScheme = 'rekindle-book';

/// How long a restored position keeps being re-applied while a chapter lays out.
const _restoreWindow = Duration(seconds: 2);

/// How long a selection has to settle before its definition appears.
const _defineDelay = Duration(milliseconds: 350);

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
  /// For [dispose], where `ref` can no longer be used.
  late final ProviderContainer _container;
  ReaderBook? _book;
  EpubChapter? _chapter;
  bool _chapterFailed = false;
  int _chapterIndex = 0;

  /// The theme picked with the palette button, for this visit only. Until then
  /// the reader follows the default in Settings.
  BookTheme? _themeOverride;
  bool _showControls = true;
  bool _notDownloaded = false;
  String? _loadError;
  final FocusNode _focusNode = FocusNode();
  final ScrollController _scroll = ScrollController();
  double? _pendingFraction;
  DateTime _restoreDeadline = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _shortChapterTimer;
  int _chapterRequest = 0;
  double _wantedFraction = 0;

  // The paged and continuous layouts keep their own place and report it here.
  GlobalKey<PagedChapterViewState> _pagedKey = GlobalKey();
  PagePosition? _pagePosition;
  double _layoutFraction = 0;
  int _continuousStart = 0;
  double _continuousFraction = 0;
  int _continuousEpoch = 0;
  DateTime _lastWheelTurn = DateTime.fromMillisecondsSinceEpoch(0);

  /// Turning into another chapter: the page being left, which the next
  /// chapter's pages slide in over, and which direction.
  ui.Image? _arrivingFrom;
  int _arrivalDirection = 0;

  /// Where the reading ruler sits, following the pointer.
  final ValueNotifier<double?> _rulerY = ValueNotifier(null);

  void _moveRuler(PointerEvent event) => _rulerY.value = event.localPosition.dy;
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey();

  // The dictionary pop-up. It appears once a selection has settled and the pointer
  // is up, so dragging across a passage doesn't flash definitions along the way.
  String? _selectedText;
  Timer? _defineTimer;
  bool _pointerDown = false;
  Offset _pointerAt = Offset.zero;
  int _defineRequest = 0;
  ({String word, List<DictionaryEntry> entries, Offset at})? _definition;
  bool _ignoreNextTap = false;

  @override
  void initState() {
    super.initState();
    _container = ProviderScope.containerOf(context, listen: false);
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

  /// A last save for scrolling still under way as the reader closes. Here, not
  /// in [dispose]: by then the scroll view is gone, so this never ran.
  /// Not while a chapter is still loading: there's no position to read yet, and
  /// saving one would overwrite the saved place.
  @override
  void deactivate() {
    if (_layout == BookLayout.scroll &&
        _chapter != null &&
        _activeRestore == null &&
        _scroll.hasClients) {
      _savePosition(_currentFraction);
    }
    super.deactivate();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _shortChapterTimer?.cancel();
    _defineTimer?.cancel();
    _scroll.dispose();
    _rulerY.dispose();
    _arrivingFrom?.dispose();
    // Through the container: `ref` throws once the widget is unmounting, which
    // used to abort this method before the reader provider was invalidated. Its
    // closing save never ran, and a still-pending debounced save would later
    // write the position of the next time the book was opened over newer
    // progress.
    _container.read(nowReadingProvider.notifier).close(widget.mediaId);
    // Reset reader state so re-opening restarts a finished book at chapter 0.
    // This also flushes the progress still waiting on the debounce.
    _container.invalidate(readerProvider((widget.mediaId, null)));
    // Refresh the chapter/grid badges: the list screen underneath stays mounted,
    // so localProgressProvider never auto-disposes and would keep showing the
    // pre-open progress.
    _container.invalidate(localProgressProvider(widget.mediaId));
    super.dispose();
  }

  Future<void> _loadEpub() async {
    final client = ref.read(apiClientProvider);
    final db = ref.read(localDbProvider);

    final ReaderBook? book;
    try {
      book = await _openBook(client, db);
    } catch (_) {
      // A malformed EPUB would otherwise throw out of here and leave the
      // reader on an endless spinner.
      if (mounted) {
        setState(() => _loadError = "This book couldn't be opened.");
      }
      return;
    }
    if (book == null || !mounted) return;
    if (book.chapterCount == 0) {
      setState(() => _loadError = 'This book has no readable chapters.');
      return;
    }

    // Resolve the saved position directly. Reading it from the reader provider
    // synchronously would return 0, because that first access only KICKS OFF
    // the provider's async init — the restored value isn't there yet.
    final saved = await _savedPosition(client, db);
    if (!mounted) return;

    final chapter = saved.chapter.clamp(0, book.chapterCount - 1);
    setState(() {
      _book = book;
      _chapterIndex = chapter;
      _continuousStart = chapter;
      _continuousFraction = saved.fraction ?? 0;
      _layoutFraction = saved.fraction ?? 0;
    });

    ref.read(readerProvider((widget.mediaId, null)).notifier).openBook(
          chapterCount: book.chapterCount,
          chapter: chapter,
          fraction: saved.fraction,
        );
    await _showChapter(chapter, saved.fraction ?? 0);
    _reportChapter();
  }

  /// The downloaded copy when there is a usable one, otherwise streamed from the
  /// server. Returns null, with the screen updated, if neither works.
  Future<ReaderBook?> _openBook(ApiClient client, Database db) async {
    // Resolve the downloaded file from the local DB (not the in-memory
    // download provider, which may still be restoring on a cold offline start).
    final dir = await resolveDownloadDir();
    final localPath = await DownloadManager(client, db, downloadBaseDir: dir)
        .localPath(widget.mediaId);
    if (localPath != null && await EpubParser.isEpubFile(localPath)) {
      final bytes = await File(localPath).readAsBytes();
      return Isolate.run(() => EpubParser.parse(bytes));
    }

    try {
      return await RemoteBook.open(client, widget.mediaId);
    } on DioException catch (e) {
      if (!mounted) return null;
      setState(() {
        final status = e.response?.statusCode;
        if (e.response == null) {
          _notDownloaded = true;
        } else if (status == 404) {
          _loadError = 'Your server needs updating to read this book without '
              'downloading it.';
        } else {
          _loadError = _serverReason(e) ?? "This book couldn't be opened.";
        }
      });
      return null;
    }
  }

  /// The explanation the server gives for a book it can't provide, such as a
  /// DRM-protected Kindle file.
  String? _serverReason(DioException e) {
    final data = e.response?.data;
    return data is Map ? data['error'] as String? : null;
  }

  /// Fetches a chapter and shows it at [fraction]. A newer request wins if the
  /// reader moves on while this one is still on its way.
  Future<void> _showChapter(int index, double fraction) async {
    final book = _book;
    if (book == null) return;
    final request = ++_chapterRequest;
    _wantedFraction = fraction;
    setState(() {
      _chapter = null;
      _chapterFailed = false;
      _pagedKey = GlobalKey();
      _pagePosition = null;
    });
    try {
      final chapter = await book.loadChapter(index);
      if (!mounted || request != _chapterRequest) return;
      setState(() => _chapter = chapter);
      if (_layout == BookLayout.scroll) {
        _restorePosition(fraction);
        _scheduleShortChapterCheck();
      }
    } catch (_) {
      if (mounted && request == _chapterRequest) {
        setState(() => _chapterFailed = true);
      }
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
    if (_chapterIndex < book.chapterCount - 1) {
      _goToChapter(_chapterIndex + 1);
    }
  }

  /// Keeps the page on screen as an image, for the next chapter to slide in
  /// over, turning in [direction].
  void _carryPage(int direction) {
    if (!ref.read(settingsProvider).readingStyle.animations) return;
    final image = _pagedKey.currentState?.snapshot();
    if (image == null) return;
    // An earlier image belongs to the view it was given to, which lets it go.
    _arrivingFrom = image;
    _arrivalDirection = direction;
  }

  /// Opens chapter [index] at [fraction]: 0 is its start, 1 its last page.
  void _goToChapter(int index, {double fraction = 0}) {
    setState(() {
      _chapterIndex = index;
      _layoutFraction = fraction;
    });
    _savePosition(fraction);
    if (_layout == BookLayout.continuous) {
      setState(() {
        _continuousStart = index;
        _continuousFraction = fraction;
        _continuousEpoch++;
      });
    } else {
      _showChapter(index, fraction);
    }
    _reportChapter();
  }

  BookLayout get _layout => ref.read(settingsProvider).readingStyle.layout;

  /// Forward a page in the paged layouts, otherwise a chapter.
  void _forward() {
    final paged = _pagedKey.currentState;
    if (_layout.paged && paged != null) {
      paged.next();
    } else {
      _nextChapter();
    }
  }

  void _back() {
    final paged = _pagedKey.currentState;
    if (_layout.paged && paged != null) {
      paged.previous();
    } else {
      _prevChapter();
    }
  }

  /// Where the reader is in the current chapter, whichever the layout.
  double _fractionIn(BookLayout layout) =>
      layout == BookLayout.scroll ? _currentFraction : _layoutFraction;

  /// Carries the reader's place across a change of layout or of anything that
  /// reflows the text.
  void _onSettingsChanged(SettingsState? before, SettingsState after) {
    if (before == null || _book == null) return;
    final from = before.readingStyle.layout;
    final to = after.readingStyle.layout;
    final fraction = _fractionIn(from);
    if (from != to) {
      _layoutFraction = fraction;
      if (to == BookLayout.continuous) {
        setState(() {
          _continuousStart = _chapterIndex;
          _continuousFraction = fraction;
          _continuousEpoch++;
        });
      } else {
        // The continuous layout loads chapters itself; the others need the
        // current one, and a fresh paged view.
        _showChapter(_chapterIndex, fraction);
      }
      return;
    }
    final reflows = before.bookFont != after.bookFont ||
        before.bookFontSize != after.bookFontSize ||
        before.readingStyle != after.readingStyle;
    if (reflows && from == BookLayout.scroll) _restorePosition(fraction);
  }

  void _onPage(PagePosition position, {required bool turned}) {
    final book = _book;
    if (!mounted || book == null) return;
    // The last page counts as the end of the chapter, so a book read page by
    // page can be finished.
    final step = _layout == BookLayout.spread ? 2 : 1;
    final atEnd = position.page + step >= position.count;
    final fraction = atEnd ? 1.0 : position.fraction;
    setState(() {
      _pagePosition = position;
      _layoutFraction = position.fraction;
    });
    if (turned) _savePosition(fraction);
  }

  void _onContinuousPosition(int chapter, double fraction,
      {required bool settled}) {
    _layoutFraction = fraction;
    if (chapter != _chapterIndex) {
      setState(() => _chapterIndex = chapter);
      _reportChapter();
    }
    if (settled) _savePosition(fraction);
  }

  /// A tap near either side of a page turns it, in the paged layouts.
  bool _turnByTap(Offset position) {
    if (!_layout.paged) return false;
    final width = MediaQuery.sizeOf(context).width;
    if (position.dx < width * 0.3) {
      _back();
      return true;
    }
    if (position.dx > width * 0.7) {
      _forward();
      return true;
    }
    return false;
  }

  /// One page per wheel gesture: a trackpad sends a stream of small scrolls.
  void _turnByWheel(PointerSignalEvent event) {
    if (!_layout.paged || event is! PointerScrollEvent) return;
    final now = DateTime.now();
    if (now.difference(_lastWheelTurn) < const Duration(milliseconds: 350)) {
      return;
    }
    final dy = event.scrollDelta.dy;
    if (dy.abs() < 1) return;
    _lastWheelTurn = now;
    dy > 0 ? _forward() : _back();
  }

  // ── Position within a chapter ────────────────────────────────────────────

  /// Scrolls to [fraction] of the chapter. The chapter's height keeps changing
  /// while it builds and its images load, so the target is held and re-applied
  /// as the height changes, until the reader scrolls or it has settled.
  void _restorePosition(double fraction) {
    _pendingFraction = fraction;
    _restoreDeadline = DateTime.now().add(_restoreWindow);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _applyPendingPosition());
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
    if (_chapter == null) return _pendingFraction ?? 0;
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
            chapterCount: book.chapterCount,
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
    // Not inside setState: saving a setting returns a Future, which setState rejects.
    change();
    setState(() {});
    _restorePosition(fraction);
  }

  // ── Dictionary ───────────────────────────────────────────────────────────

  void _onSelectionChanged(SelectedContent? content) {
    _selectedText = content?.plainText;
    _defineRequest++;
    _defineTimer?.cancel();
    if (_selectedText == null || _selectedText!.trim().isEmpty) {
      _dismissDefinition();
      return;
    }
    if (!_pointerDown) _scheduleDefine();
  }

  void _scheduleDefine() {
    _defineTimer?.cancel();
    _defineTimer = Timer(_defineDelay, _define);
  }

  Future<void> _define() async {
    final text = _selectedText;
    if (text == null ||
        !mounted ||
        !ref.read(settingsProvider).defineOnSelect) {
      return;
    }
    // A sentence selected to copy isn't a word to look up.
    final word = WordForms.normalize(text);
    if (word == null) return;

    final request = ++_defineRequest;
    final at = _pointerAt;
    final List<DictionaryEntry> entries;
    try {
      entries = await (await WordNetDictionary.open()).lookup(text);
    } catch (_) {
      return; // A missing definition should never interrupt reading.
    }
    if (!mounted || request != _defineRequest) return;
    setState(() => _definition = (word: word, entries: entries, at: at));
  }

  void _dismissDefinition() {
    if (_definition != null) setState(() => _definition = null);
  }

  /// Beside the selection, flipping above it near the bottom of the window, and
  /// never off the side. Nothing else on the page moves.
  Widget _positionedDefinition(BoxConstraints area) {
    final definition = _definition!;
    final left = (definition.at.dx - DefinitionPopup.width / 2).clamp(
        8.0,
        (area.maxWidth - DefinitionPopup.width - 8)
            .clamp(8.0, double.infinity));
    final below =
        definition.at.dy + DefinitionPopup.maxHeight + 32 < area.maxHeight;
    return Positioned(
      left: left,
      top: below ? definition.at.dy + 20 : null,
      bottom: below ? null : area.maxHeight - definition.at.dy + 20,
      child: DefinitionPopup(
        word: definition.word,
        entries: definition.entries,
        background: _bgColor,
        foreground: _fgColor,
      ),
    );
  }

  void _onTapLink(String url) {
    _ignoreNextTap = true;
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
        .updatePosition(widget.mediaId, _chapterIndex, book.chapterCount);
  }

  BookTheme get _theme =>
      _themeOverride ??
      ref
          .read(settingsProvider)
          .bookTheme
          .resolve(Theme.of(context).brightness);

  Color get _bgColor => _theme.background;

  Color get _fgColor => _theme.foreground;

  /// Separates the bars from the text beneath them.
  Color get _hairline => _fgColor.withValues(alpha: 0.12);

  /// Room the layouts keep clear for the top and bottom bars.
  static const _topInset = 72.0;
  static const _bottomInset = 80.0;

  bool get _canGoBack =>
      _chapterIndex > 0 || (_layout.paged && (_pagePosition?.page ?? 0) > 0);

  bool _canGoForward(ReaderBook book) {
    if (_chapterIndex < book.chapterCount - 1) return true;
    final position = _pagePosition;
    if (!_layout.paged || position == null) return false;
    final step = _layout == BookLayout.spread ? 2 : 1;
    return position.page + step < position.count;
  }

  String _positionLabel(ReaderBook book, BookLayout layout) {
    final chapter = 'Chapter ${_chapterIndex + 1} / ${book.chapterCount}';
    final position = _pagePosition;
    if (!layout.paged || position == null || position.count == 0) {
      return chapter;
    }
    // A spread's left page is -1 when a chapter opens alone on the right.
    final first = position.page < 0 ? 1 : position.page + 1;
    final last = layout == BookLayout.spread
        ? (position.page + 2).clamp(1, position.count)
        : first;
    final pages = first == last ? 'Page $first' : 'Pages $first–$last';
    return '$chapter · $pages of ${position.count}';
  }

  /// The chapter text as the reading options ask for it.
  TextStyle _textStyle(SettingsState reading) =>
      reading.readingStyle.applyTo(reading.bookFont.applyTo(TextStyle(
        fontSize: reading.bookFontSize,
        color: _fgColor,
      )));

  Widget _chapterView(
          ReaderBook book, EpubChapter chapter, SettingsState reading) =>
      BookChapterView(
        book: book,
        chapter: chapter,
        textStyle: _textStyle(reading),
        style: reading.readingStyle,
        onTapLink: _onTapLink,
      );

  /// The book, laid out as the reading options ask.
  Widget _readingBody(ReaderBook book, SettingsState reading) {
    final style = reading.readingStyle;
    final columnWidth = reading.bookFontSize * style.measure;

    if (style.layout == BookLayout.continuous) {
      return SelectionArea(
        onSelectionChanged: _onSelectionChanged,
        child: ContinuousBookView(
          key: ValueKey(('continuous', _continuousEpoch)),
          book: book,
          startChapter: _continuousStart,
          startFraction: _continuousFraction,
          topInset: _topInset,
          bottomInset: _bottomInset,
          onPosition: _onContinuousPosition,
          buildChapter: (chapter) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxWidth: columnWidth),
                child: _chapterView(book, chapter, reading),
              ),
            ),
          ),
        ),
      );
    }

    final chapter = _chapter;
    final leaving = _arrivingFrom;
    if (chapter == null && leaving != null && style.layout.paged) {
      // The page being left stays up while the next chapter arrives.
      return Padding(
        padding: const EdgeInsets.only(top: _topInset, bottom: _bottomInset),
        child: RawImage(image: leaving, fit: BoxFit.fill),
      );
    }
    if (chapter == null) {
      return Padding(
        padding: const EdgeInsets.only(top: _topInset),
        child: _ChapterPlaceholder(
          failed: _chapterFailed,
          fgColor: _fgColor,
          onRetry: () => _showChapter(_chapterIndex, _wantedFraction),
        ),
      );
    }

    if (style.layout.paged) {
      final arriving = _arrivingFrom;
      return SelectionArea(
        onSelectionChanged: _onSelectionChanged,
        child: PagedChapterView(
          key: _pagedKey,
          content: _chapterView(book, chapter, reading),
          startFraction: _wantedFraction,
          spread: style.layout == BookLayout.spread,
          animate: style.animations,
          turnDuration: ref.watch(settingsProvider).pageTurn,
          columnWidth: columnWidth,
          pageColor: _bgColor,
          topInset: _topInset,
          bottomInset: _bottomInset,
          onPage: _onPage,
          onPastEnd: () {
            if (_chapterIndex < book.chapterCount - 1) {
              _carryPage(1);
              _goToChapter(_chapterIndex + 1);
            }
          },
          onBeforeStart: () {
            if (_chapterIndex > 0) {
              _carryPage(-1);
              _goToChapter(_chapterIndex - 1, fraction: 1);
            }
          },
          arrivingFrom: arriving,
          arrivalDirection: _arrivalDirection,
          onArrived: () {
            // Only this view's image: a newer one may be waiting already.
            if (identical(_arrivingFrom, arriving)) {
              _arrivingFrom = null;
              _arrivalDirection = 0;
            }
            arriving?.dispose();
          },
        ),
      );
    }

    return NotificationListener<Notification>(
      onNotification: _onScrollNotification,
      child: SingleChildScrollView(
        controller: _scroll,
        padding: const EdgeInsets.fromLTRB(24, 80, 24, 100),
        // A column of comfortable line length, centred. The scroll view stays
        // full width so the whole window scrolls and the scrollbar sits at its
        // edge.
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: columnWidth),
            child: SelectionArea(
              onSelectionChanged: _onSelectionChanged,
              child: _chapterView(book, chapter, reading),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final book = _book;
    // Watched, so a change here or in Settings applies straight away.
    final reading = ref.watch(settingsProvider);
    ref.listen(settingsProvider, _onSettingsChanged);
    final style = reading.readingStyle;

    return Focus(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent || event is KeyRepeatEvent) {
          final key = event.logicalKey;
          final paged = style.layout.paged;
          if (key == LogicalKeyboardKey.arrowRight ||
              key == LogicalKeyboardKey.keyD ||
              (paged &&
                  (key == LogicalKeyboardKey.pageDown ||
                      key == LogicalKeyboardKey.space))) {
            _forward();
          }
          if (key == LogicalKeyboardKey.arrowLeft ||
              key == LogicalKeyboardKey.keyA ||
              (paged && key == LogicalKeyboardKey.pageUp)) {
            _back();
          }
        }
        // Escape closes the pop-up first, and marks the press used, so it can't
        // also close the book. Otherwise the app takes it to go back
        // (EscapeGoesBack).
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape &&
            _definition != null) {
          _dismissDefinition();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: _bgColor,
        endDrawer: Drawer(
          width: 380,
          child: ReadingOptionsPanel(
            onThemePicked: () => setState(() => _themeOverride = null),
          ),
        ),
        // Keeps the keyboard on the page once the options close.
        onEndDrawerChanged: (open) {
          if (!open) _focusNode.requestFocus();
        },
        body: book == null
            ? (_notDownloaded
                ? _OfflineUnavailable(fgColor: _fgColor)
                : _loadError != null
                    ? _EpubLoadError(message: _loadError!, fgColor: _fgColor)
                    : const Center(child: CircularProgressIndicator()))
            : Stack(
                children: [
                  PageTapDetector(
                    onTap: (position) {
                      // A tap that closes the pop-up, clears a selection or follows
                      // a link shouldn't also toggle the HUD.
                      if (_ignoreNextTap) return;
                      if (_turnByTap(position)) return;
                      setState(() => _showControls = !_showControls);
                    },
                    // Any direct input means the reader has taken over from a
                    // pending restore.
                    child: Listener(
                      onPointerDown: (event) {
                        _cancelRestore();
                        _pointerDown = true;
                        _pointerAt = event.position;
                        _defineTimer?.cancel();
                        _defineRequest++;
                        _ignoreNextTap = _definition != null ||
                            (_selectedText?.trim().isNotEmpty ?? false);
                        _dismissDefinition();
                      },
                      onPointerMove: (event) => _pointerAt = event.position,
                      onPointerUp: (event) {
                        _pointerDown = false;
                        _pointerAt = event.position;
                        if (_selectedText?.trim().isNotEmpty ?? false) {
                          _scheduleDefine();
                        }
                      },
                      onPointerCancel: (_) => _pointerDown = false,
                      onPointerSignal: (event) {
                        _cancelRestore();
                        _dismissDefinition();
                        _turnByWheel(event);
                      },
                      child: _readingBody(book, reading),
                    ),
                  ),
                  if (style.ruler)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: ValueListenableBuilder<double?>(
                          valueListenable: _rulerY,
                          builder: (context, y, _) => CustomPaint(
                            painter: ReadingRulerPainter(
                              y: y,
                              band:
                                  reading.bookFontSize * style.lineHeight * 1.5,
                              shade: _bgColor,
                              edge: _fgColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (_definition != null)
                    Positioned.fill(
                      child: LayoutBuilder(
                        builder: (_, area) => Stack(
                          children: [_positionedDefinition(area)],
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
                        decoration: BoxDecoration(
                          color: _bgColor,
                          border: Border(bottom: BorderSide(color: _hairline)),
                        ),
                        child: SafeArea(
                          bottom: false,
                          child: Row(
                            children: [
                              IconButton(
                                icon: Icon(Icons.arrow_back, color: _fgColor),
                                onPressed: () => Navigator.of(context).pop(),
                              ),
                              Expanded(
                                child: Text(
                                  book.chapterTitle(_chapterIndex),
                                  style: TextStyle(
                                    color: _fgColor,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              IconButton(
                                icon: Icon(Icons.palette, color: _fgColor),
                                tooltip: 'Theme: ${_theme.label}',
                                onPressed: () => _reflow(() {
                                  _themeOverride = _theme.next;
                                }),
                              ),
                              IconButton(
                                icon:
                                    Icon(Icons.text_decrease, color: _fgColor),
                                tooltip: 'Smaller text',
                                onPressed: () => ref
                                    .read(settingsProvider.notifier)
                                    .setBookFontSize(reading.bookFontSize - 1),
                              ),
                              IconButton(
                                icon:
                                    Icon(Icons.text_increase, color: _fgColor),
                                tooltip: 'Larger text',
                                onPressed: () => ref
                                    .read(settingsProvider.notifier)
                                    .setBookFontSize(reading.bookFontSize + 1),
                              ),
                              IconButton(
                                icon: Icon(Icons.text_format, color: _fgColor),
                                tooltip: 'Reading options',
                                onPressed: () =>
                                    _scaffoldKey.currentState?.openEndDrawer(),
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
                        decoration: BoxDecoration(
                          color: _bgColor,
                          border: Border(top: BorderSide(color: _hairline)),
                        ),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 8),
                        child: SafeArea(
                          top: false,
                          child: Row(
                            children: [
                              IconButton(
                                icon: Icon(Icons.chevron_left, color: _fgColor),
                                tooltip: style.layout.paged
                                    ? 'Previous page'
                                    : 'Previous chapter',
                                onPressed: _canGoBack ? _back : null,
                              ),
                              Expanded(
                                child: Text(
                                  _positionLabel(book, style.layout),
                                  style: TextStyle(color: _fgColor),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                              IconButton(
                                icon:
                                    Icon(Icons.chevron_right, color: _fgColor),
                                tooltip: style.layout.paged
                                    ? 'Next page'
                                    : 'Next chapter',
                                onPressed:
                                    _canGoForward(book) ? _forward : null,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],

                  // Moves the reading ruler with the pointer anywhere over the
                  // reader: margins, bars and all, and while a button is held,
                  // as when selecting text. On top, but translucent, so every
                  // pointer event still reaches what's underneath.
                  if (style.ruler)
                    Positioned.fill(
                      child: Listener(
                        behavior: HitTestBehavior.translucent,
                        onPointerHover: _moveRuler,
                        onPointerMove: _moveRuler,
                        onPointerDown: _moveRuler,
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}

/// Stands in for a chapter while it's on its way from the server.
class _ChapterPlaceholder extends StatelessWidget {
  final bool failed;
  final Color fgColor;
  final VoidCallback onRetry;

  const _ChapterPlaceholder({
    required this.failed,
    required this.fgColor,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 120),
      child: Center(
        child: failed
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    "This chapter couldn't be loaded.",
                    style: TextStyle(color: fgColor),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                      onPressed: onRetry, child: const Text('Try again')),
                ],
              )
            : const CircularProgressIndicator(),
      ),
    );
  }
}

/// One chapter, with its images and links resolved against the book.
@visibleForTesting
class BookChapterView extends StatelessWidget {
  final ReaderBook book;
  final EpubChapter chapter;
  final TextStyle textStyle;
  final ReadingStyle style;
  final void Function(String url) onTapLink;

  const BookChapterView({
    super.key,
    required this.book,
    required this.chapter,
    required this.textStyle,
    this.style = const ReadingStyle(),
    required this.onTapLink,
  });

  @override
  Widget build(BuildContext context) {
    // The widget colours links with the app theme's primary colour, which reads
    // as washed-out purple on a page. A book's links are its contents and
    // cross-references, so they take the text's colour instead.
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        colorScheme: theme.colorScheme.copyWith(primary: textStyle.color),
      ),
      child: HtmlWidget(
        chapter.html,
        baseUrl:
            Uri(scheme: _bookScheme, host: 'book', path: '/${chapter.path}'),
        factoryBuilder: () => _BookWidgetFactory(book),
        textStyle: textStyle,
        customStylesBuilder: (element) {
          final tag = element.localName ?? '';
          final book = chapter.styles.stylesFor(tag, element.classes);
          final styles = {...book, ...style.overridesFor(tag, book)};
          if (tag == 'a' && !styles.containsKey('text-decoration')) {
            styles['text-decoration'] = 'none';
          }
          return styles.isEmpty ? null : styles;
        },
        onTapUrl: (url) {
          onTapLink(url);
          return true;
        },
      ),
    );
  }
}

/// Serves images from inside the book. Anything else a book asks for is refused,
/// so opening one can't make network requests.
class _BookWidgetFactory extends WidgetFactory {
  final ReaderBook book;
  _BookWidgetFactory(this.book);

  /// Paragraph indents, which the widget otherwise drops, as em spaces at the
  /// start of the block, so they scale with the text.
  @override
  void parseStyle(BuildTree tree, css.Declaration style) {
    if (style.property == 'text-indent') {
      final ems = BookStyles.indentEms(_cssLength(style.value));
      if (ems > 0) {
        tree.register(BuildOp.v2(
          debugLabel: 'text-indent',
          onParsed: (tree) {
            tree.prepend(TextBit(tree, ' ' * ems));
            return tree;
          },
        ));
      }
      return;
    }
    super.parseStyle(tree, style);
  }

  @override
  ImageProvider<Object>? imageProviderFromNetwork(String url) {
    final uri = Uri.tryParse(url);
    if (uri == null || uri.scheme != _bookScheme) return null;
    return book.imageProvider(Uri.decodeFull(uri.path).replaceFirst('/', ''));
  }
}

/// A single CSS length as written, such as `1.2em` or `24px`. The parsed
/// declaration doesn't keep its source text.
String _cssLength(css.Expression? value) => switch (value) {
      css.EmTerm(:final value) => '${value}em',
      css.UnitTerm() => '${value.value}${value.unitToString() ?? ''}',
      css.NumberTerm(:final value) => '$value',
      _ => '',
    };

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
            Icon(Icons.cloud_off,
                size: 64, color: fgColor.withValues(alpha: 0.5)),
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
              style: TextStyle(
                  color: fgColor.withValues(alpha: 0.5), fontSize: 12),
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
