import 'dart:async';
import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:photo_view/photo_view.dart';
import 'package:photo_view/photo_view_gallery.dart';

import '../core/models/media.dart';
import '../core/storage/prefs.dart';
import '../providers/auth_provider.dart';
import '../providers/download_provider.dart';
import '../providers/media_provider.dart';
import '../providers/reader_provider.dart';

class ReaderScreen extends ConsumerStatefulWidget {
  final String mediaId;
  final String? libraryType;
  /// When set, the reader starts at this page and ignores saved server progress.
  final int? initialPage;

  const ReaderScreen({
    super.key,
    required this.mediaId,
    this.libraryType,
    this.initialPage,
  });

  @override
  ConsumerState<ReaderScreen> createState() => _ReaderScreenState();
}

class _ReaderScreenState extends ConsumerState<ReaderScreen> {
  // ── Paged mode ────────────────────────────────────────────────────────────
  late final PageController _pageCtrl;
  bool _didJump = false;
  bool _didInitialPageJump = false;
  int _lastPrefetchedPage = -1;

  // ── Scroll mode ───────────────────────────────────────────────────────────
  final ScrollController _scrollCtrl = ScrollController();
  final List<GlobalKey> _pageKeys = [];
  bool _didScrollJump = false;
  // Track scroll changes; throttle page-index updates to scroll-end events.
  int _scrollTrackedPage = 0;

  // ── Shared ────────────────────────────────────────────────────────────────
  final FocusNode _focusNode = FocusNode();

  // ── Zoom / pan ────────────────────────────────────────────────────────────
  double _zoom = 1.0;
  Offset _panOffset = Offset.zero;
  Offset? _midMouseAnchor;
  Offset? _panAtMidAnchor;
  static const double _minZoom = 1.0;
  static const double _maxZoom = 5.0;

  // ── HUD visibility ────────────────────────────────────────────────────────
  bool _hudVisible = true;
  Timer? _hideTimer;
  static const _hudTimeout = Duration(seconds: 3);
  static const _hudFade   = Duration(milliseconds: 250);

  @override
  void initState() {
    super.initState();
    _pageCtrl = PageController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _focusNode.requestFocus();
      _resetHideTimer(); // start fade-out countdown immediately
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _pageCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _onMouseMove(PointerEvent _) => _showHud();

  void _showHud() {
    if (!mounted) return;
    if (!_hudVisible) setState(() => _hudVisible = true);
    _resetHideTimer();
  }

  void _resetHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(_hudTimeout, () {
      if (mounted) setState(() => _hudVisible = false);
    });
  }

  void _toggleHud() {
    if (_hudVisible) {
      _hideTimer?.cancel();
      setState(() => _hudVisible = false);
    } else {
      _showHud();
    }
  }

  // ── Zoom / pan ────────────────────────────────────────────────────────────

  void _resetZoom() {
    if (_zoom == 1.0 && _panOffset == Offset.zero) return;
    setState(() {
      _zoom = 1.0;
      _panOffset = Offset.zero;
    });
  }

  /// Clamps [pan] so the scaled content doesn't slide fully off screen.
  Offset _clampPan(Offset pan, Size screen) {
    if (_zoom <= 1.0) return Offset.zero;
    return Offset(
      pan.dx.clamp(screen.width * (1 - _zoom), 0.0),
      pan.dy.clamp(screen.height * (1 - _zoom), 0.0),
    );
  }

  void _handleScrollZoom(PointerScrollEvent event, Size screen) {
    final dy = event.scrollDelta.dy;
    if (dy == 0) return;
    final scaleFactor = dy > 0 ? (1 / 1.15) : 1.15;
    final oldZoom = _zoom;
    final newZoom = (_zoom * scaleFactor).clamp(_minZoom, _maxZoom);
    if (newZoom == oldZoom) return;
    // Keep the screen point under the cursor fixed as zoom changes.
    final f = event.localPosition;
    final ratio = newZoom / oldZoom;
    var newPan = f * (1 - ratio) + _panOffset * ratio;
    if (newZoom <= _minZoom) newPan = Offset.zero;
    setState(() {
      _zoom = newZoom;
      _panOffset = _clampPan(newPan, screen);
    });
  }

