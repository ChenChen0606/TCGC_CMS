import 'package:intl/intl.dart';
import 'package:clinicmanagementsystem/core/services/data_tracker.dart';
import 'package:clinicmanagementsystem/features/patients/services/patient_service.dart';
import 'package:clinicmanagementsystem/core/config/supabase_config.dart';

class Visit {
  final String? id;
  final String patientId;
  final String? visitNumber;
  final String patientNo;
  final String patientName;
  final String category;
  final String department;
  final String yearPosition;
  final String complaint;
  final String reasonForVisit;
  final DateTime? visitDate;
  final String visitTime;
  final String? status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? recordedBy;

  final DateTime? outTime;

  const Visit({
    this.id,
    required this.patientId,
    this.visitNumber,
    this.patientNo = '',
    this.patientName = '',
    this.category = '',
    this.department = '',
    this.yearPosition = '',
    this.complaint = '',
    this.reasonForVisit = '',
    this.visitDate,
    this.visitTime = '',
    this.status,
    this.createdAt,
    this.updatedAt,
    this.recordedBy,
    this.outTime,
  });

  factory Visit.fromSupabase(Map<String, dynamic> row) {
    return Visit(
      id: row['visit_id'] as String? ?? row['id'] as String?,
      patientId:
          row['person_id'] as String? ?? row['patient_id'] as String? ?? '',
      visitNumber: row['visit_number'] as String?,
      patientNo: row['patient_no'] as String? ?? '',
      patientName: row['patient_name'] as String? ?? '',
      category: row['category'] as String? ?? '',
      department: row['department'] as String? ?? '',
      yearPosition: row['year_position'] as String? ?? '',
      complaint: row['complaint'] as String? ??
          row['reason_for_visit'] as String? ??
          '',
      reasonForVisit: row['reason_for_visit'] as String? ?? '',
      visitDate: _parseTs(row['visit_date']),
      visitTime: row['visit_time'] as String? ?? '',
      status: row['status'] as String?,
      createdAt: _parseTs(row['created_at']),
      updatedAt: _parseTs(row['updated_at']),
      recordedBy: row['recorded_by'] as String? ?? row['created_by'] as String?,
    );
  }

  String get visitorLabel {
    final n = patientName.trim();
    if (n.isNotEmpty) return n;
    final no = patientNo.trim();
    if (no.isNotEmpty) return no;
    if (id == null || id!.isEmpty) return 'Unnamed visitor';
    return 'Visitor #$id';
  }

  String get visitorRef {
    final no = patientNo.trim();
    if (no.isNotEmpty) return no;
    if (id == null || id!.isEmpty) return '-';
    return 'Visit #$id';
  }

  String get categoryLabel {
    final c = category.trim();
    if (c.isEmpty) return 'Unassigned';
    return c;
  }

  Map<String, String> toBookletMap({Map<String, String> userNames = const {}}) {
    final DateTime? created = createdAt?.toLocal();
    final DateTime? updated = updatedAt?.toLocal();
    final DateTime? out = outTime?.toLocal();
    String by(String? id) {
      if (id == null || id.isEmpty) return '—';
      final name = userNames[id];
      return (name == null || name.isEmpty) ? '—' : name;
    }

    String ts(DateTime? t) {
      if (t == null) return '—';
      return DateFormat("yyyy-MM-dd hh:mm a").format(t);
    }

    String clock(DateTime? t) {
      if (t == null) return '';
      return DateFormat('hh:mm a').format(t);
    }

    return {
      "visitId": id?.toString() ?? '',
      "personId": patientId,
      "date":
          visitDate == null ? '' : DateFormat("yyyy-MM-dd").format(visitDate!),
      "time": visitTime.trim().isEmpty ? '-' : visitTime.trim(),
      "timeOut": clock(out),
      "name": visitorLabel,
      "id": visitorRef,
      "type": categoryLabel,
      "dept": department,
      "year": yearPosition,
      "complaint": reasonForVisit.isNotEmpty ? reasonForVisit : complaint,
      "medicine": 'None',
      "qty": '—',
      "createdBy": by(recordedBy),
      "createdAt": ts(created),
      "updatedBy": by(recordedBy),
      "updatedAt": ts(updated),
    };
  }

  static DateTime? _parseTs(Object? v) {
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }
}

class VisitData {
  VisitData._();

