import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sqflite/sqflite.dart';

import '../core/api/libraries_api.dart';
import '../core/api/media_api.dart';
import '../core/db/local_db_provider.dart';
import '../core/models/reading_progress.dart';
import '../core/storage/prefs.dart';
import 'auth_provider.dart';
import 'connectivity_provider.dart';

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

  const ReaderState({
    this.currentPage = 0,
    this.totalPages = 0,
    this.direction = ReadingDirection.ltr,
    this.showControls = true,
    this.doublePage = false,
    this.scrollMode = false,
    this.savedProgress,
    this.spreads = const [],
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
      );
}

/// Family argument: mediaId + optional library type hint to avoid an extra
/// round-trip when the caller already knows whether this is a manga library.
typedef ReaderArgs = (String mediaId, String? libraryType);

class ReaderNotifier extends FamilyNotifier<ReaderState, ReaderArgs> {
  Timer? _syncTimer;

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
    final localPage = await _localPage(db, mediaId);

    ReadingProgress? progress;
    try {
      progress = await api.getProgress(mediaId);
    } catch (_) {
      // Offline — use local queue value
    }

    final savedPage = progress?.currentPage ?? localPage ?? 0;

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

    state = state.copyWith(
      currentPage: savedPage,
      direction: direction,
      doublePage: prefs.isDoublePage(mediaId),
      scrollMode: prefs.isScrollMode(mediaId),
      savedProgress: progress,
    );

    // Fetch page count + spread map — triggers server-side extraction if needed.
    try {
      final layout = await api.getPageCount(mediaId);
      if (layout.count > 0) {
        state = state.copyWith(
          totalPages: layout.count,
          spreads: layout.spreads,
        );
      }
    } catch (_) {
      // Offline or error — gallery stays at 0 pages until online
    }
  }

  void setTotalPages(int count) {
    state = state.copyWith(totalPages: count);
  }

  void goToPage(int page, String mediaId) {
    final clamped = page.clamp(0, (state.totalPages - 1).clamp(0, 999999));
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
  }

  void toggleScrollMode(String mediaId) {
    final newVal = !state.scrollMode;
    state = state.copyWith(scrollMode: newVal);
    Prefs.instance.setScrollMode(mediaId, scrollMode: newVal);
  }

  void _scheduleSync(String mediaId) {
    _syncTimer?.cancel();
    _syncTimer =
        Timer(const Duration(seconds: 3), () => _syncNow(mediaId));
  }

  Future<void> _syncNow(String mediaId) async {
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

  Future<int?> _localPage(Database db, String mediaId) async {
    final rows = await db.query(
      'progress_queue',
      columns: ['current_page'],
      where: 'media_id = ?',
      whereArgs: [mediaId],
    );
    if (rows.isEmpty) return null;
    return rows.first['current_page'] as int?;
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

final readerProvider =
    NotifierProviderFamily<ReaderNotifier, ReaderState, ReaderArgs>(
  ReaderNotifier.new,
);

/// Global double-page spine gap in logical pixels. Persisted to prefs.
final doublePageGapProvider = StateProvider<double>(
  (ref) => Prefs.instance.doublePageGap,
);

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
