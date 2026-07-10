import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/update/update_service.dart';

/// Desktop GitHub-release update checker. Used by the Settings screen's manual
/// "Check for updates" action.
final updateServiceProvider = Provider<UpdateService>((ref) => UpdateService());
