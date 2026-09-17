/// What the Rich Presence title line shows.
enum DiscordTitleMode {
  /// "Absolute Batman" on the first line, "Chapter 1" on the second.
  folderAndFile,

  /// Only the containing folder (series) name.
  folder,

  /// Only the file (issue / chapter / book) name.
  file,

  /// No title at all — just "Reading a comic".
  hidden;

  static DiscordTitleMode parse(String? name) => DiscordTitleMode.values
      .firstWhere((m) => m.name == name, orElse: () => folderAndFile);
}

class DiscordPresenceSettings {
  final bool enabled;
  final DiscordTitleMode titleMode;
  final bool showPage;
  final bool showElapsed;
  final bool showWhileBrowsing;

  const DiscordPresenceSettings({
    this.enabled = false,
    this.titleMode = DiscordTitleMode.folderAndFile,
    this.showPage = true,
    this.showElapsed = true,
    this.showWhileBrowsing = false,
  });

  DiscordPresenceSettings copyWith({
    bool? enabled,
    DiscordTitleMode? titleMode,
    bool? showPage,
    bool? showElapsed,
    bool? showWhileBrowsing,
  }) =>
      DiscordPresenceSettings(
        enabled: enabled ?? this.enabled,
        titleMode: titleMode ?? this.titleMode,
        showPage: showPage ?? this.showPage,
        showElapsed: showElapsed ?? this.showElapsed,
        showWhileBrowsing: showWhileBrowsing ?? this.showWhileBrowsing,
      );
}

enum ReadingKind {
  comic('comic'),
  manga('manga'),
  book('book');

  const ReadingKind(this.noun);
  final String noun;
}

/// The item currently open in a reader, as far as presence cares.
class NowReading {
  final String mediaId;
  final ReadingKind kind;

  /// Immediate parent folder, e.g. the series. Null for top-level items.
  final String? folderName;

  /// File name without extension, e.g. "Chapter 1".
  final String fileName;

  /// Zero-based page (or chapter, for books). Null until known.
  final int? position;
  final int? total;

  const NowReading({
    required this.mediaId,
    required this.kind,
    required this.fileName,
    this.folderName,
    this.position,
    this.total,
  });

  NowReading withPosition(int position, int total) => NowReading(
        mediaId: mediaId,
        kind: kind,
        fileName: fileName,
        folderName: folderName,
        position: position,
        total: total,
      );

  /// Groups consecutive chapters of one series so the elapsed timer keeps
  /// running across chapter auto-advance.
  String get sessionKey => folderName ?? mediaId;
}

/// Discord art asset key uploaded to the application in the developer portal.
const discordLargeImageKey = 'rekindle';

/// Builds the SET_ACTIVITY payload, or null when presence should be cleared.
Map<String, dynamic>? buildDiscordActivity({
  required DiscordPresenceSettings settings,
  required NowReading? reading,
  required int? startedAtMillis,
}) {
  if (!settings.enabled) return null;

  String details;
  final stateParts = <String>[];

  if (reading == null) {
    if (!settings.showWhileBrowsing) return null;
    details = 'Browsing the library';
  } else {
    final folder = reading.folderName;
    final file = reading.fileName;
    switch (settings.titleMode) {
      case DiscordTitleMode.folderAndFile:
        details = folder ?? file;
        if (folder != null) stateParts.add(file);
      case DiscordTitleMode.folder:
        // Top-level items have no folder; the file name is the only title.
        details = folder ?? file;
      case DiscordTitleMode.file:
        details = file;
      case DiscordTitleMode.hidden:
        details = 'Reading a ${reading.kind.noun}';
    }

    final pos = reading.position;
    final total = reading.total;
    if (settings.showPage && pos != null && total != null && total > 0) {
      final unit = reading.kind == ReadingKind.book ? 'Chapter' : 'Page';
      stateParts.add('$unit ${(pos + 1).clamp(1, total)} of $total');
    }
  }

  final state = stateParts.join(' · ');
  final largeText = reading == null
      ? 'Rekindle'
      : 'Reading ${reading.kind.noun} on Rekindle';

  return {
    'details': _field(details),
    if (state.isNotEmpty) 'state': _field(state),
    if (settings.showElapsed && startedAtMillis != null)
      'timestamps': {'start': startedAtMillis},
    'assets': {
      'large_image': discordLargeImageKey,
      'large_text': largeText,
    },
  };
}

/// Discord rejects text fields shorter than 2 or longer than 128 characters.
String _field(String s) {
  var out = s.trim();
  if (out.length > 128) out = '${out.substring(0, 127)}…';
  if (out.length < 2) out = out.padRight(2, ' ');
  return out;
}
