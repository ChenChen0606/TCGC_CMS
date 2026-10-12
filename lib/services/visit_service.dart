// ─────────────────────────────────────────────────────────────────────────────
//  visit_service.dart
//  Supabase-backed CRUD for clinic visits (the Records Booklet).
//
//  Visits carry SNAPSHOTS (patient_no, patient_name, category, department,
//  year_position, medicine_name, qty) frozen at intake time, exactly like the
//  old `public.visits` schema. A visit is filed under `clinic_visits.person_id`,
//  which is the visitor's `individual_records` person_id held as text — there is
//  no `patients` table in this project to reference.
//
//  `created_by` IS written by the client, from the signed-in auth user
//  (`auth.currentUser.id`, which is `useraccount.user_id` — the same value the
//  login screen files the account under). `clinic_visits.created_by` is NOT
//  NULL with no default and no trigger, so an insert that omits it fails with
//  23502; the client is the only thing that can say who filed the visit.
//  RLS policies gate every read/write.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:intl/intl.dart';
import 'package:clinicmanagementsystem/services/data_tracker.dart';
import 'package:clinicmanagementsystem/services/patient_service.dart';
import 'package:clinicmanagementsystem/services/supabase_config.dart';

/// Simple visit model matching the `public.clinic_visits` table shape (new design).
class Visit {
  final String? id; // visit_id UUID
  final String patientId; // person_id (text) from individual_records
  final String? visitNumber;
  final String patientNo; // snapshot (legacy compatibility)
  final String patientName; // snapshot
  final String category; // snapshot
  final String department; // snapshot
  final String yearPosition; // snapshot
  final String complaint; // kept for compatibility; use reasonForVisit
  final String reasonForVisit;
  final DateTime? visitDate;
  final String visitTime; // TIME as string (HH:mm:ss or display)
  final String? status;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String? recordedBy;
  // Medicine fields removed - not stored in clinic_visits table

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

  /// What the booklet prints as the visitor's name.
  ///
  /// `patient_name` is a snapshot taken at intake, so a visit saved before the
  /// snapshot columns existed has it NULL — and the booklet used to print that
  /// NULL as an empty cell, which is how a whole page of records ends up showing
  /// nothing but dates and no name on any of them.
  ///
  /// So it falls back, in order: the name, the record number, and finally the
  /// visit's own id. Every row then names something, and a row that says
  /// "Visitor #41" is telling the truth — there is no name on that visit — rather
  /// than pretending there is one.
  String get visitorLabel {
    final n = patientName.trim();
    if (n.isNotEmpty) return n;
    final no = patientNo.trim();
    if (no.isNotEmpty) return no;
    if (id == null || id!.isEmpty) return 'Unnamed visitor';
    return 'Visitor #$id';
  }

  /// The line under the name. The record number when the visit has one, otherwise
  /// the visit's id so the row can still be traced back.
  String get visitorRef {
    final no = patientNo.trim();
    if (no.isNotEmpty) return no;
    if (id == null || id!.isEmpty) return '-';
    return 'Visit #$id';
  }

  /// Student / Faculty / Staff, or an honest "Unassigned".
  ///
  /// Not defaulted to Staff: a visit whose category was never captured must not
  /// be filed under the staff badge, because that is a claim about the person
  /// that nobody made and that a reader would believe.
  String get categoryLabel {
    final c = category.trim();
    if (c.isEmpty) return 'Unassigned';
    return c;
  }

