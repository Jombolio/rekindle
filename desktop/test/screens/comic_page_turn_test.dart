import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rekindle/screens/widgets/comic_page_turn.dart';

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
}
