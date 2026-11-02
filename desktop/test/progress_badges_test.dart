import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rekindle/core/models/progress_summary.dart';
import 'package:rekindle/screens/widgets/progress_badges.dart';

/// The badges are Positioned, so they need a Stack around them.
Widget _cover(Widget badge) => MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 160,
          height: 240,
          child: Stack(children: [badge]),
        ),
      ),
    );

ProgressSummary _summary({double progress = 0, bool completed = false}) =>
    ProgressSummary(mediaId: 'm', progress: progress, isCompleted: completed);

void main() {
  group('ReadProgressRing', () {
    testWidgets('shows nothing without a summary', (tester) async {
      await tester.pumpWidget(_cover(const ReadProgressRing(summary: null)));

      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows nothing for an unstarted item', (tester) async {
      await tester.pumpWidget(_cover(ReadProgressRing(summary: _summary())));

      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('draws a partial ring while reading', (tester) async {
      await tester.pumpWidget(_cover(ReadProgressRing(summary: _summary(progress: 0.4))));

      final ring = tester.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator));
      expect(ring.value, 0.4);
      expect(find.byIcon(Icons.check), findsNothing);
      expect(find.byTooltip('40% read'), findsOneWidget);
    });

    testWidgets('a tiny fraction still draws a visible arc', (tester) async {
      await tester.pumpWidget(_cover(ReadProgressRing(summary: _summary(progress: 0.005))));

      final ring = tester.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator));
      expect(ring.value, greaterThan(0.005));
    });

    testWidgets('sits in the bottom-left corner', (tester) async {
      await tester.pumpWidget(_cover(ReadProgressRing(summary: _summary(progress: 0.4))));

      final pos = tester.widget<Positioned>(find.byType(Positioned));
      expect(pos.bottom, isNotNull);
      expect(pos.left, isNotNull);
      expect(pos.top, isNull);
      expect(pos.right, isNull);
    });

    testWidgets('a completed item shows a full ring and a check', (tester) async {
      await tester.pumpWidget(
          _cover(ReadProgressRing(summary: _summary(progress: 1, completed: true))));

      final ring = tester.widget<CircularProgressIndicator>(find.byType(CircularProgressIndicator));
      expect(ring.value, 1);
      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(find.byTooltip('Read'), findsOneWidget);
    });
  });

  group('NewChaptersBadge', () {
    testWidgets('shows nothing for zero', (tester) async {
      await tester.pumpWidget(_cover(const NewChaptersBadge(count: 0)));

      expect(find.textContaining('NEW'), findsNothing);
    });

    testWidgets('shows the count', (tester) async {
      await tester.pumpWidget(_cover(const NewChaptersBadge(count: 3)));

      expect(find.text('3 NEW'), findsOneWidget);
      expect(find.byTooltip('3 new chapters'), findsOneWidget);
    });

    testWidgets('uses the singular for one chapter', (tester) async {
      await tester.pumpWidget(_cover(const NewChaptersBadge(count: 1)));

      expect(find.byTooltip('1 new chapter'), findsOneWidget);
    });
  });
}
