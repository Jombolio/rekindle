import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rekindle/screens/widgets/comic_page_turn.dart';
import 'package:rekindle/screens/widgets/contained_page.dart';

/// The comic reader's pager, laid out as [ReaderScreen] builds it: flat slides
/// held still by [ComicPageTurn], with the turning sheet curling above them.
const Size _viewport = Size(400, 200);
const List<Color> _slides = [
  Color(0xFFFF0000),
  Color(0xFF0000FF),
  Color(0xFF00FF00),
];

void main() {
  final boundary = GlobalKey();

  Widget reader(PageController controller, bool reverse) => MaterialApp(
        home: Center(
          child: RepaintBoundary(
            key: boundary,
            child: SizedBox.fromSize(
              size: _viewport,
              child: Stack(fit: StackFit.expand, children: [
                PageView.builder(
                  controller: controller,
                  reverse: reverse,
                  itemCount: _slides.length,
                  itemBuilder: (_, index) => ComicPageTurn(
                    controller: controller,
                    index: index,
                    reverse: reverse,
                    child: SizedBox.expand(
                        child: ColoredBox(color: _slides[index])),
                  ),
                ),
                ComicPageCurl(
                  controller: controller,
                  reverse: reverse,
                  slideCount: _slides.length,
                  spreadAt: (_) => false,
                  slideBuilder: (index) =>
                      SizedBox.expand(child: ColoredBox(color: _slides[index])),
                  backBuilder: (index) =>
                      SizedBox.expand(child: ColoredBox(color: _slides[index])),
                ),
              ]),
            ),
          ),
        ),
      );

  /// The colour down the middle of the viewport at [x]. Reading the pixels
  /// back is real work, so it has to run outside the test's fake clock.
  Future<Color> pixel(WidgetTester tester, double x) async {
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = render.toImageSync();
    final bytes = (await tester.runAsync(() => image.toByteData()))!;
    image.dispose();
    final at = ((_viewport.height ~/ 2) * image.width + x.round()) * 4;
    return Color.fromARGB(
      bytes.getUint8(at + 3),
      bytes.getUint8(at),
      bytes.getUint8(at + 1),
      bytes.getUint8(at + 2),
    );
  }

  Future<void> expectSlide(WidgetTester tester, double x, int slide) async {
    expect(await pixel(tester, x), _slides[slide], reason: 'x=$x');
  }

  /// Every colour down the middle of the viewport, left to right.
  Future<Set<Color>> row(WidgetTester tester) async {
    final render =
        boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = render.toImageSync();
    final bytes = (await tester.runAsync(() => image.toByteData()))!;
    final width = image.width;
    image.dispose();
    return {
      for (var x = 0; x < width; x++)
        () {
          final at = ((_viewport.height ~/ 2) * width + x) * 4;
          return Color.fromARGB(bytes.getUint8(at + 3), bytes.getUint8(at),
              bytes.getUint8(at + 1), bytes.getUint8(at + 2));
        }(),
    };
  }

  for (final reverse in [false, true]) {
    testWidgets('a turning sheet curls off and reveals the next, RTL=$reverse',
        (tester) async {
      final controller = PageController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(reader(controller, reverse));

      // At rest nothing curls: the slide being read fills the viewport.
      for (final x in [10.0, 200.0, 390.0]) {
        await expectSlide(tester, x, 0);
      }

      // Halfway through a turn, the sheet is hinged at the edge it turns away
      // from — the left reading left to right, the right reading right to
      // left. Its flat part still covers that edge; past the roll, the slide
      // being turned to shows through.
      final turn = controller.animateToPage(1,
          duration: const Duration(milliseconds: 700), curve: Curves.easeInOut);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await expectSlide(tester, reverse ? 390 : 10, 0);
      await expectSlide(tester, reverse ? 10 : 390, 1);
      // Where the sheet has folded back on itself, its own back faces up: the
      // reader's black, not either slide.
      final back = await pixel(tester, reverse ? 250 : 150);
      expect(back, isNot(_slides[0]));
      expect(back, isNot(_slides[1]));
      expect(back.r + back.g + back.b, lessThan(1),
          reason: 'the back of the sheet, not a page: $back');

      // Settled, the slide turned to fills the viewport on its own.
      await tester.pumpAndSettle();
      await turn;
      expect(controller.page, 1);
      for (final x in [10.0, 200.0, 390.0]) {
        await expectSlide(tester, x, 1);
      }

      // Turning back runs the same sheet the other way: slide 0 is the one
      // that curls, so halfway back it covers its hinged edge again.
      final back0 = controller.animateToPage(0,
          duration: const Duration(milliseconds: 700), curve: Curves.easeInOut);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await expectSlide(tester, reverse ? 390 : 10, 0);
      await expectSlide(tester, reverse ? 10 : 390, 1);
      await tester.pumpAndSettle();
      await back0;
      for (final x in [10.0, 200.0, 390.0]) {
        await expectSlide(tester, x, 0);
      }

      // A drag curls the sheet too, straight off the pager's position.
      final drag =
          await tester.startGesture(tester.getCenter(find.byType(PageView)));
      await drag.moveBy(Offset(reverse ? 200 : -200, 0));
      await tester.pump();
      await expectSlide(tester, reverse ? 390 : 10, 0);
      await expectSlide(tester, reverse ? 10 : 390, 1);
      await drag.up();
      await tester.pumpAndSettle();
      expect(controller.page, 1);

      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('a single slide has nothing to turn', (tester) async {
    final controller = PageController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: RepaintBoundary(
          key: boundary,
          child: SizedBox.fromSize(
            size: _viewport,
            child: Stack(fit: StackFit.expand, children: [
              PageView.builder(
                controller: controller,
                itemCount: 1,
                itemBuilder: (_, index) => ComicPageTurn(
                  controller: controller,
                  index: index,
                  reverse: false,
                  child:
                      SizedBox.expand(child: ColoredBox(color: _slides[index])),
                ),
              ),
              ComicPageCurl(
                controller: controller,
                reverse: false,
                slideCount: 1,
                spreadAt: (_) => false,
                slideBuilder: (index) =>
                    SizedBox.expand(child: ColoredBox(color: _slides[index])),
                backBuilder: (index) =>
                    SizedBox.expand(child: ColoredBox(color: _slides[index])),
              ),
            ]),
          ),
        ),
      ),
    ));
    await tester.drag(find.byType(PageView), const Offset(-200, 0));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    for (final x in [10.0, 200.0, 390.0]) {
      await expectSlide(tester, x, 0);
    }
    await tester.pumpWidget(const SizedBox());
  });

  // A two-page slide, as the reader builds the sheet that turns: the printed
  // pages and nothing else, so the spine falls down the middle of the sheet.
  // Each page is a primary, so the roll's shading dims it without moving any
  // channel onto another — which is what [whichPage] reads it back by.
  const pages = [
    Color(0xFFFF0000), // slide 0, left
    Color(0xFF00FF00), // slide 0, right
    Color(0xFF0000FF), // slide 1, left
    Color(0xFFFFFF00), // slide 1, right
  ];

  /// Which page a pixel came from, however far the roll has shaded it, or
  /// null for the reader's background and the paper between the strips.
  int? whichPage(Color c) {
    const floor = 0.08;
    final lit = [c.r > floor, c.g > floor, c.b > floor];
    final index = [
      [true, false, false],
      [false, true, false],
      [false, false, true],
      [true, true, false],
    ].indexWhere((want) {
      for (var i = 0; i < 3; i++) {
        if (want[i] != lit[i]) return false;
      }
      return true;
    });
    return index < 0 ? null : index;
  }

  for (final reverse in [false, true]) {
    // The sheet that turns is the half on the side the reader turns from: the
    // right reading left to right, the left reading right to left.
    final staying = reverse ? 1 : 0;
    final turning = reverse ? 0 : 1;
    final arriving = reverse ? 3 : 2; // rides the sheet, printed on its back
    final revealed = reverse ? 2 : 3; // lies beneath, uncovered by the turn
    final stayingX = reverse ? _viewport.width - 10 : 10.0;
    final revealedX = reverse ? 10.0 : _viewport.width - 10;

    testWidgets('a spread turns about the spine down its middle, RTL=$reverse',
        (tester) async {
      final controller = PageController();
      addTearDown(controller.dispose);
      Widget spread(int index) => Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final half in [index * 2, index * 2 + 1])
                SizedBox(
                    width: _viewport.width / 2,
                    height: _viewport.height,
                    child: ColoredBox(color: pages[half])),
            ],
          );
      await tester.pumpWidget(MaterialApp(
        home: Center(
          child: RepaintBoundary(
            key: boundary,
            child: SizedBox.fromSize(
              size: _viewport,
              child: Stack(fit: StackFit.expand, children: [
                PageView.builder(
                  controller: controller,
                  reverse: reverse,
                  itemCount: 2,
                  itemBuilder: (_, index) => ComicPageTurn(
                    controller: controller,
                    index: index,
                    reverse: reverse,
                    child: spread(index),
                  ),
                ),
                ComicPageCurl(
                  controller: controller,
                  reverse: reverse,
                  slideCount: 2,
                  spreadAt: (_) => true,
                  slideBuilder: spread,
                  backBuilder: (index) => Center(child: spread(index)),
                ),
              ]),
            ),
          ),
        ),
      ));

      // At rest the slide being read fills the spread.
      expect(whichPage(await pixel(tester, stayingX)), staying);
      expect(whichPage(await pixel(tester, revealedX)), turning);

      final drag =
          await tester.startGesture(tester.getCenter(find.byType(PageView)));
      await drag.moveBy(Offset(_viewport.width / 2 * (reverse ? 1 : -1), 0));
      await tester.pump();
      final mid = (await row(tester)).map(whichPage).toSet();

      // The page on the far side of the spine has not moved: it stays down
      // until the turning sheet lands on it. That is what a centre spine
      // buys — without one the whole spread slides away at once.
      expect(whichPage(await pixel(tester, stayingX)), staying,
          reason: 'the page being turned away from should stay put');
      // Past the sheet's edge, the next slide is already showing.
      expect(whichPage(await pixel(tester, revealedX)), revealed,
          reason: "the next slide's far page should be revealed");
      // The sheet carries two pages, as a printed one does: the half being
      // left on its front, and the next slide's facing page on its back.
      expect(mid, contains(turning),
          reason: 'the page being turned should still be visible');
      expect(mid, contains(arriving),
          reason: "the next slide's facing page should ride the sheet");

      await drag.up();
      await tester.pumpAndSettle();
      expect(controller.page, 1);
      expect(whichPage(await pixel(tester, stayingX)), arriving);
      expect(whichPage(await pixel(tester, revealedX)), revealed);
      await tester.pumpWidget(const SizedBox());
    });
  }

  // A spread before a lone page, as buildSlides leaves one ahead of every
  // landscape page. It still turns about the spine down its middle, and the
  // lone page — narrower, and centred — arrives on the back of the turning
  // half. Before, this turned the whole spread over from its outer edge on a
  // grey sheet, and that grey flashed against every other turn in the book.
  testWidgets('a spread turns into a lone page about its spine',
      (tester) async {
    const left = Color(0xFFFF0000);
    const right = Color(0xFF00FF00);
    const lone = Color(0xFF0000FF);
    final controller = PageController();
    addTearDown(controller.dispose);
    Widget spread() => Row(mainAxisSize: MainAxisSize.min, children: [
          for (final c in [left, right])
            SizedBox(
                width: _viewport.width / 2,
                height: _viewport.height,
                child: ColoredBox(color: c)),
        ]);
    Widget lonePage() => const SizedBox(
        width: 120, height: 180, child: ColoredBox(color: lone));
    Widget slide(int i) => i == 0 ? spread() : lonePage();
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: RepaintBoundary(
          key: boundary,
          child: SizedBox.fromSize(
            size: _viewport,
            child: Stack(fit: StackFit.expand, children: [
              PageView.builder(
                controller: controller,
                itemCount: 2,
                itemBuilder: (_, i) => ComicPageTurn(
                  controller: controller,
                  index: i,
                  reverse: false,
                  child: Center(child: slide(i)),
                ),
              ),
              ComicPageCurl(
                controller: controller,
                reverse: false,
                slideCount: 2,
                spreadAt: (leaf) => leaf == 0,
                slideBuilder: slide,
                backBuilder: (i) => Center(child: slide(i)),
                paper: ComicPageTurn.backdrop,
              ),
            ]),
          ),
        ),
      ),
    ));

    final turn = controller.animateToPage(1,
        duration: const Duration(milliseconds: 700), curve: Curves.easeInOut);
    await tester.pump();
    // Late in the turn, with most of the sheet over.
    await tester.pump(const Duration(milliseconds: 516));
    final late = await row(tester);
    // The left page is still down: the spine is the hinge, not the outer
    // edge, so the sheet has not reached it yet.
    expect(await pixel(tester, 10), left,
        reason: 'the page beside the spine should stay put');
    // The lone page has arrived: on the back of the sheet, and beyond its
    // edge. Either way the roll shades it a little, so look for blue rather
    // than for the exact colour.
    expect(late.any((c) => c.b > 0.8 && c.r < 0.1 && c.g < 0.1), isTrue,
        reason: 'the lone page should be arriving');
    // And nowhere is there the grey a single sheet's back is printed on, or
    // any neutral grey like it.
    final greys = late.where((c) =>
        (c.r - c.g).abs() < 0.02 &&
        (c.g - c.b).abs() < 0.02 &&
        c.r > 0.1 &&
        c.r < 0.3);
    expect(greys, isEmpty, reason: 'no grey sheet in double-page reading');

    await tester.pumpAndSettle();
    await turn;
    expect(controller.page, 1);
    expect(await pixel(tester, _viewport.width / 2), lone);
    expect(await pixel(tester, 10), const Color(0xFF000000));
    await tester.pumpWidget(const SizedBox());
  });

  // A turn from a page to a bigger one — a landscape page, or the next scan
  // simply measuring differently. The pager already has the next slide down
  // beneath the sheet from the turn's first frame; the margins around the
  // sheet have to stay the reader's black until the turn moves, not show it.
  testWidgets('the margins hold still as a turn begins', (tester) async {
    const small = Color(0xFFFF0000);
    const big = Color(0xFF00FF00);
    final controller = PageController();
    addTearDown(controller.dispose);
    Widget slide(int i) => i == 0
        ? const SizedBox(
            width: 120, height: 180, child: ColoredBox(color: small))
        : const SizedBox.expand(child: ColoredBox(color: big));
    await tester.pumpWidget(MaterialApp(
      home: Center(
        child: RepaintBoundary(
          key: boundary,
          child: SizedBox.fromSize(
            size: _viewport,
            child: Stack(fit: StackFit.expand, children: [
              PageView.builder(
                controller: controller,
                itemCount: 2,
                itemBuilder: (_, i) => ComicPageTurn(
                  controller: controller,
                  index: i,
                  reverse: false,
                  child: Center(child: slide(i)),
                ),
              ),
              ComicPageCurl(
                controller: controller,
                reverse: false,
                slideCount: 2,
                spreadAt: (_) => false,
                slideBuilder: slide,
                backBuilder: slide,
              ),
            ]),
          ),
        ),
      ),
    ));
    // A margin, well clear of the small page.
    const margin = 15.0;
    expect(await pixel(tester, margin), const Color(0xFF000000));

    final turn = controller.animateToPage(1,
        duration: const Duration(milliseconds: 700), curve: Curves.easeInOut);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    // The first frame of the turn: still the margin of the page being left.
    final first = await pixel(tester, margin);
    expect(first.g, lessThan(0.05),
        reason: 'the bigger page beneath should not jump into the margin');
    // Half way, it is coming through.
    await tester.pump(const Duration(milliseconds: 334));
    final half = await pixel(tester, margin);
    expect(half.g, greaterThan(0.2));
    expect(half.g, lessThan(0.8));
    await tester.pumpAndSettle();
    await turn;
    expect(await pixel(tester, margin), big);
    await tester.pumpWidget(const SizedBox());
  });

  // The pager draws a lone page to fill the viewport, scaling up as well as
  // down; an Image left to size itself keeps its natural size and only
  // shrinks. A page smaller than the window was one size in the pager and a
  // smaller one as the sheet, and visibly shrank as every turn began.
  testWidgets('a lone page is sized as the pager draws it', (tester) async {
    tester.view.physicalSize = const Size(1000, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final png = (await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 300, 450),
          Paint()..color = const Color(0xFFFF0000));
      final image = await recorder.endRecording().toImage(300, 450);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      return bytes!.buffer.asUint8List();
    }))!;
    final provider = MemoryImage(png);
    final key = GlobalKey();
    await tester.pumpWidget(Center(
      child: SizedBox(
        width: 1000,
        height: 700,
        child: Align(
          child: ContainedPage(
            key: key,
            image: provider,
            child: Image(image: provider, fit: BoxFit.contain),
          ),
        ),
      ),
    ));
    await tester.runAsync(() => precacheImage(provider, key.currentContext!));
    await tester.pump();
    // 300x450 scaled to fit 1000x700: as tall as it can be, in proportion.
    final size = tester.getSize(find.byKey(key));
    expect(size.height, moreOrLessEquals(700, epsilon: 0.5));
    expect(size.width, moreOrLessEquals(700 * 300 / 450, epsilon: 0.5));
  });
}
