import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../core/api/libraries_api.dart';
import '../core/api/media_api.dart';
import '../core/db/local_db_provider.dart';
import '../core/download/download_manager.dart';
import '../core/models/reading_progress.dart';
import '../core/storage/prefs.dart';
import 'auth_provider.dart';
import 'connectivity_provider.dart';
import 'download_provider.dart';
import 'settings_provider.dart';

enum ReadingDirection { ltr, rtl }

class ReaderState {
  final int currentPage;
  final int totalPages;
  final ReadingDirection direction;
  final bool showControls;
  final bool doublePage;
  final bool scrollMode;
  final ReadingProgress? savedProgress;
  final List<bool> spreads;

  /// True when no pages could be resolved locally AND the server was
  /// unreachable — the reader shows an explicit offline message instead of an
  /// endless loading spinner.
  final bool pagesUnavailable;

  const ReaderState({
    this.currentPage = 0,
    this.totalPages = 0,
    this.direction = ReadingDirection.ltr,
    this.showControls = true,
    this.doublePage = false,
    this.scrollMode = false,
    this.savedProgress,
    this.spreads = const [],
    this.pagesUnavailable = false,
  });

  ReaderState copyWith({
    int? currentPage,
    int? totalPages,
    ReadingDirection? direction,
    bool? showControls,
    bool? doublePage,
    bool? scrollMode,
    ReadingProgress? savedProgress,
    List<bool>? spreads,
    bool? pagesUnavailable,
  }) =>
      ReaderState(
        currentPage: currentPage ?? this.currentPage,
        totalPages: totalPages ?? this.totalPages,
        direction: direction ?? this.direction,
        showControls: showControls ?? this.showControls,
        doublePage: doublePage ?? this.doublePage,
        scrollMode: scrollMode ?? this.scrollMode,
        savedProgress: savedProgress ?? this.savedProgress,
        spreads: spreads ?? this.spreads,
        pagesUnavailable: pagesUnavailable ?? this.pagesUnavailable,
      );
}

/// Family argument: mediaId + optional library type hint to avoid an extra
/// round-trip when the caller already knows whether this is a manga library.
typedef ReaderArgs = (String mediaId, String? libraryType);

class ReaderNotifier extends FamilyNotifier<ReaderState, ReaderArgs> {
  Timer? _syncTimer;

  // Guard against wiping a finished item's completion flag: completed items
  // restart at page/chapter 0, so the dispose-time flush would otherwise push
  // (page 0, isCompleted=false) over the server's isCompleted=true after a
  // mere open+close.
  bool _completedOnLoad = false;
  bool _userNavigated = false;

  @override
  ReaderState build(ReaderArgs arg) {
    final (mediaId, _) = arg;
    ref.onDispose(() {
      _syncTimer?.cancel();
      _syncNow(mediaId);
    });

    _init(arg);
    return const ReaderState();
  }

