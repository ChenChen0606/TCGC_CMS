import 'package:intl/intl.dart';

import 'package:clinicmanagementsystem/features/patients/models/patient_directory.dart'
    as terms;
import 'package:clinicmanagementsystem/features/patients/models/patient_directory.dart'
    show academicTermLabel;
import 'package:clinicmanagementsystem/core/services/data_tracker.dart';

import 'package:clinicmanagementsystem/features/patients/models/individual_record_data.dart'
    show canonicalCategory;
import 'package:clinicmanagementsystem/features/patients/services/individual_record_service.dart';
import 'package:clinicmanagementsystem/core/services/reference_data_service.dart';
import 'package:clinicmanagementsystem/core/config/supabase_config.dart';
import 'package:clinicmanagementsystem/features/visits/services/visit_service.dart';

class ArchivedPatient {
  final String id;
  final String name;
  final String department;
  final String position;
  final String category;
  final String archivedDate;
  final String reason;
  final String archivedBy;
  final String uuid;

  final String academicYear;
  final String semester;

  const ArchivedPatient({
    required this.id,
    required this.name,
    required this.department,
    required this.position,
    required this.category,
    required this.archivedDate,
    required this.reason,
    required this.archivedBy,
    required this.uuid,
    this.academicYear = '',
    this.semester = '',
  });

  String get termLabel => academicTermLabel(academicYear, semester);

  bool get isCurrentTerm => terms.isCurrentTerm(academicYear, semester);
}

class ArchivedMedicine {
  final int id;
  final String name;
  final int lastStock;

  const ArchivedMedicine({
    required this.id,
    required this.name,
    required this.lastStock,
  });
}

class ArchivedRecord {
  final int logId;
  final String patient;
  final String type;
  final String complaint;
  final String medicine;
  final int qty;
  final String visitDate;
  final String status;
  final String category;
  final Map<String, dynamic> snapshot;

  const ArchivedRecord({
    required this.logId,
    required this.patient,
    required this.type,
    required this.complaint,
    required this.medicine,
    required this.qty,
    required this.visitDate,
    required this.status,
    required this.category,
    this.snapshot = const {},
  });
}

class ArchiveService {
  ArchiveService._();

  static const String _lastEnrolmentSelect = '''
    person_id,
    academic_period_id,
    status,
    institute_id,
    program_id,
    year_level,
    department_office_id,
    position_id,
    created_at''';

  static String _ts(DateTime? t) {
    if (t == null) return '—';
    return DateFormat('yyyy-MM-dd').format(t.toLocal());
  }

  static String _who(String? id, Map<String, String> userNames) {
    if (id == null || id.isEmpty || id == '—') return '—';
    final n = userNames[id];
    return (n == null || n.isEmpty) ? id.substring(0, 8) : n;
  }

