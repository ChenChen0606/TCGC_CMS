import 'package:intl/intl.dart';
import 'package:clinicmanagementsystem/core/services/data_tracker.dart';
import 'package:clinicmanagementsystem/core/services/time_service.dart';
import 'package:clinicmanagementsystem/core/services/ttl_cache.dart';
import 'package:clinicmanagementsystem/features/patients/services/patient_service.dart';
import 'package:clinicmanagementsystem/core/config/supabase_config.dart';
import 'package:clinicmanagementsystem/core/services/reference_data_service.dart';

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
  final String? academicPeriodId;

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
    this.academicPeriodId,
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
      outTime: _parseTs(row['time_out']),
      academicPeriodId: row['academic_period_id'] as String?,
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
      "time": visitTime.trim().isEmpty ? '-' : _to12(visitTime),
      "timeOut": clock(out),
      "timeOutDate": out == null ? '' : DateFormat("yyyy-MM-dd").format(out),
      "name": visitorLabel,
      "id": visitorRef,
      "type": categoryLabel,
      "dept": department,
      "year": yearPosition,
      "complaint": reasonForVisit.isNotEmpty ? reasonForVisit : complaint,
      "medicine": 'None',
      "qty": '—',
      "periodId": academicPeriodId ?? '',
      "visitYear": ReferenceCatalog.periodById(academicPeriodId)?.acadYear ?? '',
      "visitSemester":
          ReferenceCatalog.periodById(academicPeriodId)?.semester ?? '',
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

  /// "22:49:00" -> "10:49 PM". Anything it can't parse is returned as is.
  static String _to12(String raw) {
    final t = raw.trim();
    for (final pattern in const ['HH:mm:ss', 'HH:mm']) {
      try {
        return DateFormat('hh:mm a').format(DateFormat(pattern).parseStrict(t));
      } catch (_) {}
    }
    return t;
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

  // ---------------------------------------------------------------------
  // Booklet records (fast path)
  // ---------------------------------------------------------------------

   static Map<String, String>? _namesCache;
  static DateTime? _namesAt;
  static bool _namesHooked = false;

  static Future<Map<String, String>> _userNames() async {
    if (!_namesHooked) {
      _namesHooked = true;
      // A saved profile / any data change drops the remembered names.
      DataTracker.onInvalidate(() {
        _namesCache = null;
        _namesAt = null;
      });
    }
    final cached = _namesCache;
    final at = _namesAt;
    if (cached != null &&
        at != null &&
        DateTime.now().difference(at).inMinutes < 10) {
      return cached;
    }
    try {
      final m = await PatientService.fetchUserNames();
      _namesCache = m;
      _namesAt = DateTime.now();
      return m;
    } catch (_) {
      return cached ?? const <String, String>{};
    }
  }

  static const int _pageSize = 1000;

  /// Every visit, with the completed_at of its services joined in one query
  /// (this replaces the separate scan of clinic_visit_services) and paged so
  /// Supabase's 1000-row cap does not cut the list short.
  static Future<List<Map<String, dynamic>>> _fetchAllVisitRows() async {
    const parallelPages = 4;

    Future<List<Map<String, dynamic>>> readPage(int index) async {
      final rows = await supabaseClient
          .from('clinic_visits')
          .select('*, clinic_visit_services!left(completed_at)')
          .order('created_at', ascending: false)
          .order('visit_id')
          .range(index * _pageSize, (index + 1) * _pageSize - 1);
      return rows.map((r) => Map<String, dynamic>.from(r)).toList();
    }

    final all = <Map<String, dynamic>>[];
    final first = await readPage(0);
    all.addAll(first);
    var more = first.length >= _pageSize;
    var next = 1;
    while (more) {
      final batch = await Future.wait([
        for (var i = 0; i < parallelPages; i++) readPage(next + i),
      ]);
      for (final page in batch) {
        all.addAll(page);
        if (page.length < _pageSize) more = false;
      }
      next += parallelPages;
    }
    return all;
  }

  static final TtlCache<List<Map<String, String>>> _bookletCache =
      TtlCache<List<Map<String, String>>>(ttl: const Duration(minutes: 2));

  /// Instant read (no network) of the booklet rows loaded earlier.
  static List<Map<String, String>>? peekBookletRecords() =>
      _bookletCache.peek;

  static Future<List<Map<String, String>>> fetchAllBookletRecords(
          {bool force = false}) =>
      _bookletCache.get(_downloadBookletRecords, force: force);

  static Future<List<Map<String, String>>> _downloadBookletRecords() async {
    final namesF = _userNames();
    final rowsF = _fetchAllVisitRows();
    final userNames = await namesF;
    final rows = await rowsF;

    return rows.map((map) {
      final visit = Visit.fromSupabase(map);

      // The saved Time Out wins; old rows without one fall back to the
      // latest completed service.
      DateTime? out = visit.outTime;
      if (out == null) {
        for (final s in _mapList(map['clinic_visit_services'])) {
          final raw = s['completed_at'];
          final ts = raw is DateTime
              ? raw
              : (raw is String ? DateTime.tryParse(raw) : null);
          if (ts != null && (out == null || ts.isAfter(out))) out = ts;
        }
      }

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
        academicPeriodId: visit.academicPeriodId,
      ).toBookletMap(userNames: userNames);
    }).toList();
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
    DateTime? timeOut,
    String? academicPeriodId,
    String? reasonForVisit,
    String? recordedBy,
  }) async {
    // Defaults come from the Supabase server clock, not the desktop clock.
    final now = await TimeService.serverNow();
    final visitNum = 'V${now.millisecondsSinceEpoch}';
    final time24 = visitTime.isEmpty
        ? DateFormat('HH:mm:ss').format(now)
        : VisitService._toTime24(visitTime);
    final day = visitDate ?? now;

    if (timeOut != null) {
      final start = _startOf(day, time24);
      if (_minute(timeOut.toLocal()).isBefore(_minute(start))) {
        throw ArgumentError('Time Out cannot be earlier than Time In.');
      }
    }

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
          'visit_date': DateFormat("yyyy-MM-dd").format(day),
          'visit_time': time24,
          if (timeOut != null) 'time_out': timeOut.toUtc().toIso8601String(),
          'reason_for_visit': reason.isNotEmpty ? reason : complaint,
          'status': 'Completed',
          'created_by': createdBy,
          if (academicPeriodId != null && academicPeriodId.isNotEmpty)
            'academic_period_id': academicPeriodId,
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
    String? academicPeriodId,
  }) async {
    final sid = id.toString();
    await supabaseClient.from('clinic_visits').update({
      'reason_for_visit': complaint,
      if (academicPeriodId != null && academicPeriodId.isNotEmpty)
        'academic_period_id': academicPeriodId,
    }).eq('visit_id', sid);
    DataTracker.bump();
  }

  static Future<String?> periodIdOf(String visitId) async {
    try {
      final row = await supabaseClient
          .from('clinic_visits')
          .select('academic_period_id')
          .eq('visit_id', visitId)
          .maybeSingle();
      final v = '${row?['academic_period_id'] ?? ''}'.trim();
      return v.isEmpty ? null : v;
    } catch (_) {
      return null;
    }
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

  static DateTime _startOf(DateTime day, String time24) {
    final p = time24.split(':');
    final h = int.tryParse(p.isNotEmpty ? p[0] : '') ?? 0;
    final m = int.tryParse(p.length > 1 ? p[1] : '') ?? 0;
    return DateTime(day.year, day.month, day.day, h, m);
  }

  static DateTime _minute(DateTime t) =>
      DateTime(t.year, t.month, t.day, t.hour, t.minute);

  static final TtlCache<List<DashboardVisit>> _dashboardCache =
      TtlCache<List<DashboardVisit>>(ttl: const Duration(seconds: 30));

  /// Instant read (no network) of the dashboard visits loaded earlier, or
  /// null when there are none. Cleared by any save/edit/delete.
  static List<DashboardVisit>? peekDashboardVisits() => _dashboardCache.peek;

  static Future<List<DashboardVisit>> fetchDashboardVisits(
          {bool force = false}) =>
      _dashboardCache.get(_downloadDashboardVisits, force: force);

  static Future<List<DashboardVisit>> _downloadDashboardVisits() async {
    // The dashboard only shows TODAY's visits, so only recent ones are asked
    // for. Downloading every visit ever recorded (each with its person,
    // enrolment, institute, program and services) made this screen slower
    // every week. One extra day back covers a visit saved around midnight or
    // a device clock / time-zone difference.
    final since = DateFormat('yyyy-MM-dd')
        .format(DateTime.now().subtract(const Duration(days: 1)));
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
    ''').gte('visit_date', since).order('created_at', ascending: false);

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