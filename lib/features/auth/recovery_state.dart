import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:clinicmanagementsystem/core/config/supabase_config.dart';

class RecoveryState {
  static final ValueNotifier<bool> pending = ValueNotifier(false);
  static bool _started = false;

  /// Call once in main(), right after initSupabase().
  /// Pass the URI captured at launch, before any history rewriting.
  static void start(Uri launchUri) {
    if (_started) return;
    _started = true;

    if (launchUri.fragment.contains('type=recovery') ||
        launchUri.queryParameters.containsKey('code')) {
      pending.value = true;
    }

    supabaseClient.auth.onAuthStateChange.listen((data) {
      if (data.event == AuthChangeEvent.passwordRecovery) {
        pending.value = true;
      }
    });
  }
}