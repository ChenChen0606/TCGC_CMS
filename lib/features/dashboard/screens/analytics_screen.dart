import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:clinicmanagementsystem/core/config/supabase_config.dart';
import 'package:clinicmanagementsystem/core/services/data_tracker.dart';
import 'package:clinicmanagementsystem/features/inventory/services/medicine_service.dart';
import 'package:clinicmanagementsystem/features/account/services/account_service.dart';
import 'package:clinicmanagementsystem/features/visits/models/visit_details.dart';
import 'package:clinicmanagementsystem/features/visits/models/visit_service_forms.dart';
import 'package:clinicmanagementsystem/features/visits/models/visit_service_summary.dart';
import 'package:clinicmanagementsystem/features/visits/services/visit_details_service.dart';
import 'package:clinicmanagementsystem/features/visits/services/visit_service.dart';
import 'package:clinicmanagementsystem/features/vitals/models/vitals.dart';
import 'package:clinicmanagementsystem/core/theme/app_colors.dart';

const kTeal = AppColors.primary;
const kBg = AppColors.bg;
const kBorder = AppColors.border;
const kTextMuted = AppColors.textSub;
const kTextDark = AppColors.textDark;

/// One clinic visit, with everything the Reports page needs
/// (including the school year / semester and the full list of services).
class _ReportVisit {
  final String visitId;
  final String personId;
  final String name;
  final String personType;
  final DateTime? visitDate;
  final String visitTime;
  final String timeOut;
  final String reason;
  final String instituteCode;
  final String programCode;
  final List<String> services;

  /// service name -> service code (used to match a service to its details).
  final Map<String, String> serviceCodes;

  /// Every (school year, semester) the patient has an academic record in.
  final List<({String year, String semester})> periods;

  const _ReportVisit({
    required this.visitId,
    required this.personId,
    this.name = '',
    this.personType = '',
    this.visitDate,
    this.visitTime = '',
    this.timeOut = '',
    this.reason = '',
    this.instituteCode = '',
    this.programCode = '',
    this.services = const [],
    this.serviceCodes = const {},
    this.periods = const [],
  });

  String get displayName {
    if (name.trim().isNotEmpty) return name.trim();
    if (personId.trim().isNotEmpty) return personId.trim();
    return 'Unnamed visitor';
  }

  String get affiliation {
    final i = instituteCode.trim();
    final p = programCode.trim();
    if (i.isEmpty && p.isEmpty) return '';
    if (i.isEmpty) return p;
    if (p.isEmpty) return i;
    return '$i - $p';
  }
}

/// The recorded answers of ONE service on ONE visit, flattened so they can be
/// shown as table columns (label -> value) plus the service status.
class _ServiceCells {
  final Map<String, String> values;
  final String status;
  const _ServiceCells(this.values, this.status);
}

Map<String, dynamic> _asMap(Object? value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  if (value is List && value.isNotEmpty && value.first is Map) {
    return Map<String, dynamic>.from(value.first as Map);
  }
  return const {};
}

