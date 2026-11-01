import 'package:flutter_test/flutter_test.dart';
import 'package:rekindle/core/models/progress_summary.dart';
import 'package:rekindle/core/models/reading_progress.dart';
import 'package:rekindle/providers/progress_summary_provider.dart';

ReadingProgress _local({int page = 0, bool completed = false}) =>
    ReadingProgress(userId: '', mediaId: 'm', currentPage: page, isCompleted: completed);

void main() {
  group('ProgressSummary.fromJson', () {
    test('reads every field', () {
      final s = ProgressSummary.fromJson({
        'mediaId': 'a',
        'progress': 0.5,
        'isCompleted': false,
        'newCount': 3,
        'isNew': true,
      });

      expect(s.mediaId, 'a');
      expect(s.progress, 0.5);
      expect(s.isCompleted, isFalse);
      expect(s.newCount, 3);
      expect(s.isNew, isTrue);
      expect(s.percent, 50);
    });

    test('accepts integer progress and clamps out-of-range values', () {
      expect(ProgressSummary.fromJson({'mediaId': 'a', 'progress': 1}).progress, 1.0);
      expect(ProgressSummary.fromJson({'mediaId': 'a', 'progress': 1.7}).progress, 1.0);
      expect(ProgressSummary.fromJson({'mediaId': 'a', 'progress': -0.2}).progress, 0.0);
    });

    test('defaults missing optional fields', () {
      final s = ProgressSummary.fromJson({'mediaId': 'a'});

      expect(s.progress, 0);
      expect(s.isCompleted, isFalse);
      expect(s.newCount, 0);
      expect(s.isNew, isFalse);
      expect(s.isStarted, isFalse);
    });
  });

  group('ProgressSummary.fromLocal', () {
    test('uses the page count when known', () {
      expect(ProgressSummary.fromLocal(_local(page: 10), 40).progress, 0.25);
    });

    test('completed is full regardless of page count', () {
      final s = ProgressSummary.fromLocal(_local(page: 2, completed: true), null);

      expect(s.progress, 1);
      expect(s.isCompleted, isTrue);
    });

    test('unknown page count gives no fraction', () {
      final s = ProgressSummary.fromLocal(_local(page: 10), null);

      expect(s.progress, 0);
      expect(s.isStarted, isFalse);
    });
  });

  group('summaryChunkKey', () {
    final ids = [for (var i = 0; i < 30; i++) 'id$i'];

    test('items in the same chunk share a key', () {
      expect(summaryChunkKey(ids, 0, 24), summaryChunkKey(ids, 23, 24));
      expect(summaryChunkKey(ids, 0, 24).split(','), ids.sublist(0, 24));
    });

    test('the last chunk is short', () {
      expect(summaryChunkKey(ids, 25, 24).split(','), ids.sublist(24));
    });

    test('a growing list keeps earlier keys stable', () {
      final grown = [...ids, for (var i = 30; i < 48; i++) 'id$i'];

      expect(summaryChunkKey(grown, 5, 24), summaryChunkKey(ids, 5, 24));
    });
  });
}
