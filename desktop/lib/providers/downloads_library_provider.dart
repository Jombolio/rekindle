import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../core/db/local_db_provider.dart';
import '../core/download/download_manager.dart';
import '../core/utils/natural_sort.dart';
import 'auth_provider.dart';
import 'download_provider.dart';
import 'settings_provider.dart';

/// A single downloaded chapter/archive, resolved from the local `downloads`
/// table. Everything here comes from on-device state — no server call — so the
/// Downloads screen works with the server unreachable.
class DownloadedItem {
  final String mediaId;
  final String title;
  final String format;
  final String? localPath;

  const DownloadedItem({
    required this.mediaId,
    required this.title,
    required this.format,
    this.localPath,
  });

  bool get isEpub => format.toLowerCase() == 'epub';

  /// Series name derived from the download's parent directory (the download
  /// path mirrors the server's on-disk layout, e.g. ".../Batman/Chapter1.cbz").
  /// Flat downloads with no series folder fall back to "Downloads".
  String get series {
    final path = localPath;
    if (path == null || path.isEmpty) return 'Downloads';
    final name = p.basename(p.dirname(path));
    if (name.isEmpty || name == '.' || name == 'Rekindle' ||
        name == 'Rekindle Downloads') {
      return 'Downloads';
    }
    return name;
  }
}

/// A group of downloaded chapters sharing a series folder.
class DownloadedSeries {
  final String series;
  final List<DownloadedItem> items;

  const DownloadedSeries({required this.series, required this.items});

  /// The chapter whose cover represents the folder (first, natural-sorted).
  DownloadedItem get representative => items.first;
}

/// All completed downloads, grouped into series folders and naturally sorted.
/// Reads the local DB only — safe offline. Invalidate to refresh after a
/// delete / purge.
final downloadsLibraryProvider =
    FutureProvider.autoDispose<List<DownloadedSeries>>((ref) async {
  final client = ref.read(apiClientProvider);
  final db = ref.read(localDbProvider);
  final dir = await resolveDownloadDir();
  final manager = DownloadManager(client, db, downloadBaseDir: dir);
  final records = await manager.listCompleted();

  final grouped = <String, List<DownloadedItem>>{};
  for (final r in records) {
    final item = DownloadedItem(
      mediaId: r.mediaId,
      title: r.title,
      format: r.format,
      localPath: r.localPath,
    );
    grouped.putIfAbsent(item.series, () => []).add(item);
  }

  final series = grouped.entries.map((e) {
    final items = e.value
      ..sort((a, b) => naturalCompare(a.title, b.title));
    return DownloadedSeries(series: e.key, items: items);
  }).toList()
    ..sort((a, b) => naturalCompare(a.series, b.series));

  return series;
});

/// Local cover path for a downloaded item. Returns the persistent local file
/// if present; otherwise attempts a best-effort fetch (online only) and
/// returns the result. Null when no local cover is available.
final downloadedCoverProvider =
    FutureProvider.autoDispose.family<String?, String>((ref, mediaId) async {
  final client = ref.read(apiClientProvider);
  final db = ref.read(localDbProvider);
  final dir = await resolveDownloadDir();
  final manager = DownloadManager(client, db, downloadBaseDir: dir);
  final existing = await manager.localCoverPath(mediaId);
  if (existing != null) return existing;
  await manager.downloadCover(mediaId);
  return manager.localCoverPath(mediaId);
});

/// Deletes every download from this device and refreshes the library list.
Future<void> purgeAllDownloads(WidgetRef ref) async {
  final client = ref.read(apiClientProvider);
  final db = ref.read(localDbProvider);
  final dir = await resolveDownloadDir();
  await DownloadManager(client, db, downloadBaseDir: dir).deleteAll();
  ref.invalidate(downloadsLibraryProvider);
  // deleteAll() removes rows directly, bypassing the per-media/per-folder
  // notifiers. Those families are NOT autoDispose, so already-created instances
  // (from the media/chapter grids) would keep reporting 'complete'. Invalidate
  // the whole families so each instance re-derives idle state from the now-empty
  // DB — otherwise purged items still show as downloaded until an app restart.
  ref.invalidate(downloadProvider);
  ref.invalidate(folderDownloadProvider);
}
