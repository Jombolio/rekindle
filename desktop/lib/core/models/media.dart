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
  final String
      relativePath; // path relative to library root, e.g. "Absolute Batman/Chapter1.cbz"
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

  /// The file's extension, as on disk ("cbz", "epub"), or empty for a folder.
  /// From the file name when it has one, otherwise the format.
  String get extension {
    if (isFolder) return '';
    final name = relativePath.split('/').last;
    final dot = name.lastIndexOf('.');
    if (dot > 0 && dot < name.length - 1) return name.substring(dot + 1);
    return format;
  }

  /// [name] (by default [displayTitle]) with the file extension added when
  /// [showExtension] is on, as Settings → Show file extensions asks.
  String label({required bool showExtension, String? name}) =>
      withExtension(name ?? displayTitle, extension, show: showExtension);
  bool get isImageBased => ['cbz', 'cbr', 'pdf'].contains(format);
}

/// [name] with [extension] added, when [show] is on and there is one.
String withExtension(String name, String extension, {required bool show}) {
  if (!show || extension.isEmpty) return name;
  final suffix = '.$extension';
  // Titles taken straight from a file name may already end with it.
  return name.toLowerCase().endsWith(suffix.toLowerCase())
      ? name
      : '$name$suffix';
}
