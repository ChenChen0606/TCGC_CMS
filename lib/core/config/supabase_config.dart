import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

const String _defaultSupabaseUrl = '';
const String _defaultSupabaseAnonKey =
    '';

const String _envSupabaseUrl = String.fromEnvironment('SUPABASE_URL');
const String _envSupabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

String get supabaseUrl =>
    _envSupabaseUrl.isNotEmpty ? _envSupabaseUrl : _defaultSupabaseUrl;

String get supabaseAnonKey => _envSupabaseAnonKey.isNotEmpty
    ? _envSupabaseAnonKey
    : _defaultSupabaseAnonKey;

bool get isSupabaseConfigured =>
    supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

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

SupabaseClient get supabaseClient => Supabase.instance.client;

bool get hasSignedInUser {
  try {
    return supabaseClient.auth.currentUser != null;
  } catch (_) {
    return false;
  }
}
