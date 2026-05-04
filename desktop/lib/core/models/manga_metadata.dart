class MangaMetadata {
  final String mediaId;
  final String? title;
  final String? synopsis;
  final String? genres;
  final double? score;
  final String? status;
  final int? year;
  final int? malId;
  final int? anilistId;
  final int? comicvineId;
  final String? source;
  final DateTime? lastScrapedAt;

  const MangaMetadata({
    required this.mediaId,
    this.title,
    this.synopsis,
    this.genres,
    this.score,
    this.status,
    this.year,
    this.malId,
    this.anilistId,
    this.comicvineId,
    this.source,
    this.lastScrapedAt,
  });

  factory MangaMetadata.fromJson(Map<String, dynamic> j) => MangaMetadata(
        mediaId:     j['mediaId'] as String,
        title:       j['title'] as String?,
        synopsis:    j['synopsis'] as String?,
        genres:      j['genres'] as String?,
        score:       (j['score'] as num?)?.toDouble(),
        status:      j['status'] as String?,
        year:        j['year'] as int?,
        malId:       j['malId'] as int?,
        anilistId:   j['anilistId'] as int?,
        comicvineId: j['comicvineId'] as int?,
        source:      j['source'] as String?,
        lastScrapedAt: j['lastScrapedAt'] != null
            ? DateTime.tryParse(j['lastScrapedAt'] as String)
            : null,
      );

  List<String> get genreList =>
      genres?.split(',').map((g) => g.trim()).where((g) => g.isNotEmpty).toList() ?? [];
}
