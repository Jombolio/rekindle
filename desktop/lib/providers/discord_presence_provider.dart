import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/api/libraries_api.dart';
import '../core/db/local_db_provider.dart';
import '../core/discord/discord_activity.dart';
import '../core/discord/discord_ipc.dart';
import 'auth_provider.dart';
import 'media_provider.dart';
import 'settings_provider.dart';

/// Discord application ID of the official Rekindle app. Not a secret: local RPC
/// needs no client secret. The application's name is what Discord shows as
/// "Playing <name>", and its `rekindle` art asset is the large image.
/// Forks can point at their own application with
/// `--dart-define=DISCORD_CLIENT_ID=...`.
const discordClientId = String.fromEnvironment(
  'DISCORD_CLIENT_ID',
  defaultValue: '1549939655846404286',
);

bool get discordPresenceAvailable =>
    DiscordIpcClient.isSupported && discordClientId.isNotEmpty;

// ---------------------------------------------------------------------------
// What is being read right now
// ---------------------------------------------------------------------------

/// Fed by the reader screens. Every mutation is deferred to a microtask
/// because the screens call these from initState/dispose, where Riverpod
/// forbids modifying providers.
class NowReadingNotifier extends Notifier<NowReading?> {
  // The media the most recent open() was for; resolutions for anything else
  // (a chapter the user already moved past) are discarded.
  String? _openMediaId;
  // Position reported before the names finished resolving.
  (int, int)? _pendingPosition;

  @override
  NowReading? build() => null;

  void open(String mediaId, {String? libraryType, String? fallbackTitle}) {
    _openMediaId = mediaId;
    _pendingPosition = null;
    Future.microtask(() async {
      final reading = await _resolve(mediaId, libraryType, fallbackTitle);
      if (_openMediaId != mediaId) return;
      final pos = _pendingPosition;
      state = pos == null ? reading : reading.withPosition(pos.$1, pos.$2);
    });
  }

  void updatePosition(String mediaId, int position, int total) {
    if (_openMediaId != mediaId) return;
    Future.microtask(() {
      final current = state;
      if (current == null || current.mediaId != mediaId) {
        _pendingPosition = (position, total);
      } else if (current.position != position || current.total != total) {
        state = current.withPosition(position, total);
      }
    });
  }

  void close(String mediaId) {
    // Chapter auto-advance opens the next reader before the previous one is
    // disposed; only the reader that owns the presence may clear it.
    if (_openMediaId != mediaId) return;
    _openMediaId = null;
    Future.microtask(() {
      if (_openMediaId == null) state = null;
    });
  }

  Future<NowReading> _resolve(
      String mediaId, String? libraryType, String? fallbackTitle) async {
    try {
      final media = await ref.read(mediaDetailProvider(mediaId).future);
      final rel = media.relativePath;
      final folder = rel.isEmpty ? '' : p.basename(p.dirname(rel));

      var kind = _kindFor(media.format, libraryType);
      if (libraryType == null && kind != ReadingKind.book) {
        try {
          final library = await LibrariesApi(ref.read(apiClientProvider))
              .getById(media.libraryId);
          kind = _kindFor(media.format, library.type);
        } catch (_) {}
      }

      return NowReading(
        mediaId: mediaId,
        kind: kind,
        fileName: rel.isEmpty ? media.title : p.basenameWithoutExtension(rel),
        folderName: folder.isEmpty || folder == '.' ? null : folder,
      );
    } catch (_) {
      // Offline: the downloads table only knows the title and format.
      final rows = await ref.read(localDbProvider).query(
        'downloads',
        columns: ['title', 'format'],
        where: 'media_id = ?',
        whereArgs: [mediaId],
      );
      final row = rows.firstOrNull;
      return NowReading(
        mediaId: mediaId,
        kind: _kindFor(row?['format'] as String?, libraryType),
        fileName: row?['title'] as String? ?? fallbackTitle ?? 'Unknown title',
      );
    }
  }

