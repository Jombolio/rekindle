import 'package:dio/dio.dart';
import 'package:flutter/material.dart';

import '../../core/api/admin_api.dart';

/// The intervals offered, in hours, and how they read. 0 is off.
const scanIntervals = <int, String>{
  0: 'Off',
  1: 'Every hour',
  6: 'Every 6 hours',
  12: 'Every 12 hours',
  24: 'Daily',
  168: 'Weekly',
};

String scanIntervalLabel(int hours) =>
    scanIntervals[hours] ?? 'Every $hours hours';

/// When a scheduled scan ran or will run, as a short local date and time:
/// "Today 18:00", "Tomorrow 06:00", or "Fri 13 Nov 09:30".
String scanTimeLabel(DateTime when, {DateTime? now}) {
  final today = DateUtils.dateOnly(now ?? DateTime.now());
  final day = DateUtils.dateOnly(when);
  final time =
      '${when.hour.toString().padLeft(2, '0')}:${when.minute.toString().padLeft(2, '0')}';
  final diff = day.difference(today).inDays;
  if (diff == 0) return 'Today $time';
  if (diff == 1) return 'Tomorrow $time';
  if (diff == -1) return 'Yesterday $time';
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  return '${days[when.weekday - 1]} ${when.day} ${months[when.month - 1]} $time';
}

/// The Admin Panel's scheduled scans: each library, how often it's scanned on
/// its own, and when that last and next happens. Admins only, like the rest of
/// the panel.
class ScanSchedulesTab extends StatefulWidget {
  final AdminApi api;
  const ScanSchedulesTab({super.key, required this.api});

  @override
  State<ScanSchedulesTab> createState() => _ScanSchedulesTabState();
}

class _ScanSchedulesTabState extends State<ScanSchedulesTab> {
  late Future<List<ScanScheduleInfo>> _schedules =
      widget.api.getScanSchedules();
  final Set<String> _saving = {};

  void _reload() => setState(() => _schedules = widget.api.getScanSchedules());

  Future<void> _set(ScanScheduleInfo library, int hours) async {
    setState(() => _saving.add(library.libraryId));
    try {
      await widget.api.setScanSchedule(library.libraryId, hours);
      _reload();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text("Couldn't change the schedule: ${_describe(e)}")),
      );
    } finally {
      if (mounted) setState(() => _saving.remove(library.libraryId));
    }
  }

  static String _describe(Object e) {
    if (e is DioException) {
      final data = e.response?.data;
      if (data is Map && data['error'] is String) {
        return data['error'] as String;
      }
      return e.message ?? 'the server didn\'t answer';
    }
    return e.toString();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FutureBuilder<List<ScanScheduleInfo>>(
      future: _schedules,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final error = snapshot.error;
        if (error != null) {
          final old =
              error is DioException && error.response?.statusCode == 404;
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    old
                        ? 'Your server needs updating to schedule scans.'
                        : "Scan schedules couldn't be loaded: ${_describe(error)}",
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  if (!old)
                    TextButton(
                        onPressed: _reload, child: const Text('Try again')),
                ],
              ),
            ),
          );
        }
        final libraries = snapshot.data!;
        return ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('Scheduled scans', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(
              'Scan libraries on their own, to pick up new and removed files without '
              'anyone pressing Scan. Scheduled scans run one at a time, and wait for '
              'a scan already running.',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            if (libraries.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 24),
                child: Text('There are no libraries yet.'),
              ),
            for (final library in libraries)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.event_repeat_outlined),
                  title: Text(library.libraryName),
                  subtitle: Text(_when(library)),
                  trailing: _saving.contains(library.libraryId)
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : DropdownButton<int>(
                          value: library.intervalHours,
                          underline: const SizedBox(),
                          items: [
                            for (final hours in {
                              ...scanIntervals.keys,
                              library.intervalHours,
                            })
                              DropdownMenuItem(
                                value: hours,
                                child: Text(scanIntervalLabel(hours)),
                              ),
                          ],
                          onChanged: (hours) {
                            if (hours != null &&
                                hours != library.intervalHours) {
                              _set(library, hours);
                            }
                          },
                        ),
                ),
              ),
          ],
        );
      },
    );
  }

  static String _when(ScanScheduleInfo library) {
    if (library.intervalHours == 0) {
      return 'Only scanned when someone presses Scan';
    }
    final parts = <String>[
      if (library.nextRunAt != null)
        'Next: ${scanTimeLabel(library.nextRunAt!)}',
      library.lastRunAt != null
          ? 'Last: ${scanTimeLabel(library.lastRunAt!)}'
          : 'Not run yet',
    ];
    return parts.join('  ·  ');
  }
}
