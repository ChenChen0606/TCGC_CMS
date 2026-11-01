import 'package:clinicmanagementsystem/core/services/data_tracker.dart';
import 'package:clinicmanagementsystem/core/config/supabase_config.dart';

class ProcedureRecord {
  final int? id;
  final String patientId;
  final String patientNo;
  final String patientName;
  final String? visitId;
  final String procedureName;
  final String category;
  final DateTime? performedAt;
  final String? performedBy;
  final String status;
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

  static Future<ProcedureRecord> create({
    required String patientId,
    required String patientNo,
    required String patientName,
    String? visitId,
    required String procedureName,
    required String category,
    required DateTime performedAt,
    String? performedBy,
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

  static Future<void> delete(int id) async {
    await supabaseClient.from('procedures').delete().eq('id', id);
    DataTracker.bump();
  }
}
