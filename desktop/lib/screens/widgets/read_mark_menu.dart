import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/media_api.dart';
import '../../core/models/media.dart';
import '../../core/models/progress_summary.dart';
import '../../providers/auth_provider.dart';
import '../../providers/progress_summary_provider.dart';

/// What the right-click menu on a chapter or series can do.
enum ReadStateAction { markRead, unmarkRead, ignoreTracking, trackAgain }

/// Shows the right-click menu for a chapter or series, at [position].
///
/// - **Mark as read**: a read mark is separate from reading progress. The
///   chapter counts as read however far into it the reader is, and stays so
///   while they reread or catch up, until they remove the mark; their place in
///   it is never changed.
/// - **Ignore archive tracking**: leaves the archive out of its series'
///   progress, so an annual or bundled volume the reader skips doesn't keep the
///   series from looking finished or up to date. Its own progress is kept.
///
/// On a series or folder, each applies to every archive in it, so both
/// directions are offered there.
Future<void> showReadMarkMenu(
  BuildContext context,
  WidgetRef ref, {
  required Media media,
  required ProgressSummary? summary,
  required Offset position,
}) async {
  final marked = summary?.markedRead ?? false;
  final ignored = summary?.ignored ?? false;
  final folder = media.isFolder;
  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;

  PopupMenuItem<ReadStateAction> item(
    ReadStateAction action,
    IconData icon,
    String title, [
    String? subtitle,
  ]) =>
      PopupMenuItem(
        value: action,
        child: ListTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: subtitle == null ? null : Text(subtitle),
          dense: true,
          contentPadding: EdgeInsets.zero,
        ),
      );

  final choice = await showMenu<ReadStateAction>(
    context: context,
    position: RelativeRect.fromRect(
      position & const Size(1, 1),
      Offset.zero & overlay.size,
    ),
    items: [
      if (!marked)
        item(
          ReadStateAction.markRead,
          Icons.done_all,
          folder ? 'Mark series as read' : 'Mark as read',
          'Stays read while you reread. Your place is kept.',
        ),
      if (marked || folder)
        item(ReadStateAction.unmarkRead, Icons.remove_done,
            folder ? 'Remove read marks' : 'Remove read mark'),
      const PopupMenuDivider(),
      if (!ignored)
        item(
          ReadStateAction.ignoreTracking,
          Icons.visibility_off_outlined,
          'Ignore archive tracking',
          folder
              ? "Leave everything in here out of the series' progress."
              : "Leave it out of the series' progress, like an annual you skip.",
        ),
      if (ignored || folder)
        item(ReadStateAction.trackAgain, Icons.visibility_outlined,
            folder ? 'Track archives again' : 'Track archive again'),
    ],
  );
  if (choice == null || !context.mounted) return;
  await applyReadStateAction(context, ref, media: media, action: choice);
}

/// Applies [action] to [media], then refreshes the badges.
Future<void> applyReadStateAction(
  BuildContext context,
  WidgetRef ref, {
  required Media media,
  required ReadStateAction action,
}) async {
  final messenger = ScaffoldMessenger.maybeOf(context);
  final folder = media.isFolder;
  try {
    final api = MediaApi(ref.read(apiClientProvider));
    final String done;
    switch (action) {
      case ReadStateAction.markRead:
        await api.markRead(media.id);
        done = folder ? 'Series marked as read.' : 'Marked as read.';
      case ReadStateAction.unmarkRead:
        await api.unmarkRead(media.id);
        done = folder ? 'Read marks removed.' : 'Read mark removed.';
      case ReadStateAction.ignoreTracking:
        await api.ignoreTracking(media.id);
        done = "Left out of the series' progress.";
      case ReadStateAction.trackAgain:
        await api.trackAgain(media.id);
        done = "Counted in the series' progress again.";
    }
    ref.invalidate(progressSummariesProvider);
    messenger?.showSnackBar(SnackBar(content: Text(done)));
  } catch (e) {
    final old = e is DioException && e.response?.statusCode == 404;
    messenger?.showSnackBar(SnackBar(
      content: Text(old
          ? 'Your server needs updating for this.'
          : "Couldn't make the change. Check your connection."),
    ));
  }
}

/// Opens the read-state menu on a right-click, around [child].
class ReadMarkMenuArea extends ConsumerWidget {
  final Media media;
  final ProgressSummary? summary;
  final Widget child;

  const ReadMarkMenuArea({
    super.key,
    required this.media,
    required this.summary,
    required this.child,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onSecondaryTapUp: (details) => showReadMarkMenu(
        context,
        ref,
        media: media,
        summary: summary,
        position: details.globalPosition,
      ),
      child: child,
    );
  }
}
