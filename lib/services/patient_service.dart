// ─────────────────────────────────────────────────────────────────────────────
//  patient_service.dart
//  Supabase-backed CRUD for patient records.
//
//  Audit trail (created_by / created_at / updated_by / updated_at) is NOT
//  written by the client — the database triggers in clinic_schema.sql
//  (`touch_audit_columns`) maintain it automatically from the authenticated
//  session (auth.uid()). RLS policies gate every read/write.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:clinicmanagementsystem/screen/patient_data.dart';
import 'package:clinicmanagementsystem/services/data_tracker.dart';
import 'package:clinicmanagementsystem/services/supabase_config.dart';

class PatientService {
  PatientService._();

  /// Loads all non-archived patients, newest first.
  static Future<List<Patient>> fetchAll() async {
    final rows = await supabaseClient
        .from('patients')
        .select()
        .eq('is_archived', false)
        .order('created_at', ascending: false);
    return rows
        .map<Patient>((r) => Patient.fromSupabase(Map<String, dynamic>.from(r)))
        .toList();
  }

  /// Looks up an existing patient by (category, patient_no) — the pair the
  /// `unique (category, patient_no)` constraint protects. Returns null when
  /// the record does not exist yet.
  static Future<Patient?> fetchByKey(String category, String patientNo) async {
    final key = patientNo.trim();
    if (key.isEmpty) return null;
    final rows = await supabaseClient
        .from('patients')
        .select()
        .eq('category', category)
        .eq('patient_no', key)
        .limit(1);
    if (rows.isEmpty) return null;
    return Patient.fromSupabase(Map<String, dynamic>.from(rows.first));
  }

  /// Computes the next available Faculty/Staff ID (F### / S###) straight from
  /// the database, so the auto-generated ID can never collide with a row that
  /// was saved on another page but isn't in this screen's in-memory copy yet.
  static Future<String> nextIdFor(String category) async {
    final prefix = category == 'Staff' ? 'S' : 'F';
    final rows = await supabaseClient
        .from('patients')
        .select('patient_no')
        .eq('category', category);
    int max = 0;
    for (final r in rows) {
      final id = (r['patient_no'] as String? ?? '').trim();
      if (!id.startsWith(prefix)) continue;
      final numPart = id.substring(prefix.length);
      if (numPart.isEmpty || !RegExp(r'^\d+$').hasMatch(numPart)) continue;
      final n = int.tryParse(numPart);
      if (n != null && n > max) max = n;
    }
    final next = max + 1;
    return '$prefix${next.toString().padLeft(3, '0')}';
  }

  /// Seeds the demo patients into an empty `patients` table so the app (and
  /// the visit form's patient search) is usable out of the box. No-op when any
  /// patients already exist — mirrors `MedicineService.seedIfEmpty`.
  static Future<void> seedIfEmpty() async {
    final rows = await supabaseClient.from('patients').select('id').limit(1);
    if (rows.isNotEmpty) return;

    await supabaseClient.from('patients').insert([
      {
        'patient_no': '234567',
        'category': 'Student',
        'last_name': 'Delacruz',
        'first_name': 'Cresa',
        'middle_initial': 'S',
        'institute': 'ICS',
        'year_level': '2nd Year',
        'position': null,
        'office_department': null,
        'contact': '09171234567',
        'emergency_name': 'Maria Delacruz',
        'emergency_contact': '09179876543',
      },
      {
        'patient_no': '234889',
        'category': 'Student',
        'last_name': 'Doe',
        'first_name': 'John',
        'middle_initial': 'A',
        'institute': 'ITE',
        'year_level': '3rd Year',
        'position': null,
        'office_department': null,
        'contact': '09201234567',
        'emergency_name': 'Anna Doe',
        'emergency_contact': '09209876543',
      },
      {
        'patient_no': 'F001',
        'category': 'Faculty',
        'last_name': 'Smith',
        'first_name': 'Jane',
        'middle_initial': '',
        'institute': null,
        'year_level': null,
        'position': 'Dean',
        'office_department': 'IAS',
        'contact': '09151234567',
        'emergency_name': '',
        'emergency_contact': '',
      },
      {
        'patient_no': 'F002',
        'category': 'Faculty',
        'last_name': 'Garcia',
        'first_name': 'Ramon',
        'middle_initial': '',
        'institute': null,
        'year_level': null,
        'position': 'Instructor',
        'office_department': 'ICS',
        'contact': '09161234567',
        'emergency_name': '',
        'emergency_contact': '',
      },
      {
        'patient_no': 'S001',
        'category': 'Staff',
        'last_name': 'Lee',
        'first_name': 'Mark',
        'middle_initial': '',
        'institute': null,
        'year_level': null,
        'position': 'Security Guard',
        'office_department': 'Registrar',
        'contact': '09181234567',
        'emergency_name': '',
        'emergency_contact': '',
      },
      {
        'patient_no': 'S002',
        'category': 'Staff',
        'last_name': 'Navarro',
        'first_name': 'Rosa',
        'middle_initial': '',
        'institute': null,
        'year_level': null,
        'position': 'Librarian',
        'office_department': 'Library',
        'contact': '09191234567',
        'emergency_name': '',
        'emergency_contact': '',
      },
    ]);
  }

  /// Inserts a patient and returns the persisted row (which now carries the
  /// server-assigned uuid, created_by and created_at).
  static Future<Patient> create(Patient p) async {
    final row = await supabaseClient
        .from('patients')
        .insert(p.toSupabase())
        .select()
        .single();
    DataTracker.bump();
    return Patient.fromSupabase(Map<String, dynamic>.from(row));
  }

  /// Updates an existing patient by its uuid. updated_by / updated_at are
  /// set automatically by the DB trigger.
  static Future<void> update(Patient p) async {
    if (p.uuid == null) {
      throw StateError('Cannot update a patient without a Supabase id.');
    }
    await supabaseClient
        .from('patients')
        .update(p.toSupabase())
        .eq('id', p.uuid!);
    DataTracker.bump();
  }

  /// Hard-deletes a patient by its uuid. (Matches the existing UI delete.)
  /// Future option: soft-delete via is_archived + archive_log instead.
  static Future<void> delete(Patient p) async {
    if (p.uuid == null) {
      throw StateError('Cannot delete a patient without a Supabase id.');
    }
    await supabaseClient.from('patients').delete().eq('id', p.uuid!);
    DataTracker.bump();
  }

  /// Maps useraccount.user_id -> "First Last" for display in the audit trail.
  ///
  /// Uses the table's abbreviated name columns (fn / ln). Falls back to the
  /// username for rows whose name is blank.
  static Future<Map<String, String>> fetchUserNames() async {
    try {
      final rows = await supabaseClient
          .from('useraccount')
          .select('user_id, username, fn, ln');
      return {
        for (final r in rows)
          if (r['user_id'] != null) r['user_id'] as String: _nameOf(r),
      };
    } catch (_) {
      return const {};
    }
  }

  /// "First Last" when both parts exist, otherwise the username.
  static String _nameOf(Map<String, dynamic> row) {
    final name = [
      (row['fn'] as String? ?? '').trim(),
      (row['ln'] as String? ?? '').trim(),
    ].where((s) => s.isNotEmpty).join(' ');
    return name.isNotEmpty ? name : (row['username'] as String? ?? '').trim();
  }
}
