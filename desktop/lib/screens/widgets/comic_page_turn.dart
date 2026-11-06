import 'dart:math' as math;
import 'package:flutter/material.dart';

/// A hinged paper turn driven by the pager, so dragging and button navigation
/// use the same motion and keep the pager's progress and gesture handling.
class ComicPageTurn extends StatelessWidget {
  final PageController controller;
  final int index;
  final bool reverse;
  final Widget child;

  const ComicPageTurn(
      {super.key,
      required this.controller,
      required this.index,
      required this.reverse,
      required this.child});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) => AnimatedBuilder(
          animation: controller,
          child: RepaintBoundary(child: child),
          builder: (context, child) {
            final page = controller.hasClients &&
                    controller.position.hasContentDimensions
                ? controller.page ?? controller.initialPage.toDouble()
                : controller.initialPage.toDouble();
            final offset = (page - index).clamp(-1.0, 1.0);
            if (offset.abs() >= 1) return const SizedBox.expand();
            final physical = reverse ? -offset : offset;
            return Transform.translate(
              // Cancel the pager's slide; the leaf turns around its edge instead.
              offset: Offset(physical * constraints.maxWidth, 0),
              child: Transform(
                alignment: physical >= 0
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0008)
                  ..rotateY(-physical * math.pi / 2),
                child: Stack(fit: StackFit.expand, children: [
                  const ColoredBox(color: Colors.black),
                  child!,
                  IgnorePointer(
                      child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.22 * offset.abs()),
                  )),
                ]),
              ),
            );
          },
        ),
      );
}