  static Future<List<ArchivedPatient>> fetchArchivedPatients({
    String? year,
    String? semester,
    String? category,
  }) async {
    Map<String, String> userNames = const {};
    try {
      userNames = await _fetchUserNames();
    } catch (_) {}

    final archivedIds = await supabaseClient
        .from('individual_academic_records')
        .select('person_id')
        .eq('status', 'Archived');

    final activeIds = await supabaseClient
        .from('individual_academic_records')
        .select('person_id')
        .eq('status', 'Active');

    final stillActive = <String>{
      for (final r in activeIds) '${r['person_id']}',
    };

    final ids = <String>{
      for (final r in archivedIds) '${r['person_id']}',
    }..removeWhere(stillActive.contains);

    if (ids.isEmpty) return const [];

    final people = await supabaseClient
        .from('individual_records')
        .select()
        .inFilter('person_id', ids.toList());

    if (people.isEmpty) return const [];

    final enrolments = await supabaseClient
        .from('individual_academic_records')
        .select(
            '$_lastEnrolmentSelect, academic_period:academic_periods(acad_year, semester)')
        .inFilter('person_id', people.map((p) => p['person_id']).toList())
        .order('created_at', ascending: false);

    final latestByPerson = <String, Map<String, dynamic>>{};
    for (final row in enrolments) {
      final m = Map<String, dynamic>.from(row);
      final personId = '${m['person_id'] ?? ''}';
      if (personId.isEmpty || latestByPerson.containsKey(personId)) continue;
      latestByPerson[personId] = m;
    }

    final ay = year?.trim() ?? '';
    final sem = semester?.trim() ?? '';
    final cat = category?.trim() ?? '';

    final out = <ArchivedPatient>[];
    for (final row in people) {
      final m = Map<String, dynamic>.from(row);

      final category = canonicalCategory(m['person_type']);
      if (cat.isNotEmpty && category != canonicalCategory(cat)) continue;

      final uuid = m['person_id'] as String? ?? '';
      final academic = latestByPerson[uuid] ?? const <String, dynamic>{};
      final period = academic['academic_period'] as Map<String, dynamic>?;
      final academicYear = (period?['acad_year'] as String?) ?? '';
      final term = (period?['semester'] as String?) ?? '';
      if (ay.isNotEmpty && academicYear != ay) continue;
      if (sem.isNotEmpty && term != sem) continue;

      final isStudent = category == 'Student';
      final first = (m['fn'] as String? ?? '').trim();
      final middle = (m['mn'] as String? ?? '').trim();
      final last = (m['ln'] as String? ?? '').trim();
      final name = [first, middle, last].where((e) => e.isNotEmpty).join(' ');

      out.add(ArchivedPatient(
        id: uuid,
        name: name.isEmpty ? 'Unnamed record' : name,
        department: isStudent
            ? ReferenceCatalog.instituteNameOf(
                academic['institute_id'] as String?)
            : ReferenceCatalog.departmentNameOf(
                academic['department_office_id'] as String?),
        position: isStudent
            ? ((academic['year_level'] as String?) ?? '')
            : ReferenceCatalog.positionNameOf(
                academic['position_id'] as String?),
        category: category,
        archivedDate: _ts(_parseTs(m['created_at'])),
        reason: _lastReason(academic),
        archivedBy: _who(m['created_by'] as String?, userNames),
        uuid: uuid,
        academicYear: academicYear,
        semester: term,
      ));
    }

    out.sort((a, b) {
      final byYear = b.academicYear.compareTo(a.academicYear);
      if (byYear != 0) return byYear;
      final byTerm = b.semester.compareTo(a.semester);
      if (byTerm != 0) return byTerm;
      return a.name.compareTo(b.name);
    });
    return out;
  }

  static String _lastReason(Map<String, dynamic> academic) {
    final status = (academic['status'] as String?)?.trim();
    if (status != null && status.isNotEmpty) return status;
    return 'Archived';
  }

  static Future<List<ArchivedMedicine>> fetchArchivedMedicines() async {
    final rows = await supabaseClient
        .from('medicines')
        .select()
        .eq('is_archived', true)
        .order('name');
    return rows.map((r) {
      final m = Map<String, dynamic>.from(r);
      return ArchivedMedicine(
        id: m['id'] as int? ?? 0,
        name: m['name'] as String? ?? '',
        lastStock: m['stock'] as int? ?? 0,
      );
    }).toList();
  }

