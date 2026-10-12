// ─────────────────────────────────────────────────────────────────────────────
//  time_service.dart
//  Single source of truth for "the clinic time".
//
//  Every terminal's local clock can drift, so the app never treats its own
//  DateTime.now() as authoritative. Instead it asks the database server for
//  its current timestamp (RPC `server_now()`, see migration 2026-09-15). The
//  dashboard clock, report periods, visit-intake stamps and printed "Generated"
//  timestamps all resolve through this service so that every PC in the clinic
//  shows and records exactly the same time.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:clinicmanagementsystem/services/supabase_config.dart';

class TimeService {
  TimeService._();

  /// The clinic's official current time — the database server's clock,
  /// converted to local time for display. Falls back to the device clock
  /// only when the server can't be reached (e.g. offline), so behaviour is
  /// never blocked on the network.
  static Future<DateTime> serverNow() async {
    try {
      final dynamic res = await supabaseClient.rpc('server_now');
      return _toLocal(res) ?? DateTime.now();
    } catch (_) {
      return DateTime.now();
    }
  }

  /// Offset between the server's clock and this device's clock. Add this to
  /// `DateTime.now()` to keep a live display ticking on the server clock
  /// without re-querying the database every second/refresh.
  static Future<Duration> serverOffset() async {
    final DateTime server = await serverNow();
    return server.difference(DateTime.now());
  }

  /// Best-effort parse of a PostgREST RPC result into a local DateTime.
  /// Depending on content-type the response can arrive as a `DateTime`
  /// (supabase parses typed JSON) or as an ISO-8601 string.
  static DateTime? _toLocal(dynamic v) {
    if (v is DateTime) return v.toLocal();
    if (v is String) {
      final DateTime? d = DateTime.tryParse(v);
      if (d != null) return d.toLocal();
    }
    return null;
  }
}