  /// Converts a Visit into the Records Booklet's record map. The booklet
  /// screens work with `Map<String, String>` values, and every key the UI
  /// reads is produced here (plus a `visitId` used for DB-backed edits).
  ///
  /// [userNames] maps useraccount.user_id -> a display name (see
  /// PatientService.fetchUserNames).
  /// fetchUserNames) so audit columns that are stored as uuids render as
  /// human-friendly names.
  Map<String, String> toBookletMap({Map<String, String> userNames = const {}}) {
    final DateTime? created = createdAt?.toLocal();
    final DateTime? updated = updatedAt?.toLocal();
    String by(String? id) {
      if (id == null || id.isEmpty) return '—';
      final name = userNames[id];
      return (name == null || name.isEmpty) ? '—' : name;
    }

    String ts(DateTime? t) {
      if (t == null) return '—';
      return DateFormat("yyyy-MM-dd hh:mm a").format(t);
    }

    return {
      "visitId": id?.toString() ?? '',
      "personId": patientId,
      "date":
          visitDate == null ? '' : DateFormat("yyyy-MM-dd").format(visitDate!),
      "time": visitTime.trim().isEmpty ? '-' : visitTime.trim(),
      "timeOut": '',
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

/// Shared in-memory record of visits for tabs that are kept alive by the
/// dashboard's IndexedStack (consultation form + Records Booklet). Mirrors
/// the `PatientData` store pattern so other screens can react to changes.
class VisitData {
  VisitData._();

  static final List<Visit> visits = [];
}

class VisitService {
  VisitService._();

  /// Loads all visits, newest first.
  static Future<List<Visit>> fetchAll() async {
    final rows = await supabaseClient
        .from('clinic_visits')
        .select()
        .order('created_at', ascending: false);
    return rows
        .map<Visit>((r) => Visit.fromSupabase(Map<String, dynamic>.from(r)))
        .toList();
  }

  /// Loads the visit history for one patient, newest first.
  ///
  /// Backs the "Visit History" panel on the Clinic Visit screen's Visitor
  /// Information card. [personId] is the same `person_id` that
  /// [VisitService.create] writes, so a visitor who has never had a visit comes
  /// back empty rather than throwing.
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

  /// Loads all visits and converts them straight into the Records Booklet's
  /// `Map<String, String>` shape, resolving audit uuids to profile names.
  static Future<List<Map<String, String>>> fetchAllBookletRecords() async {
    Map<String, String> userNames = const {};
    try {
      userNames = await PatientService.fetchUserNames();
    } catch (_) {}
    final rows = await supabaseClient
        .from('clinic_visits')
        .select()
        .order('created_at', ascending: false);
    return rows.map((r) {
      return Visit.fromSupabase(Map<String, dynamic>.from(r))
          .toBookletMap(userNames: userNames);
    }).toList();
  }

  /// Inserts a visit. Returns the persisted row (server-assigned id,
  /// created_by and created_at).
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
    // Generate visit number (simple: timestamp-based)
    final now = DateTime.now();
    final visitNum = 'V${now.millisecondsSinceEpoch}';
    final time24 = visitTime.isEmpty
        ? DateFormat('HH:mm:ss').format(now)
        : VisitService._toTime24(visitTime);

    // `clinic_visits.created_by` is NOT NULL with no default and no trigger, so
    // an insert that omits it is rejected (23502). It is the signed-in auth
    // user's id, which is also `useraccount.user_id` (see login_screen). Refuse
    // to write a visit we cannot attribute rather than let the database reject
    // it with a message that does not name the cause.
    final createdBy = supabaseClient.auth.currentUser?.id ?? '';
    if (createdBy.isEmpty) {
      throw StateError(
          'No signed-in user — cannot record who filed this visit.');
    }

    final row = await supabaseClient
        .from('clinic_visits')
        .insert({
          'visit_number': visitNum,
          'person_id': patientId,
          'visit_date': DateFormat("yyyy-MM-dd").format(visitDate ?? now),
          'visit_time': time24,
          'reason_for_visit': reasonForVisit ?? complaint,
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

  /// Updates the editable fields of an existing visit. updated_by /
  /// updated_at are set automatically by the DB trigger.
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

  /// Deletes a visit by id (hard delete, matches the booklet UI).
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

  /// Every visit, joined to the person who made it and the services performed
  /// on it — the shape the Overview cards need.
  ///
  /// `clinic_visits` stores no name, category, services or institute/program of
  /// its own; all of that lives one hop away in `individual_records` (via
  /// `person_id`), `individual_academic_records` (the affiliation) and
  /// `clinic_visit_services` → `service_types` (the services). Every embed is
  /// `!left`, so a visit whose person row or service rows are missing still
  /// counts rather than silently disappearing from the summary.
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

/// One visit as the Overview shows it: the header joined to its patient and the
/// services performed. See [VisitService.fetchDashboardVisits].
class DashboardVisit {
  final String visitId;
  final String personId;
  final String name;
  final String personType; // Student / Faculty / Staff, or '' when unknown
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

  /// "ICS - BSCS", or whichever half is known, or ''.
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

/// The single object an embedded to-one relationship returns, or the first of a
/// to-many. `{}` when there is nothing usable.
Map<String, dynamic> _firstMap(Object? value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  if (value is List && value.isNotEmpty && value.first is Map) {
    return Map<String, dynamic>.from(value.first as Map);
  }
  return const {};
}

/// Every map in an embedded to-many relationship (or the single one).
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
