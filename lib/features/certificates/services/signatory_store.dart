import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:clinicmanagementsystem/features/account/services/account_service.dart';
import 'package:clinicmanagementsystem/core/config/supabase_config.dart';

class SignatoryEntry {
  const SignatoryEntry({
    required this.name,
    this.changedAt = '',
    this.changedBy = '',
  });

  final String name;

  final String changedAt;

  final String changedBy;

  Map<String, dynamic> toJson() => {
        'name': name,
        if (changedAt.isNotEmpty) 'changed_at': changedAt,
        if (changedBy.isNotEmpty) 'changed_by': changedBy,
      };

  factory SignatoryEntry.fromJson(Map<String, dynamic> j) => SignatoryEntry(
        name: '${j['name'] ?? ''}'.trim(),
        changedAt: '${j['changed_at'] ?? ''}',
        changedBy: '${j['changed_by'] ?? ''}',
      );
}

class SignatorySnapshot {
  const SignatorySnapshot({required this.name, this.history = const []});

  final String name;
  final List<SignatoryEntry> history;
}

class SignatoryStore {
  SignatoryStore._();

  static const String defaultName = 'Francislee N. Famacion';

  static const String defaultRole = 'Head, Medical and Dental Clinic';

  static const String _nameKey = 'certificate_signatory_name';
  static const String _historyKey = 'certificate_signatory_history';

  static const int _maxHistory = 25;

  static SignatorySnapshot read() {
    final meta = AccountService.metadataOf(supabaseClient.auth.currentUser);
    final rawName = meta[_nameKey];
    final name = rawName is String && rawName.trim().isNotEmpty
        ? rawName.trim()
        : defaultName;

    final history = <SignatoryEntry>[];
    final raw = meta[_historyKey];
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) {
          final entry = SignatoryEntry.fromJson(Map<String, dynamic>.from(e));
          if (entry.name.isNotEmpty) history.add(entry);
        } else if (e is String && e.trim().isNotEmpty) {
          history.add(SignatoryEntry(name: e.trim()));
        }
      }
    }
    return SignatorySnapshot(name: name, history: history);
  }

  static Future<bool> save(String name, {String changedBy = ''}) async {
    final user = supabaseClient.auth.currentUser;
    if (user == null) return false;

    final clean = name.trim();
    if (clean.isEmpty) return false;

    final meta = Map<String, dynamic>.from(AccountService.metadataOf(user));
    final before = meta[_nameKey];
    final current = before is String ? before.trim() : '';
    if (clean == current) return true;

    final history = <SignatoryEntry>[...read().history];
    if (current.isNotEmpty) {
      history.insert(
        0,
        SignatoryEntry(
          name: current,
          changedAt: DateTime.now().toIso8601String(),
          changedBy: changedBy,
        ),
      );
    }
    while (history.length > _maxHistory) {
      history.removeLast();
    }

    meta[_nameKey] = clean;
    meta[_historyKey] = [for (final h in history) h.toJson()];

    try {
      await supabaseClient.auth.updateUser(UserAttributes(data: meta));
      return true;
    } catch (_) {
      return false;
    }
  }
}