List<Map<String, dynamic>> _asList(Object? value) {
  if (value is List) {
    return [
      for (final e in value)
        if (e is Map) Map<String, dynamic>.from(e),
    ];
  }
  if (value is Map) return [Map<String, dynamic>.from(value)];
  return const [];
}

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  static const List<String> _views = [
    'Daily',
    'Weekly',
    'Monthly',
    'School Year',
    'Custom',
  ];

  static const List<String> _visitorTypes = [
    'All',
    'Student',
    'Faculty',
    'Staff',
  ];

  static const List<String> _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];

  /// Rows shown per page in the Visit Records table.
  static const int _pageSize = 10;

  /// The vital-sign sub-services, named the same way as in the Records
  /// Booklet (BP Taking, Temperature Checking, ...).
  static const List<String> _vitalSubs = [
    'BP Taking',
    'Pulse Taking',
    'Temperature Checking',
    'Respiratory Rate',
    'SpO₂ Taking',
  ];

  /// Words that tell which recorded column belongs to which vital sign.
  static const Map<String, List<String>> _vitalKeys = {
    'BP Taking': [
      'blood pressure',
      'bp',
      'systolic',
      'diastolic',
      'pulse',
      'heart'
    ],
    'Pulse Taking': ['pulse', 'heart'],
    'Temperature Checking': ['temp'],
    'Respiratory Rate': ['resp'],
    'SpO₂ Taking': ['o₂', 'o2', 'spo', 'oxygen', 'saturation'],
  };

  String _selectedView = 'Daily';
  DateTimeRange? _insightsCustomRange;

  String _selectedAcadYear = 'All';
  String _selectedSemester = 'All';
  bool _showAllServices = false;

  // Visit Records table filters (they work on top of the period above).
  String _recordType = 'All';
  String _recordService = 'All';
  int _page = 0;
  final ScrollController _tableScroll = ScrollController();

  List<Medicine> _medicines = [];

  List<_ReportVisit> _visits = [];

  /// Full service details (same data the record booklet shows), loaded
  /// lazily for the visits that are on screen.
  final Map<String, VisitDetailsController> _details = {};
  final Set<String> _detailsRequested = {};
  final Set<String> _detailsDone = {};
  List<({String year, String semester})> _periodOptions = [];
  bool _loadingVisits = true;
  String? _visitsError;

  VoidCallback? _dataListener;

  @override
  void initState() {
    super.initState();
    _loadMedicines();
    _loadVisits();
    _dataListener = () {
      _loadMedicines();
      _loadVisits();
    };
    DataTracker.listen(_dataListener!);
  }

  @override
  void dispose() {
    if (_dataListener != null) DataTracker.unlisten(_dataListener!);
    _tableScroll.dispose();
    super.dispose();
  }

  Future<void> _loadMedicines() async {
    try {
      final meds = await MedicineService.fetchAll();
      if (mounted) setState(() => _medicines = meds);
    } catch (_) {}
  }

  Future<void> _loadVisits() async {
    setState(() {
      _loadingVisits = true;
      _visitsError = null;
    });
    try {
      // School years / semesters that exist in the database.
      final periods = <({String year, String semester})>[];
      try {
        final rows = await supabaseClient
            .from('academic_periods')
            .select('acad_year, semester');
        for (final r in _asList(rows)) {
          final y = '${r['acad_year'] ?? ''}'.trim();
          final s = '${r['semester'] ?? ''}'.trim();
          if (y.isNotEmpty) periods.add((year: y, semester: s));
        }
      } catch (_) {}

      // Time in / time out come from the same source the Records Booklet uses.
      final times = <String, ({String tin, String tout})>{};
      try {
        final recs = await VisitService.fetchAllBookletRecords();
        for (final r in recs) {
          final id = (r['visitId'] ?? '').trim();
          if (id.isEmpty) continue;
          times[id] = (
            tin: (r['time'] ?? '').trim(),
            tout: (r['timeOut'] ?? '').trim(),
          );
        }
      } catch (_) {}

      // Page through clinic_visits so we are not capped at 1000 rows.
      final all = <Map<String, dynamic>>[];
      const page = 1000;
      var from = 0;
      while (true) {
        final rows = await supabaseClient.from('clinic_visits').select('''
          visit_id, person_id, visit_date, visit_time, reason_for_visit, created_at,
          individual_records!left(
            fn, mn, ln, person_type,
            individual_academic_records!left(
              status,
              institutes!left(code),
              program!left(code),
              academic_periods!left(acad_year, semester)
            )
          ),
          clinic_visit_services!left(
            service_types!left(service_name, service_code)
          )
        ''').order('created_at', ascending: false).range(from, from + page - 1);
        final list = _asList(rows);
        all.addAll(list);
        if (list.length < page) break;
        from += page;
      }

      final visits = all.map<_ReportVisit>((row) {
        final person = _asMap(row['individual_records']);

        final acadList = _asList(person['individual_academic_records']);
        Map<String, dynamic> acad = const {};
        for (final a in acadList) {
          if ('${a['status']}'.trim() == 'Active') {
            acad = a;
            break;
          }
        }
        if (acad.isEmpty && acadList.isNotEmpty) acad = acadList.first;
        final institute = _asMap(acad['institutes']);
        final program = _asMap(acad['program']);

        final vPeriods = <({String year, String semester})>[];
        for (final a in acadList) {
          final p = _asMap(a['academic_periods']);
          final y = '${p['acad_year'] ?? ''}'.trim();
          final s = '${p['semester'] ?? ''}'.trim();
          if (y.isEmpty) continue;
          if (!vPeriods.any((e) => e.year == y && e.semester == s)) {
            vPeriods.add((year: y, semester: s));
          }
        }

        final services = <String>[];
        final codes = <String, String>{};
        for (final s in _asList(row['clinic_visit_services'])) {
          final st = _asMap(s['service_types']);
          final n = '${st['service_name'] ?? st['service_code'] ?? ''}'.trim();
          if (n.isNotEmpty && !services.contains(n)) {
            services.add(n);
            codes[n] = '${st['service_code'] ?? ''}'.trim();
          }
        }

        final name = [
          '${person['fn'] ?? ''}'.trim(),
          '${person['mn'] ?? ''}'.trim(),
          '${person['ln'] ?? ''}'.trim(),
        ].where((e) => e.isNotEmpty).join(' ');

        final visitId = '${row['visit_id'] ?? ''}';
        final t = times[visitId.trim()];
        final rawTime = '${row['visit_time'] ?? ''}'.trim();

        return _ReportVisit(
          visitId: visitId,
          personId: '${row['person_id'] ?? ''}',
          name: name,
          personType: '${person['person_type'] ?? ''}'.trim(),
          visitDate: DateTime.tryParse('${row['visit_date'] ?? ''}'),
          visitTime: (t != null && t.tin.isNotEmpty) ? t.tin : rawTime,
          timeOut: (t != null && t.tout != '-') ? t.tout : '',
          reason: '${row['reason_for_visit'] ?? ''}'.trim(),
          instituteCode: '${institute['code'] ?? ''}'.trim(),
          programCode: '${program['code'] ?? ''}'.trim(),
          services: services,
          serviceCodes: codes,
          periods: vPeriods,
        );
      }).toList();

      if (!mounted) return;
      _details.clear();
      _detailsRequested.clear();
      _detailsDone.clear();
      setState(() {
        _visits = visits;
        _periodOptions = periods;
        _loadingVisits = false;
        if (_recordService != 'All' &&
            !_serviceOptions.contains(_recordService)) {
          _recordService = 'All';
        }
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loadingVisits = false;
        _visitsError = '$e';
      });
    }
  }

  String get _outOfStockCount =>
      _medicines.where((m) => m.stock == 0).length.toString();

  String _fmtDate(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';

  /// Nov 2, 2026 · Nov 1–3, 2026 · Oct 1 – Nov 1, 2026 ·
  /// Oct 1, 2025 – Nov 1, 2026
  String _fmtRange(DateTime s, DateTime e) {
    if (s == e) return _fmtDate(s);
    if (s.year != e.year) return '${_fmtDate(s)} – ${_fmtDate(e)}';
    if (s.month == e.month) {
      return '${_months[s.month - 1]} ${s.day}–${e.day}, ${s.year}';
    }
    return '${_months[s.month - 1]} ${s.day} – '
        '${_months[e.month - 1]} ${e.day}, ${s.year}';
  }

  /// The label shown at the right of the Visit Records card.
  String _periodDateLabel() {
    if (_selectedView == 'School Year') {
      return _selectedAcadYear == 'All'
          ? 'All school years'
          : _selectedViewLabel;
    }
    final r = _rangeFor(_selectedView);
    if (r == null) return 'Pick dates';
    return _fmtRange(r.start, r.end);
  }

  // ── Clock helpers (accept "09:15:00" and "09:15 AM") ──────────────────

  static ({int h, int m})? _parseClock(String t) {
    final m = RegExp(r'^(\d{1,2}):(\d{2})(?::\d{2})?\s*([AaPp][Mm])?$')
        .firstMatch(t.trim());
    if (m == null) return null;
    var h = int.parse(m.group(1)!);
    final mi = int.parse(m.group(2)!);
    final ap = m.group(3)?.toLowerCase();
    if (ap == 'pm' && h < 12) h += 12;
    if (ap == 'am' && h == 12) h = 0;
    return (h: h, m: mi);
  }

  /// "09:15:00" / "9:15 AM" -> "9:15 AM"; anything else is shown as saved.
  String _fmtTime(String t) {
    final s = t.trim();
    if (s.isEmpty || s == '-') return '—';
    final c = _parseClock(s);
    if (c == null) return s;
    final h12 = c.h % 12 == 0 ? 12 : c.h % 12;
    final ap = c.h >= 12 ? 'PM' : 'AM';
    return '$h12:${c.m.toString().padLeft(2, '0')} $ap';
  }

  int _minutes(String t) {
    final c = _parseClock(t);
    return c == null ? 0 : c.h * 60 + c.m;
  }

  /// "8:00 AM – 9:10 AM" (just the time in when there is no time out yet).
  String _sessionTimes(_ReportVisit v) {
    final tin = _fmtTime(v.visitTime);
    final out = v.timeOut.trim();
    if (out.isEmpty || out == '-') return tin;
    return '$tin – ${_fmtTime(out)}';
  }

  bool _isMorning(_ReportVisit v) => _minutes(v.visitTime) < 720;

  String _sessionLabel(_ReportVisit v) =>
      _isMorning(v) ? 'Morning (AM)' : 'Afternoon (PM)';

  // ── School year / semester / service options ──────────────────────────

  static int _semRank(String s) {
    final t = s.toLowerCase();
    if (t.contains('summer')) return 3;
    if (t.contains('1') || t.contains('first')) return 1;
    if (t.contains('2') || t.contains('second')) return 2;
    return 9;
  }

  List<String> get _availableAcadYears {
    final years = <String>{};
    for (final p in _periodOptions) {
      if (p.year.isNotEmpty) years.add(p.year);
    }
    for (final v in _visits) {
      for (final p in v.periods) {
        years.add(p.year);
      }
    }
    return years.toList()..sort((a, b) => b.compareTo(a));
  }

  List<String> get _availableSemesters {
    final sems = <String>{};
    for (final p in _periodOptions) {
      if (p.year == _selectedAcadYear && p.semester.isNotEmpty) {
        sems.add(p.semester);
      }
    }
    for (final v in _visits) {
      for (final p in v.periods) {
        if (p.year == _selectedAcadYear && p.semester.isNotEmpty) {
          sems.add(p.semester);
        }
      }
    }
    final list = sems.toList();
    list.sort((a, b) {
      final c = _semRank(a).compareTo(_semRank(b));
      return c != 0 ? c : a.compareTo(b);
    });
    return list;
  }

  List<String> get _availableServices {
    final s = <String>{};
    for (final v in _visits) {
      s.addAll(v.services);
    }
    return s.toList()..sort();
  }

  /// Service dropdown: every service, with the vital-sign sub-services
  /// listed right under "Vital signs".
  List<String> get _serviceOptions {
    final out = <String>['All'];
    for (final s in _availableServices) {
      out.add(s);
      if (_isVitalName(s)) {
        for (final sub in _vitalSubs) {
          if (!out.contains(sub)) out.add(sub);
        }
      }
    }
    return out;
  }

  // ── Vital signs, split the same way as the Records Booklet ────────────

  static bool _isVitalName(String n) => _norm(n).contains('vital');

  Set<String> _vitalsTaken(ServiceDraft d, VisitVitals v) {
    final picked = d
        .chosen(kVitalsSelectedKey)
        .where((e) => e != kSelectAllLabel)
        .toSet();
    if (picked.isNotEmpty) return picked;
    return {
      if (v.systolic != null && v.diastolic != null) 'Blood Pressure',
      if (v.tempC != null) 'Temperature',
      if (v.heartRate != null) 'Pulse',
      if (v.respRate != null) 'Respiratory Rate',
      if (v.o2Sat != null) 'O₂ Saturation',
    };
  }

  String _vitalLabel(ServiceDraft d, VisitVitals v) {
    if (d.serviceId != 'vital_signs') return d.label;
    final taken = _vitalsTaken(d, v);

    // BP alone, or BP + Pulse together, is one "BP Taking" service.
    if (taken.contains('Blood Pressure') &&
        taken.difference({'Blood Pressure', 'Pulse'}).isEmpty) {
      return 'BP Taking';
    }
    if (taken.length == 1) {
      return switch (taken.first) {
        'Pulse' => 'Pulse Taking',
        'Temperature' => 'Temperature Checking',
        'Respiratory Rate' => 'Respiratory Rate',
        'O₂ Saturation' => 'SpO₂ Taking',
        _ => d.label,
      };
    }
    return d.label; // several different vitals -> "Vital signs"
  }

  List<String> _vitalLabelsOf(VisitDetailsController c) => [
        for (final d in c.drafts)
          if (d.serviceId == 'vital_signs') _vitalLabel(d, c.vitals),
      ];

  /// Service names of a visit as they should be displayed: vital signs are
  /// replaced by BP Taking / Temperature Checking / ... once details load.
  List<String> _displayServices(_ReportVisit v) {
    final c = _details[v.visitId];
    if (c == null) return v.services;
    final vit = _vitalLabelsOf(c);
    if (vit.isEmpty) return v.services;
    final out = <String>[];
    for (final s in v.services) {
      if (_isVitalName(s)) {
        for (final l in vit) {
          if (!out.contains(l)) out.add(l);
        }
      } else if (!out.contains(s)) {
        out.add(s);
      }
    }
    return out;
  }

  bool _hasVitalSub(_ReportVisit v, String sub) {
    if (!v.services.any(_isVitalName)) return false;
    final c = _details[v.visitId];
    if (c == null) return false; // wait until its details are loaded
    return _vitalLabelsOf(c).contains(sub);
  }

  bool _keepVitalLabel(String sub, String label) {
    final l = label.toLowerCase();
    bool hit(List<String> ks) => ks.any(l.contains);
    if (hit(_vitalKeys[sub] ?? const [])) return true;
    // Hide columns that clearly belong to a different vital sign.
    return !_vitalKeys.values.any(hit);
  }

  // ── Date range / filtering ────────────────────────────────────────────

  DateTimeRange? _rangeFor(String view) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    switch (view) {
      case 'Daily':
        return DateTimeRange(start: today, end: today);
      case 'Weekly':
        final start = today.subtract(Duration(days: today.weekday - 1));
        final end = start.add(const Duration(days: 6));
        return DateTimeRange(start: start, end: end);
      case 'Monthly':
        return DateTimeRange(
          start: DateTime(now.year, now.month),
          end: DateTime(now.year, now.month + 1, 0),
        );
      case 'Custom':
        if (_insightsCustomRange == null) return null;
        return DateTimeRange(
          start: DateTime(
              _insightsCustomRange!.start.year,
              _insightsCustomRange!.start.month,
              _insightsCustomRange!.start.day),
          end: DateTime(_insightsCustomRange!.end.year,
              _insightsCustomRange!.end.month, _insightsCustomRange!.end.day),
        );
      default:
        return null;
    }
  }

  String get _semesterLabel {
    if (_selectedSemester == 'All') return '';
    final t = _selectedSemester.toLowerCase();
    return (t.contains('sem') || t.contains('summer'))
        ? _selectedSemester
        : '$_selectedSemester Semester';
  }

  String get _selectedViewLabel {
    switch (_selectedView) {
      case 'Custom':
        return _insightsCustomRange != null
            ? '${_fmtDate(_insightsCustomRange!.start)} - ${_fmtDate(_insightsCustomRange!.end)}'
            : 'Custom range - pick dates';
      case 'School Year':
        if (_selectedAcadYear == 'All') return 'all school years';
        var base = 'A.Y. $_selectedAcadYear';
        if (_selectedSemester != 'All') base += ' - $_semesterLabel';
        return base;
      default:
        return _selectedView;
    }
  }

  bool _inPeriod(_ReportVisit v) {
    if (_selectedView == 'School Year') {
      if (_selectedAcadYear == 'All') return true;
      return v.periods.any((p) =>
          p.year == _selectedAcadYear &&
          (_selectedSemester == 'All' || p.semester == _selectedSemester));
    }
    final range = _rangeFor(_selectedView);
    if (range == null) return false;
    final d = v.visitDate;
    if (d == null) return false;
    final day = DateTime(d.year, d.month, d.day);
    return !day.isBefore(range.start) && !day.isAfter(range.end);
  }

  List<_ReportVisit> _visitsInRange() => _visits.where(_inPeriod).toList();

  Map<String, double> get _currentViewData {
    final list = _visitsInRange();
    double count(String type) =>
        list.where((v) => v.personType == type).length.toDouble();
    final students = count('Student');
    final faculty = count('Faculty');
    final staff = count('Staff');
    return {
      'Students': students,
      'Faculty': faculty,
      'Staff': staff,
      'Total': students + faculty + staff,
    };
  }

  List<MapEntry<String, int>> _topReasons({int limit = 5}) {
    final counts = <String, int>{};
    for (final v in _visitsInRange()) {
      final r = v.reason.trim();
      if (r.isEmpty) continue;
      counts[r] = (counts[r] ?? 0) + 1;
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(limit).toList();
  }

  List<MapEntry<String, int>> _topServices({int? limit = 5}) {
    final counts = <String, int>{};
    for (final v in _visitsInRange()) {
      for (final s in v.services) {
        final n = s.trim();
        if (n.isEmpty) continue;
        counts[n] = (counts[n] ?? 0) + 1;
      }
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return limit == null ? sorted : sorted.take(limit).toList();
  }

  List<MapEntry<String, int>> _topInstitutes({int limit = 5}) {
    final counts = <String, int>{};
    for (final v in _visitsInRange()) {
      final i = v.instituteCode.trim();
      if (i.isEmpty) continue;
      counts[i] = (counts[i] ?? 0) + 1;
    }
    final sorted = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return sorted.take(limit).toList();
  }

  List<MapEntry<String, int>> _repeatVisitors({int limit = 5}) {
    final counts = <String, int>{};
    for (final v in _visitsInRange()) {
      final key = '${v.displayName}|${v.personId}';
      counts[key] = (counts[key] ?? 0) + 1;
    }
    final repeats = counts.entries.where((e) => e.value >= 2).toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return repeats.take(limit).toList();
  }

  DateTimeRange? _previousRangeFor(String view) {
    final range = _rangeFor(view);
    if (range == null) return null;
    final days = range.duration.inDays + 1;
    final prevEnd = range.start.subtract(const Duration(days: 1));
    final prevStart = prevEnd.subtract(Duration(days: days - 1));
    return DateTimeRange(start: prevStart, end: prevEnd);
  }

  /// Visits in the previous period; null when a comparison makes no sense
  /// (school year view or an unpicked custom range).
  int? get _previousTotalVisits {
    final range = _previousRangeFor(_selectedView);
    if (range == null) return null;
    return _visits.where((v) {
      final d = v.visitDate;
      if (d == null) return false;
      final day = DateTime(d.year, d.month, d.day);
      return !day.isBefore(range.start) && !day.isAfter(range.end);
    }).length;
  }

  Future<void> _pickInsightsDateRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: _insightsCustomRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(primary: kTeal),
          ),
          child: Dialog(
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
              child: child,
            ),
          ),
        );
      },
    );
    if (range != null) {
      setState(() {
        _insightsCustomRange = range;
        _selectedView = 'Custom';
        _page = 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 18, 24, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_loadingVisits) const _LoadingBar(),
                  if (_visitsError != null) _errorBanner(),
                  const SizedBox(height: 2),
                  _buildVisitationSummaryCard(),
                  const SizedBox(height: 18),
                  _breakdownAndServicesRow(),
                  const SizedBox(height: 18),
                  _buildRecordsCard(),
                  const SizedBox(height: 18),
                  _twoUp(_topInstitutesCard(), _lowStockCard()),
                  const SizedBox(height: 18),
                  _frequentVisitorsCard(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [kTeal, AppColors.primaryDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.bar_chart_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Reports',
                    style: TextStyle(
                        color: kTextDark,
                        fontWeight: FontWeight.w800,
                        fontSize: 22)),
                SizedBox(height: 2),
                Text('Clinic insights for TCGC Clinic',
                    style: TextStyle(color: kTextMuted, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _errorBanner() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.dangerContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFCA5A5)),
      ),
      child: Row(children: [
        const Icon(Icons.cloud_off_rounded, size: 18, color: AppColors.danger),
        const SizedBox(width: 10),
        Expanded(
          child: Text('Could not load visit records: $_visitsError',
              style: const TextStyle(color: AppColors.danger, fontSize: 12.5)),
        ),
        TextButton(onPressed: _loadVisits, child: const Text("Retry")),
      ]),
    );
  }

  Widget _buildVisitationSummaryCard() {
    final data = _currentViewData;
    final prev = _previousTotalVisits;

    final metrics = <Map<String, dynamic>>[
      {
        'label': 'Total Visits',
        'value': (data['Total'] ?? 0).toInt(),
        'color': kTeal,
        'icon': Icons.groups_rounded,
        if (prev != null) 'delta': (data['Total'] ?? 0).toInt() - prev,
      },
      {
        'label': 'Students',
        'value': (data['Students'] ?? 0).toInt(),
        'color': AppColors.student,
        'icon': Icons.school_outlined,
      },
      {
        'label': 'Faculty',
        'value': (data['Faculty'] ?? 0).toInt(),
        'color': AppColors.faculty,
        'icon': Icons.co_present_outlined,
      },
      {
        'label': 'Staff',
        'value': (data['Staff'] ?? 0).toInt(),
        'color': AppColors.staff,
        'icon': Icons.badge_outlined,
      },
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kBorder),
            boxShadow: const [
              BoxShadow(
                  color: Color(0x0A0F172A),
                  blurRadius: 16,
                  offset: Offset(0, 6)),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              LayoutBuilder(builder: (context, constraints) {
                final title = Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                          color: kTeal.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.insights_rounded,
                          size: 18, color: kTeal),
                    ),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('VISITATION SUMMARY',
                              style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: kTeal,
                                  letterSpacing: 1.1)),
                          Text('Real-time data for $_selectedViewLabel',
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 12, color: kTextMuted)),
                        ],
                      ),
                    ),
                  ],
                );
                if (constraints.maxWidth < 1000) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      title,
                      const SizedBox(height: 12),
                      _buildFilterBar(alignEnd: false),
                    ],
                  );
                }
                // Wide: filters sit on the right, level with the title.
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(flex: 2, child: title),
                    const SizedBox(width: 16),
                    Expanded(flex: 5, child: _buildFilterBar(alignEnd: true)),
                  ],
                );
              }),
              const SizedBox(height: 22),
              LayoutBuilder(builder: (context, constraints) {
                final isSmall = constraints.maxWidth < 700;
                return isSmall
                    ? Column(children: _metricWidgets(metrics, true))
                    : Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: _metricWidgets(metrics, false));
              }),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _outOfStockBanner(),
      ],
    );
  }

  // ── Filters: view selector + school year/semester ─────────────────────

  Widget _buildFilterBar({required bool alignEnd}) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: alignEnd ? WrapAlignment.end : WrapAlignment.start,
      runAlignment: alignEnd ? WrapAlignment.end : WrapAlignment.start,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _buildViewSelector(),
        if (_selectedView == 'School Year') ...[
          _filterDropdown(
            icon: Icons.event_note_rounded,
            value: _selectedAcadYear,
            options: ['All', ..._availableAcadYears],
            allLabel: 'All Years',
            onChanged: (v) => setState(() {
              _selectedAcadYear = v;
              _selectedSemester = 'All';
              _page = 0;
            }),
          ),
          // Semester only shows once a specific school year is picked.
          if (_selectedAcadYear != 'All')
            _filterDropdown(
              icon: Icons.calendar_view_month_rounded,
              value: _selectedSemester,
              options: ['All', ..._availableSemesters],
              allLabel: 'All Semesters',
              onChanged: (v) => setState(() {
                _selectedSemester = v;
                _page = 0;
              }),
            ),
        ],
      ],
    );
  }

  Widget _filterDropdown({
    required IconData icon,
    required String value,
    required List<String> options,
    required String allLabel,
    required ValueChanged<String> onChanged,
    String Function(String)? labelOf,
  }) {
    final safe = options.contains(value) ? value : 'All';
    final active = safe != 'All';
    return Container(
      height: 42,
      padding: const EdgeInsets.only(left: 12, right: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: active ? kTeal : kBorder),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: active ? kTeal : kTextMuted),
          const SizedBox(width: 8),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: safe,
              isDense: true,
              borderRadius: BorderRadius.circular(12),
              icon: const Icon(Icons.keyboard_arrow_down_rounded,
                  size: 18, color: kTextMuted),
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: kTextDark),
              items: [
                for (final o in options)
                  DropdownMenuItem(
                    value: o,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: Text(
                          o == 'All' ? allLabel : (labelOf?.call(o) ?? o),
                          overflow: TextOverflow.ellipsis),
                    ),
                  ),
              ],
              onChanged: (v) {
                if (v == null) return;
                onChanged(v);
              },
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _metricWidgets(
      List<Map<String, dynamic>> metrics, bool isMobile) {
    return List.generate(metrics.length, (i) {
      final m = metrics[i];
      return Padding(
        padding: EdgeInsets.symmetric(vertical: isMobile ? 10 : 0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                  color: (m['color'] as Color).withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(12)),
              child: Icon(m['icon'] as IconData,
                  color: m['color'] as Color, size: 22),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${m['value']}',
                    style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w900,
                        color: kTextDark)),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(m['label'] as String,
                        style: const TextStyle(
                            fontSize: 13,
                            color: kTextMuted,
                            fontWeight: FontWeight.w600)),
                    if (m['delta'] != null) ...[
                      const SizedBox(width: 7),
                      _deltaChip(m['delta'] as int),
                    ],
                  ],
                ),
              ],
            ),
            if (!isMobile && metrics.last != m)
              Padding(
                padding: const EdgeInsets.only(left: 26),
                child: Container(width: 1.2, height: 40, color: kBorder),
              ),
          ],
        ),
      );
    });
  }

  Widget _deltaChip(int delta) {
    final bool flat = delta == 0;
    final bool up = delta > 0;
    final Color color =
        flat ? kTextMuted : (up ? AppColors.success : AppColors.danger);
    final String text = flat ? 'no change' : '${delta.abs()} vs prev';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(6)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(
            flat
                ? Icons.remove
                : (up ? Icons.arrow_upward : Icons.arrow_downward),
            size: 11,
            color: color),
        const SizedBox(width: 3),
        Text(text,
            style: TextStyle(
                fontSize: 10.5, fontWeight: FontWeight.w700, color: color)),
      ]),
    );
  }

  Widget _outOfStockBanner() {
    final count = int.tryParse(_outOfStockCount) ?? 0;
    final bool hasIssue = count > 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color:
            hasIssue ? AppColors.dangerContainer : AppColors.successContainer,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color:
                hasIssue ? const Color(0xFFFECACA) : const Color(0xFFBBF7D0)),
      ),
      child: Row(
        children: [
          Icon(
              hasIssue
                  ? Icons.warning_amber_rounded
                  : Icons.check_circle_outline,
              color: hasIssue ? AppColors.danger : AppColors.success,
              size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              hasIssue
                  ? '$count medicine${count > 1 ? 's' : ''} out of stock - please review inventory'
                  : 'All medicines are sufficiently stocked',
              style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: hasIssue ? AppColors.danger : const Color(0xFF166534)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildViewSelector() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kBorder)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: _views.map((view) {
          final isSelected = _selectedView == view;
          return GestureDetector(
            onTap: () {
              if (view == 'Custom') {
                _pickInsightsDateRange();
              } else {
                setState(() {
                  _selectedView = view;
                  _page = 0;
                });
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: isSelected ? kTeal : Colors.white,
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(view,
                  style: TextStyle(
                      fontSize: 13,
                      color: isSelected ? Colors.white : kTextMuted,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.w600)),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── Patient breakdown (small, counts only) + services ─────────────────

  /// Patient Breakdown sits in a small container on the left; Services &
  /// Reasons takes the rest of the row. On narrow screens they stack.
  Widget _breakdownAndServicesRow() {
    return LayoutBuilder(builder: (context, constraints) {
      final breakdown = _buildDemographicCard();
      final services = _servicesReasonsCard();
      if (constraints.maxWidth < 900) {
        return Column(
          children: [breakdown, const SizedBox(height: 18), services],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 290, child: breakdown),
          const SizedBox(width: 18),
          Expanded(child: services),
        ],
      );
    });
  }

  Widget _buildDemographicCard() {
    final data = _currentViewData;
    final total = (data['Total'] ?? 0).toInt();

    return _sectionCard(
      icon: Icons.donut_large_rounded,
      title: 'Patient Breakdown',
      subtitle: 'Tap a group to filter the records below',
      child: Column(
        children: [
          _countRow('Student', 'Student', (data['Students'] ?? 0).toInt(),
              AppColors.student, Icons.school_outlined),
          _countRow('Faculty', 'Faculty', (data['Faculty'] ?? 0).toInt(),
              AppColors.faculty, Icons.co_present_outlined),
          _countRow('Staff', 'Staff', (data['Staff'] ?? 0).toInt(),
              AppColors.staff, Icons.badge_outlined),
          const SizedBox(height: 2),
          const Divider(height: 1, color: kBorder),
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 12, 4, 0),
            child: Row(
              children: [
                const Expanded(
                  child: Text('Total visits',
                      style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: kTextMuted)),
                ),
                Text('$total',
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: kTextDark)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _countRow(
      String personType, String label, int count, Color color, IconData icon) {
    final selected = _recordType == personType;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() {
          _recordType = selected ? 'All' : personType;
          _page = 0;
        }),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
          decoration: BoxDecoration(
            color:
                selected ? color.withValues(alpha: 0.08) : const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? color : kBorder),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(9)),
                child: Icon(icon, color: color, size: 16),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(label,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: kTextDark)),
              ),
              Text('$count',
                  style: TextStyle(
                      fontWeight: FontWeight.w900, color: color, fontSize: 18)),
            ],
          ),
        ),
      ),
    );
  }

  // ── Lazy loading of full service details ──────────────────────────────

  void _requestDetails(List<_ReportVisit> visits) {
    final missing = [
      for (final v in visits)
        if (v.visitId.isNotEmpty && !_detailsRequested.contains(v.visitId))
          v.visitId
    ];
    if (missing.isEmpty) return;
    _detailsRequested.addAll(missing);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadDetails(missing));
  }

  Future<void> _loadDetails(List<String> ids) async {
    const chunk = 40;
    for (var i = 0; i < ids.length; i += chunk) {
      final part = ids.sublist(i, (i + chunk).clamp(0, ids.length));
      try {
        final got = await VisitDetailsService.readVisits(part);
        _details.addAll(got);
      } catch (_) {}
      _detailsDone.addAll(part);
      if (!mounted) return;
      setState(() {});
    }
  }

  // ── Visit Records table ───────────────────────────────────────────────

  static const Color _ink = AppColors.textMain;
  static const Color _soft = Color(0xFFF8FAFC);

  /// Visits of the chosen period, narrowed by visitor type and service.
  /// For a vital-sign sub-service this is every visit that has vital signs
  /// (their details are loaded, then [_recordRows] keeps the right ones).
  List<_ReportVisit> _candidateRows() {
    final svc = _recordService;
    return _visitsInRange().where((v) {
      if (_recordType != 'All' && v.personType != _recordType) return false;
      if (svc == 'All') return true;
      if (_vitalSubs.contains(svc)) return v.services.any(_isVitalName);
      return v.services.contains(svc);
    }).toList();
  }

  List<_ReportVisit> _recordRows() {
    final list = _candidateRows();
    if (_vitalSubs.contains(_recordService)) {
      return list.where((v) => _hasVitalSub(v, _recordService)).toList();
    }
    return list;
  }

  /// Same patient + same day (AM and PM visits) become ONE row, just like
  /// the Records Booklet. Newest day first.
  List<List<_ReportVisit>> _recordGroups() {
    final map = <String, List<_ReportVisit>>{};
    for (final v in _recordRows()) {
      final d = v.visitDate;
      final day = d == null ? '' : '${d.year}-${d.month}-${d.day}';
      final who = v.personId.isNotEmpty ? v.personId : v.displayName;
      map.putIfAbsent('$who|$day', () => []).add(v);
    }
    final groups = map.values.toList();
    for (final g in groups) {
      g.sort((a, b) => _minutes(a.visitTime).compareTo(_minutes(b.visitTime)));
    }
    groups.sort((a, b) {
      final da = a.first.visitDate;
      final db = b.first.visitDate;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      final c = db.compareTo(da);
      return c != 0
          ? c
          : _minutes(b.last.visitTime).compareTo(_minutes(a.last.visitTime));
    });
    return groups;
  }

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// Finds the service form (draft) of a visit that belongs to [service].
  ServiceDraft? _matchDraft(
      VisitDetailsController c, _ReportVisit v, String service) {
    final drafts = c.drafts;
    if (drafts.isEmpty) return null;

    // A vital-sign sub-service (BP Taking, ...) lives in the vital_signs form.
    if (_vitalSubs.contains(service)) {
      for (final d in drafts) {
        if (d.serviceId == 'vital_signs') return d;
      }
      return null;
    }

    final name = _norm(service);
    final code = _norm(v.serviceCodes[service] ?? '');
    for (final d in drafts) {
      if (_norm(d.label) == name ||
          _norm(d.shortLabel) == name ||
          _norm(d.serviceId) == name ||
          (code.isNotEmpty && _norm(d.serviceId) == code)) {
        return d;
      }
    }
    if (name.length >= 3) {
      for (final d in drafts) {
        final l = _norm(d.label);
        if (l.isNotEmpty && (l.contains(name) || name.contains(l))) return d;
      }
    }
    if (v.services.length == 1 && drafts.length == 1) return drafts.first;
    return null;
  }

  /// The recorded answers of [service] on visit [v], as label -> value.
  _ServiceCells? _serviceCells(_ReportVisit v, String service) {
    final c = _details[v.visitId];
    if (c == null) return null;
    final d = _matchDraft(c, v, service);
    if (d == null) return null;
    final isSub = _vitalSubs.contains(service);
    final values = <String, String>{};
    final plain = <String>[];
    final sections = serviceSummary(
      d,
      c.vitals,
      canSeeRestricted: AccountService.canSeeRestrictedCounselling,
    );
    for (final sec in sections) {
      for (final r in sec.rows) {
        final label = r.label.trim();
        final value = r.value.trim();
        if (label.isEmpty && value.isEmpty) continue;
        if (label.isEmpty) {
          plain.add(value);
          continue;
        }
        if (isSub && !_keepVitalLabel(service, label)) continue;
        values[label] = value.isEmpty ? '—' : value;
      }
    }
    if (plain.isNotEmpty) values['Other details'] = plain.join('; ');
    return _ServiceCells(values, d.status.label);
  }

  /// Pill at the right of the card header: the period the table covers.
  Widget _dateRangePill() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: kTeal.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kTeal.withValues(alpha: 0.25)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.calendar_today_outlined, size: 14, color: kTeal),
        const SizedBox(width: 7),
        Text(_periodDateLabel(),
            style: const TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w700, color: kTeal)),
      ]),
    );
  }

  Widget _buildRecordsCard() {
    final groups = _recordGroups();
    final total = groups.length;
    final patients = {
      for (final g in groups)
        g.first.personId.isNotEmpty ? g.first.personId : g.first.displayName
    }.length;

    final pageCount = total == 0 ? 1 : (total + _pageSize - 1) ~/ _pageSize;
    final page = _page.clamp(0, pageCount - 1).toInt();
    final start = page * _pageSize;
    final end = (start + _pageSize) > total ? total : start + _pageSize;
    final pageGroups = groups.sublist(start, end);
    final pageVisits = [for (final g in pageGroups) ...g];

    final service = _recordService;
    final specific = service != 'All';

    // A chosen service shows its answers as columns, so every matching visit
    // needs its details; otherwise only the visible page does.
    final candidates = specific ? _candidateRows() : pageVisits;
    _requestDetails(candidates);

    final cells = <String, _ServiceCells>{};
    final columns = <String>[];
    var pending = 0;
    if (specific) {
      for (final v in candidates) {
        if (v.visitId.isNotEmpty && !_detailsDone.contains(v.visitId)) {
          pending++;
        }
      }
      for (final g in groups) {
        for (final v in g) {
          final sc = _serviceCells(v, service);
          if (sc == null) continue;
          cells[v.visitId] = sc;
          for (final k in sc.values.keys) {
            if (!columns.contains(k)) columns.add(k);
          }
        }
      }
    }

    final subtitle = total == 0
        ? (pending > 0
            ? 'Loading records…'
            : 'No records for the current filters')
        : '$total record${total == 1 ? '' : 's'} · '
            '$patients patient${patients == 1 ? '' : 's'}';

    return _sectionCard(
      icon: Icons.table_chart_outlined,
      title: specific ? 'Visit Records · $service' : 'Visit Records',
      subtitle: subtitle,
      trailing: _dateRangePill(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _recordFilters(),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: Text(
                  specific
                      ? 'Showing what was recorded for $service. Use the eye icon to open the whole visit.'
                      : 'Pick a service to see its recorded details as columns.',
                  style: const TextStyle(fontSize: 11.5, color: kTextMuted),
                ),
              ),
            ],
          ),
          if (specific && pending > 0)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('Loading service details… ($pending left)',
                  style: const TextStyle(fontSize: 11.5, color: kTextMuted)),
            ),
          const SizedBox(height: 12),
          if (total == 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 28),
              decoration: BoxDecoration(
                color: _soft,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: kBorder),
              ),
              child: Center(
                child: Text(
                    pending > 0
                        ? 'Loading records…'
                        : 'No records match the current filters.',
                    style: const TextStyle(color: kTextMuted, fontSize: 13)),
              ),
            )
          else ...[
            _tableShell(
              _recordsTable(pageGroups, start, service, columns, cells),
            ),
            const SizedBox(height: 10),
            _pager(page, pageCount, total, start, end),
          ],
        ],
      ),
    );
  }

  Widget _recordFilters() {
    final active = _recordType != 'All' || _recordService != 'All';
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _filterDropdown(
          icon: Icons.people_outline_rounded,
          value: _recordType,
          options: _visitorTypes,
          allLabel: 'All Visitors',
          onChanged: (v) => setState(() {
            _recordType = v;
            _page = 0;
          }),
        ),
        _filterDropdown(
          icon: Icons.medical_services_outlined,
          value: _recordService,
          options: _serviceOptions,
          allLabel: 'All Services',
          labelOf: (o) => _vitalSubs.contains(o) ? '↳ $o' : o,
          onChanged: (v) => setState(() {
            _recordService = v;
            _page = 0;
          }),
        ),
        if (active)
          TextButton.icon(
            onPressed: () => setState(() {
              _recordType = 'All';
              _recordService = 'All';
              _page = 0;
            }),
            icon: const Icon(Icons.close_rounded, size: 16),
            label: const Text('Clear'),
          ),
      ],
    );
  }

  Widget _tableShell(Widget table) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: LayoutBuilder(builder: (context, constraints) {
          return ScrollConfiguration(
            behavior: ScrollConfiguration.of(context).copyWith(
              dragDevices: {
                PointerDeviceKind.touch,
                PointerDeviceKind.mouse,
                PointerDeviceKind.trackpad,
              },
            ),
            child: Scrollbar(
              controller: _tableScroll,
              thumbVisibility: true,
              trackVisibility: true,
              child: SingleChildScrollView(
                controller: _tableScroll,
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(bottom: 14),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minWidth: constraints.maxWidth),
                  child: table,
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _recordsTable(
    List<List<_ReportVisit>> rows,
    int startIndex,
    String service,
    List<String> columns,
    Map<String, _ServiceCells> cells,
  ) {
    final specific = service != 'All';
    final headers = <String>[
      'No.',
      'Time In – Out',
      'Name',
      'Type',
      'Institute / Program',
      if (!specific) ...['Reason', 'Services'] else ...[...columns, 'Status'],
      'Record',
    ];

    return DataTable(
      headingRowHeight: 46,
      dataRowMinHeight: 46,
      dataRowMaxHeight: 70,
      headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
      headingTextStyle: const TextStyle(
          fontWeight: FontWeight.w800,
          color: kTextMuted,
          fontSize: 11.5,
          letterSpacing: 0.6),
      dataTextStyle: const TextStyle(color: _ink, fontSize: 13),
      columnSpacing: 22,
      horizontalMargin: 16,
      dividerThickness: 1,
      border: const TableBorder(
        horizontalInside: BorderSide(color: kBorder, width: 0.8),
      ),
      columns: [for (final h in headers) DataColumn(label: Text(h))],
      rows: [
        for (final (i, g) in rows.indexed)
          _recordDataRow(i, startIndex, g, specific, columns, cells),
      ],
    );
  }

  /// One column value for a (possibly AM + PM) row. When the two sessions
  /// differ they are shown as "AM: ..." / "PM: ...".
  String _groupCell(List<_ReportVisit> g, Map<String, _ServiceCells> cells,
      String col, String blank) {
    final parts = <(_ReportVisit, String)>[];
    for (final v in g) {
      final x = cells[v.visitId]?.values[col];
      if (x != null && x.isNotEmpty) parts.add((v, x));
    }
    if (parts.isEmpty) return blank;
    final distinct = parts.map((p) => p.$2).toSet();
    if (distinct.length == 1 || g.length == 1) return parts.first.$2;
    return parts
        .map((p) => '${_isMorning(p.$1) ? 'AM' : 'PM'}: ${p.$2}')
        .join('\n');
  }

  DataRow _recordDataRow(
    int i,
    int startIndex,
    List<_ReportVisit> g,
    bool specific,
    List<String> columns,
    Map<String, _ServiceCells> cells,
  ) {
    final v = g.first;
    final waiting =
        g.any((x) => x.visitId.isNotEmpty && !_detailsDone.contains(x.visitId));
    final blank = waiting ? '…' : '—';

    final statuses = <String>[];
    for (final x in g) {
      final s = cells[x.visitId]?.status ?? '';
      if (s.isNotEmpty && !statuses.contains(s)) statuses.add(s);
    }

    final reasons = <String>[];
    for (final x in g) {
      if (x.reason.isNotEmpty && !reasons.contains(x.reason)) {
        reasons.add(x.reason);
      }
    }

    final services = <String>[];
    for (final x in g) {
      for (final s in _displayServices(x)) {
        if (!services.contains(s)) services.add(s);
      }
    }

    return DataRow(
      color: WidgetStateProperty.resolveWith((s) {
        if (s.contains(WidgetState.hovered)) {
          return kTeal.withValues(alpha: 0.04);
        }
        return i.isEven ? Colors.white : const Color(0xFFFAFCFD);
      }),
      cells: [
        DataCell(Text('${startIndex + i + 1}')),
        DataCell(Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (final x in g) Text(_sessionTimes(x)),
          ],
        )),
        DataCell(_wrapCell(v.displayName, maxWidth: 200, bold: true)),
        DataCell(_typePill(v.personType)),
        DataCell(_wrapCell(v.affiliation.isEmpty ? '—' : v.affiliation,
            maxWidth: 200)),
        if (!specific) ...[
          DataCell(_wrapCell(reasons.isEmpty ? '—' : reasons.join(' / '),
              maxWidth: 240)),
          DataCell(_wrapCell(services.isEmpty ? '—' : services.join(', '),
              maxWidth: 260)),
        ] else ...[
          for (final col in columns)
            DataCell(_wrapCell(_groupCell(g, cells, col, blank))),
          DataCell(Text(statuses.isNotEmpty ? statuses.join(' / ') : blank)),
        ],
        DataCell(
          IconButton(
            tooltip: 'View full record',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.visibility_outlined, size: 18, color: kTeal),
            onPressed: () => _openGroup(g),
          ),
        ),
      ],
    );
  }

  Widget _wrapCell(String text, {double maxWidth = 220, bool bold = false}) {
    final child = ConstrainedBox(
      constraints: BoxConstraints(maxWidth: maxWidth),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: bold ? const TextStyle(fontWeight: FontWeight.w600) : null,
      ),
    );
    if (text.length < 28) return child;
    return Tooltip(message: text, child: child);
  }

  Color _typeColor(String type) {
    switch (type) {
      case 'Student':
        return AppColors.student;
      case 'Faculty':
        return AppColors.faculty;
      case 'Staff':
        return AppColors.staff;
      default:
        return kTextMuted;
    }
  }

  Widget _typePill(String type) {
    final color = _typeColor(type);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(type.isEmpty ? '—' : type,
          style: TextStyle(
              fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
    );
  }

  Widget _pager(int page, int pageCount, int total, int start, int end) {
    return Row(
      children: [
        Text('Showing ${start + 1}–$end of $total',
            style: const TextStyle(fontSize: 12, color: kTextMuted)),
        const Spacer(),
        IconButton(
          tooltip: 'Previous page',
          visualDensity: VisualDensity.compact,
          onPressed: page > 0 ? () => setState(() => _page = page - 1) : null,
          icon: const Icon(Icons.chevron_left_rounded),
        ),
        Text('Page ${page + 1} of $pageCount',
            style: const TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: kTextDark)),
        IconButton(
          tooltip: 'Next page',
          visualDensity: VisualDensity.compact,
          onPressed: page < pageCount - 1
              ? () => setState(() => _page = page + 1)
              : null,
          icon: const Icon(Icons.chevron_right_rounded),
        ),
      ],
    );
  }

  /// Opens the whole visit day (reason + every service with all its answers).
  /// An AM + PM pair opens together, one section per session.
  Future<void> _openGroup(List<_ReportVisit> g) async {
    final missing = [
      for (final v in g)
        if (v.visitId.isNotEmpty &&
            !_details.containsKey(v.visitId) &&
            !_detailsDone.contains(v.visitId))
          v.visitId
    ];
    if (missing.isNotEmpty) {
      _detailsRequested.addAll(missing);
      await _loadDetails(missing);
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => _visitDialog(ctx, g),
    );
  }

  int _cardCount(_ReportVisit v) {
    final c = _details[v.visitId];
    if (c != null && c.drafts.isNotEmpty) return c.drafts.length;
    return _detailsDone.contains(v.visitId) || c != null ? v.services.length : 0;
  }

  Widget _sessionBanner(_ReportVisit v) {
    final am = _isMorning(v);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: kTeal.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kTeal.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        Icon(am ? Icons.wb_sunny_outlined : Icons.nights_stay_outlined,
            size: 17, color: kTeal),
        const SizedBox(width: 8),
        Text('${_sessionLabel(v)} visit  ·  ${_sessionTimes(v)}',
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: AppColors.primaryDark)),
      ]),
    );
  }

  Widget _reasonBox(_ReportVisit v) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kTeal.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kTeal.withValues(alpha: 0.20)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.chat_bubble_outline_rounded, size: 18, color: kTeal),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('REASON FOR VISIT',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.7,
                        color: kTeal)),
                const SizedBox(height: 3),
                Text(
                  v.reason.isEmpty ? 'No reason recorded' : v.reason,
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: v.reason.isEmpty ? kTextMuted : kTextDark),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Reason + services of ONE visit (one session) inside the dialog.
  List<Widget> _visitSection(_ReportVisit v, {required bool multi}) {
    final controller = _details[v.visitId];
    final loading = controller == null && !_detailsDone.contains(v.visitId);

    final cards = <Widget>[];
    if (controller != null && controller.drafts.isNotEmpty) {
      for (final d in controller.drafts) {
        cards.add(_dialogServiceCard(
          title: d.serviceId == 'vital_signs'
              ? _vitalLabel(d, controller.vitals)
              : d.label,
          status: d.status.label,
          sections: serviceSummary(
            d,
            controller.vitals,
            canSeeRestricted: AccountService.canSeeRestrictedCounselling,
          ),
        ));
      }
    } else if (!loading) {
      // Details could not be read: still list every service by name.
      for (final n in v.services) {
        cards.add(_dialogServiceCard(title: n, status: '', sections: const []));
      }
    }

    return [
      if (multi) _sessionBanner(v),
      _reasonBox(v),
      const SizedBox(height: 18),
      Row(children: [
        const Text('SERVICES',
            style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                letterSpacing: 0.8,
                color: kTextMuted)),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: kTeal.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text('${cards.length}',
              style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: kTeal)),
        ),
      ]),
      const SizedBox(height: 10),
      if (loading)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text('Loading service details...',
              style: TextStyle(fontSize: 12.5, color: kTextMuted)),
        )
      else if (cards.isEmpty)
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16),
          child: Text('No services on this visit.',
              style: TextStyle(fontSize: 12.5, color: kTextMuted)),
        )
      else
        ...cards,
    ];
  }

  Widget _visitDialog(BuildContext ctx, List<_ReportVisit> g) {
    final v = g.first;
    final initial =
        v.displayName.isEmpty ? '?' : v.displayName[0].toUpperCase();
    final multi = g.length > 1;
    final serviceCount = g.fold<int>(0, (s, x) => s + _cardCount(x));

    final date = v.visitDate == null ? '' : _fmtDate(v.visitDate!);
    final time = g
        .where((x) => x.visitTime.isNotEmpty)
        .map(_sessionTimes)
        .join('  |  ');

    return Dialog(
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 780, maxHeight: 700),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Header ──
            Container(
              padding: const EdgeInsets.fromLTRB(22, 18, 10, 18),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [kTeal, AppColors.primaryDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.18),
                      shape: BoxShape.circle,
                    ),
                    child: Text(initial,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(v.displayName,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.w800)),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            if (v.personId.isNotEmpty)
                              _headerPill(v.personId, Icons.badge_outlined),
                            if (v.personType.isNotEmpty)
                              _headerPill(
                                  v.personType, Icons.person_outline_rounded),
                            if (v.affiliation.isNotEmpty)
                              _headerPill(v.affiliation, Icons.apartment_rounded),
                          ],
                        ),
                        if (date.isNotEmpty || time.isNotEmpty) ...[
                          const SizedBox(height: 10),
                          Row(children: [
                            const Icon(Icons.calendar_today_outlined,
                                size: 13, color: Colors.white70),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                [date, time]
                                    .where((e) => e.isNotEmpty)
                                    .join('  ·  '),
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12.5),
                              ),
                            ),
                          ]),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                    onPressed: () => Navigator.of(ctx).pop(),
                  ),
                ],
              ),
            ),

            // ── Body (scrolls when there are many details) ──
            Flexible(
              child: _ScrollBox(
                builder: (sc) => Scrollbar(
                  controller: sc,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: sc,
                    padding: const EdgeInsets.fromLTRB(22, 18, 22, 8),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final (i, x) in g.indexed) ...[
                          if (i > 0) const SizedBox(height: 22),
                          ..._visitSection(x, multi: multi),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // ── Footer ──
            Container(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 14),
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: kBorder)),
              ),
              child: Row(
                children: [
                  Text(
                      '$serviceCount service${serviceCount == 1 ? "" : "s"}'
                      '${multi ? ' · ${g.length} sessions' : ' on this visit'}',
                      style: const TextStyle(fontSize: 12, color: kTextMuted)),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: () => Navigator.of(ctx).pop(),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kTeal,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 22, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('Close',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerPill(String text, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: Colors.white),
        const SizedBox(width: 5),
        Text(text,
            style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.white)),
      ]),
    );
  }

  /// One service on the visit: coloured title bar + status, then its answers
  /// as small label/value tiles grouped by section.
  Widget _dialogServiceCard({
    required String title,
    required String status,
    required List<SummarySection> sections,
  }) {
    final hasData = sections.any((s) => s.rows.any(
        (r) => r.value.trim().isNotEmpty || r.label.trim().isNotEmpty));
    final st = status.toLowerCase();
    final Color statusColor = st.contains('complete')
        ? AppColors.success
        : (st.contains('progress') ? AppColors.warning : kTextMuted);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(13),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              color: kTeal.withValues(alpha: 0.06),
              child: Row(
                children: [
                  const Icon(Icons.medical_services_outlined,
                      size: 16, color: kTeal),
                  const SizedBox(width: 9),
                  Expanded(
                    child: Text(title,
                        style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: kTeal)),
                  ),
                  if (status.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 3),
                      decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(status,
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: statusColor)),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 2),
              child: !hasData
                  ? const Padding(
                      padding: EdgeInsets.only(bottom: 12),
                      child: Text('No record',
                          style: TextStyle(fontSize: 12.5, color: kTextMuted)),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final sec in sections)
                          if (sec.rows.isNotEmpty) _dialogSection(sec),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dialogSection(SummarySection sec) {
    final rows = [
      for (final r in sec.rows)
        if (r.label.trim().isNotEmpty || r.value.trim().isNotEmpty) r
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (sec.title.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                Container(
                  width: 3,
                  height: 12,
                  decoration: BoxDecoration(
                    color: kTeal,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(width: 7),
                Text(sec.title.toUpperCase(),
                    style: const TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w800,
                        color: kTextMuted,
                        letterSpacing: 0.7)),
              ]),
            ),
          LayoutBuilder(builder: (context, c) {
            const gap = 10.0;
            final twoCol = c.maxWidth > 460;
            final colW = twoCol ? (c.maxWidth - gap) / 2 : c.maxWidth;
            return Wrap(
              spacing: gap,
              runSpacing: gap,
              children: [
                for (final r in rows)
                  SizedBox(
                    // Long answers (notes, remarks) take the full row.
                    width: (r.value.length > 60 || r.label.trim().isEmpty)
                        ? c.maxWidth
                        : colW,
                    child: _dialogCell(r.label, r.value),
                  ),
              ],
            );
          }),
        ],
      ),
    );
  }

  Widget _dialogCell(String label, String value) {
    final shown = value.trim().isEmpty ? '—' : value.trim();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: _soft,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (label.trim().isNotEmpty) ...[
            Text(label.trim(),
                style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: kTextMuted)),
            const SizedBox(height: 3),
          ],
          Text(shown,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: _ink,
                  height: 1.3)),
        ],
      ),
    );
  }

  // ── Services & reasons ────────────────────────────────────────────────

  Widget _servicesReasonsCard() {
    final allServices = _topServices(limit: null);
    final services =
        _showAllServices ? allServices : allServices.take(5).toList();
    final reasons = _topReasons();
    return _sectionCard(
      icon: Icons.summarize_outlined,
      title: 'Services & Reasons for Visit',
      subtitle: 'Tap a service to see its records in the table below',
      trailing: allServices.length > 5
          ? TextButton(
              onPressed: () =>
                  setState(() => _showAllServices = !_showAllServices),
              child: Text(_showAllServices
                  ? 'Show top 5'
                  : 'Show all (${allServices.length})'),
            )
          : null,
      child: LayoutBuilder(builder: (context, constraints) {
        final narrow = constraints.maxWidth < 560;
        final left = _miniRanked(
          'Services performed',
          Icons.medical_services_outlined,
          kTeal,
          services,
          onTap: (name) => setState(() {
            _recordService = name;
            _page = 0;
          }),
        );
        final right = _miniRanked(
          'Reasons for Visit',
          Icons.sick_outlined,
          const Color(0xFFEA580C),
          reasons,
        );
        if (narrow) {
          return Column(children: [left, const SizedBox(height: 20), right]);
        }
        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: left),
              const SizedBox(width: 22),
              Container(width: 1, color: kBorder),
              const SizedBox(width: 22),
              Expanded(child: right),
            ],
          ),
        );
      }),
    );
  }

  Widget _miniRanked(String title, IconData icon, Color color,
      List<MapEntry<String, int>> entries,
      {ValueChanged<String>? onTap}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 7),
          Text(title.toUpperCase(),
              style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                  color: color,
                  letterSpacing: 0.6)),
        ]),
        const SizedBox(height: 12),
        _rankedList(
            entries: entries, unitLabel: 'visits', color: color, onTap: onTap),
      ],
    );
  }

  Widget _lowStockCard() {
    final low = _lowStockMedicines();
    return _sectionCard(
      icon: Icons.warning_amber_rounded,
      title: 'Low Stock Medicines',
      subtitle: 'Medicines running low or already out of stock',
      trailing: low.isEmpty
          ? null
          : Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.dangerContainer,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text('${low.length}',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: AppColors.danger)),
            ),
      child: low.isEmpty
          ? Row(children: const [
              Icon(Icons.check_circle_outline,
                  size: 18, color: AppColors.success),
              SizedBox(width: 8),
              Expanded(
                child: Text('All medicines are sufficiently stocked.',
                    style: TextStyle(color: kTextMuted, fontSize: 13)),
              ),
            ])
          : Column(
              children: [for (final m in low) _lowStockRow(m)],
            ),
    );
  }

  List<Medicine> _lowStockMedicines({int limit = 6}) {
    bool isLow(Medicine m) {
      if (m.stock <= 0) return true;
      if (m.maxCapacity > 0) {
        return m.stock <= (m.maxCapacity * 0.2).ceil();
      }
      return m.stock <= 10;
    }

    final low = _medicines.where(isLow).toList()
      ..sort((a, b) => a.stock.compareTo(b.stock));
    return low.take(limit).toList();
  }

  Widget _lowStockRow(Medicine m) {
    final out = m.stock <= 0;
    final color = out ? AppColors.danger : AppColors.warning;
    final pct =
        m.maxCapacity > 0 ? (m.stock / m.maxCapacity).clamp(0.0, 1.0) : 0.0;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(9),
            ),
            child: Icon(
                out ? Icons.error_outline_rounded : Icons.warning_amber_rounded,
                size: 18,
                color: color),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(m.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        color: kTextDark)),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: pct,
                    minHeight: 6,
                    backgroundColor: kBorder,
                    valueColor: AlwaysStoppedAnimation<Color>(color),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(out ? 'Out of stock' : '${m.stock} left',
              style: TextStyle(
                  fontSize: 11.5, color: color, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }

  Widget _topInstitutesCard() {
    return _sectionCard(
      icon: Icons.apartment_rounded,
      title: 'Consultations by Institute',
      subtitle: 'Where this period\'s visitors come from',
      child: _rankedList(
        entries: _topInstitutes(),
        unitLabel: 'visits',
        color: AppColors.info,
      ),
    );
  }

  Widget _frequentVisitorsCard() {
    return _sectionCard(
      icon: Icons.repeat_rounded,
      title: 'Frequent Visitors',
      subtitle: 'Patients with 2 or more visits in this period',
      child: _frequentVisitorsList(),
    );
  }

  Widget _twoUp(Widget a, Widget b) {
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < 900) {
        return Column(children: [a, const SizedBox(height: 18), b]);
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: a),
          const SizedBox(width: 18),
          Expanded(child: b),
        ],
      );
    });
  }

  Widget _sectionCard({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
    required Widget child,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0A0F172A), blurRadius: 16, offset: Offset(0, 6)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: kTeal.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(10)),
                child: Icon(icon, size: 18, color: kTeal),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                            color: kTextDark)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style:
                            const TextStyle(fontSize: 12, color: kTextMuted)),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 12), trailing],
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _rankedList({
    required List<MapEntry<String, int>> entries,
    required String unitLabel,
    required Color color,
    ValueChanged<String>? onTap,
  }) {
    if (entries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Text('No data yet.',
            style: TextStyle(color: kTextMuted, fontSize: 13)),
      );
    }
    final maxValue = entries.first.value;
    return Column(
      children: List.generate(entries.length, (i) {
        final e = entries[i];
        final pct = maxValue == 0 ? 0.0 : e.value / maxValue;
        final row = Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6)),
                child: Text('${i + 1}',
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        color: color)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(e.key,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: kTextDark)),
                    const SizedBox(height: 6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: LinearProgressIndicator(
                        value: pct,
                        minHeight: 6,
                        backgroundColor: kBorder,
                        valueColor: AlwaysStoppedAnimation<Color>(color),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Text('${e.value} $unitLabel',
                  style: const TextStyle(
                      fontSize: 11.5,
                      color: kTextMuted,
                      fontWeight: FontWeight.w600)),
            ],
          ),
        );
        if (onTap == null) return row;
        return InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => onTap(e.key),
          child: row,
        );
      }),
    );
  }

  Widget _frequentVisitorsList() {
    final repeats = _repeatVisitors();
    if (repeats.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 10),
        child: Text('No repeat visitors in this period.',
            style: TextStyle(color: kTextMuted, fontSize: 13)),
      );
    }
    return Column(
      children: repeats.map((e) {
        final parts = e.key.split('|');
        final name = parts.isNotEmpty && parts[0].trim().isNotEmpty
            ? parts[0]
            : 'Unnamed visitor';
        final id = parts.length > 1 ? parts[1] : '';
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                    color: kTeal.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.person_outline, size: 16, color: kTeal),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: kTextDark)),
                    if (id.isNotEmpty)
                      Text(id,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 11.5, color: kTextMuted)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                    color: kTeal.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(6)),
                child: Text('${e.value} visits',
                    style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: kTeal)),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}

class _LoadingBar extends StatelessWidget {
  const _LoadingBar();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 14),
      child: LinearProgressIndicator(
        minHeight: 3,
        borderRadius: BorderRadius.all(Radius.circular(3)),
      ),
    );
  }
}

/// Owns a ScrollController so a Scrollbar and its scroll view can share it.
class _ScrollBox extends StatefulWidget {
  const _ScrollBox({required this.builder});

  final Widget Function(ScrollController controller) builder;

  @override
  State<_ScrollBox> createState() => _ScrollBoxState();
}

class _ScrollBoxState extends State<_ScrollBox> {
  final ScrollController _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.builder(_controller);
}