  Future<void> _init(ReaderArgs arg) async {
    final (mediaId, libraryType) = arg;
    final prefs = Prefs.instance;
    final db = ref.read(localDbProvider);
    final client = ref.read(apiClientProvider);
    final api = MediaApi(client);

    // Load local queue first for instant offline start
    final local = await _localProgress(db, mediaId);
    // Unsynced local progress is newer than anything the server has (it was
    // never pushed), so prefer it — otherwise an online open resumes at the
    // stale server page and the debounce overwrites the real progress.
    // (Kept as a nullable snapshot, not a bool, so this compiles on Dart
    // versions without boolean-variable promotion.)
    final unsynced = (local != null && !local.$3) ? local : null;

    // Offline-first: seed the page count from the local extracted manifest BEFORE
    // any network call, so a downloaded comic renders immediately instead of
    // stalling behind sequential server timeouts. Extraction happens on demand
    // (idempotent) for CBZ; other formats return null and fall through.
    try {
      final downloadDir = await resolveDownloadDir();
      final manager = DownloadManager(client, db, downloadBaseDir: downloadDir);
      final localPages = await manager.ensureExtractedPages(mediaId);
      if (localPages != null && localPages.isNotEmpty) {
        state = state.copyWith(totalPages: localPages.length);
        // The reader screen reads page files from this provider — refresh it in
        // case extraction only just happened.
        ref.invalidate(extractedPagesProvider(mediaId));
      }
    } catch (_) {
      // No local pages — rely on the server below.
    }

    ReadingProgress? progress;
    if (unsynced == null) {
      try {
        progress = await api.getProgress(mediaId);
      } catch (_) {
        // Offline — use local queue value
      }
    }

    // If the archive was finished, start from the beginning on the next open.
    final isCompleted =
        unsynced?.$2 ?? progress?.isCompleted ?? local?.$2 ?? false;
    _completedOnLoad = isCompleted;
    final savedPage = isCompleted
        ? 0
        : (unsynced?.$1 ?? progress?.currentPage ?? local?.$1 ?? 0);

    // Determine reading direction. If the user has never explicitly toggled
    // direction for this item, fall back to the library type: manga → RTL.
    final explicitRtl = prefs.isRtlExplicit(mediaId);
    ReadingDirection direction;
    if (explicitRtl != null) {
      direction =
          explicitRtl ? ReadingDirection.rtl : ReadingDirection.ltr;
    } else {
      var isManga = libraryType == 'manga';
      if (libraryType == null) {
        // Library type not provided by caller — fetch it.
        try {
          final media = await api.getById(mediaId);
          final library = await LibrariesApi(client).getById(media.libraryId);
          isManga = library.type == 'manga';
        } catch (_) {
          // Offline or missing — stay LTR
        }
      }
      direction = isManga ? ReadingDirection.rtl : ReadingDirection.ltr;
    }

    final sessionMode = ref.read(readerModeProvider);
    final doublePage =
        prefs.isDoublePageExplicit(mediaId) ?? sessionMode.doublePage;
    final scrollMode =
        prefs.isScrollModeExplicit(mediaId) ?? sessionMode.scrollMode;

    // Keep session mode in sync so the next chapter inherits these settings.
    ref.read(readerModeProvider.notifier).state =
        (doublePage: doublePage, scrollMode: scrollMode);

    state = state.copyWith(
      currentPage: savedPage,
      direction: direction,
      doublePage: doublePage,
      scrollMode: scrollMode,
      savedProgress: progress,
    );

    // Fetch page count + spread map from the server (augments spreads, triggers
    // server-side extraction if needed). Overrides the local count when online.
    try {
      final layout = await api.getPageCount(mediaId);
      if (layout.count > 0) {
        state = state.copyWith(
          totalPages: layout.count,
          spreads: layout.spreads,
        );
      }
    } catch (_) {
      // Offline or error — keep whatever the local manifest provided.
    }

    // Neither local pages nor a reachable server: surface an explicit offline
    // message instead of an endless loading spinner.
    if (state.totalPages == 0) {
      state = state.copyWith(pagesUnavailable: true);
    }
  }

  void setTotalPages(int count) {
    state = state.copyWith(totalPages: count);
  }

  void goToPage(int page, String mediaId) {
    final clamped = page.clamp(0, (state.totalPages - 1).clamp(0, 999999));
    if (clamped != state.currentPage) _userNavigated = true;
    state = state.copyWith(currentPage: clamped);
    _scheduleSync(mediaId);
  }

  void toggleControls() {
    state = state.copyWith(showControls: !state.showControls);
  }

  void toggleDirection(String mediaId) {
    final newDir = state.direction == ReadingDirection.ltr
        ? ReadingDirection.rtl
        : ReadingDirection.ltr;
    state = state.copyWith(direction: newDir);
    Prefs.instance.setRtl(mediaId, rtl: newDir == ReadingDirection.rtl);
  }

  void toggleDoublePage(String mediaId) {
    final newVal = !state.doublePage;
    state = state.copyWith(doublePage: newVal);
    Prefs.instance.setDoublePage(mediaId, doublePage: newVal);
    ref.read(readerModeProvider.notifier).update(
        (m) => (doublePage: newVal, scrollMode: m.scrollMode));
  }

  void toggleScrollMode(String mediaId) {
    final newVal = !state.scrollMode;
    state = state.copyWith(scrollMode: newVal);
    Prefs.instance.setScrollMode(mediaId, scrollMode: newVal);
    ref.read(readerModeProvider.notifier).update(
        (m) => (doublePage: m.doublePage, scrollMode: newVal));
  }

  void _scheduleSync(String mediaId) {
    _syncTimer?.cancel();
    _syncTimer =
        Timer(const Duration(seconds: 3), () => _syncNow(mediaId));
  }

