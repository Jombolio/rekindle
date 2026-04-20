class Media {
  final String id;
  final String libraryId;
  final String title;
  final String? series;
  final int? volume;
  final String format;
  final int? pageCount;
  final String? coverCachePath;
  final String mediaType; // "archive" | "folder"
  final String relativePath; // path relative to library root, e.g. "Absolute Batman/Chapter1.cbz"
  final String? parentId;

  const Media({
    required this.id,
    required this.libraryId,
    required this.title,
    this.series,
    this.volume,
    required this.format,
    this.pageCount,
    this.coverCachePath,
    this.mediaType = 'archive',
    this.relativePath = '',
    this.parentId,
  });

  factory Media.fromJson(Map<String, dynamic> j) => Media(
        id: j['id'] as String,
        libraryId: j['libraryId'] as String,
        title: j['title'] as String,
        series: j['series'] as String?,
        volume: j['volume'] as int?,
        format: j['format'] as String,
        pageCount: j['pageCount'] as int?,
        coverCachePath: j['coverCachePath'] as String?,
        mediaType: j['mediaType'] as String? ?? 'archive',
        relativePath: j['relativePath'] as String? ?? '',
        parentId: j['parentId'] as String?,
      );

  String get displayTitle {
    if (series != null && volume != null) return '$series #$volume';
    return title;
  }

  bool get isFolder => mediaType == 'folder';
  bool get isImageBased => ['cbz', 'cbr', 'pdf'].contains(format);
}
