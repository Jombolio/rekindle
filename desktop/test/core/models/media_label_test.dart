import 'package:flutter_test/flutter_test.dart';
import 'package:rekindle/core/models/media.dart';

Media archive(
        {String title = 'Chapter 1',
        String path = 'Series/Chapter 1.cbz',
        String format = 'cbz'}) =>
    Media(
        id: 'a',
        libraryId: 'l',
        title: title,
        format: format,
        relativePath: path);

void main() {
  test('extensions are off unless asked for', () {
    expect(archive().label(showExtension: false), 'Chapter 1');
    expect(archive().label(showExtension: true), 'Chapter 1.cbz');
  });

  test("the extension is the file's own, as written", () {
    final m = archive(path: 'Books/Dune.AZW3', format: 'azw3', title: 'Dune');
    expect(m.label(showExtension: true), 'Dune.AZW3');
  });

  test('without a file name, the format stands in', () {
    expect(archive(path: '').label(showExtension: true), 'Chapter 1.cbz');
  });

  test('folders have no extension', () {
    const folder = Media(
        id: 'f',
        libraryId: 'l',
        title: 'Series',
        format: 'folder',
        mediaType: 'folder');
    expect(folder.label(showExtension: true), 'Series');
  });

  test("a name that already ends with it isn't given it twice", () {
    expect(withExtension('Issue 3.cbz', 'cbz', show: true), 'Issue 3.cbz');
    expect(withExtension('Issue 3', 'cbz', show: true), 'Issue 3.cbz');
    expect(withExtension('Issue 3', 'cbz', show: false), 'Issue 3');
  });
}
