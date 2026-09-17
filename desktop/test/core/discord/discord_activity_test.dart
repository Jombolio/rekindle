import 'package:flutter_test/flutter_test.dart';
import 'package:rekindle/core/discord/discord_activity.dart';

void main() {
  const reading = NowReading(
    mediaId: 'm1',
    kind: ReadingKind.manga,
    folderName: 'One Piece',
    fileName: 'Chapter 1001',
    position: 4,
    total: 20,
  );
  const on = DiscordPresenceSettings(enabled: true);

  Map<String, dynamic>? build(DiscordPresenceSettings s,
          {NowReading? r = reading, int? start = 1000}) =>
      buildDiscordActivity(settings: s, reading: r, startedAtMillis: start);

  test('disabled clears presence', () {
    expect(build(const DiscordPresenceSettings()), isNull);
  });

  test('folder and file with page', () {
    final a = build(on)!;
    expect(a['details'], 'One Piece');
    expect(a['state'], 'Chapter 1001 · Page 5 of 20');
    expect(a['timestamps'], {'start': 1000});
  });

  test('folder only falls back to file for top-level items', () {
    final s = on.copyWith(titleMode: DiscordTitleMode.folder);
    expect(build(s)!['details'], 'One Piece');
    expect(build(s)!['state'], 'Page 5 of 20');

    const topLevel =
        NowReading(mediaId: 'm2', kind: ReadingKind.comic, fileName: 'Saga 01');
    expect(build(s, r: topLevel)!['details'], 'Saga 01');
  });

  test('file only', () {
    final a = build(on.copyWith(titleMode: DiscordTitleMode.file))!;
    expect(a['details'], 'Chapter 1001');
  });

  test('hidden title shares only the kind', () {
    final a = build(on.copyWith(
        titleMode: DiscordTitleMode.hidden, showPage: false, showElapsed: false))!;
    expect(a['details'], 'Reading a manga');
    expect(a.containsKey('state'), isFalse);
    expect(a.containsKey('timestamps'), isFalse);
  });

  test('the EPUB reader reports chapters', () {
    const book = NowReading(
        mediaId: 'b',
        kind: ReadingKind.book,
        fileName: 'Dune',
        position: 2,
        total: 48,
        countsChapters: true);
    expect(build(on.copyWith(titleMode: DiscordTitleMode.file), r: book)!['state'],
        'Chapter 3 of 48');
  });

  test('page-based items in a book library report pages', () {
    const pdf = NowReading(
        mediaId: 'p', kind: ReadingKind.book, fileName: 'Manual', position: 4, total: 523);
    expect(build(on.copyWith(titleMode: DiscordTitleMode.file), r: pdf)!['state'],
        'Page 5 of 523');
  });

  test('browsing only when opted in', () {
    expect(build(on, r: null), isNull);
    expect(build(on.copyWith(showWhileBrowsing: true), r: null)!['details'],
        'Browsing the library');
  });

  test('long titles are truncated to Discord limits', () {
    final long = NowReading(mediaId: 'x', kind: ReadingKind.comic, fileName: 'a' * 300);
    final details = build(on, r: long)!['details'] as String;
    expect(details.length, 128);
  });
}