  Future<void> _syncNow(String mediaId) async {
    // A finished item restarts at 0 — don't overwrite its completion flag
    // unless the user actually navigated this session.
    if (_completedOnLoad && !_userNavigated) return;
    final page = state.currentPage;
    final isCompleted =
        state.totalPages > 0 && page >= state.totalPages - 1;

    final db = ref.read(localDbProvider);
    await _saveLocal(db, mediaId, page, isCompleted);

    final isOnline = ref.read(isOnlineProvider);
    if (!isOnline) return;

    try {
      final client = ref.read(apiClientProvider);
      await MediaApi(client).saveProgress(
        mediaId,
        currentPage: page,
        isCompleted: isCompleted,
      );
      await _markSynced(db, mediaId);
    } catch (_) {
      // Will be picked up by the background sync on next online event
    }
  }

  // ── Local DB helpers ─────────────────────────────────────────────────────

  /// Returns `(currentPage, isCompleted, synced)` from the local queue, or null
  /// if absent.
  Future<(int, bool, bool)?> _localProgress(Database db, String mediaId) async {
    final rows = await db.query(
      'progress_queue',
      columns: ['current_page', 'is_completed', 'synced'],
      where: 'media_id = ?',
      whereArgs: [mediaId],
    );
    if (rows.isEmpty) return null;
    return (
      rows.first['current_page'] as int,
      (rows.first['is_completed'] as int) == 1,
      (rows.first['synced'] as int? ?? 0) == 1,
    );
  }

  Future<void> _saveLocal(
    Database db,
    String mediaId,
    int page,
    bool isCompleted,
  ) =>
      db.insert(
        'progress_queue',
        {
          'media_id': mediaId,
          'current_page': page,
          'is_completed': isCompleted ? 1 : 0,
          'last_read_at': DateTime.now().millisecondsSinceEpoch,
          'synced': 0,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

  Future<void> _markSynced(Database db, String mediaId) =>
      db.update(
        'progress_queue',
        {'synced': 1},
        where: 'media_id = ?',
        whereArgs: [mediaId],
      );
}

/// Kept non-autoDispose because the EPUB screen only reads it (autoDispose would
/// churn it and re-run _init on every access). To still get fresh state per
/// open — so a finished chapter restarts at 0 and cross-device progress is
/// re-fetched — the reader screens invalidate this on dispose (see #20).
final readerProvider =
    NotifierProviderFamily<ReaderNotifier, ReaderState, ReaderArgs>(
  ReaderNotifier.new,
);

/// Carries the active reading mode across chapter navigation within a session.
/// Updated whenever the user toggles a mode or a chapter loads its settings.
final readerModeProvider =
    StateProvider<({bool doublePage, bool scrollMode})>(
  (_) => (doublePage: false, scrollMode: false),
);

/// Global double-page spine gap in logical pixels. Persisted to prefs.
final doublePageGapProvider = StateProvider<double>(
  (ref) => Prefs.instance.doublePageGap,
);

// ---------------------------------------------------------------------------
// Local progress badge data — fast DB-only read for grid/list indicators
// ---------------------------------------------------------------------------

/// Returns local reading progress for [mediaId], or null if never opened.
/// Uses autoDispose so the value is always fresh when the screen re-enters.
final localProgressProvider =
    FutureProvider.autoDispose.family<ReadingProgress?, String>(
        (ref, mediaId) async {
  final db = ref.read(localDbProvider);
  final rows = await db.query(
    'progress_queue',
    columns: ['current_page', 'is_completed'],
    where: 'media_id = ?',
    whereArgs: [mediaId],
  );
  if (rows.isEmpty) return null;
  return ReadingProgress(
    userId: '',
    mediaId: mediaId,
    currentPage: rows.first['current_page'] as int,
    isCompleted: (rows.first['is_completed'] as int) == 1,
  );
});

/// Flushes all unsynced local progress to the server.
/// Call this when the app comes back online.
Future<void> syncPendingProgress(WidgetRef ref) async {
  final isOnline = ref.read(isOnlineProvider);
  if (!isOnline) return;

  final db = ref.read(localDbProvider);
  final rows = await db.query(
    'progress_queue',
    where: 'synced = 0',
  );

  if (rows.isEmpty) return;

  final client = ref.read(apiClientProvider);
  final api = MediaApi(client);

  for (final row in rows) {
    try {
      final mediaId = row['media_id'] as String;
      final page = row['current_page'] as int;
      final completed = (row['is_completed'] as int) == 1;
      await api.saveProgress(mediaId,
          currentPage: page, isCompleted: completed);
      await db.update(
        'progress_queue',
        {'synced': 1},
        where: 'media_id = ?',
        whereArgs: [mediaId],
      );
    } catch (_) {
      // Keep row as unsynced; will retry next time
    }
  }
}
