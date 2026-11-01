import 'package:clinicmanagementsystem/core/config/supabase_config.dart';

class TimeService {
  TimeService._();

  static Future<DateTime> serverNow() async {
    try {
      final dynamic res = await supabaseClient.rpc('server_now');
      return _toLocal(res) ?? DateTime.now();
    } catch (_) {
      return DateTime.now();
    }
  }

  static DateTime? _toLocal(dynamic v) {
    if (v is DateTime) return v.toLocal();
    if (v is String) {
      final DateTime? d = DateTime.tryParse(v);
      if (d != null) return d.toLocal();
    }
    return null;
  }
}
