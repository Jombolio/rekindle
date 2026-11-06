import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:rekindle/screens/book/paged_chapter_view.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('curl endpoints match the flat pages in both directions', () async {
    const size = ui.Size(240, 40);
    const red = ui.Color(0xFFFF0000);
    const blue = ui.Color(0xFF0000FF);
    final sourceRecorder = ui.PictureRecorder();
    final sourceCanvas = ui.Canvas(sourceRecorder);
    sourceCanvas.drawRect(
        const ui.Rect.fromLTWH(0, 0, 120, 40), ui.Paint()..color = blue);
    sourceCanvas.drawRect(
        const ui.Rect.fromLTWH(120, 0, 120, 40), ui.Paint()..color = red);
    final sourcePicture = sourceRecorder.endRecording();
    final source = await sourcePicture.toImage(240, 40);
    sourcePicture.dispose();
    addTearDown(source.dispose);

    for (final direction in [1, -1]) {
      for (final progress in [0.0, 1.0]) {
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        PageCurlPainter(
          front: source,
          back: source,
          area: size,
          spine: 120,
          direction: direction,
          width: 120,
          progress: progress,
          paper: const ui.Color(0xFFFFFFFF),
        ).paint(canvas, size);
        final picture = recorder.endRecording();
        final image = await picture.toImage(240, 40);
        picture.dispose();
        final bytes = (await image.toByteData())!;
        image.dispose();
        final right = (direction == 1) == (progress == 0);
        final start = right ? 120 : 0;
        for (var x = start; x < start + 120; x++) {
          final offset = (20 * 240 + x) * 4;
          expect(
            [for (var c = 0; c < 4; c++) bytes.getUint8(offset + c)],
            right ? [255, 0, 0, 255] : [0, 0, 255, 255],
            reason: 'direction=$direction progress=$progress x=$x',
          );
        }
      }
    }
  });
}
