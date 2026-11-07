import 'package:flutter/widgets.dart';

/// A page at the size [BoxFit.contain] draws it, even when nothing makes it
/// fill a box.
///
/// Given a box to fill, an [Image] with [BoxFit.contain] scales its picture up
/// or down to fit, and that is how the pager draws a page. Given room to choose
/// its own size instead, the same [Image] keeps the picture's natural size and
/// only ever shrinks it. So a page smaller than the window would be one size
/// in the pager and a smaller one as the sheet a turn lifts off it, and visibly
/// shrink as the turn began.
///
/// This takes the largest size that fits, in the picture's own proportions,
/// which is the rect [BoxFit.contain] would have drawn it in. Until the
/// picture's proportions are known it leaves [child] to size itself.
class ContainedPage extends StatefulWidget {
  /// The picture [child] draws, read for its proportions.
  final ImageProvider image;
  final Widget child;

  const ContainedPage({super.key, required this.image, required this.child});

  @override
  State<ContainedPage> createState() => _ContainedPageState();
}

class _ContainedPageState extends State<ContainedPage> {
  ImageStream? _stream;
  late final ImageStreamListener _listener =
      ImageStreamListener(_onImage, onError: (_, __) {});
  double? _aspect;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _resolve();
  }

  @override
  void didUpdateWidget(ContainedPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.image != oldWidget.image) _resolve();
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    super.dispose();
  }

  void _resolve() {
    final stream = widget.image.resolve(createLocalImageConfiguration(context));
    if (stream.key == _stream?.key) return;
    _stream?.removeListener(_listener);
    // A picture already decoded reports straight away, so a page that was
    // prefetched has its size from its first frame.
    _stream = stream..addListener(_listener);
  }

  void _onImage(ImageInfo info, bool synchronousCall) {
    final aspect = info.image.width / info.image.height;
    info.dispose();
    if (aspect == _aspect || !mounted) return;
    setState(() => _aspect = aspect);
  }

  @override
  Widget build(BuildContext context) {
    final aspect = _aspect;
    if (aspect == null || !aspect.isFinite || aspect <= 0) return widget.child;
    return AspectRatio(aspectRatio: aspect, child: widget.child);
  }
}