  static final List<Visit> visits = [];
}

class VisitService {
  VisitService._();

  static Future<List<Visit>> fetchAll() async {
    final rows = await supabaseClient
        .from('clinic_visits')
        .select()
        .order('created_at', ascending: false);
    return rows
        .map<Visit>((r) => Visit.fromSupabase(Map<String, dynamic>.from(r)))
        .toList();
  }

  static Future<List<Visit>> fetchByPatient(String personId) async {
    if (personId.trim().isEmpty) return const [];
    final rows = await supabaseClient
        .from('clinic_visits')
        .select()
        .eq('person_id', personId.trim())
        .order('visit_date', ascending: false)
        .order('created_at', ascending: false);
    return rows
        .map<Visit>((r) => Visit.fromSupabase(Map<String, dynamic>.from(r)))
        .toList();
  }

  static Future<List<Map<String, String>>> fetchAllBookletRecords() async {
    Map<String, String> userNames = const {};
    try {
      userNames = await PatientService.fetchUserNames();
    } catch (_) {}
    final rows = await supabaseClient
        .from('clinic_visits')
        .select()
        .order('created_at', ascending: false);

    final outByVisit = await _completedAtByVisit();

    return rows.map((r) {
      final map = Map<String, dynamic>.from(r);
      final visitId = '${map['visit_id'] ?? map['id'] ?? ''}';
      final visit = Visit.fromSupabase(map);
      final out = outByVisit[visitId];
      return Visit(
        id: visit.id,
        patientId: visit.patientId,
        visitNumber: visit.visitNumber,
        patientNo: visit.patientNo,
        patientName: visit.patientName,
        category: visit.category,
        department: visit.department,
        yearPosition: visit.yearPosition,
        complaint: visit.complaint,
        reasonForVisit: visit.reasonForVisit,
        visitDate: visit.visitDate,
        visitTime: visit.visitTime,
        status: visit.status,
        createdAt: visit.createdAt,
        updatedAt: visit.updatedAt,
        recordedBy: visit.recordedBy,
        outTime: out,
      ).toBookletMap(userNames: userNames);
    }).toList();
  }

  static Future<Map<String, DateTime>> _completedAtByVisit() async {
    final out = <String, DateTime>{};
    try {
      final rows = await supabaseClient
          .from('clinic_visit_services')
          .select('visit_id, completed_at')
          .not('completed_at', 'is', null);
      for (final r in rows) {
        final visitId = '${r['visit_id'] ?? ''}';
        if (visitId.isEmpty) continue;
        final raw = r['completed_at'];
        final ts = raw is DateTime
            ? raw
            : (raw is String ? DateTime.tryParse(raw) : null);
        if (ts == null) continue;
        final existing = out[visitId];
        if (existing == null || ts.isAfter(existing)) out[visitId] = ts;
      }
    } catch (_) {}
    return out;
  }

  static Future<Visit> create({
    required String patientId,
    required String patientNo,
    required String patientName,
    required String category,
    String department = '',
    String yearPosition = '',
    required String complaint,
    DateTime? visitDate,
    String visitTime = '',
    String? timeOut,
    String? reasonForVisit,
    String? recordedBy,
  }) async {
    final now = DateTime.now();
    final visitNum = 'V${now.millisecondsSinceEpoch}';
    final time24 = visitTime.isEmpty
        ? DateFormat('HH:mm:ss').format(now)
        : VisitService._toTime24(visitTime);

    final createdBy = supabaseClient.auth.currentUser?.id ?? '';
    if (createdBy.isEmpty) {
      throw StateError(
          'No signed-in user — cannot record who filed this visit.');
    }

    final reason = (reasonForVisit ?? '').trim();
    final row = await supabaseClient
        .from('clinic_visits')
        .insert({
          'visit_number': visitNum,
          'person_id': patientId,
          'visit_date': DateFormat("yyyy-MM-dd").format(visitDate ?? now),
          'visit_time': time24,
          'reason_for_visit': reason.isNotEmpty ? reason : complaint,
          'status': 'Completed',
          'created_by': createdBy,
        })
        .select()
        .single();
    final persisted = Visit.fromSupabase(Map<String, dynamic>.from(row));
    VisitData.visits.insert(0, persisted);
    DataTracker.bump();
    return persisted;
  }