  void _handlePointerDown(PointerDownEvent event) {
    if (event.buttons & kMiddleMouseButton != 0) {
      _midMouseAnchor = event.localPosition;
      _panAtMidAnchor = _panOffset;
    }
  }

  void _handlePointerMove(PointerMoveEvent event, Size screen) {
    if (_midMouseAnchor == null) return;
    if (event.buttons & kMiddleMouseButton == 0) {
      _midMouseAnchor = null;
      _panAtMidAnchor = null;
      return;
    }
    final newPan = _panAtMidAnchor! + (event.localPosition - _midMouseAnchor!);
    setState(() => _panOffset = _clampPan(newPan, screen));
  }

  void _handlePointerUp(PointerUpEvent event) {
    if (event.buttons & kMiddleMouseButton == 0) {
      _midMouseAnchor = null;
      _panAtMidAnchor = null;
    }
  }

  /// Left-click zone navigation: left third → prev, right third → next.
  /// Respects RTL reading direction. No-op in scroll mode.
  void _handleTapZone(
    TapUpDetails details,
    BuildContext context,
    List<Media> siblings,
    bool isRtl,
  ) {
    final x = details.localPosition.dx;
    final width = MediaQuery.sizeOf(context).width;
    if (x < width / 3) {
      isRtl ? _nextSlide(context, siblings) : _prevSlide(context, siblings);
    } else if (x > width * 2 / 3) {
      isRtl ? _prevSlide(context, siblings) : _nextSlide(context, siblings);
    }
  }

  // ── Chapter navigation ────────────────────────────────────────────────────

  void _tryPrevChapter(BuildContext context, List<Media> siblings) {
    final idx = siblings.indexWhere((m) => m.id == widget.mediaId);
    if (idx > 0) _openAdjacentChapter(context, siblings[idx - 1].id);
  }

  void _tryNextChapter(BuildContext context, List<Media> siblings) {
    final idx = siblings.indexWhere((m) => m.id == widget.mediaId);
    if (idx >= 0 && idx < siblings.length - 1) {
      _openAdjacentChapter(context, siblings[idx + 1].id);
    }
  }

  /// Navigates to [targetId], carrying the current reading direction forward
  /// unless the target already has an explicit user preference saved.
  void _openAdjacentChapter(BuildContext context, String targetId) {
    final currentState = ref.read(readerProvider((widget.mediaId, widget.libraryType)));

    if (Prefs.instance.isRtlExplicit(targetId) == null) {
      Prefs.instance.setRtl(targetId,
          rtl: currentState.direction == ReadingDirection.rtl);
    }
    Prefs.instance.setDoublePage(targetId, doublePage: currentState.doublePage);
    Prefs.instance.setScrollMode(targetId, scrollMode: currentState.scrollMode);

    context.replace('/reader/$targetId',
        extra: {'initialPage': 0, 'libraryType': widget.libraryType});
  }

  // ── Page-key pool ─────────────────────────────────────────────────────────

  void _ensurePageKeys(int count) {
    while (_pageKeys.length < count) {
      _pageKeys.add(GlobalKey());
    }
  }

  // ── Slide layout helpers ──────────────────────────────────────────────────