  static ReadingKind _kindFor(String? format, String? libraryType) {
    if (format == 'epub') return ReadingKind.book;
    return switch (libraryType) {
      'manga' => ReadingKind.manga,
      'book' || 'books' => ReadingKind.book,
      _ => ReadingKind.comic,
    };
  }
}

final nowReadingProvider =
    NotifierProvider<NowReadingNotifier, NowReading?>(NowReadingNotifier.new);

// ---------------------------------------------------------------------------
// Discord connection
// ---------------------------------------------------------------------------

/// Mirrors settings + [nowReadingProvider] into Discord. Keep it alive by
/// watching it from the app root.
final discordPresenceProvider = Provider<DiscordPresenceController?>((ref) {
  if (!discordPresenceAvailable) return null;
  final controller = DiscordPresenceController(DiscordIpcClient(discordClientId));
  ref.onDispose(controller.dispose);

  void sync() => controller.update(
        ref.read(settingsProvider).discord,
        ref.read(nowReadingProvider),
      );
  ref.listen(settingsProvider.select((s) => s.discord), (_, __) => sync());
  ref.listen(nowReadingProvider, (_, __) => sync());
  sync();
  return controller;
});

class DiscordPresenceController {
  DiscordPresenceController(this._client);

  final DiscordIpcClient _client;

  // Discord allows 5 activity updates per 20 s; page flipping must not trip it.
  static const _minPushInterval = Duration(seconds: 4);
  // Coalesces the close→open pair of a chapter auto-advance into one update.
  static const _debounce = Duration(milliseconds: 750);
  static const _retryInterval = Duration(seconds: 20);

  Map<String, dynamic>? _desired;
  String? _pushedJson;
  bool _pushedOnce = false;
  DateTime _lastPush = DateTime.fromMillisecondsSinceEpoch(0);
  Timer? _timer;
  bool _busy = false;
  bool _disposed = false;

  String? _sessionKey;
  int? _sessionStart;

  void update(DiscordPresenceSettings settings, NowReading? reading) {
    final key = settings.enabled ? (reading?.sessionKey ?? '') : null;
    if (key != _sessionKey) {
      _sessionKey = key;
      _sessionStart = DateTime.now().millisecondsSinceEpoch;
    }
    _desired = buildDiscordActivity(
      settings: settings,
      reading: reading,
      startedAtMillis: _sessionStart,
    );
    _schedule(_debounce);
  }

  void _schedule(Duration minDelay) {
    if (_disposed || _timer != null) return;
    final sinceLast = DateTime.now().difference(_lastPush);
    final throttle = _minPushInterval - sinceLast;
    _timer = Timer(throttle > minDelay ? throttle : minDelay, _flush);
  }

  Future<void> _flush() async {
    _timer = null;
    if (_busy || _disposed) {
      _schedule(_debounce);
      return;
    }
    final desired = _desired;
    final json = jsonEncode(desired);
    if (_pushedOnce && json == _pushedJson) return;

    _busy = true;
    try {
      if (desired == null) {
        // Nothing to show: clear what we set, then free the socket so Discord
        // stops listing Rekindle entirely.
        if (_client.isConnected) {
          await _client.setActivity(null);
          await _client.close();
        }
      } else {
        if (!_client.isConnected) {
          await _client.connect();
          debugPrint('Discord presence: connected');
        }
        await _client.setActivity(desired);
        debugPrint('Discord presence: set "${desired['details']}"');
      }
      _pushedJson = json;
      _pushedOnce = true;
      _lastPush = DateTime.now();
    } catch (e) {
      debugPrint('Discord presence: $e');
      if (e is DiscordIpcException && e.rejected) {
        // Don't resend a payload Discord refused; the next change is tried.
        _pushedJson = json;
        _pushedOnce = true;
        _lastPush = DateTime.now();
        return;
      }
      // Discord not running (or restarted) — try again later if there is still
      // something to show.
      if (_desired != null) _schedule(_retryInterval);
    } finally {
      _busy = false;
    }
    if (!_disposed && jsonEncode(_desired) != _pushedJson) _schedule(_debounce);
  }

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _client.close();
  }
}