  static Future<void> update(
    dynamic id, {
    required String complaint,
  }) async {
    final sid = id.toString();
    await supabaseClient.from('clinic_visits').update({
      'reason_for_visit': complaint,
    }).eq('visit_id', sid);
    DataTracker.bump();
  }

  static Future<void> delete(dynamic id) async {
    final sid = id.toString();
    await supabaseClient.from('clinic_visits').delete().eq('visit_id', sid);
    DataTracker.bump();
  }

  static String _toTime24(String t) {
    try {
      final d = DateFormat('hh:mm a').parse(t);
      return DateFormat('HH:mm:ss').format(d);
    } catch (_) {
      return t;
    }
  }

  static Future<List<DashboardVisit>> fetchDashboardVisits() async {
    final rows = await supabaseClient.from('clinic_visits').select('''
      visit_id, person_id, visit_date, visit_time, reason_for_visit, created_at,
      individual_records!left(
        fn, mn, ln, person_type,
        individual_academic_records!left(
          status,
          institutes!left(code),
          program!left(code)
        )
      ),
      clinic_visit_services!left(
        service_types!left(service_name, service_code)
      )
    ''').order('created_at', ascending: false);

    return rows.map<DashboardVisit>((raw) {
      final row = Map<String, dynamic>.from(raw);
      final person = _firstMap(row['individual_records']);

      final acadList = _mapList(person['individual_academic_records']);
      Map<String, dynamic> acad = const {};
      for (final a in acadList) {
        if ('${a['status']}'.trim() == 'Active') {
          acad = a;
          break;
        }
      }
      if (acad.isEmpty && acadList.isNotEmpty) acad = acadList.first;
      final institute = _firstMap(acad['institutes']);
      final program = _firstMap(acad['program']);

      final services = <String>[];
      for (final s in _mapList(row['clinic_visit_services'])) {
        final st = _firstMap(s['service_types']);
        final n = '${st['service_name'] ?? st['service_code'] ?? ''}'.trim();
        if (n.isNotEmpty && !services.contains(n)) services.add(n);
      }

      final name = [
        '${person['fn'] ?? ''}'.trim(),
        '${person['mn'] ?? ''}'.trim(),
        '${person['ln'] ?? ''}'.trim(),
      ].where((e) => e.isNotEmpty).join(' ');

      return DashboardVisit(
        visitId: '${row['visit_id'] ?? ''}',
        personId: '${row['person_id'] ?? ''}',
        name: name,
        personType: '${person['person_type'] ?? ''}'.trim(),
        visitDate: Visit._parseTs(row['visit_date']),
        visitTime: '${row['visit_time'] ?? ''}'.trim(),
        reason: '${row['reason_for_visit'] ?? ''}'.trim(),
        instituteCode: '${institute['code'] ?? ''}'.trim(),
        programCode: '${program['code'] ?? ''}'.trim(),
        services: services,
      );
    }).toList();
  }
}

class DashboardVisit {
  final String visitId;
  final String personId;
  final String name;
  final String personType;
  final DateTime? visitDate;
  final String visitTime;
  final String reason;
  final String instituteCode;
  final String programCode;
  final List<String> services;

  const DashboardVisit({
    required this.visitId,
    required this.personId,
    this.name = '',
    this.personType = '',
    this.visitDate,
    this.visitTime = '',
    this.reason = '',
    this.instituteCode = '',
    this.programCode = '',
    this.services = const [],
  });

  String get affiliation {
    final i = instituteCode.trim();
    final p = programCode.trim();
    if (i.isEmpty && p.isEmpty) return '';
    if (i.isEmpty) return p;
    if (p.isEmpty) return i;
    return '$i - $p';
  }

  String get displayName {
    if (name.trim().isNotEmpty) return name.trim();
    if (personId.trim().isNotEmpty) return personId.trim();
    return 'Unnamed visitor';
  }
}

Map<String, dynamic> _firstMap(Object? value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  if (value is List && value.isNotEmpty && value.first is Map) {
    return Map<String, dynamic>.from(value.first as Map);
  }
  return const {};
}

List<Map<String, dynamic>> _mapList(Object? value) {
  if (value is List) {
    return [
      for (final e in value)
        if (e is Map) Map<String, dynamic>.from(e),
    ];
  }
  if (value is Map) return [Map<String, dynamic>.from(value)];
  return const [];
}