  /// Groups pages into slides for double-page mode.
  /// Landscape pages (spreads) occupy a slide alone; portrait pages are paired.
  static List<List<int>> buildSlides(int totalPages, List<bool> spreads) {
    final slides = <List<int>>[];
    var i = 0;
    while (i < totalPages) {
      final isSpread = i < spreads.length && spreads[i];
      // Page 0 (cover) always occupies its own slide so it isn't paired with
      // the first interior page — matching the physical book convention.
      if (isSpread || i == 0) {
        slides.add([i]);
        i++;
      } else {
        final nextIsSpread = (i + 1) < spreads.length && spreads[i + 1];
        if (i + 1 < totalPages && !nextIsSpread) {
          slides.add([i, i + 1]);
          i += 2;
        } else {
          slides.add([i]);
          i++;
        }
      }
    }
    return slides;
  }

  // ── Paged-mode helpers ────────────────────────────────────────────────────

  void _jumpToSavedPage(int savedPage, List<List<int>> slides, bool isRtl) {
    if (_didJump || savedPage == 0 || !_pageCtrl.hasClients) return;
    _didJump = true;
    _pageCtrl.jumpToPage(_pageToViewIndex(savedPage, slides, isRtl));
  }

  int _pageToViewIndex(int page, List<List<int>> slides, bool isRtl) {
    var slideIndex = slides.indexWhere((s) => s.contains(page));
    if (slideIndex < 0) slideIndex = 0;
    // reverse:isRtl on PhotoViewGallery already places viewIndex 0 on the
    // visual right, so viewIndex == slideIndex — no extra inversion needed.
    return slideIndex;
  }

  void _goLeft(BuildContext context, List<Media> siblings) {
    final isRtl = ref.read(readerProvider((widget.mediaId, widget.libraryType))).direction ==
        ReadingDirection.rtl;
    isRtl ? _nextSlide(context, siblings) : _prevSlide(context, siblings);
  }

  void _goRight(BuildContext context, List<Media> siblings) {
    final isRtl = ref.read(readerProvider((widget.mediaId, widget.libraryType))).direction ==
        ReadingDirection.rtl;
    isRtl ? _prevSlide(context, siblings) : _nextSlide(context, siblings);
  }