  static Future<List<ArchivedRecord>> fetchArchivedRecords() async {
    try {
      final rows = await supabaseClient
          .from('archive_log')
          .select()
          .eq('entity_type', 'visit')
          .order('archived_at', ascending: false);
      return rows.map((r) {
        final m = Map<String, dynamic>.from(r);
        final snap = (m['snapshot'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
        return ArchivedRecord(
          logId: m['id'] as int? ?? 0,
          patient: snap['patient_name'] as String? ?? '—',
          type: snap['category'] as String? ?? '—',
          complaint: snap['complaint'] as String? ?? '—',
          medicine: snap['medicine_name'] as String? ?? 'None',
          qty: _asInt(snap['qty']),
          visitDate: DateFormat('yyyy-MM-dd').format(
              _parseTs(snap['visit_date']) ??
                  (_parseTs(m['archived_at']) ?? DateTime.now())),
          status: m['status'] as String? ?? 'Archived',
          category: snap['category'] as String? ?? '—',
          snapshot: snap,
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  static Future<void> archiveMedicine(int id, String name, int stock,
      {required String reason}) async {
    await supabaseClient.from('medicines').update({
      'is_archived': true,
    }).eq('id', id);

    try {
      await supabaseClient.from('archive_log').insert({
        'entity_type': 'medicine',
        'entity_id': id.toString(),
        'reason': reason,
        'status': null,
        'snapshot': {'id': id, 'name': name, 'stock': stock},
      });
    } catch (_) {}
  }

  static Future<void> archiveVisit(Visit v) async {
    if (v.id == null) {
      throw StateError('Cannot archive a visit without a database id.');
    }
    final stringify = DateFormat('yyyy-MM-dd');
    await supabaseClient
        .from('archive_log')
        .insert({
          'entity_type': 'visit',
          'entity_id': v.id.toString(),
          'reason': 'Archived',
          'status': v.category,
          'snapshot': {
            'id': v.id,
            'patient_id': v.patientId,
            'patient_no': v.patientNo,
            'patient_name': v.patientName,
            'category': v.category,
            'department': v.department,
            'year_position': v.yearPosition,
            'complaint': v.complaint,
            if (v.visitDate != null)
              'visit_date': stringify.format(v.visitDate!),
            'visit_time': v.visitTime,
          },
        })
        .select('id')
        .single();
    await VisitService.delete(v.id!);
  }

  static Future<void> archiveVisitById(int id) async {
    final rows = await supabaseClient.from('visits').select().eq('id', id);
    if (rows.isEmpty) {
      throw StateError('Visit $id no longer exists.');
    }
    final v = Visit.fromSupabase(Map<String, dynamic>.from(rows.first));
    await archiveVisit(v);
  }

  static Future<void> restorePatient(ArchivedPatient p) async {
    if (p.uuid.isEmpty) return;

    await IndividualRecordService.restorePerson(p.uuid);

    DataTracker.bump();
    try {
      await supabaseClient
          .from('archive_log')
          .delete()
          .eq('entity_type', 'patient')
          .eq('entity_id', p.uuid);
    } catch (_) {}
  }

  static Future<void> restoreMedicine(ArchivedMedicine m) async {
    await supabaseClient.from('medicines').update({
      'is_archived': false,
    }).eq('id', m.id);
    try {
      await supabaseClient
          .from('archive_log')
          .delete()
          .eq('entity_type', 'medicine')
          .eq('entity_id', m.id.toString());
    } catch (_) {}
  }

  static Future<Visit> restoreRecord(ArchivedRecord r) async {
    final snap = r.snapshot;
    final v = await VisitService.create(
      patientId: snap['patient_id']?.toString() ?? '',
      patientNo: snap['patient_no']?.toString() ?? '—',
      patientName: snap['patient_name']?.toString() ?? '—',
      category: snap['category']?.toString() ?? 'Student',
      department: snap['department']?.toString() ?? '',
      yearPosition: snap['year_position']?.toString() ?? '',
      complaint: snap['complaint']?.toString() ?? '',
      visitDate: _parseTs(snap['visit_date']) ?? DateTime.now(),
      visitTime: snap['visit_time']?.toString() ?? '',
    );
    await supabaseClient.from('archive_log').delete().eq('id', r.logId);
    return v;
  }

  static Future<Map<String, String>> _fetchUserNames() async {
    final rows = await supabaseClient
        .from('useraccount')
        .select('user_id, username, fn, ln');
    return {
      for (final r in rows)
        if (r['user_id'] != null) r['user_id'] as String: _nameOf(r),
    };
  }

  static String _nameOf(Map<String, dynamic> row) {
    final name = [
      (row['fn'] as String? ?? '').trim(),
      (row['ln'] as String? ?? '').trim(),
    ].where((s) => s.isNotEmpty).join(' ');
    return name.isNotEmpty ? name : (row['username'] as String? ?? '').trim();
  }

  static DateTime? _parseTs(Object? v) {
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  static int _asInt(Object? v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }
}
