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
    final status = switch (statusStr) {
      'no_change' => ScrapeStatus.noChange,
      'conflict'  => ScrapeStatus.conflict,
      _           => ScrapeStatus.created,
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
