import 'manga_metadata.dart';

enum ScrapeStatus { created, noChange, conflict }

class ScrapeResult {
  final ScrapeStatus status;
  final MangaMetadata data;
  final MangaMetadata? existing;

  const ScrapeResult({
    required this.status,
    required this.data,
    this.existing,
  });

  factory ScrapeResult.fromJson(Map<String, dynamic> j) {
    final statusStr = j['status'] as String? ?? '';
    // The server emits Status.ToString().ToLowerInvariant(), i.e. "nochange"
    // (no underscore). "no_change" is accepted too in case that ever changes.
    final status = switch (statusStr) {
      'nochange' || 'no_change' => ScrapeStatus.noChange,
      'conflict'                => ScrapeStatus.conflict,
      _                         => ScrapeStatus.created,
    };
    return ScrapeResult(
      status:   status,
      data:     MangaMetadata.fromJson(j['data'] as Map<String, dynamic>),
      existing: j['existing'] != null
          ? MangaMetadata.fromJson(j['existing'] as Map<String, dynamic>)
          : null,
    );
  }
}
