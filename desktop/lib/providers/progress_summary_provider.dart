import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/media_api.dart';
import '../core/models/progress_summary.dart';
import 'auth_provider.dart';

/// Matches the media grid's page size, so each loaded page is one request.
const kGridSummaryChunk = 24;

/// Chapter lists can run to thousands of entries; fetch them in larger chunks.
const kListSummaryChunk = 100;

/// Reading state for a chunk of media ids, keyed by a comma-joined id list
/// (see [summaryChunkKey]). Ids are GUIDs, so the comma is unambiguous.
///
/// Fetching in fixed chunks means a growing grid only requests its new page,
/// and summaries already shown stay put while later chunks load. Invalidated
/// after reading progress syncs, so covers catch up when the reader closes.
///
/// Errors (offline, or a server too old to have the endpoint) yield an empty
/// map: covers then fall back to this device's local progress.
final progressSummariesProvider = FutureProvider.autoDispose
    .family<Map<String, ProgressSummary>, String>((ref, idsKey) async {
  final client = ref.watch(apiClientProvider);
  if (idsKey.isEmpty) return const {};
  try {
    return await MediaApi(client).getProgressSummaries(idsKey.split(','));
  } catch (_) {
    return const {};
  }
});

/// The [progressSummariesProvider] key for the chunk containing [index].
String summaryChunkKey(List<String> ids, int index, int chunkSize) {
  final start = (index ~/ chunkSize) * chunkSize;
  final end = min(start + chunkSize, ids.length);
  return ids.sublist(start, end).join(',');
}
