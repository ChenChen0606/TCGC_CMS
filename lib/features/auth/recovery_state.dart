import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:clinicmanagementsystem/core/config/supabase_config.dart';

class RecoveryState {
  static final ValueNotifier<bool> pending = ValueNotifier(false);
  static String? linkError;
  static bool _started = false;

  /// Call right AFTER initSupabase(), passing the URI captured
  /// at the very top of main() (before Supabase rewrites the URL).
  static void start(Uri launchUri) {
    if (_started) return;
    _started = true;

    _inspectLaunchUri(launchUri);

    supabaseClient.auth.onAuthStateChange.listen((data) {
      debugPrint('AUTH EVENT: ${data.event}');
      if (data.event == AuthChangeEvent.passwordRecovery) {
        pending.value = true;
      }
    });
  }

  static void _inspectLaunchUri(Uri uri) {
    final full = uri.toString();
    debugPrint('RECOVERY launch url: $full');

    final hasError = full.contains('error_code=') ||
        full.contains('error=access_denied') ||
        full.contains('otp_expired');
    final isRecovery =
        full.contains('type=recovery') || RegExp(r'[?&#]code=').hasMatch(full);

    if (hasError) {
      linkError = 'This reset link is invalid or has expired. '
          'Please request a new one.';
    } else if (isRecovery) {
      pending.value = true;
    }
  }
}