  void _nextSlide(BuildContext context, List<Media> siblings) {
    _resetZoom();
    final state = ref.read(readerProvider((widget.mediaId, widget.libraryType)));
    final slideCount = state.doublePage
        ? buildSlides(state.totalPages, state.spreads).length
        : state.totalPages;
    if (_pageCtrl.page != null && _pageCtrl.page! < slideCount - 1) {
      _pageCtrl.nextPage(
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    } else {
      _tryNextChapter(context, siblings);
    }
  }

  void _prevSlide(BuildContext context, List<Media> siblings) {
    _resetZoom();
    if (_pageCtrl.page != null && _pageCtrl.page! > 0) {
      _pageCtrl.previousPage(
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    } else {
      _tryPrevChapter(context, siblings);
    }
  }

  // ── Scroll-mode helpers ───────────────────────────────────────────────────

  /// Jump to [savedPage] in scroll mode.
  /// Uses GlobalKey if the item is already rendered, otherwise falls back to
  /// an estimated offset (typical manga page: width × 1.45 height).
  void _jumpToSavedPageInScrollMode(int savedPage) {
    if (_didScrollJump || savedPage == 0 || !_scrollCtrl.hasClients) return;
    _didScrollJump = true;

    // Try the key first (item may already be rendered near the top).
    if (savedPage < _pageKeys.length) {
      final ctx = _pageKeys[savedPage].currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(ctx, alignment: 0.0, duration: Duration.zero);
        _scrollTrackedPage = savedPage;
        return;
      }
    }

    // Fallback: estimated offset based on screen width and a 2:3 page ratio.
    final screenWidth = MediaQuery.sizeOf(context).width;
    final estimatedPageHeight = screenWidth * 1.45;
    final target = (savedPage * estimatedPageHeight)
        .clamp(0.0, _scrollCtrl.position.maxScrollExtent);
    _scrollCtrl.jumpTo(target);
    _scrollTrackedPage = savedPage;
  }

  /// Scroll keyboard navigation: move by ~90 % of the viewport height.
  /// At the bottom/top boundary, tries to advance to the next/previous chapter.
  void _scrollDown(BuildContext context, List<Media> siblings) {
    if (!_scrollCtrl.hasClients) return;
    if (_scrollCtrl.offset >= _scrollCtrl.position.maxScrollExtent) {
      _tryNextChapter(context, siblings);
      return;
    }
    _scrollCtrl.animateTo(
      (_scrollCtrl.offset + MediaQuery.sizeOf(context).height * 0.9)
          .clamp(0.0, _scrollCtrl.position.maxScrollExtent),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  void _scrollUp(BuildContext context, List<Media> siblings) {
    if (!_scrollCtrl.hasClients) return;
    if (_scrollCtrl.offset <= 0) {
      _tryPrevChapter(context, siblings);
      return;
    }
    _scrollCtrl.animateTo(
      (_scrollCtrl.offset - MediaQuery.sizeOf(context).height * 0.9)
          .clamp(0.0, _scrollCtrl.position.maxScrollExtent),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  /// Called on `ScrollEndNotification` — find which page's centre is closest
  /// to the viewport midpoint and update the reader state.
  void _updateCurrentPageFromScroll(int totalPages) {
    if (!mounted || totalPages == 0) return;

    final viewportMid = context.size!.height / 2;

    // Search a window of ±8 around the last known page to stay O(1)-ish.
    final lo = (_scrollTrackedPage - 8).clamp(0, totalPages - 1);
    final hi = (_scrollTrackedPage + 8).clamp(0, totalPages - 1);

    int bestPage = _scrollTrackedPage;
    double bestDist = double.infinity;

    for (int i = lo; i <= hi; i++) {
      if (i >= _pageKeys.length) break;
      final ctx = _pageKeys[i].currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.attached) continue;
      final topInViewport = box.localToGlobal(Offset.zero).dy;
      final centerInViewport = topInViewport + box.size.height / 2;
      final dist = (centerInViewport - viewportMid).abs();
      if (dist < bestDist) {
        bestDist = dist;
        bestPage = i;
      }
    }

    _scrollTrackedPage = bestPage;

    final notifier = ref.read(readerProvider((widget.mediaId, widget.libraryType)).notifier);
    if (bestPage != ref.read(readerProvider((widget.mediaId, widget.libraryType))).currentPage) {
      notifier.goToPage(bestPage, widget.mediaId);
    }
  }

  /// Jump the scroll position to [page] (called from the slider).
  void _scrollToPage(int page) {
    if (!_scrollCtrl.hasClients || page >= _pageKeys.length) return;
    final ctx = _pageKeys[page].currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(ctx, alignment: 0.0, duration: Duration.zero);
    } else {
      // Item not rendered yet — use estimate.
      final screenWidth = MediaQuery.sizeOf(context).width;
      final estimatedPageHeight = screenWidth * 1.45;
      final target = (page * estimatedPageHeight)
          .clamp(0.0, _scrollCtrl.position.maxScrollExtent);
      _scrollCtrl.jumpTo(target);
    }
    _scrollTrackedPage = page;
  }

  // ── Prefetch ──────────────────────────────────────────────────────────────

  /// Pre-warms the Flutter image cache for pages surrounding [currentPage].
  /// Called whenever the current page changes in paged mode.
  void _prefetchAround(
    int currentPage,
    List<String>? extractedPages,
    dynamic client,
    List<List<int>> slides,
  ) {
    if (!mounted) return;
    const ahead = 4;
    const behind = 1;
    final slideIdx = slides.indexWhere((s) => s.contains(currentPage));
    if (slideIdx < 0) return;

    for (var offset = -behind; offset <= ahead; offset++) {
      if (offset == 0) continue;
      final idx = slideIdx + offset;
      if (idx < 0 || idx >= slides.length) continue;
      for (final pageIdx in slides[idx]) {
        precacheImage(_buildImageProvider(pageIdx, extractedPages, client), context)
            .ignore();
      }
    }
  }

  // ── Image provider ────────────────────────────────────────────────────────

  ImageProvider _buildImageProvider(
    int pageIndex,
    List<String>? extractedPages,
    dynamic client,
  ) {
    if (extractedPages != null && pageIndex < extractedPages.length) {
      return FileImage(File(extractedPages[pageIndex]));
    }
    return NetworkImage(
      client.pageUrl(widget.mediaId, pageIndex),
      headers: client.authHeaders,
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final readerState = ref.watch(readerProvider((widget.mediaId, widget.libraryType)));
    final mediaAsync = ref.watch(mediaDetailProvider(widget.mediaId));
    final client = ref.watch(apiClientProvider);
    final extractedPages =
        ref.watch(extractedPagesProvider(widget.mediaId)).valueOrNull;

    final totalPages = readerState.totalPages;
    final isRtl = readerState.direction == ReadingDirection.rtl;
    final doublePage = readerState.doublePage;
    final scrollMode = readerState.scrollMode;
    final pageGap = ref.watch(doublePageGapProvider);

    final slides = doublePage
        ? buildSlides(totalPages, readerState.spreads)
        : List.generate(totalPages, (i) => [i]);

    final siblings =
        ref.watch(siblingArchivesProvider(widget.mediaId)).valueOrNull ?? [];

    _ensurePageKeys(totalPages);

    // Prefetch surrounding pages whenever the current page changes (paged mode).
    if (totalPages > 0 && !scrollMode &&
        readerState.currentPage != _lastPrefetchedPage) {
      _lastPrefetchedPage = readerState.currentPage;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _prefetchAround(readerState.currentPage, extractedPages, client, slides);
      });
    }

    // Post-frame jumps — only relevant until first jump fires.
    if (totalPages > 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (widget.initialPage != null) {
          // Caller specified an explicit start page (e.g. chapter auto-advance).
          // Jump once, then block the saved-progress jump from firing.
          if (!_didInitialPageJump) {
            _didInitialPageJump = true;
            _didJump = true;
            _didScrollJump = true;
            final target = widget.initialPage!;
            if (scrollMode) {
              if (target > 0) _jumpToSavedPageInScrollMode(target);
            } else {
              _pageCtrl.jumpToPage(_pageToViewIndex(target, slides, isRtl));
            }
          }
        } else if (readerState.currentPage > 0) {
          if (scrollMode) {
            _jumpToSavedPageInScrollMode(readerState.currentPage);
          } else {
            _jumpToSavedPage(readerState.currentPage, slides, isRtl);
          }
        }
      });
    }

    return MouseRegion(
      onHover: _onMouseMove,
      child: KeyboardListener(
        focusNode: _focusNode,
        autofocus: true,
        onKeyEvent: (event) {
          if (event is! KeyDownEvent) return;
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            Navigator.of(context).pop();
            return;
          }
          if (scrollMode) {
            if (event.logicalKey == LogicalKeyboardKey.arrowDown ||
                event.logicalKey == LogicalKeyboardKey.pageDown) {
              _scrollDown(context, siblings);
            } else if (event.logicalKey == LogicalKeyboardKey.arrowUp ||
                event.logicalKey == LogicalKeyboardKey.pageUp) {
              _scrollUp(context, siblings);
            }
          } else {
            if (event.logicalKey == LogicalKeyboardKey.arrowLeft ||
                event.logicalKey == LogicalKeyboardKey.keyA) _goLeft(context, siblings);
            if (event.logicalKey == LogicalKeyboardKey.arrowRight ||
                event.logicalKey == LogicalKeyboardKey.keyD) _goRight(context, siblings);
          }
        },
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Stack(
            children: [
              // ── Zoom / pan / tap layer ─────────────────────────────────
              Listener(
                onPointerSignal: (event) {
                  if (event is PointerScrollEvent && !scrollMode) {
                    _handleScrollZoom(event, MediaQuery.sizeOf(context));
                  }
                },
                onPointerDown: _handlePointerDown,
                onPointerMove: (e) => _handlePointerMove(e, MediaQuery.sizeOf(context)),
                onPointerUp: _handlePointerUp,
                child: GestureDetector(
                  onSecondaryTap: _toggleHud,
                  onTapUp: scrollMode
                      ? null
                      : (d) => _handleTapZone(d, context, siblings, isRtl),
                  child: Transform(
                    transform: Matrix4.identity()
                      ..translate(_panOffset.dx, _panOffset.dy)
                      ..scale(_zoom),
                    child: totalPages == 0
                        ? const SizedBox.expand()
                        : scrollMode
                            ? _buildScrollView(
                                context, readerState, extractedPages, client, siblings)
                            : _buildPagedView(
                                context, readerState, extractedPages, client,
                                totalPages, isRtl, doublePage, slides, pageGap,
                                siblings),
                  ),
                ),
              ),

              // ── Loading indicator (unzoomed) ───────────────────────────
              if (totalPages == 0)
                const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Colors.white54),
                      SizedBox(height: 16),
                      Text('Loading pages…',
                          style: TextStyle(color: Colors.white54)),
                    ],
                  ),
                ),

