// ─────────────────────────────────────────────────────────────────────────────
//  supabase_config.dart
//  Central Supabase configuration for the TCGC Clinic Management System.
//
//  Credentials are injected at build/run time via `--dart-define` so nothing
//  secret is ever committed to the repo:
//
//    flutter run --dart-define=SUPABASE_URL=https://xxxx.supabase.co \
//                --dart-define=SUPABASE_ANON_KEY=your-publishable-anon-key
//
//  The anon/publishable key is safe to ship in a client app because Row Level
//  Security (RLS) on the Supabase project controls what it can actually access.
//  The secret `service_role` key MUST never be used here.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Default project URL + publishable anon key so the app connects even when
/// run with a plain `flutter run` (no --dart-define flags). The anon key is a
/// PUBLISHABLE key — safe to ship in the client; Row Level Security on the
/// server is what actually controls what it can access.
const String _defaultSupabaseUrl = 'https://bwhrosebljcdgykreyyp.supabase.co';
const String _defaultSupabaseAnonKey =
    'sb_publishable_abP2YIYcKdimif792RwkUQ_o67GA8jJ';

/// Compile-time overrides (via `--dart-define`): empty when not supplied.
const String _envSupabaseUrl = String.fromEnvironment('SUPABASE_URL');
const String _envSupabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

/// Supabase project URL. `--dart-define` wins when supplied; otherwise the
/// bundled default above is used so the app always has a backend to talk to.
String get supabaseUrl =>
    _envSupabaseUrl.isNotEmpty ? _envSupabaseUrl : _defaultSupabaseUrl;

/// Supabase publishable anon key (see `supabaseUrl` for precedence rules).
String get supabaseAnonKey => _envSupabaseAnonKey.isNotEmpty
    ? _envSupabaseAnonKey
    : _defaultSupabaseAnonKey;

/// `true` when usable credentials are available. With the bundled default this
/// is always `true` unless an override explicitly blanks a value.
bool get isSupabaseConfigured =>
    supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

/// Initializes the global Supabase client. Safe to call only once, before
/// `runApp`. Throws `StateError` if called twice.
Future<void> initSupabase() async {
  if (!isSupabaseConfigured) {
    debugPrint('[Supabase] Not configured — '
        'pass SUPABASE_URL and SUPABASE_ANON_KEY via --dart-define.');
    return;
  }

  await Supabase.initialize(
    url: supabaseUrl,
    publishableKey: supabaseAnonKey,
  );

  debugPrint('[Supabase] Initialized.');
}

/// Convenience accessor for any screen/service that needs the shared client
/// once real tables exist: `SupabaseClient client = supabaseClient`.
SupabaseClient get supabaseClient => Supabase.instance.client;

/// Whether there is a signed-in user, i.e. whether a read will carry that user's
/// JWT and Row Level Security will let any rows through.
///
/// The reason this exists: with RLS on, a read made with no session is not an
/// error — it is `HTTP 200` with an empty body — which the client cannot tell
/// apart from a genuinely empty table. Code that reads before sign-in and then
/// caches the answer therefore concludes the school has no terms, no institutes
/// and no positions, and keeps saying so for the rest of the session. Anything
/// that reads the database has to ask this first.
///
/// False before sign-in, false after sign-out, and false when Supabase was never
/// initialised — never throws, so it is safe on a start-up path.
bool get hasSignedInUser {
  try {
    return supabaseClient.auth.currentUser != null;
  } catch (_) {
    // Supabase.initialize was skipped (no credentials): nothing can be read.
    return false;
  }
}
