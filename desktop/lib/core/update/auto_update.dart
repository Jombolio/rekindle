import 'update_service.dart';

/// How often the startup check may run.
const autoCheckInterval = Duration(hours: 24);

/// Whether the startup check should run now: it's switched on, and the last
/// one was at least [autoCheckInterval] ago (or never ran).
bool shouldAutoCheck({
  required bool enabled,
  required DateTime? lastCheck,
  required DateTime now,
}) {
  if (!enabled) return false;
  if (lastCheck == null) return true;
  // A clock set backwards shouldn't block checks until it catches up.
  if (lastCheck.isAfter(now)) return true;
  return now.difference(lastCheck) >= autoCheckInterval;
}

/// Whether the startup check should offer [result]'s release: an update is
/// available and the user hasn't chosen to skip that version. A manual check
/// offers it regardless.
bool shouldOfferAutomatically(UpdateCheckResult result, String? skippedVersion) =>
    result.status == UpdateStatus.updateAvailable &&
    result.release?.version != null &&
    result.release!.version != skippedVersion;
