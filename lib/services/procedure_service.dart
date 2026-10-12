// ─────────────────────────────────────────────────────────────────────────────
//  procedure_service.dart
//  Supabase-backed CRUD for the procedures table (Procedure Performance).
//
//  Procedures carry patient SNAPSHOTS (patient_no, patient_name) frozen at
//  record time, a nullable visit link (visit_id), the performer as a
//  uuid, and a jsonb `details` bag of procedure-specific values.
//
//  Audit trail (created_by / created_at / updated_by / updated_at) is NOT
//  written by the client — the DB trigger `touch_audit_columns` maintains it.
//  RLS policies gate every read/write.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:clinicmanagementsystem/services/data_tracker.dart';
import 'package:clinicmanagementsystem/services/supabase_config.dart';

/// Simple procedure model matching the `public.procedures` table shape.
class ProcedureRecord {
  final int? id;
  final String patientId; // FK -> patients.id (uuid)
  final String patientNo; // snapshot
  final String patientName; // snapshot
  final String? visitId; // FK -> clinic_visits.visit_id (uuid, nullable)
  final String procedureName;
  final String category;
  final DateTime? performedAt;
  final String? performedBy; // useraccount.user_id (uuid)
  final String status; // Completed | Pending | Cancelled
  final Map<String, dynamic> details;
  final String findings;
  final String remarks;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? createdBy;
  final String? updatedBy;

  const ProcedureRecord({
    this.id,
    required this.patientId,
    required this.patientNo,
    required this.patientName,
    this.visitId,
    required this.procedureName,
    required this.category,
    this.performedAt,
    this.performedBy,
    this.status = 'Completed',
    this.details = const {},
    this.findings = '',
    this.remarks = '',
    this.createdAt,
    this.updatedAt,
    this.createdBy,
    this.updatedBy,
  });

  factory ProcedureRecord.fromSupabase(Map<String, dynamic> row) {
    return ProcedureRecord(
      id: row['id'] as int?,
      patientId: row['patient_id'] as String? ?? '',
      patientNo: row['patient_no'] as String? ?? '',
      patientName: row['patient_name'] as String? ?? '',
      visitId: row['visit_id'] as String?,
      procedureName: row['procedure_name'] as String? ?? '',
      category: row['category'] as String? ?? '',
      performedAt: _parseTs(row['performed_at']),
      performedBy: row['performed_by'] as String?,
      status: row['status'] as String? ?? 'Completed',
      details:
          (row['details'] as Map?)?.map((k, v) => MapEntry(k.toString(), v)) ??
              const {},
      findings: row['findings'] as String? ?? '',
      remarks: row['remarks'] as String? ?? '',
      createdAt: _parseTs(row['created_at']),
      updatedAt: _parseTs(row['updated_at']),
      createdBy: row['created_by'] as String?,
      updatedBy: row['updated_by'] as String?,
    );
  }

  static DateTime? _parseTs(Object? v) {
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }
}

class ProcedureService {
  ProcedureService._();

  /// Loads all procedures, newest first.
  static Future<List<ProcedureRecord>> fetchAll() async {
    final rows = await supabaseClient
        .from('procedures')
        .select()
        .order('performed_at', ascending: false);
    return rows
        .map<ProcedureRecord>(
            (r) => ProcedureRecord.fromSupabase(Map<String, dynamic>.from(r)))
        .toList();
  }

  /// Returns the auto-created Pending procedure linked to a visit, if any.
  /// Queries the database directly so completing a from-visit procedure can
  /// update the Pending row even before the in-memory list has finished
  /// loading (previously a race could insert a duplicate procedure).
  static Future<String?> fetchPendingByVisit(String? visitId) async {
    if (visitId == null) return null;
    final rows = await supabaseClient
        .from('procedures')
        .select('id')
        .eq('visit_id', visitId)
        .eq('status', 'Pending')
        .limit(1);
    if (rows.isEmpty) return null;
    return rows.first['id'] as String?;
  }

  /// Inserts a procedure. Returns the persisted row with server-assigned id.
  static Future<ProcedureRecord> create({
    required String patientId, // patients.id (uuid)
    required String patientNo,
    required String patientName,
    String? visitId,
    required String procedureName,
    required String category,
    required DateTime performedAt,
    String? performedBy, // useraccount.user_id (uuid)
    String status = 'Completed',
    Map<String, dynamic> details = const {},
    String findings = '',
    String remarks = '',
  }) async {
    final row = await supabaseClient
        .from('procedures')
        .insert({
          'patient_id': patientId,
          'patient_no': patientNo,
          'patient_name': patientName,
          'visit_id': visitId,
          'procedure_name': procedureName,
          'category': category,
          'performed_at': performedAt.toUtc().toIso8601String(),
          'performed_by': performedBy,
          'status': status,
          'details': details,
          'findings': findings.isEmpty ? null : findings,
          'remarks': remarks.isEmpty ? null : remarks,
        })
        .select()
        .single();
    DataTracker.bump();
    return ProcedureRecord.fromSupabase(Map<String, dynamic>.from(row));
  }

  /// Updates an existing procedure by id. updated_by / updated_at are set
  /// automatically by the DB trigger.
  static Future<void> update(
    int id, {
    String? patientNo,
    String? patientName,
    int? visitId,
    required String procedureName,
    required String category,
    required DateTime performedAt,
    String? performedBy,
    String status = 'Completed',
    Map<String, dynamic> details = const {},
    String findings = '',
    String remarks = '',
  }) async {
    await supabaseClient.from('procedures').update({
      if (patientNo != null) 'patient_no': patientNo,
      if (patientName != null) 'patient_name': patientName,
      'visit_id': visitId,
      'procedure_name': procedureName,
      'category': category,
      'performed_at': performedAt.toUtc().toIso8601String(),
      'performed_by': performedBy,
      'status': status,
      'details': details,
      'findings': findings.isEmpty ? null : findings,
      'remarks': remarks.isEmpty ? null : remarks,
    }).eq('id', id);
    DataTracker.bump();
  }

  /// Removes a procedure by id. (Not currently exposed in the UI, but kept
  /// for completeness / future trash integration.)
  static Future<void> delete(int id) async {
    await supabaseClient.from('procedures').delete().eq('id', id);
    DataTracker.bump();
  }
}
