import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:clinicmanagementsystem/core/config/supabase_config.dart';

class RecoveryState {
  static final ValueNotifier<bool> pending = ValueNotifier(false);
  static String? linkError;
  static bool _started = false;

  /// Called from main() right after initSupabase(), with the URL captured at launch.
  static void start(Uri launchUri) {
    if (_started) return;
    _started = true;

    final full = launchUri.toString();
    debugPrint('RECOVERY launch url: $full');

    if (full.contains('error_code=') || full.contains('error=access_denied')) {
      linkError = 'This reset link is invalid or has expired. '
          'Please request a new one.';
    } else if (full.contains('type=recovery') ||
        launchUri.queryParameters.containsKey('code')) {
      pending.value = true;
    }

    supabaseClient.auth.onAuthStateChange.listen((data) {
      debugPrint('AUTH EVENT: ${data.event}');
      if (data.event == AuthChangeEvent.passwordRecovery) {
        pending.value = true;
      }
    });
  }
}