              // ── Controls overlay (unzoomed) ────────────────────────────
              IgnorePointer(
                ignoring: !_hudVisible,
                child: AnimatedOpacity(
                  opacity: _hudVisible ? 1.0 : 0.0,
                  duration: _hudFade,
                  child: Stack(
                    children: [
                      _buildTopBar(context, readerState, mediaAsync,
                          isRtl, doublePage, scrollMode, pageGap),
                      _buildBottomBar(context, readerState,
                          totalPages, isRtl, doublePage, scrollMode, slides),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Scroll-mode view ──────────────────────────────────────────────────────

  Widget _buildScrollView(
    BuildContext context,
    ReaderState readerState,
    List<String>? extractedPages,
    dynamic client,
    List<Media> siblings,
  ) {
    final totalPages = readerState.totalPages;
    return NotificationListener<ScrollNotification>(
      onNotification: (notif) {
        if (notif is ScrollEndNotification) {
          _updateCurrentPageFromScroll(totalPages);
        }
        return false;
      },
      child: ListView.builder(
          controller: _scrollCtrl,
          itemCount: totalPages,
          // Pre-render 3 screens worth of content below (and above) the
          // visible area so images are already decoded before they scroll in.
          cacheExtent: MediaQuery.sizeOf(context).height * 3,
          itemBuilder: (context, pageIndex) {
            return Image(
              key: _pageKeys[pageIndex],
              image: _buildImageProvider(pageIndex, extractedPages, client),
              width: double.infinity,
              fit: BoxFit.fitWidth,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, __, ___) => SizedBox(
                height: MediaQuery.sizeOf(context).height * 0.5,
                child: const Center(
                  child: Icon(Icons.broken_image,
                      color: Colors.white54, size: 64),
                ),
              ),
            );
          },
        ),
    );
  }

  // ── Paged-mode view ───────────────────────────────────────────────────────

  Widget _buildPagedView(
    BuildContext context,
    ReaderState readerState,
    List<String>? extractedPages,
    dynamic client,
    int totalPages,
    bool isRtl,
    bool doublePage,
    List<List<int>> slides,
    double pageGap,
    List<Media> siblings,
  ) {
    final slideCount = slides.length;
    return PhotoViewGallery.builder(
        pageController: _pageCtrl,
        scrollDirection: Axis.horizontal,
        reverse: isRtl,
        itemCount: slideCount,
        backgroundDecoration: const BoxDecoration(color: Colors.black),
        builder: (context, viewIndex) {
          final slide = slides[viewIndex];
          // Single-image slide: a spread page shown full-width, or an orphaned
          // last page in double-page mode.
          if (slide.length == 1) {
            return PhotoViewGalleryPageOptions(
              imageProvider:
                  _buildImageProvider(slide[0], extractedPages, client),
              // Scale locked — outer Transform handles zoom.
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.contained,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, __, ___) => const Center(
                child:
                    Icon(Icons.broken_image, color: Colors.white54, size: 64),
              ),
            );
          }
          // Two-image slide: standard double-page layout.
          return _buildDoublePageSlide(
              context, slide[0], slide[1], isRtl, extractedPages, client, pageGap);
        },
        onPageChanged: (viewIndex) {
          final pageIndex = slides[viewIndex].first;
          ref
              .read(readerProvider((widget.mediaId, widget.libraryType)).notifier)
              .goToPage(pageIndex, widget.mediaId);
        },
      );
  }

  PhotoViewGalleryPageOptions _buildDoublePageSlide(
    BuildContext context,
    int pageA,  // lower page number (LTR: left side, RTL: right side)
    int pageB,  // higher page number (LTR: right side, RTL: left side)
    bool isRtl,
    List<String>? extractedPages,
    dynamic client,
    double gap,
  ) {
    final size = MediaQuery.of(context).size;

    // In RTL: pageA (lower number, read first) goes on the right; pageB on left.
    final leftContent  = isRtl ? pageB : pageA;
    final rightContent = isRtl ? pageA : pageB;

    // Alignment is determined by physical position relative to the spine.
    // Left Expanded → anchor right (flush to spine); right Expanded → anchor left.
    Widget pageWidget(int pageIndex, Alignment spineAlignment) {
      return ClipRect(
        child: Align(
          alignment: spineAlignment,
          child: Image(
            image: _buildImageProvider(pageIndex, extractedPages, client),
            fit: BoxFit.contain,
            filterQuality: FilterQuality.medium,
            errorBuilder: (_, __, ___) => const Center(
              child: Icon(Icons.broken_image, color: Colors.white54, size: 48),
            ),
          ),
        ),
      );
    }

    return PhotoViewGalleryPageOptions.customChild(
      childSize: size,
      // Scale locked — outer Transform handles zoom.
      minScale: PhotoViewComputedScale.contained,
      maxScale: PhotoViewComputedScale.contained,
      child: Row(
        children: [
          Expanded(child: pageWidget(leftContent,  Alignment.centerRight)),
          SizedBox(width: gap),
          Expanded(child: pageWidget(rightContent, Alignment.centerLeft)),
        ],
      ),
    );
  }

  // ── Overlay bars ──────────────────────────────────────────────────────────

  Widget _buildTopBar(
    BuildContext context,
    ReaderState readerState,
    AsyncValue mediaAsync,
    bool isRtl,
    bool doublePage,
    bool scrollMode,
    double pageGap,
  ) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        child: SafeArea(
          child: Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => Navigator.of(context).pop(),
              ),
              Expanded(
                child: mediaAsync.when(
                  data: (m) => Text(m.displayTitle,
                      style: const TextStyle(color: Colors.white),
                      overflow: TextOverflow.ellipsis),
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
                ),
              ),
              // Scroll mode toggle
              Tooltip(
                message: scrollMode ? 'Switch to paged' : 'Switch to scroll',
                child: IconButton(
                  color: Colors.white,
                  icon: Icon(scrollMode
                      ? Icons.view_carousel_outlined
                      : Icons.view_day_outlined),
                  onPressed: () {
                    ref
                        .read(readerProvider((widget.mediaId, widget.libraryType)).notifier)
                        .toggleScrollMode(widget.mediaId);
                    // Reset jump flags so the new mode can seek to the
                    // current page once it renders.
                    _didJump = false;
                    _didScrollJump = false;
                  },
                ),
              ),
              // Double-page toggle (not relevant in scroll mode)
              if (!scrollMode)
                Tooltip(
                  message: doublePage ? 'Single page' : 'Double page spread',
                  child: IconButton(
                    color: Colors.white,
                    icon: Icon(doublePage
                        ? Icons.menu_book
                        : Icons.auto_stories),
                    onPressed: () {
                      ref
                          .read(readerProvider((widget.mediaId, widget.libraryType)).notifier)
                          .toggleDoublePage(widget.mediaId);
                      _didJump = false;
                    },
                  ),
                ),
              // Spine gap control (only in double-page mode)
              if (!scrollMode && doublePage) ...[
                Tooltip(
                  message: 'Decrease page gap',
                  child: IconButton(
                    icon: const Icon(Icons.remove, color: Colors.white),
                    onPressed: pageGap <= 0
                        ? null
                        : () {
                            final v = (pageGap - 4).clamp(0.0, 64.0);
                            ref.read(doublePageGapProvider.notifier).state = v;
                            Prefs.instance.setDoublePageGap(v);
                          },
                  ),
                ),
                Text('${pageGap.round()}',
                    style: const TextStyle(color: Colors.white70, fontSize: 12)),
                Tooltip(
                  message: 'Increase page gap',
                  child: IconButton(
                    icon: const Icon(Icons.add, color: Colors.white),
                    onPressed: pageGap >= 64
                        ? null
                        : () {
                            final v = (pageGap + 4).clamp(0.0, 64.0);
                            ref.read(doublePageGapProvider.notifier).state = v;
                            Prefs.instance.setDoublePageGap(v);
                          },
                  ),
                ),
              ],
              // RTL toggle (not relevant in scroll mode)
              if (!scrollMode)
                Tooltip(
                  message: isRtl ? 'Switch to LTR' : 'Switch to RTL',
                  child: TextButton.icon(
                    style:
                        TextButton.styleFrom(foregroundColor: Colors.white),
                    onPressed: () {
                      final s = ref.read(readerProvider((widget.mediaId, widget.libraryType)));
                      final newIsRtl = s.direction == ReadingDirection.ltr;
                      ref
                          .read(readerProvider((widget.mediaId, widget.libraryType)).notifier)
                          .toggleDirection(widget.mediaId);
                      final sl = s.doublePage
                          ? buildSlides(s.totalPages, s.spreads)
                          : List.generate(s.totalPages, (i) => [i]);
                      _pageCtrl.jumpToPage(
                          _pageToViewIndex(s.currentPage, sl, newIsRtl));
                    },
                    icon: Icon(isRtl
                        ? Icons.format_textdirection_r_to_l
                        : Icons.format_textdirection_l_to_r),
                    label: Text(isRtl ? 'RTL' : 'LTR'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomBar(
    BuildContext context,
    ReaderState readerState,
    int totalPages,
    bool isRtl,
    bool doublePage,
    bool scrollMode,
    List<List<int>> slides,
  ) {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black87, Colors.transparent],
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (totalPages > 1)
                Directionality(
                  textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
                  child: Slider(
                    value: readerState.currentPage
                        .toDouble()
                        .clamp(0, (totalPages - 1).toDouble()),
                    min: 0,
                    max: (totalPages - 1).toDouble(),
                    divisions: totalPages - 1,
                    activeColor: Colors.white,
                    inactiveColor: Colors.white30,
                    onChanged: (v) {
                      final page = v.round();
                      _resetZoom();
                      ref
                          .read(readerProvider((widget.mediaId, widget.libraryType)).notifier)
                          .goToPage(page, widget.mediaId);
                      if (scrollMode) {
                        _scrollToPage(page);
                      } else {
                        _pageCtrl.jumpToPage(_pageToViewIndex(page, slides, isRtl));
                      }
                    },
                  ),
                ),
              Text(
                '${readerState.currentPage + 1} / $totalPages',
                style: const TextStyle(color: Colors.white70),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
