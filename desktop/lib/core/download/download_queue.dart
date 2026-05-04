import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Runs up to [maxConcurrent] download tasks simultaneously.
///
/// Additional tasks are held in a FIFO pending list and start as slots free
/// up. A task failing never blocks subsequent tasks — errors propagate only
/// to the individual caller of [enqueue].
class DownloadQueue {
  final int _max;
  int _active = 0;
  final _pending = <void Function()>[];

  DownloadQueue({int maxConcurrent = 3}) : _max = maxConcurrent;

  Future<T> enqueue<T>(Future<T> Function() task) {
    final completer = Completer<T>();

    // Wrap the task so slot bookkeeping happens automatically on finish.
    _pending.add(() {
      _active++;
      task().then(
        (v) {
          completer.complete(v);
          _done();
        },
        onError: (Object e, StackTrace st) {
          completer.completeError(e, st);
          _done();
        },
      );
    });

    _drain();
    return completer.future;
  }

  /// Starts as many pending tasks as there are free slots.
  void _drain() {
    while (_active < _max && _pending.isNotEmpty) {
      _pending.removeAt(0)();
    }
  }

  /// Called when a running task finishes (success or error).
  void _done() {
    _active--;
    _drain();
  }
}

final downloadQueueProvider = Provider<DownloadQueue>(
  (_) => DownloadQueue(),
);
