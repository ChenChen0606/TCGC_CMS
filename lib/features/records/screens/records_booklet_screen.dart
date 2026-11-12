// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'package:clinicmanagementsystem/core/theme/app_colors.dart';
import 'package:clinicmanagementsystem/core/config/supabase_config.dart';

import 'package:clinicmanagementsystem/features/patients/models/patient_directory.dart';
import 'package:clinicmanagementsystem/features/visits/models/visit_details.dart';
import 'package:clinicmanagementsystem/features/visits/models/visit_service_forms.dart';
import 'package:clinicmanagementsystem/features/vitals/models/vitals.dart';
import 'package:clinicmanagementsystem/features/certificates/models/certificate_engine.dart';
import 'package:clinicmanagementsystem/features/account/services/account_service.dart';
import 'package:clinicmanagementsystem/core/services/data_tracker.dart';
import 'package:clinicmanagementsystem/core/services/reference_data_service.dart';
import 'package:clinicmanagementsystem/features/certificates/services/signatory_store.dart';
import 'package:clinicmanagementsystem/features/visits/services/visit_service.dart';
import 'package:clinicmanagementsystem/features/visits/services/procedure_service.dart';
import 'package:clinicmanagementsystem/features/patients/services/individual_record_service.dart';
import 'package:clinicmanagementsystem/features/visits/services/visit_details_service.dart';
import 'package:clinicmanagementsystem/features/patients/models/individual_record_data.dart';
import 'package:clinicmanagementsystem/features/visits/widgets/visit_review_card.dart';
import 'package:clinicmanagementsystem/features/visits/screens/visit_edit_screen.dart';
import 'package:clinicmanagementsystem/features/records/services/booklet_print.dart';
import 'package:clinicmanagementsystem/shared/widgets/simple_print_preview.dart';
import 'package:clinicmanagementsystem/shared/printing/html_print.dart';
import 'package:clinicmanagementsystem/shared/printing/print_service.dart'
    show medicalCertificateRequirements;

List<Map<String, String>> filterRecordsByInstitute(
    List<Map<String, String>> records, String? institute) {
  if (institute == null) return List<Map<String, String>>.from(records);
  final String want = institute.trim().toLowerCase();
  if (want.isEmpty) return List<Map<String, String>>.from(records);
  return records.where((record) {
    final String dept = (record["dept"] ?? "").trim().toLowerCase();
    return dept.isNotEmpty && dept == want;
  }).toList();
}




enum _PrintReport { service, individual, daily, byInstitute, certificate }

extension _PrintReportText on _PrintReport {
  String get label => switch (this) {
        _PrintReport.service => 'Service Report',
        _PrintReport.individual => 'Individual Client Record',
        _PrintReport.daily => 'Daily Clinic Visit Report',
        _PrintReport.byInstitute => 'Visits by Institute',
        _PrintReport.certificate => 'Medical Certificate',
      };

  String get paperTitle => switch (this) {
        _PrintReport.service => 'SERVICE REPORT',
        _PrintReport.individual => 'INDIVIDUAL CLIENT RECORD',
        _PrintReport.daily => 'DAILY CLINIC VISIT REPORT',
        _PrintReport.byInstitute => 'CLINIC VISITS BY INSTITUTE',
        _PrintReport.certificate => 'MEDICAL CERTIFICATE',
      };
}

typedef _PrintPerson = ({String id, String name});

typedef _Roster = ({
  Map<String, Map<String, String>> facts,
  Map<String, IndividualRecord> byId,
});

class _PrintCriteria {
  const _PrintCriteria({
    required this.report,
    required this.window,
    required this.periodLabel,
    this.services = const [],
    this.institute,
    this.personId,
    this.personName,
    this.blankRows = false,
    this.certVisit,
    this.excusedFor = '',
    this.reason = '',
    this.issuedOn,
    this.signatory = '',
    this.acadYear = '',
    this.semester = '',
  });

  final _PrintReport report;
  final DateTimeRange? window;
  final String periodLabel;
  final List<String> services;
  final String? institute;
  final String? personId;
  final String? personName;
  final bool blankRows;
  final Map<String, String>? certVisit;
  final String excusedFor;
  final String reason;
  final DateTime? issuedOn;
  final String signatory;
  final String acadYear;
  final String semester;
}

typedef _DayGroup = List<Map<String, String>>;

class _VisitState {
  const _VisitState(this.label, this.color);

  final String label;
  final Color color;
}

class RecordsBooklet extends StatefulWidget {
  final bool isActive;

  const RecordsBooklet({super.key, this.isActive = false});

  @override
  State<RecordsBooklet> createState() => RecordsBookletState();
}

class RecordsBookletState extends State<RecordsBooklet> {
  static const Color kPrimary = AppColors.primary;
  static const Color kPrimaryDk = AppColors.primaryDark;
  static const Color kBg = AppColors.bg;
  static const Color kCard = AppColors.surface;
  static const Color kBorder = AppColors.border;
  static const Color kTextMain = AppColors.textMain;
  static const Color kTextDark = AppColors.textDark;
  static const Color kTextSub = AppColors.textSub;
  static const Color kDanger = AppColors.danger;
  static const Color kSuccess = AppColors.success;
  static const Color kWarning = AppColors.warning;

  static const Color kStudentColor = AppColors.student;
  static const Color kFacultyColor = AppColors.faculty;
  static const Color kStaffColor = AppColors.staff;

  static const String _currentUser = "Anna Gonzaga";

  static const List<String> _dateFilterModes = [
    'Today',
    'All',
    'This Week',
    'This Month',
    'Pick Date',
    'Date Range',
    'Academic Year'
  ];

  String selectedFilter = "Today";
  DateTime selectedDate = DateTime.now();
  DateTimeRange? selectedRange;

  int? selectedYear;
  String selectedAcadYear = '';
  String selectedSemester = '';
  String searchQuery = "";
  String selectedInstitute = "";
  String selectedProgram = "";

  // ---- filters: Sex, Age, Birth date ------------------------------------
  String selectedSex = '';
  int? selectedAge;
  DateTimeRange? birthRange;

  static const List<String> _institutes = [
    'IBFS',
    'ICJE',
    'ITE',
    'IHS',
    'ICS',
    'IAS'
  ];

  static const Map<String, String> _instituteNames = {
    'ICS': 'Institute of Computer Science',
    'IAS': 'Institute of Arts and Sciences',
    'IBFS': 'Institute of Business and Financial Administration',
    'IHS': 'Institute of Health Sciences',
    'ITE': 'Institute of Teacher Education',
    'ICJE': 'Institute of Criminal Justice Education',
  };

  String _instituteFullName(String code) {
    final c = code.trim();
    return _instituteNames[c.toUpperCase()] ?? c;
  }

  // ---- data kept in memory between visits to this page -------------------
  // These are static so reopening the page shows the last data instantly
  // while a quiet refresh runs in the background.
  static final List<Map<String, String>> _allRecords = [];
  static final List<ProcedureRecord> _procedures = [];
  static final Map<String, VisitDetailsController> _savedVisits = {};
  static final Map<String, IndividualRecord> _rosterById = {};
  static final Set<String> _detailsRequested = {};
    static final Set<String> _detailsDone = {};
  static final Map<String, int> _timeKeyCache = {};
  static String? _cacheUser;
  static bool _everLoaded = false;
  final Set<Future<void>> _inflight = {};

  String? _loadError;

  VoidCallback? _dataListener;
  Timer? _debounce;
  Timer? _searchDebounce;

  int _reloadToken = 0;
  DateTime? _lastLoad;

  // ---- caches so filtering/grouping is not redone on every rebuild -------
  int _dataVersion = 0;
  final Map<String, List<_DayGroup>> _groupCache = {};
  Set<String>? _periodsWithVisits;
  int _periodsVer = -1;
  List<int>? _ageCache;
  int _ageVer = -1;

  // ---- paging of the table ----------------------------------------------
  static const int _pageSize = 50;
  int _shown = _pageSize;
  String _shownSig = '';
  List<String> _lastShownIds = const [];

  @override
  void initState() {
    super.initState();

    final uid = supabaseClient.auth.currentUser?.id;
    if (_cacheUser != uid) {
      // A different account signed in: never show the previous one's data.
      _detailsDone.clear();
      _allRecords.clear();
      _procedures.clear();
      _savedVisits.clear();
      _rosterById.clear();
      _detailsRequested.clear();
      _everLoaded = false;
      _cacheUser = uid;
    }
    // Paint what was downloaded at sign-in / last visit at once.
    if (_allRecords.isEmpty) {
      final cached = VisitService.peekBookletRecords();
      if (cached != null && cached.isNotEmpty) {
        _allRecords.addAll(cached);
        _everLoaded = true;
      }
    }
    _reloadRecords();
    _dataListener = () {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 250), _reloadRecords);
    };
    DataTracker.listen(_dataListener!);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchDebounce?.cancel();
    if (_dataListener != null) DataTracker.unlisten(_dataListener!);
    super.dispose();
  }

  @override
  void didUpdateWidget(RecordsBooklet oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Reload on tab-open only when the data is older than 30 seconds.
    final stale = _lastLoad == null ||
        DateTime.now().difference(_lastLoad!) > const Duration(seconds: 30);
    if (widget.isActive && !oldWidget.isActive && stale) {
      _reloadRecords();
    }
  }

  Future<void> _reloadRecords() async {
    final int token = ++_reloadToken;

    try {
      // roster, visits and reference data all load at the same time
      final results = await Future.wait<dynamic>([
        _loadRosterFacts(),
        VisitService.fetchAllBookletRecords(),
        Future(() async {
          try {
            await ReferenceCatalog.loadQuietly();
          } catch (_) {}
        }),
      ]);
      final roster = results[0] as _Roster;
      final records = results[1] as List<Map<String, String>>;
      if (!mounted || token != _reloadToken) return;

      _rosterById
        ..clear()
        ..addAll(roster.byId);
      for (final r in records) {
        _enrichFromRoster(r, roster.facts);
      }
      setState(() {
        _allRecords
          ..clear()
          ..addAll(records);
        _dataVersion++;
        _loadError = null;
      });
      _lastLoad = DateTime.now();
      _everLoaded = true;
    } catch (e) {
      if (!mounted || token != _reloadToken) return;
      setState(() => _loadError = _describeReadFailure(e));
      return;
    }

    // Start loading the services of the first page right away
    // (no more waiting for a frame to be drawn first).
    if (!mounted || token != _reloadToken) return;
    final ids = {..._firstPageIds(), ..._lastShownIds}.toList();
    await _ensureDetails(ids, force: _savedVisits.isNotEmpty);
  }

  List<String> _firstPageIds() => [
        for (final g in _groupsFor(null).take(_shown))
          for (final r in g)
            if ((r["visitId"] ?? '').trim().isNotEmpty)
              (r["visitId"] ?? '').trim(),
      ];

  /// Loads the saved services (and linked procedures) ONLY for the given
  /// visits, in parallel. Visits already loaded are skipped unless [force].
  Future<void> _ensureDetails(Iterable<String> ids,
      {bool force = false}) async {
    final want = <String>[];
    for (final raw in ids) {
      final id = raw.trim();
      if (id.isEmpty) continue;
      if (!force &&
          (_savedVisits.containsKey(id) || _detailsRequested.contains(id))) {
        continue;
      }
      want.add(id);
    }
    if (want.isEmpty) return;
    _detailsRequested.addAll(want);

    final job = _fetchDetails(want);
    _inflight.add(job);
    try {
      await job;
    } finally {
      _inflight.remove(job);
    }
  }

    Future<void> _fetchDetails(List<String> want) async {
    try {
      final results = await Future.wait<dynamic>([
        VisitDetailsService.readVisits(want),
        ProcedureService.fetchForVisits(want)
            .catchError((_) => <ProcedureRecord>[]),
      ]);
      if (!mounted) return;
      final saved = results[0] as Map<String, VisitDetailsController>;
      final procs = results[1] as List<ProcedureRecord>;
      setState(() {
        for (final id in want) {
          if (!saved.containsKey(id)) _savedVisits.remove(id);
        }
        _savedVisits.addAll(saved);
        final wanted = want.toSet();
        _procedures
            .removeWhere((p) => wanted.contains((p.visitId ?? '').trim()));
        _procedures.addAll(procs);
        _detailsDone.addAll(want);
      });
    } catch (_) {
      // Show the rows anyway instead of waiting forever.
      _detailsDone.addAll(want);
      if (mounted) setState(() {});
    }
  }

  Future<_Roster> _loadRosterFacts() async {
    try {
      final roster = await IndividualRecordService.fetchAllOnePerPerson();
      return (
        facts: {
          for (final r in roster)
            r.id: {
              "name": _lastFirst(r),
              "type": r.category,
              "institute": r.institute,
              "program": r.program,
              "department": r.department,
              "position": r.position,
              "yearLevel": r.yearLevel,
              "academicYear": r.academicYear,
              "semester": r.semester,
              "sex": r.sex,
              "birthDate": r.birthDate == null
                  ? ''
                  : DateFormat('yyyy-MM-dd').format(r.birthDate!),
            },
        },
        byId: {for (final r in roster) r.id: r},
      );
    } catch (_) {
      return (
        facts: const <String, Map<String, String>>{},
        byId: const <String, IndividualRecord>{},
      );
    }
  }

  void _enrichFromRoster(
    Map<String, String> r,
    Map<String, Map<String, String>> roster,
  ) {
    final personId = (r["personId"] ?? "").trim();
    final facts = roster[personId];
    if (facts == null || personId.isEmpty) return;

    String pick(String primary, String fallback) =>
        primary.trim().isEmpty ? fallback : primary;

    r["name"] = facts["name"] ?? r["name"] ?? '';
    r["sex"] = facts["sex"] ?? '';
    r["birthDate"] = facts["birthDate"] ?? '';

    r["id"] = personId;
    r["type"] = facts["type"] ?? r["type"] ?? '';

    final category = r["type"] ?? '';
    if (category == 'Staff') {
      r["department"] = facts["department"] ?? '';
      r["position"] = facts["position"] ?? '';

      r["dept"] = pick(facts["department"] ?? '', r["dept"] ?? '');
      r["year"] = pick(facts["position"] ?? '', r["year"] ?? '');
    } else if (category == 'Faculty') {
      r["institute"] = facts["institute"] ?? '';
      r["position"] = facts["position"] ?? '';
      r["dept"] = pick(facts["institute"] ?? '', r["dept"] ?? '');
      r["year"] = pick(facts["position"] ?? '', r["year"] ?? '');
    } else {
      r["institute"] = facts["institute"] ?? '';
      r["program"] = facts["program"] ?? '';
      r["year"] = pick(facts["yearLevel"] ?? '', r["year"] ?? '');
      r["dept"] = pick(facts["institute"] ?? '', r["dept"] ?? '');
    }

    r["academicYear"] = (r["visitYear"] ?? '').isNotEmpty
        ? r["visitYear"]!
        : (facts["academicYear"] ?? r["academicYear"] ?? '');
    r["semester"] = (r["visitSemester"] ?? '').isNotEmpty
        ? r["visitSemester"]!
        : (facts["semester"] ?? r["semester"] ?? '');
  }

  String _describeReadFailure(Object e) {
    final raw = e.toString();
    final m = RegExp(r"Could not find the table '([^']+)'").firstMatch(raw);
    if (m != null) {
      return "The clinic visits could not be read: the database has no table "
          "called '${m.group(1)}'. Nothing is lost — the page is showing worked "
          "examples until that is fixed.";
    }
    if (raw.contains('JWT') || raw.contains('401')) {
      return 'The clinic visits could not be read: this session is not signed '
          'in, or has expired. Sign in again and the records return.';
    }
    if (raw.contains('42501') || raw.contains('permission denied')) {
      return 'The clinic visits could not be read: this account is not allowed '
          'to read the visits table.';
    }
    return 'The clinic visits could not be read, so this page is showing worked '
        'examples instead of the clinic\'s records.';
  }

  List<Map<String, String>> _getPrintRecords({String? institute}) {
    return filterRecordsByInstitute(_allRecords, institute);
  }

  // ---- age helpers -------------------------------------------------------
  int? _ageFromDate(DateTime b) {
    final n = DateTime.now();
    var age = n.year - b.year;
    if (n.month < b.month || (n.month == b.month && n.day < b.day)) age--;
    return age < 0 ? null : age;
  }

  int? _ageOf(String? yyyyMmDd) {
    final b = DateTime.tryParse((yyyyMmDd ?? '').trim());
    return b == null ? null : _ageFromDate(b);
  }

      List<int> get _ageOptions {
        final ages = <int>{};
        // Apply every filter except Age itself, so the selected age
        // does not hide the other choices.
        final saved = selectedAge;
        selectedAge = null;
        final records = _getFilteredRecords();
        selectedAge = saved;

        for (final r in records) {
          final a = _ageOf(r["birthDate"]);
          if (a != null) ages.add(a);
        }
        return ages.toList()..sort();
      }

  // ---- filter cache ------------------------------------------------------
  String get _filterSig => [
        selectedFilter,
        DateTime.now().day,
        selectedDate,
        selectedRange,
        selectedYear,
        selectedAcadYear,
        selectedSemester,
        selectedInstitute,
        selectedProgram,
        selectedSex,
        selectedAge,
        birthRange,
        searchQuery,
      ].join('|');

  /// Filtering + grouping is done once per data/filter change,
  /// not on every rebuild.
  List<_DayGroup> _groupsFor(String? type) {
    final key = '$_dataVersion|${type ?? ''}|$_filterSig';
    final hit = _groupCache[key];
    if (hit != null) return hit;
    if (_groupCache.length > 12) _groupCache.clear();
    return _groupCache[key] =
        _groupByDay(_getFilteredRecords(typeFilter: type));
  }

  List<Map<String, String>> _getFilteredRecords(
      {String? typeFilter, String? institute}) {
    var filtered = List<Map<String, String>>.from(_allRecords);

    if (institute != null) {
      filtered = filterRecordsByInstitute(filtered, institute);
    }
    if (typeFilter != null) {
      filtered = filtered.where((e) => e["type"] == typeFilter).toList();
    }
    if (_activeInstitute.isNotEmpty) {
      final String want = _activeInstitute.trim().toLowerCase();
      filtered = filtered
          .where((e) => (e["institute"] ?? "").trim().toLowerCase() == want)
          .toList();
    }
    if (_activeProgram.isNotEmpty) {
      final String want = _activeProgram.trim().toLowerCase();
      filtered = filtered
          .where((e) => (e["program"] ?? "").trim().toLowerCase() == want)
          .toList();
    }

    // Sex
    if (selectedSex.isNotEmpty) {
      final want = selectedSex.toLowerCase();
      filtered = filtered
          .where((e) => (e["sex"] ?? '').trim().toLowerCase() == want)
          .toList();
    }

    // Age (calculated from the birth date)
    if (selectedAge != null) {
      filtered =
          filtered.where((e) => _ageOf(e["birthDate"]) == selectedAge).toList();
    }

    // Birth date range
    if (birthRange != null) {
      final s = birthRange!.start;
      final en = birthRange!.end;
      filtered = filtered.where((e) {
        final d = DateTime.tryParse((e["birthDate"] ?? '').trim());
        if (d == null) return false;
        final day = DateTime(d.year, d.month, d.day);
        return !day.isBefore(s) && !day.isAfter(en);
      }).toList();
    }

    if (searchQuery.isNotEmpty) {
      filtered = filtered
          .where((e) => e.entries
              .where((x) => x.key != 'sex' && x.key != 'birthDate')
              .map((x) => x.value)
              .join(" ")
              .toLowerCase()
              .contains(searchQuery))
          .toList();
    }

    if (selectedFilter == 'Academic Year') {
      filtered = filtered.where((e) {
        if (selectedAcadYear.isNotEmpty &&
            (e["visitYear"] ?? '') != selectedAcadYear) {
          return false;
        }
        if (selectedSemester.isNotEmpty &&
            (e["visitSemester"] ?? '') != selectedSemester) {
          return false;
        }
        return true;
      }).toList();
    }

    final DateTimeRange? window = _activeWindow();
    if (window != null) {
      final DateTime start = window.start;
      final DateTime end = window.end;
      filtered = filtered.where((e) {
        final DateTime? d = DateTime.tryParse(e["date"] ?? '');
        if (d == null) return false;
        final DateTime day = DateTime(d.year, d.month, d.day);
        return !day.isBefore(start) && !day.isAfter(end);
      }).toList();
    }
    return filtered;
  }

  DateTimeRange? _activeWindow() {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    switch (selectedFilter) {
      case 'Today':
        return DateTimeRange(start: today, end: today);
      case 'This Week':
        final DateTime start =
            today.subtract(Duration(days: today.weekday - 1));
        return DateTimeRange(
            start: start, end: start.add(const Duration(days: 6)));
      case 'This Month':
        return DateTimeRange(
            start: DateTime(now.year, now.month, 1),
            end: DateTime(now.year, now.month + 1, 0));
      case 'Year':
        final int year = selectedYear ?? now.year;
        return DateTimeRange(
            start: DateTime(year, 1, 1), end: DateTime(year, 12, 31));
      case 'Pick Date':
        return DateTimeRange(
            start: DateTime(
                selectedDate.year, selectedDate.month, selectedDate.day),
            end: DateTime(
                selectedDate.year, selectedDate.month, selectedDate.day));
      case 'Date Range':
        final DateTimeRange? range = selectedRange;
        if (range == null) return null;
        return DateTimeRange(
            start:
                DateTime(range.start.year, range.start.month, range.start.day),
            end: DateTime(range.end.year, range.end.month, range.end.day));
      default:
        return null;
    }
  }

  Map<String, int> _getVisitSummary() {
    final all = _groupsFor(null);
    int c(String t) => all.where((g) => g.first["type"] == t).length;
    return {
      "all": all.length,
      "student": c("Student"),
      "faculty": c("Faculty"),
      "staff": c("Staff"),
    };
  }

  List<_DayGroup> _groupByDay(List<Map<String, String>> records) {
    final map = <String, _DayGroup>{};
    for (final r in records) {
      final key = '${_idOfRecord(r)}|${(r["date"] ?? '').trim()}';
      map.putIfAbsent(key, () => []).add(r);
    }
    final groups = map.values.toList();
    for (final g in groups) {
      g.sort((a, b) =>
          _timeKey(a["time"] ?? '').compareTo(_timeKey(b["time"] ?? '')));
    }
    groups.sort((a, b) {
      final byDate = (b.first["date"] ?? '').compareTo(a.first["date"] ?? '');
      if (byDate != 0) return byDate; // newest date first
      // same date: the latest recorded time goes on top
      return _timeKey(b.last["time"] ?? '')
          .compareTo(_timeKey(a.last["time"] ?? ''));
    });
    return groups;
  }

  List<String> _mergedServiceNames(_DayGroup g) {
    final seen = <String>{};
    final out = <String>[];
    for (final r in g) {
      for (final n in _serviceNames(r)) {
        if (seen.add(n)) out.add(n);
      }
    }
    return out;
  }

  String _mergedReason(_DayGroup g) {
    final parts = <String>[];
    for (final r in g) {
      final t = ((r["reason"] ?? '').trim().isNotEmpty
              ? r["reason"]!
              : (r["complaint"] ?? ''))
          .trim();
      if (t.isNotEmpty && !parts.contains(t)) parts.add(t);
    }
    return parts.join(' / ');
  }

  String _sessionLabel(Map<String, String> r) =>
      _timeKey(r["time"] ?? '') < 720 ? 'Morning (AM)' : 'Afternoon (PM)';

  String _sessionTimes(Map<String, String> r) {
    final out = (r["timeOut"] ?? '').trim();
    final tin = r["time"] ?? '';
    return out.isEmpty || out == '-' ? tin : '$tin – $out';
  }

  _VisitState _groupState(_DayGroup g) {
    if (g.length == 1) return _stateFor(g.first);
    final s = g.map(_stateFor).toList();
    if (s.every((x) => x.label == 'Completed')) return s.first;
    if (s.any((x) => x.label != 'Not Recorded' && x.label != 'Not Started')) {
      return const _VisitState('Partly Complete', kWarning);
    }
    return s.first;
  }

  Future<DateTime?> _chooseDate() async {
    return showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: kPrimary,
            onPrimary: Colors.white,
            onSurface: kTextMain,
          ),
        ),
        child: child!,
      ),
    );
  }

  Future<DateTimeRange?> _chooseRange() async {
    return showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: selectedRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme:
                Theme.of(context).colorScheme.copyWith(primary: kPrimary),
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
  }

  Future<void> _onDateModeChanged(String? mode) async {
    if (mode == null) return;
    if (mode == 'Pick Date') {
      final DateTime? picked = await _chooseDate();
      if (!mounted) return;
      setState(() {
        selectedFilter = 'Pick Date';
        if (picked != null) selectedDate = picked;
      });
      return;
    }
    if (mode == 'Academic Year') {
      final cur = ReferenceCatalog.currentPeriod;
      setState(() {
        selectedFilter = 'Academic Year';
        if (selectedAcadYear.isEmpty) {
          selectedAcadYear = cur?.acadYear ?? '';
          selectedSemester = cur?.semester ?? '';
        }
      });
      return;
    }
    if (mode == 'Date Range') {
      final DateTimeRange? range = await _chooseRange();
      if (!mounted || range == null) return;
      setState(() {
        selectedRange = range;
        selectedFilter = 'Date Range';
      });
      return;
    }
    setState(() {
      selectedFilter = mode;
      if (mode == 'Year' && selectedYear == null) {
        selectedYear = DateTime.now().year;
      }
    });
  }

  Future<void> _changeDate() async {
    final DateTime? picked = await _chooseDate();
    if (!mounted || picked == null) return;
    setState(() => selectedDate = picked);
  }

  Future<void> _changeRange() async {
    final DateTimeRange? range = await _chooseRange();
    if (!mounted || range == null) return;
    setState(() => selectedRange = range);
  }

  VisitDetailsController? _visitFor(Map<String, String> record) {
    final id = (record["visitId"] ?? "").trim();
    if (id.isNotEmpty) {
      final saved =
          _savedVisits[id] ?? VisitDetailsService.recentSavedFor([id])[id];
      if (saved != null) {
        saved.vitals.setSubject(
          sex: record["sex"],
          birthDate: DateTime.tryParse((record["birthDate"] ?? '').trim()),
          asOf: DateTime.tryParse((record["date"] ?? '').trim()),
        );
        return saved;
      }
    }
    return null;
  }

  List<String> _serviceNames(Map<String, String> record) {
    final visit = _visitFor(record);
    if (visit != null && visit.drafts.isNotEmpty) {
      return [for (final d in visit.drafts) _draftLabel(d, visit.vitals)];
    }
    return (record["complaint"] ?? "")
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

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

  String _draftLabel(ServiceDraft d, VisitVitals v) {
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
    return d.label; // several different vitals → "Vital signs"
  }

  _VisitState _stateFor(Map<String, String> record) {
    final drafts = _visitFor(record)?.drafts ?? <ServiceDraft>[];
    if (drafts.isEmpty) return const _VisitState('Not Recorded', kTextSub);
    final done =
        drafts.where((d) => d.status == ServiceDraftStatus.completed).length;
    final started =
        drafts.where((d) => d.status == ServiceDraftStatus.inProgress).length;
    if (done == drafts.length) {
      return const _VisitState('Completed', kSuccess);
    }
    if (done > 0) return const _VisitState('Partly Complete', kWarning);
    if (started > 0) return const _VisitState('In Progress', kWarning);
    return const _VisitState('Not Started', kTextSub);
  }

  String _fmtDisplayDate(String yyyyMmDd) {
    if (yyyyMmDd.trim().isEmpty) return '—';
    try {
      final d = DateFormat("yyyy-MM-dd").parse(yyyyMmDd);
      return DateFormat("MMM d, yyyy").format(d);
    } catch (_) {
      return yyyyMmDd;
    }
  }

  String _fmtShort(DateTime d) => DateFormat("MMM d, yyyy").format(d);

  Future<void> _showDetailDialog(_DayGroup group) async {
    final ids = [
      for (final r in group)
        if ((r["visitId"] ?? '').trim().isNotEmpty) (r["visitId"] ?? '').trim(),
    ];

    // The dialog opens at once. If this row's services are not loaded yet,
    // a spinner shows inside it until they arrive.
    final bool needsLoad = _inflight.isNotEmpty ||
        ids.any((i) =>
            !_savedVisits.containsKey(i) && !_detailsRequested.contains(i));
    final Future<bool> ready = () async {
      await _ensureDetails(ids);
      if (_inflight.isNotEmpty) await Future.wait(_inflight.toList());
      return true;
    }();
    if (!mounted) return;

    final record = group.first;
    final state = _groupState(group);
    final person =
        _rosterById[(record["personId"] ?? record["id"] ?? '').trim()];
    final category = (person?.category ?? record["type"] ?? '').trim();

    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: kCard,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 660, maxHeight: 720),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _detailHeader(record, person, category, state),
                const SizedBox(height: 18),
                const Divider(color: kBorder, height: 1),
                const SizedBox(height: 6),
                Flexible(
                  child: FutureBuilder<bool>(
                    future: ready,
                    initialData: needsLoad ? null : true,
                    builder: (c, s) {
                      if (!s.hasData) {
                        return const Padding(
                          padding: EdgeInsets.all(48),
                          child: Center(
                              child: CircularProgressIndicator(strokeWidth: 3)),
                        );
                      }
                      return SingleChildScrollView(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: _detailBody(
                            group: group,
                            person: person,
                            category: category),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 8),
                const Divider(color: kBorder, height: 1),
                const SizedBox(height: 14),
                _detailFooter(group),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailFooter(_DayGroup group) {
    return Row(children: [
      for (var i = 0; i < group.length; i++) ...[
        if (i > 0) const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _openVisitEditor(group[i]);
            },
            icon: const Icon(Icons.edit_outlined, size: 16, color: kPrimary),
            label: Text(
                group.length == 1
                    ? 'Edit Record'
                    : 'Edit ${_sessionLabel(group[i])}',
                style: const TextStyle(color: kPrimary)),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: kBorder),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
          ),
        ),
      ],
    ]);
  }

  Widget _sessionBanner(Map<String, String> s) {
    final am = _timeKey(s["time"] ?? '') < 720;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 20),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: kPrimary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kPrimary.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        Icon(am ? Icons.wb_sunny_outlined : Icons.nights_stay_outlined,
            size: 17, color: kPrimary),
        const SizedBox(width: 8),
        Text('${_sessionLabel(s)} visit  ·  ${_sessionTimes(s)}',
            style: const TextStyle(
                fontSize: 13.5, fontWeight: FontWeight.w800, color: kPrimaryDk)),
      ]),
    );
  }

  List<Widget> _sessionBlock(Map<String, String> s, {required bool multi}) {
    final visit = _visitFor(s);
    final services = _serviceNames(s);
    final procedures = _linkedProcedures(s["visitId"] ?? "");
    return [
      if (multi) _sessionBanner(s),
      _sectionHeader('Services & Records', Icons.fact_check_outlined),
      const SizedBox(height: 4),
      if (visit == null)
        _emptyServicesNote(services)
      else
        for (final draft in visit.drafts) ...[
          VisitReviewCard(
            title: _draftLabel(draft, visit.vitals),
            lines: visitReviewAnswerLines(draft, visit.vitals,
                canSeeRestricted: AccountService.canSeeRestrictedCounselling),
            trailing: _draftStatePill(draft),
          ),
          const SizedBox(height: 10),
        ],
      if (procedures.isNotEmpty) ...[
        _sectionHeader('Linked Procedures', Icons.link_rounded),
        const SizedBox(height: 10),
        ...procedures.map(_procedureTile),
      ],
      _infoSection('Record Information', Icons.history_rounded, [
        _infoRow('Date', _fmtDisplayDate(s["date"] ?? '')),
        _infoRow('Time in', s["time"] ?? ''),
        _infoRow('Time out',
            (s["timeOut"] ?? '').trim().isEmpty ? '-' : s["timeOut"]!),
        _infoRow('Recorded by', s["createdBy"] ?? '-'),
        if ((s["complaint"] ?? '').trim().isNotEmpty)
          _infoRow('Complaint', s["complaint"]!),
      ]),
    ];
  }

  Widget _detailBody({
    required _DayGroup group,
    required IndividualRecord? person,
    required String category,
  }) {
    final record = group.first;
    final isStudent = category == 'Student';
    final isFaculty = category == 'Faculty';

    final personalRows = person != null
        ? <Widget>[
            _infoRow('First Name', person.firstName),
            _infoRow('Middle Name', person.middleName),
            _infoRow('Last Name', person.lastName),
            _infoRow('Suffix', person.suffix),
            _infoRow('Sex', person.sex),
            _infoRow(
                'Birth Date',
                person.birthDate == null
                    ? ''
                    : DateFormat('MMMM d, yyyy').format(person.birthDate!)),
            _infoRow(
                'Age',
                person.birthDate == null
                    ? ''
                    : '${_ageFromDate(person.birthDate!) ?? ''}'),
            _infoRow('Contact', person.contact),
            _infoRow('Email', person.email),
            _infoRow('Address', person.address),
          ]
        : <Widget>[
            _infoRow('Name', record["name"] ?? ''),
            _infoRow('Record No', record["id"] ?? ''),
            _infoRow('Role', category),
          ];

    final academicRows = <Widget>[
      _infoRow('Academic Year',
          record["academicYear"] ?? person?.academicYear ?? ''),
      _infoRow('Semester', record["semester"] ?? person?.semester ?? ''),
      if (isStudent) ...[
        _infoRow('Institute', person?.institute ?? record["institute"] ?? ''),
        _infoRow('Program', person?.program ?? record["program"] ?? ''),
        _infoRow('Year Level', person?.yearLevel ?? record["year"] ?? ''),
      ] else if (isFaculty) ...[
        _infoRow('Institute', person?.institute ?? record["institute"] ?? ''),
        _infoRow('Position', person?.position ?? record["position"] ?? ''),
      ] else ...[
        _infoRow('Department / Office',
            person?.department ?? record["department"] ?? ''),
        _infoRow('Position', person?.position ?? record["position"] ?? ''),
      ],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _infoSection(
            'Personal Information', Icons.person_outline, personalRows),
        _infoSection(
          isStudent
              ? 'Academic Information'
              : (isFaculty ? 'Teaching Assignment' : 'Employment Information'),
          isStudent ? Icons.school_outlined : Icons.work_outline,
          academicRows,
        ),
        for (final s in group) ..._sessionBlock(s, multi: group.length > 1),
      ],
    );
  }

  Widget _detailHeader(
    Map<String, String> record,
    IndividualRecord? person,
    String category,
    _VisitState state,
  ) {
    final color = _categoryColor(category);
    final isStudent = category == 'Student';
    final ay = (record["academicYear"] ?? person?.academicYear ?? '').trim();
    final sem = (record["semester"] ?? person?.semester ?? '').trim();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            isStudent
                ? Icons.person_outline_rounded
                : Icons.work_outline_rounded,
            color: Colors.white,
            size: 22,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(record["name"] ?? '',
                  style: const TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: kTextMain),
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 5),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(category.isEmpty ? 'Unassigned' : category,
                        style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.bold,
                            color: color)),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(record["id"] ?? '',
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: kTextSub)),
                  ),
                  if (ay.isNotEmpty || sem.isNotEmpty)
                    Text('AY $ay · $sem',
                        style:
                            const TextStyle(fontSize: 13, color: kTextSub)),
                  _statusPill(state),
                ],
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close_rounded, color: kTextSub),
          iconSize: 20,
        ),
      ],
    );
  }

  Color _categoryColor(String category) => category == 'Student'
      ? kStudentColor
      : category == 'Faculty'
          ? kFacultyColor
          : kStaffColor;

  Widget _sectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(children: [
        Icon(icon, size: 16, color: kPrimary),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: kTextMain,
                letterSpacing: 0.3)),
        const SizedBox(width: 12),
        const Expanded(child: Divider(color: kBorder, height: 1)),
      ]),
    );
  }

  Widget _infoSection(String title, IconData icon, List<Widget> rows) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionHeader(title, icon),
      const SizedBox(height: 12),
      LayoutBuilder(builder: (context, c) {
        final twoCol = c.maxWidth > 460;
        final pairs = <Widget>[];
        for (var i = 0; i < rows.length; i += (twoCol ? 2 : 1)) {
          final end = (i + (twoCol ? 2 : 1)).clamp(0, rows.length);
          pairs.add(Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: rows[i]),
              if (twoCol && end - i == 2) ...[
                const SizedBox(width: 16),
                Expanded(child: rows[i + 1]),
              ],
            ]),
          ));
        }
        return Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: pairs);
      }),
    ]);
  }

  Widget _infoRow(String label, String value) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: const TextStyle(
              fontSize: 12, color: kTextSub, fontWeight: FontWeight.w600)),
      const SizedBox(height: 2),
      Text(value.trim().isEmpty ? '—' : value,
          style: const TextStyle(
              fontSize: 15, color: kTextMain, fontWeight: FontWeight.w600)),
    ]);
  }

  Widget _emptyServicesNote(List<String> services) {
    return _noteBanner(
      kWarning,
      Icons.cloud_off_outlined,
      services.isEmpty
          ? 'No services were recorded on this visit.'
          : 'The ${services.length} service'
              '${services.length == 1 ? '' : 's'} on this visit could not have '
              'their answers loaded. They are stored on the server and come back '
              'on the next read.',
    );
  }

  Widget _draftStatePill(ServiceDraft draft) {
    final Color color = draft.isComplete
        ? kSuccess
        : draft.status == ServiceDraftStatus.notStarted
            ? kTextSub
            : kWarning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        draft.status.label,
        style:
            TextStyle(fontSize: 11.5, fontWeight: FontWeight.w800, color: color),
      ),
    );
  }

  Widget _noteBanner(Color color, IconData icon, String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: color,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openVisitEditor(Map<String, String> record) async {
    final visitId = (record["visitId"] ?? '').trim();
    if (visitId.isEmpty) return;

    final person =
        _rosterById[(record["personId"] ?? record["id"] ?? '').trim()];
    if (person == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'This visitor is not on the current roster, so the visit cannot be edited here.'),
        backgroundColor: kWarning,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    final visit = _visitFor(record);
    final drafts = visit?.drafts ?? const <ServiceDraft>[];

    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => VisitEditScreen(
          userName: _currentUser,
          visitId: visitId,
          person: person,
          serviceIds: [for (final d in drafts) d.serviceId],
          serviceData: {
            for (final d in drafts) d.serviceId: d.toJson(),
          },
          vitals: visit?.vitals,
          medicines: [
            for (final m in visit?.draftFor('medication')?.medicines ??
                const <MedicineDose>[])
              m.copy(),
          ],
          initialReason: record["complaint"] ?? '',
          visitStamp: _checkedInFromRecord(record),
        ),
      ),
    );
    if (!mounted) return;
    await _reloadRecords();
  }

  DateTime? _checkedInFromRecord(Map<String, String> record) {
    final date = (record["date"] ?? '').trim();
    if (date.isEmpty) return null;
    final time = (record["time"] ?? '').trim();
    final stamp = '$date ${time.isEmpty || time == '-' ? '12:00 AM' : time}';
    return DateFormat('yyyy-MM-dd hh:mm a').tryParse(stamp) ??
        DateTime.tryParse(date);
  }

  static const List<String> _printPeriods = [
    'Today',
    'This Week',
    'This Month',
    'Academic Year',
    'Custom',
  ];

  static DateTimeRange? _windowForPeriod(String period, DateTimeRange? custom) {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    switch (period) {
      case 'Today':
        return DateTimeRange(start: today, end: today);
      case 'This Week':
        final DateTime start =
            today.subtract(Duration(days: today.weekday - 1));
        return DateTimeRange(
            start: start, end: start.add(const Duration(days: 6)));
      case 'This Month':
        return DateTimeRange(
            start: DateTime(now.year, now.month, 1),
            end: DateTime(now.year, now.month + 1, 0));
      case 'Custom':
        if (custom == null) return null;
        return DateTimeRange(
            start: DateTime(
                custom.start.year, custom.start.month, custom.start.day),
            end: DateTime(custom.end.year, custom.end.month, custom.end.day));
      default:
        return null; // Academic Year has no date window
    }
  }

  String _rangeText(DateTimeRange r) => r.start == r.end
      ? _fmtShort(r.start)
      : '${_fmtShort(r.start)} – ${_fmtShort(r.end)}';

  int _timeKey(String t) => _timeKeyCache.putIfAbsent(t, () {
        final DateTime? d = DateFormat('hh:mm a').tryParse(t.trim());
        return d == null ? 0 : d.hour * 60 + d.minute;
      });

  List<String> _allServiceNames() {
    final Set<String> names = <String>{};
    for (final r in _allRecords) {
      for (final n in _serviceNames(r)) {
        if (n.trim().isNotEmpty) names.add(n.trim());
      }
    }
    return names.toList()..sort();
  }

  List<_PrintPerson> _printablePeople() {
    final Map<String, String> m = {};
    _rosterById.forEach((id, p) => m[id] = _lastFirst(p));
    for (final r in _allRecords) {
      final String pid = (r["personId"] ?? '').trim();
      final String id = pid.isNotEmpty ? pid : (r["id"] ?? '').trim();
      if (id.isEmpty) continue;
      m.putIfAbsent(id, () => r["name"] ?? '');
    }
    final List<_PrintPerson> list = [
      for (final e in m.entries) (id: e.key, name: e.value),
    ];
    list.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return list;
  }

    String _nameKey(Map<String, String> r) {
    final id = _idOfRecord(r);
    final p = _rosterById[id];
    if (p != null && p.lastName.trim().isNotEmpty) {
      return '${p.lastName}|${p.firstName}|${p.middleName}|$id'
          .toLowerCase()
          .trim();
    }
    return '${(r["name"] ?? '').trim()}|$id'.toLowerCase();
  }

  /// "LAST, First Middle Suffix"  (comma only after the last name)
    String _lastFirst(IndividualRecord r) {
      final given = [r.firstName, r.middleName, r.suffix]
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .join(' ');
      final last = r.lastName.trim();
      if (last.isEmpty) return given;
      return given.isEmpty ? last : '$last, $given';
    }

    List<Map<String, String>> _recordsForPrint(_PrintCriteria c) {
    var list = _getPrintRecords(institute: c.institute);

    final DateTimeRange? w = c.window;
    if (w != null) {
      list = list.where((e) {
        final DateTime? d = DateTime.tryParse(e["date"] ?? '');
        if (d == null) return false;
        final DateTime day = DateTime(d.year, d.month, d.day);
        return !day.isBefore(w.start) && !day.isAfter(w.end);
      }).toList();
    }
    if (c.acadYear.isNotEmpty) {
      list = list.where((e) {
        if ((e["visitYear"] ?? '') != c.acadYear) return false;
        if (c.semester.isNotEmpty && (e["visitSemester"] ?? '') != c.semester) {
          return false;
        }
        return true;
      }).toList();
    }

    if (c.services.isNotEmpty) {
      final want = c.services.map((e) => e.trim().toLowerCase()).toSet();
      list = list
          .where((e) => _serviceNames(e)
              .any((n) => want.contains(n.trim().toLowerCase())))
          .toList();
    }

    final String pid = (c.personId ?? '').trim();
    if (pid.isNotEmpty) {
      list = list.where((e) {
        final String p = (e["personId"] ?? '').trim();
        return (p.isNotEmpty ? p : (e["id"] ?? '').trim()) == pid;
      }).toList();
    }

    // Individual report: oldest-first here (BookletPrint reverses it later).
    // All other reports: newest date first, then A-Z by last name on the same day.
    final bool single = c.report == _PrintReport.individual;
    list.sort((a, b) {
      final String da = a["date"] ?? '';
      final String db = b["date"] ?? '';
      final int byDate = single ? da.compareTo(db) : db.compareTo(da);
      if (byDate != 0) return byDate;
      if (!single) {
        final int byName = _nameKey(a).compareTo(_nameKey(b));
        if (byName != 0) return byName;
      }
      return _timeKey(a["time"] ?? '').compareTo(_timeKey(b["time"] ?? ''));
    });
    return list;
  }

  Widget _dlgLabel(String t) => Padding(
        padding: const EdgeInsets.only(top: 14, bottom: 6),
        child: Text(t.toUpperCase(),
            style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: kTextSub,
                letterSpacing: 0.8)),
      );

  Widget _dlgDropdown({
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
  }) {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kBorder),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: value,
          isExpanded: true,
          borderRadius: BorderRadius.circular(12),
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              size: 20, color: kTextSub),
          style: const TextStyle(
              fontSize: 14, fontWeight: FontWeight.w600, color: kTextMain),
          items: items,
          onChanged: onChanged,
        ),
      ),
    );
  }

  Widget _dlgPickerButton(
      {required IconData icon,
      required String text,
      required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: kPrimary.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: kPrimary.withValues(alpha: 0.35)),
        ),
        child: Row(children: [
          Icon(icon, size: 17, color: kPrimary),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: kPrimary)),
          ),
        ]),
      ),
    );
  }

  Future<DateTime?> _pickDay(BuildContext ctx, DateTime initial) {
    return showDatePicker(
      context: ctx,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
              primary: kPrimary, onPrimary: Colors.white, onSurface: kTextMain),
        ),
        child: child!,
      ),
    );
  }

  Future<DateTimeRange?> _pickRange(
    BuildContext ctx,
    DateTimeRange? initial, {
    DateTime? first,
    DateTime? last,
  }) {
    return showDateRangePicker(
      context: ctx,
      firstDate: first ?? DateTime(2020),
      lastDate: last ?? DateTime(2100),
      initialDateRange: initial,
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme:
              Theme.of(context).colorScheme.copyWith(primary: kPrimary),
        ),
        child: Dialog(
          insetPadding:
              const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
            child: child,
          ),
        ),
      ),
    );
  }

  ClinicProfile _clinicProfileOf(IndividualRecord r) {
    final existing = PatientDirectory.instance.byId(r.id);
    return ClinicProfile(
      uuid: r.uuid,
      id: r.id,
      category: r.category,
      firstName: r.firstName,
      middleName: r.middleName,
      lastName: r.lastName,
      suffix: r.suffix,
      sex: r.sex,
      birthDate: r.birthDate == null
          ? ''
          : DateFormat('yyyy-MM-dd').format(r.birthDate!),
      contact: r.contact,
      email: r.email,
      address: r.address,
      academicYear: r.academicYear,
      semester: r.semester,
      institute: r.institute,
      program: r.program,
      yearLevel: r.yearLevel,
      department: r.department,
      position: r.position,
      emergencyName: existing?.emergencyName ?? '',
      emergencyContact: existing?.emergencyContact ?? '',
      status: r.status,
      createdAt: r.createdAt,
      createdBy: r.createdBy,
    );
  }

  String _idOfRecord(Map<String, String> e) {
    final p = (e["personId"] ?? '').trim();
    return p.isNotEmpty ? p : (e["id"] ?? '').trim();
  }


  List<Map<String, String>> _visitsOf(String personId) {
    final list = _allRecords
        .where((e) =>
            _idOfRecord(e) == personId &&
            (e["visitId"] ?? '').trim().isNotEmpty)
        .toList();
    list.sort((a, b) {
      final byDate = (b["date"] ?? '').compareTo(a["date"] ?? '');
      if (byDate != 0) return byDate;
      return _timeKey(b["time"] ?? '').compareTo(_timeKey(a["time"] ?? ''));
    });
    return list;
  }

  Future<void> _printCertificate(_PrintCriteria c) async {
    final record = c.certVisit;
    final person = _rosterById[(c.personId ?? '').trim()];
    if (record == null || person == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('This patient is not on the roster, so a certificate '
            'cannot be issued.'),
        backgroundColor: kWarning,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }
    final issued = c.issuedOn ?? DateTime.now();
    final controller =
        VisitDetailsController(serviceIds: const ['medicine_certificate']);
    controller.setField('medicine_certificate', 'excused_for', c.excusedFor);
    controller.setField('medicine_certificate', 'reason', c.reason);
    controller.setField('medicine_certificate', 'cert_issued_on',
        DateFormat('yyyy-MM-dd').format(issued));

    final draft = buildCertificateDraft(
      template: DocTemplate.medicalCertificate,
      controller: controller,
      profile: _clinicProfileOf(person),
      clinicVisitDate: DateTime.tryParse(record["date"] ?? ''),
      issuedOn: issued,
      visitReason: c.reason,
      issuedBy: _currentUser,
      signatoryName: c.signatory,
      signatoryRole: SignatoryStore.defaultRole,
    );
    final rendered = draft?.resolve();
    if (rendered == null || !mounted) return;

    await SimplePrintPreview.show(
      context,
      document: rendered,
      fileName: 'Medical Certificate - ${person.fullName}',
      title: 'Print Preview — Medical Certificate',
      requirements: medicalCertificateRequirements,
    );
  }

  // ---- which academic years / semesters already have visits --------------
  Set<String> get _visitPeriods {
    if (_periodsWithVisits != null && _periodsVer == _dataVersion) {
      return _periodsWithVisits!;
    }
    final s = <String>{};
    for (final r in _allRecords) {
      final y = (r["visitYear"] ?? '').trim();
      if (y.isEmpty) continue;
      s.add('$y|');
      s.add('$y|${(r["visitSemester"] ?? '').trim()}');
    }
    _periodsVer = _dataVersion;
    return _periodsWithVisits = s;
  }

  /// True when at least one visit exists for that academic year (and
  /// semester, when given). Used to label empty periods in the dropdowns.
  bool _hasVisitsIn(String year, [String semester = '']) =>
      _visitPeriods.contains('$year|$semester');

  Future<void> _showPrintRecordsDialog() async {
    final List<String> services = _allServiceNames();
    final List<_PrintPerson> people = _printablePeople();

    _PrintReport report = _PrintReport.service;
    String period = 'This Month';
    String acadYear = '';
    String semester = '';
    DateTimeRange? custom;
    DateTime day = DateTime.now();
    final Set<String> selectedServices = <String>{};
    String institute = '';
    String? personId;
    String personName = '';
    bool blankRows = true;
    int resetTick = 0;
    String? error;

    final excusedCtrl = TextEditingController();
    final reasonCtrl = TextEditingController();
    String certVisitId = '';
    DateTime issueDay = DateTime.now();

    // The dialog opens at once; the signatory name is filled in as soon as
    // it arrives (it no longer makes the dialog wait).
    final sigCtrl = TextEditingController(text: SignatoryStore.defaultName);
    () async {
      try {
        final heads = await AccountService.fetchActiveClinicHeads();
        if (heads.isEmpty || sigCtrl.text != SignatoryStore.defaultName) return;
        final uid = AccountService.currentUserId;
        final own = heads.where((h) => h.id == uid);
        sigCtrl.text = (own.isEmpty ? heads.first : own.first).displayName;
      } catch (_) {}
    }();

    String defaultPeriodFor(_PrintReport r) => 'This Month';

    void resetAll() {
      period = defaultPeriodFor(report);
      acadYear = '';
      semester = '';
      custom = null;
      day = DateTime.now();
      selectedServices.clear();
      excusedCtrl.clear();
      reasonCtrl.clear();
      certVisitId = '';
      issueDay = DateTime.now();
      institute = '';
      personId = null;
      personName = '';
      blankRows = true;
      resetTick++;
      error = null;
    }

    String? validate() {
      if (report == _PrintReport.byInstitute && institute.isEmpty) {
        return 'Choose an institute for this report.';
      }
      if ((report == _PrintReport.individual ||
              report == _PrintReport.certificate) &&
          personId == null) {
        return 'Search and select a patient from the list.';
      }
      if (report == _PrintReport.certificate) {
        if (certVisitId.isEmpty) return 'Choose the clinic visit.';
        if (excusedCtrl.text.trim().isEmpty) {
          return 'Enter the excuse / purpose details.';
        }
        if (sigCtrl.text.trim().isEmpty) return 'Enter the signatory name.';
      }
      if (report != _PrintReport.daily &&
          report != _PrintReport.certificate &&
          period == 'Custom' &&
          custom == null) {
        return 'Pick the custom date range.';
      }
      return null;
    }

    _PrintCriteria buildCriteria() {
      final bool isDaily = report == _PrintReport.daily;
      final bool isCert = report == _PrintReport.certificate;
      final DateTimeRange? window = isDaily
          ? DateTimeRange(
              start: DateTime(day.year, day.month, day.day),
              end: DateTime(day.year, day.month, day.day))
          : (period == 'Academic Year'
              ? null
              : _windowForPeriod(period, custom));
      Map<String, String>? certVisit;
      if (isCert) {
        for (final v in _visitsOf(personId ?? '')) {
          if (v["visitId"] == certVisitId) {
            certVisit = v;
            break;
          }
        }
      }
      return _PrintCriteria(
        report: report,
        window: window,
        periodLabel: window == null ? 'All Records' : _rangeText(window),
        services: const <String>[],
        institute: report != _PrintReport.individual &&
                report != _PrintReport.certificate &&
                institute.isNotEmpty
            ? institute
            : null,
        personId:
            (report == _PrintReport.individual || isCert) ? personId : null,
        personName:
            (report == _PrintReport.individual || isCert) ? personName : null,
        blankRows: report == _PrintReport.individual && blankRows,
        certVisit: certVisit,
        excusedFor: excusedCtrl.text.trim(),
        reason: reasonCtrl.text.trim(),
        issuedOn: issueDay,
        signatory: sigCtrl.text.trim(),
        acadYear: period == 'Academic Year' ? acadYear : '',
        semester: period == 'Academic Year' ? semester : '',
      );
    }

    final _PrintCriteria? result = await showDialog<_PrintCriteria>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final bool isCert = report == _PrintReport.certificate;
          final bool showPeriod = report != _PrintReport.daily && !isCert;
          final bool showService = false;
          final bool showInstitute =
              report != _PrintReport.individual && !isCert;
          final bool showPatient = report == _PrintReport.individual || isCert;

          final DateTimeRange? resolved = _windowForPeriod(period, custom);
          final String resolvedText = resolved != null
              ? _rangeText(resolved)
              : (period == 'Custom'
                  ? 'Pick a date range'
                  : 'Every record on file');

          return Dialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            backgroundColor: Colors.white,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440, maxHeight: 700),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 20, 22, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Icon(Icons.print_outlined,
                          color: kPrimary, size: 20),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text('Print Records',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: kTextMain)),
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close_rounded,
                            size: 20, color: kTextSub),
                      ),
                    ]),
                    const Text('Select record type and specify report criteria',
                        style: TextStyle(fontSize: 12.5, color: kTextSub)),
                    const Divider(color: kBorder, height: 22),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _dlgLabel('Report type *'),
                            _dlgDropdown(
                              value: report.name,
                              items: [
                                for (final r in _PrintReport.values)
                                  DropdownMenuItem(
                                      value: r.name, child: Text(r.label)),
                              ],
                              onChanged: (v) {
                                if (v == null) return;
                                setDialogState(() {
                                  report = _PrintReport.values
                                      .firstWhere((r) => r.name == v);
                                  period = defaultPeriodFor(report);
                                  custom = null;
                                  error = null;
                                });
                              },
                            ),
                            if (showPatient) ...[
                              _dlgLabel('Patient *'),
                              Autocomplete<_PrintPerson>(
                                key: ValueKey('patient$resetTick'),
                                displayStringForOption: (o) =>
                                    '${o.name} (${o.id})',
                                optionsBuilder: (v) {
                                  final String q = v.text.trim().toLowerCase();
                                  if (q.isEmpty) {
                                    return const Iterable<_PrintPerson>.empty();
                                  }
                                  return people
                                      .where((p) =>
                                          p.name.toLowerCase().contains(q) ||
                                          p.id.toLowerCase().contains(q))
                                      .take(8);
                                },
                                onSelected: (o) => setDialogState(() {
                                  personId = o.id;
                                  personName = o.name;
                                  certVisitId = '';
                                  error = null;
                                }),
                                fieldViewBuilder:
                                    (c, ctrl, focus, onSubmitted) => TextField(
                                  controller: ctrl,
                                  focusNode: focus,
                                  onChanged: (_) {
                                    if (personId != null) {
                                      setDialogState(() {
                                        personId = null;
                                        personName = '';
                                        certVisitId = '';
                                      });
                                    }
                                  },
                                  style: const TextStyle(fontSize: 14),
                                  decoration: InputDecoration(
                                    hintText: 'Search by name or ID...',
                                    hintStyle: const TextStyle(
                                        color: kTextSub, fontSize: 13.5),
                                    prefixIcon: Icon(
                                      personId != null
                                          ? Icons.check_circle_rounded
                                          : Icons.search_rounded,
                                      size: 18,
                                      color: personId != null
                                          ? kSuccess
                                          : kTextSub,
                                    ),
                                    isDense: true,
                                    contentPadding: const EdgeInsets.symmetric(
                                        vertical: 13, horizontal: 12),
                                    border: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide:
                                            const BorderSide(color: kBorder)),
                                    enabledBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide:
                                            const BorderSide(color: kBorder)),
                                    focusedBorder: OutlineInputBorder(
                                        borderRadius: BorderRadius.circular(10),
                                        borderSide: const BorderSide(
                                            color: kPrimary, width: 1.5)),
                                  ),
                                ),
                              ),
                            ],
                            if (isCert && personId != null) ...[
                              _dlgLabel('Clinic visit *'),
                              Builder(builder: (_) {
                                final visits = _visitsOf(personId!);
                                final bool known = visits
                                    .any((v) => v["visitId"] == certVisitId);
                                return _dlgDropdown(
                                  value: known ? certVisitId : '',
                                  items: [
                                    const DropdownMenuItem(
                                        value: '',
                                        child: Text('Select visit...')),
                                    for (final v in visits)
                                      DropdownMenuItem(
                                        value: v["visitId"] ?? '',
                                        child: Text(
                                            '${_fmtDisplayDate(v["date"] ?? '')} · ${v["time"] ?? ''}'),
                                      ),
                                  ],
                                  onChanged: (val) => setDialogState(() {
                                    certVisitId = val ?? '';
                                    for (final v in visits) {
                                      if (v["visitId"] == certVisitId) {
                                        final r = (v["reason"] ?? '').trim();
                                        reasonCtrl.text = r.isNotEmpty
                                            ? r
                                            : (v["complaint"] ?? '').trim();
                                        break;
                                      }
                                    }
                                    error = null;
                                  }),
                                );
                              }),
                              _dlgLabel('Reason for visit'),
                              TextField(
                                controller: reasonCtrl,
                                maxLines: 2,
                                style: const TextStyle(fontSize: 14),
                                decoration: const InputDecoration(
                                    isDense: true,
                                    border: OutlineInputBorder()),
                              ),
                              _dlgLabel('Excuse / purpose details *'),
                              TextField(
                                controller: excusedCtrl,
                                maxLines: 3,
                                style: const TextStyle(fontSize: 14),
                                decoration: const InputDecoration(
                                    isDense: true,
                                    hintText:
                                        'Printed on the certificate as you write it',
                                    border: OutlineInputBorder()),
                              ),
                              _dlgLabel('Issuance date'),
                              _dlgPickerButton(
                                icon: Icons.calendar_today_outlined,
                                text:
                                    DateFormat('MMMM d, yyyy').format(issueDay),
                                onTap: () async {
                                  final d = await _pickDay(ctx, issueDay);
                                  if (d == null) return;
                                  setDialogState(() => issueDay = d);
                                },
                              ),
                              _dlgLabel('Authorized signature *'),
                              TextField(
                                controller: sigCtrl,
                                style: const TextStyle(fontSize: 14),
                                decoration: const InputDecoration(
                                    isDense: true,
                                    border: OutlineInputBorder()),
                              ),
                            ],
                            if (showService) ...[
                              _dlgLabel('Service type'),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  ChoiceChip(
                                    label: const Text('All Services'),
                                    selected: selectedServices.isEmpty,
                                    showCheckmark: false,
                                    selectedColor:
                                        kPrimary.withValues(alpha: 0.14),
                                    onSelected: (_) => setDialogState(
                                        () => selectedServices.clear()),
                                  ),
                                  for (final s in services)
                                    FilterChip(
                                      label: Text(s),
                                      selected: selectedServices.contains(s),
                                      selectedColor:
                                          kPrimary.withValues(alpha: 0.14),
                                      onSelected: (on) => setDialogState(() {
                                        if (on) {
                                          selectedServices.add(s);
                                        } else {
                                          selectedServices.remove(s);
                                        }
                                      }),
                                    ),
                                ],
                              ),
                            ],
                            if (showPeriod) ...[
                              _dlgLabel('Period'),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  for (final p in _printPeriods)
                                    ChoiceChip(
                                      label: Text(p),
                                      selected: period == p,
                                      showCheckmark: false,
                                      selectedColor:
                                          kPrimary.withValues(alpha: 0.14),
                                      labelStyle: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color:
                                            period == p ? kPrimary : kTextSub,
                                      ),
                                      side: BorderSide(
                                          color:
                                              period == p ? kPrimary : kBorder),
                                      onSelected: (_) => setDialogState(() {
                                        period = p;
                                        if (p == 'Academic Year' &&
                                            !_acadYears.contains(acadYear)) {
                                          final cur =
                                              ReferenceCatalog.currentPeriod;
                                          acadYear = (cur != null &&
                                                  _acadYears
                                                      .contains(cur.acadYear))
                                              ? cur.acadYear
                                              : (_acadYears.isNotEmpty
                                                  ? _acadYears.first
                                                  : '');
                                          semester = (cur != null &&
                                                  cur.acadYear == acadYear)
                                              ? cur.semester
                                              : '';
                                        }
                                        error = null;
                                      }),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              if (period == 'Custom')
                                _dlgPickerButton(
                                  icon: Icons.date_range_outlined,
                                  text: custom == null
                                      ? 'Pick a date range'
                                      : _rangeText(custom!),
                                  onTap: () async {
                                    final r = await _pickRange(ctx, custom);
                                    if (r == null) return;
                                    setDialogState(() {
                                      custom = r;
                                      error = null;
                                    });
                                  },
                                )
                              else if (period == 'Academic Year')
                                Row(children: [
                                  Expanded(
                                    child: _dlgDropdown(
                                      value: _acadYears.contains(acadYear)
                                          ? acadYear
                                          : '',
                                      items: [
                                        if (!_acadYears.contains(acadYear))
                                          const DropdownMenuItem(
                                              value: '',
                                              child: Text('No academic year')),
                                        for (final y in _acadYears)
                                          DropdownMenuItem(
                                              value: y,
                                              child: Text(
                                                  'AY $y${_hasVisitsIn(y) ? '' : ''}')),
                                      ],
                                      onChanged: (v) => setDialogState(() {
                                        acadYear = v ?? '';
                                        semester = '';
                                      }),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Builder(builder: (_) {
                                      final sems = <String>[];
                                      for (final p
                                          in ReferenceCatalog
                                              .periodsNewestFirst) {
                                        if (p.acadYear == acadYear &&
                                            p.semester.isNotEmpty &&
                                            !sems.contains(p.semester)) {
                                          sems.add(p.semester);
                                        }
                                      }
                                      return _dlgDropdown(
                                        value: sems.contains(semester)
                                            ? semester
                                            : '',
                                        items: [
                                          const DropdownMenuItem(
                                              value: '',
                                              child: Text('All Semesters')),
                                          for (final s in sems)
                                            DropdownMenuItem(
                                                value: s,
                                                child: Text(
                                                    '$s${_hasVisitsIn(acadYear, s) ? '' : ' '}')),
                                        ],
                                        onChanged: (v) => setDialogState(
                                            () => semester = v ?? ''),
                                      );
                                    }),
                                  ),
                                ])
                              else
                                Text(resolvedText,
                                    style: const TextStyle(
                                        fontSize: 12.5, color: kTextSub)),
                            ],
                            if (report == _PrintReport.daily) ...[
                              _dlgLabel('Date'),
                              _dlgPickerButton(
                                icon: Icons.calendar_today_outlined,
                                text: DateFormat('MMMM d, yyyy').format(day),
                                onTap: () async {
                                  final d = await _pickDay(ctx, day);
                                  if (d == null) return;
                                  setDialogState(() => day = d);
                                },
                              ),
                            ],
                            if (showInstitute) ...[
                              _dlgLabel(report == _PrintReport.byInstitute
                                  ? 'Institute *'
                                  : 'Institute'),
                              _dlgDropdown(
                                value: institute,
                                items: [
                                  DropdownMenuItem(
                                      value: '',
                                      child: Text(
                                          report == _PrintReport.byInstitute
                                              ? 'Select institute...'
                                              : 'All Institutes')),
                                  for (final i in _institutes)
                                    DropdownMenuItem(value: i, child: Text(i)),
                                ],
                                onChanged: (v) => setDialogState(() {
                                  institute = v ?? '';
                                  error = null;
                                }),
                              ),
                            ],
                            if (report == _PrintReport.individual) ...[
                              const SizedBox(height: 8),
                              CheckboxListTile(
                                value: blankRows,
                                onChanged: (v) => setDialogState(
                                    () => blankRows = v ?? false),
                                contentPadding: EdgeInsets.zero,
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                dense: true,
                                activeColor: kPrimary,
                                title: const Text(
                                    'Include printable blank rows',
                                    style: TextStyle(fontSize: 13.5)),
                              ),
                            ],
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: const Row(children: [
                                Icon(Icons.info_outline,
                                    size: 16, color: kPrimary),
                                SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                      'Only records matching the selected criteria will be included. '
                                      'Paper size is chosen in the print dialog.',
                                      style: TextStyle(
                                          fontSize: 12.5, color: kTextSub)),
                                ),
                              ]),
                            ),
                            if (error != null) ...[
                              const SizedBox(height: 12),
                              Text(error!,
                                  style: const TextStyle(
                                      color: kDanger,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600)),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      TextButton(
                        onPressed: () => setDialogState(resetAll),
                        child: const Text('Reset Filters',
                            style: TextStyle(color: kTextSub, fontSize: 13)),
                      ),
                      const Spacer(),
                      OutlinedButton(
                        onPressed: () => Navigator.pop(ctx),
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: kBorder),
                          foregroundColor: kTextSub,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                        child: const Text('Cancel'),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton.icon(
                        onPressed: () {
                          final String? err = validate();
                          if (err != null) {
                            setDialogState(() => error = err);
                            return;
                          }
                          final _PrintCriteria c = buildCriteria();
                          final bool blankOk =
                              c.report == _PrintReport.individual &&
                                  c.blankRows;
                          if (c.report != _PrintReport.certificate &&
                              _recordsForPrint(c).isEmpty &&
                              !blankOk) {
                            setDialogState(() => error =
                                'No records found for the selected criteria.');
                            return;
                          }
                          Navigator.pop(ctx, c);
                        },
                        icon: const Icon(Icons.print_outlined, size: 16),
                        label: const Text('Preview & Print',
                            style: TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 13)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: kPrimary,
                          foregroundColor: Colors.white,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 16, vertical: 12),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    if (result == null) return;
    if (result.report == _PrintReport.certificate) {
      await _printCertificate(result);
      return;
    }
    await _showPrintPreview(criteria: result);
  }

  Future<void> _showPrintPreview({required _PrintCriteria criteria}) async {
    final ids = <String>{
      for (final r in _recordsForPrint(criteria))
        if ((r["visitId"] ?? '').trim().isNotEmpty) (r["visitId"] ?? '').trim(),
    }.toList();

    if (!mounted) return;

    // Web: build an HTML page and open Chrome's print dialog. Chrome lays the
    // page out again for whatever paper size is chosen in that dialog.
    if (htmlPrintSupported) {
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => const Center(child: CircularProgressIndicator()),
      );
      String? html;
      Object? failure;
      try {
        await _loadForPrint(ids);
        html = await _buildHtml(criteria);
      } catch (e) {
        failure = e;
      }
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // close the spinner
      if (failure != null || html == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not prepare the report: $failure')),
        );
        return;
      }
      try {
        await printHtml(html, title: 'TCGC ${criteria.report.label}');
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not print the report: $e')),
        );
      }
      return;
    }

    // Other platforms: the original PDF preview.
    // The preview opens at once and shows "Preparing report…" while the
    // missing visit details load.
    await showDialog<void>(
      context: context,
      builder: (_) => _BookletPrintSheet(
        title: 'Print Preview — ${criteria.report.label}',
        fileName: 'TCGC ${criteria.report.label}',
        prepare: () => _loadForPrint(ids),
        buildPdf: (format) async =>
            (await _buildDocument(criteria: criteria, pageFormat: format))
                .save(),
      ),
    );
  }

  /// Only fetches visits that are not loaded yet.
  Future<void> _loadForPrint(List<String> ids) async {
    if (_inflight.isNotEmpty) await Future.wait(_inflight.toList());
    final missing = [
      for (final i in ids)
        if (!_savedVisits.containsKey(i) && !_detailsRequested.contains(i)) i,
    ];
    if (missing.isEmpty) return;
    final saved = await VisitDetailsService.readVisits(missing);
    _savedVisits.addAll(saved);
    _detailsRequested.addAll(missing);
    if (mounted) setState(() {});
  }

  String _dateLine(_PrintCriteria c) {
    if (c.acadYear.isNotEmpty) {
      return 'AY ${c.acadYear}${c.semester.isEmpty ? '' : ' · ${c.semester}'}';
    }
    final w = c.window;
    if (w == null) return 'All Records';
    final s = w.start, e = w.end;
    if (s == e) return DateFormat('MMM d, yyyy').format(s).toUpperCase();
    if (s.year != e.year) {
      return '${DateFormat('MMMM d, yyyy').format(s)} - ${DateFormat('MMMM d, yyyy').format(e)}';
    }
    if (s.month == e.month) {
      return '${DateFormat('MMMM').format(s)} ${s.day}-${e.day}, ${s.year}';
    }
    return '${DateFormat('MMMM d').format(s)} - ${DateFormat('MMMM d').format(e)}, ${s.year}';
  }

  String _instituteLineFor(_PrintCriteria criteria) => _instituteFullName(
        criteria.report == _PrintReport.individual
            ? (_rosterById[(criteria.personId ?? '').trim()]?.institute ?? '')
            : (criteria.institute ?? ''),
      );

  Future<pw.Document> _buildDocument(
      {required _PrintCriteria criteria, required PdfPageFormat pageFormat}) {
    return BookletPrint.build(
      kind: BookletReportKind.values.byName(criteria.report.name),
      title: criteria.report.paperTitle,
      dateLine: _dateLine(criteria),
      nameLine: criteria.personName ?? '',
      instituteLine: _instituteLineFor(criteria),
      records: _recordsForPrint(criteria),
      visitFor: _visitFor,
      roster: _rosterById,
      pageFormat: pageFormat,
      serviceLabels: criteria.services,
      blankRows: criteria.blankRows,
      draftLabel: (d, c) => _draftLabel(d, c.vitals),
    );
  }

  Future<String> _buildHtml(_PrintCriteria criteria) {
    return BookletPrint.buildHtml(
      kind: BookletReportKind.values.byName(criteria.report.name),
      title: criteria.report.paperTitle,
      dateLine: _dateLine(criteria),
      nameLine: criteria.personName ?? '',
      instituteLine: _instituteLineFor(criteria),
      records: _recordsForPrint(criteria),
      visitFor: _visitFor,
      roster: _rosterById,
      serviceLabels: criteria.services,
      blankRows: criteria.blankRows,
      draftLabel: (d, c) => _draftLabel(d, c.vitals),
    );
  }

  @override
  Widget build(BuildContext context) {
    final summary = _getVisitSummary();

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: kBg,
        floatingActionButton: FloatingActionButton(
          onPressed: _showPrintRecordsDialog,
          backgroundColor: kPrimary,
          child: const Icon(Icons.print_outlined, color: Colors.white),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeaderRow(summary),
                const SizedBox(height: 20),
                _buildSearchAndFilters(),
                const SizedBox(height: 16),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildTable(null),
                      _buildTable("Student"),
                      _buildTable("Faculty"),
                      _buildTable("Staff"),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderRow(Map<String, int> summary) {
    return LayoutBuilder(builder: (context, constraints) {
      final bool isNarrow = constraints.maxWidth < 700;

      final titleBlock = Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [kPrimary, kPrimaryDk],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.menu_book_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text("Medical Records",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        color: kTextDark,
                        fontWeight: FontWeight.w800,
                        fontSize: 22)),
                Text("Manage student, faculty & staff visit records",
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: kTextSub, fontSize: 13.5)),
              ],
            ),
          ),
          const SizedBox(width: 6),
        ],
      );

      final chips = _buildCategorySummary(summary);

      if (isNarrow) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(width: constraints.maxWidth, child: titleBlock),
            const SizedBox(height: 12),
            chips,
          ],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(child: titleBlock),
          const SizedBox(width: 12),
          Flexible(
            child: Align(alignment: Alignment.centerRight, child: chips),
          ),
        ],
      );
    });
  }

  Widget _buildCategorySummary(Map<String, int> summary) {
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 8,
      children: [
        _summaryChip('All', summary['all']!, kPrimary, Icons.groups_rounded),
        _summaryChip('Students', summary['student']!, kStudentColor,
            Icons.school_outlined),
        _summaryChip('Faculty', summary['faculty']!, kFacultyColor,
            Icons.co_present_outlined),
        _summaryChip(
            'Staff', summary['staff']!, kStaffColor, Icons.badge_outlined),
      ],
    );
  }

  Widget _summaryChip(String label, int count, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text('$count',
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 13, color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  /// All / Students / Faculty / Staff switch. It still drives the
  /// TabBarView, so tapping it changes the table exactly as before.
  Widget _buildTabsBar() {
    const labels = ['All', 'Students', 'Faculty', 'Staff'];
    return Builder(builder: (context) {
      final c = DefaultTabController.of(context);
      return AnimatedBuilder(
        animation: c,
        builder: (_, __) => Container(
          height: 40,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: const Color(0xFFEEF2F6),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < labels.length; i++)
                InkWell(
                  borderRadius: BorderRadius.circular(9),
                  onTap: () => c.animateTo(i),
                  child: Container(
                    alignment: Alignment.center,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: c.index == i ? kPrimary : Colors.transparent,
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Text(
                      labels[i],
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: c.index == i ? Colors.white : kTextSub,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }

  /// Search bar on top; the filter chips below it on the left and the
  /// All / Students / Faculty / Staff switch on the right.
  Widget _buildSearchAndFilters() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _searchField(),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, constraints) {
          final controls = Wrap(
            spacing: 10,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: _filterControls(),
          );
          if (constraints.maxWidth < 1180) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                controls,
                const SizedBox(height: 10),
                _buildTabsBar(),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: controls),
              const SizedBox(width: 16),
              _buildTabsBar(),
            ],
          );
        }),
      ],
    );
  }

  List<Widget> _filterControls() {
    final Widget? extra = _extraDateControl();
    return [
      _dateModeDropdown(),
      if (extra != null) extra,
      _instituteDropdown(),
      if (_activeInstitute.isNotEmpty) _programDropdown(),
      _sexDropdown(),
      _ageDropdown(),
      _birthChip(),
      if (_hasActiveFilters) _clearFiltersButton(),
    ];
  }

  bool get _hasActiveFilters =>
      selectedFilter != 'Today' ||
      _activeInstitute.isNotEmpty ||
      _activeProgram.isNotEmpty ||
      selectedSex.isNotEmpty ||
      selectedAge != null ||
      birthRange != null;

  void _clearFilters() {
    setState(() {
      selectedFilter = 'Today';
      selectedYear = null;
      selectedRange = null;
      selectedAcadYear = '';
      selectedSemester = '';
      selectedInstitute = '';
      selectedProgram = '';
      selectedSex = '';
      selectedAge = null;
      birthRange = null;
    });
  }

  Widget _clearFiltersButton() {
    return Tooltip(
      message: 'Clear filters',
      child: InkWell(
        onTap: _clearFilters,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          width: 40,
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kBorder),
          ),
          child: const Icon(Icons.close_rounded, size: 16, color: kTextSub),
        ),
      ),
    );
  }

  // ---- Sex / Age / Birth date controls -----------------------------------
  Widget _sexDropdown() => _filterDropdown<String>(
        icon: Icons.wc_rounded,
        value: selectedSex,
        active: selectedSex.isNotEmpty,
        items: const [
          DropdownMenuItem(value: '', child: Text('All Sexes')),
          DropdownMenuItem(value: 'Male', child: Text('Male')),
          DropdownMenuItem(value: 'Female', child: Text('Female')),
        ],
        onChanged: (v) => setState(() => selectedSex = v ?? ''),
      );

  /// Lists every age found in the database (from the birth dates).
  Widget _ageDropdown() {
    final ages = _ageOptions;
    final int safe =
        (selectedAge != null && ages.contains(selectedAge)) ? selectedAge! : -1;
    return _filterDropdown<int>(
      icon: Icons.person_outline_rounded,
      value: safe,
      active: selectedAge != null,
      items: [
        const DropdownMenuItem(value: -1, child: Text('All Ages')),
        for (final a in ages)
          DropdownMenuItem(value: a, child: Text('$a yrs')),
      ],
      onChanged: (v) =>
          setState(() => selectedAge = (v == null || v < 0) ? null : v),
    );
  }

  Widget _birthChip() => _pickerChip(
        icon: Icons.cake_outlined,
        label:
            birthRange == null ? 'Birthdate' : _compactRangeLabel(birthRange!),
        active: birthRange != null,
        onTap: _pickBirthRange,
      );

  Future<void> _pickBirthRange() async {
    final r = await _pickRange(
      context,
      birthRange,
      first: DateTime(1930),
      last: DateTime.now(),
    );
    if (r != null && mounted) setState(() => birthRange = r);
  }

  Widget? _extraDateControl() {
    switch (selectedFilter) {
      case 'Academic Year':
        return Row(mainAxisSize: MainAxisSize.min, children: [
          _acadYearDropdown(),
          const SizedBox(width: 8),
          _semesterDropdown(),
        ]);
      case 'Year':
        return _yearDropdown();
      case 'Pick Date':
        return _pickerChip(
          icon: Icons.calendar_today_outlined,
          label: DateFormat("MMM d, yyyy").format(selectedDate),
          active: true,
          onTap: _changeDate,
        );
      case 'Date Range':
        final DateTimeRange? range = selectedRange;
        return _pickerChip(
          icon: Icons.date_range_outlined,
          label: range == null ? "Pick a range" : _compactRangeLabel(range),
          active: true,
          onTap: _changeRange,
        );
      default:
        return null;
    }
  }

  String _compactRangeLabel(DateTimeRange range) {
    if (range.start.year == range.end.year) {
      return '${DateFormat('MMM d').format(range.start)} – '
          '${_fmtShort(range.end)}';
    }
    return '${_fmtShort(range.start)} – ${_fmtShort(range.end)}';
  }

  List<int> get _availableYears {
    final Set<int> years = <int>{DateTime.now().year};
    for (final Map<String, String> r in _allRecords) {
      final DateTime? d = DateTime.tryParse(r["date"] ?? '');
      if (d != null) years.add(d.year);
    }
    return years.toList()..sort((a, b) => b.compareTo(a));
  }

  Widget _dateModeDropdown() {
    final String safe =
        _dateFilterModes.contains(selectedFilter) ? selectedFilter : 'All';
    return _filterDropdown<String>(
      value: safe,
      icon: Icons.calendar_month_outlined,
      active: selectedFilter != 'Today',
      items: [
        for (final String mode in _dateFilterModes)
          DropdownMenuItem(value: mode, child: Text(mode)),
      ],
      onChanged: _onDateModeChanged,
    );
  }

  /// Every academic year in the academic_periods table (newest first),
  /// whether or not it has visits yet.
  List<String> get _acadYears {
    final out = <String>[];
    for (final p in ReferenceCatalog.periodsNewestFirst) {
      if (p.acadYear.isNotEmpty && !out.contains(p.acadYear)) {
        out.add(p.acadYear);
      }
    }
    return out;
  }

  List<String> get _semestersOfYear {
    final out = <String>[];
    for (final p in ReferenceCatalog.periodsNewestFirst) {
      if (p.acadYear == selectedAcadYear &&
          p.semester.isNotEmpty &&
          !out.contains(p.semester)) {
        out.add(p.semester);
      }
    }
    return out;
  }

  Widget _acadYearDropdown() {
    final years = _acadYears;
    if (years.isEmpty) {
      return _filterDropdown<String>(
        icon: Icons.school_outlined,
        value: '',
        active: true,
        items: const [
          DropdownMenuItem(value: '', child: Text('No academic year'))
        ],
        onChanged: (_) {},
      );
    }
    final safe =
        years.contains(selectedAcadYear) ? selectedAcadYear : years.first;
    return _filterDropdown<String>(
      icon: Icons.school_outlined,
      value: safe,
      active: true,
      items: [
        for (final y in years)
          DropdownMenuItem(
              value: y,
              child: Text('AY $y${_hasVisitsIn(y) ? '' : ' '}')),
      ],
      onChanged: (v) {
        if (v == null) return;
        setState(() {
          selectedAcadYear = v;
          selectedSemester = '';
        });
      },
    );
  }

  Widget _semesterDropdown() {
    final sems = _semestersOfYear;
    final safe = sems.contains(selectedSemester) ? selectedSemester : '';
    return _filterDropdown<String>(
      icon: Icons.event_note_outlined,
      value: safe,
      active: true,
      items: [
        const DropdownMenuItem(value: '', child: Text('All Semesters')),
        for (final s in sems)
          DropdownMenuItem(
              value: s,
              child: Text(
                  '$s${_hasVisitsIn(selectedAcadYear, s) ? '' : ' '}')),
      ],
      onChanged: (v) => setState(() => selectedSemester = v ?? ''),
    );
  }

  Widget _yearDropdown() {
    final List<int> years = _availableYears;
    final int safe = years.contains(selectedYear)
        ? selectedYear!
        : (years.isNotEmpty ? years.first : DateTime.now().year);
    return _filterDropdown<int>(
      icon: Icons.calendar_today_outlined,
      value: safe,
      active: true,
      items: [
        for (final int y in years)
          DropdownMenuItem(value: y, child: Text('$y')),
      ],
      onChanged: (v) {
        if (v == null) return;
        setState(() => selectedYear = v);
      },
    );
  }

  String get _activeInstitute {
    final String code = selectedInstitute.trim();
    if (code.isEmpty) return '';
    return _instituteOptions.contains(code) ? code : '';
  }

  String get _activeProgram {
    final String code = selectedProgram.trim();
    if (code.isEmpty) return '';
    return _programOptions.contains(code) ? code : '';
  }

  Widget _instituteDropdown() {
    final List<String> options = _instituteOptions;
    return _filterDropdown<String>(
      icon: Icons.apartment_rounded,
      value: _activeInstitute,
      active: _activeInstitute.isNotEmpty,
      items: [
        const DropdownMenuItem(value: '', child: Text('All Institutes')),
        for (final String code in options)
          DropdownMenuItem(value: code, child: Text(code)),
      ],
      onChanged: (v) {
        if (v == null) return;
        setState(() {
          selectedInstitute = v;
          selectedProgram = '';
        });
      },
    );
  }

  Widget _programDropdown() {
    final List<String> options = _programOptions;
    return _filterDropdown<String>(
      icon: Icons.school_outlined,
      value: _activeProgram,
      active: _activeProgram.isNotEmpty,
      items: [
        const DropdownMenuItem(value: '', child: Text('All Programs')),
        for (final String code in options)
          DropdownMenuItem(value: code, child: Text(code)),
      ],
      onChanged: (v) {
        if (v == null) return;
        setState(() => selectedProgram = v);
      },
    );
  }

  List<String> get _instituteOptions {
    final Set<String> codes = <String>{};
    for (final Map<String, String> r in _allRecords) {
      final String code = (r["institute"] ?? '').trim();
      if (code.isNotEmpty) codes.add(code);
    }
    for (final String code in ReferenceCatalog.instituteCodes) {
      final String trimmed = code.trim();
      if (trimmed.isNotEmpty) codes.add(trimmed);
    }
    return codes.toList()..sort();
  }

  List<String> get _programOptions {
    final Set<String> codes = <String>{};
    final String institute = _activeInstitute;
    final bool scoped = institute.isNotEmpty;
    final String want = institute.toLowerCase();
    for (final Map<String, String> r in _allRecords) {
      if (scoped && (r["institute"] ?? '').trim().toLowerCase() != want) {
        continue;
      }
      final String code = (r["program"] ?? '').trim();
      if (code.isNotEmpty) codes.add(code);
    }
    if (scoped) {
      final String? instituteId =
          ReferenceCatalog.instituteByCode(institute)?.id;
      if (instituteId != null) {
        for (final String code in ReferenceCatalog.programsOf(instituteId)) {
          final String trimmed = code.trim();
          if (trimmed.isNotEmpty) codes.add(trimmed);
        }
      }
    } else {
      for (final ProgramOption p in ReferenceCatalog.programs) {
        final String trimmed = p.code.trim();
        if (trimmed.isNotEmpty) codes.add(trimmed);
      }
    }
    return codes.toList()..sort();
  }

  /// One look for every filter control: white chip, soft border, icon in
  /// front. Turns green when the filter is active.
  BoxDecoration _filterDeco(bool active) => BoxDecoration(
        color: active ? kPrimary.withValues(alpha: 0.07) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: active ? kPrimary : kBorder, width: active ? 1.2 : 1),
      );

  Widget _filterDropdown<T>({
    required T value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T?> onChanged,
    bool active = false,
    IconData? icon,
  }) {
    return Container(
      height: 40,
      padding: const EdgeInsets.only(left: 12, right: 6),
      decoration: _filterDeco(active),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 16, color: active ? kPrimary : kTextSub),
            const SizedBox(width: 8),
          ],
          DropdownButtonHideUnderline(
            child: DropdownButton<T>(
              value: value,
              isDense: true,
              dropdownColor: Colors.white,
              borderRadius: BorderRadius.circular(12),
              icon: Icon(Icons.keyboard_arrow_down_rounded,
                  size: 18, color: active ? kPrimary : kTextSub),
              style: const TextStyle(
                  fontSize: 13, fontWeight: FontWeight.w600, color: kTextMain),
              items: items,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchField() {
    return TextField(
      // Waits a moment after typing stops, so the table is not
      // re-filtered on every key press.
      onChanged: (v) {
        _searchDebounce?.cancel();
        _searchDebounce = Timer(const Duration(milliseconds: 250), () {
          if (mounted) setState(() => searchQuery = v.trim().toLowerCase());
        });
      },
      style: const TextStyle(fontSize: 13.5, color: kTextMain),
      decoration: InputDecoration(
        hintText: "Search by name, ID, complaint...",
        hintStyle: const TextStyle(color: kTextSub, fontSize: 13.5),
        prefixIcon: const Icon(Icons.search_rounded, color: kTextSub, size: 20),
        isDense: true,
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kBorder)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kBorder)),
        focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: kPrimary, width: 1.5)),
      ),
    );
  }

  Widget _pickerChip(
      {required IconData icon,
      required String label,
      required bool active,
      required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: _filterDeco(active),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: active ? kPrimary : kTextSub),
          const SizedBox(width: 8),
          Text(label,
              style: const TextStyle(
                  fontSize: 13,
                  color: kTextMain,
                  fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }

  List<ProcedureRecord> _linkedProcedures(String visitId) {
    final id = visitId.trim();
    if (id.isEmpty) return [];
    return _procedures.where((p) => (p.visitId ?? '').trim() == id).toList();
  }

  String _fmtPDate(DateTime? d) =>
      d == null ? '—' : DateFormat('MMM d, yyyy').format(d);

  String _fmtFollowUp(String yyyyMmDd) {
    final DateTime? d = DateTime.tryParse(yyyyMmDd);
    return d == null ? yyyyMmDd : DateFormat('MMM d, yyyy').format(d);
  }

  Widget _procedureStatusChip(String status) {
    final (Color bg, Color fg) = switch (status) {
      'Pending' => (kWarning.withValues(alpha: 0.14), kWarning),
      'Cancelled' => (kDanger.withValues(alpha: 0.12), kDanger),
      _ => (kSuccess.withValues(alpha: 0.14), kSuccess),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(status,
          style:
              TextStyle(color: fg, fontSize: 11.5, fontWeight: FontWeight.bold)),
    );
  }

  Widget _procedureTile(ProcedureRecord p) {
    final supplies = (p.details["suppliesUsed"] as List?)?.cast<Map>();
    final followUp = p.details["followUpOn"]?.toString();
    final referred = p.details["referredTo"]?.toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.medical_services_outlined,
              size: 16, color: kPrimary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(p.procedureName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: kTextMain)),
          ),
          _procedureStatusChip(p.status),
        ]),
        const SizedBox(height: 6),
        Text(_fmtPDate(p.performedAt),
            style: const TextStyle(fontSize: 12.5, color: kTextSub)),
        if (supplies != null && supplies.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
                "Supplies: ${supplies.map((s) => "${s["name"]} x${s["qty"]}").join(", ")}",
                style: const TextStyle(fontSize: 12.5, color: kTextSub)),
          ),
        if (followUp != null && followUp.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text("Follow-up: ${_fmtFollowUp(followUp)}",
                style: const TextStyle(fontSize: 12.5, color: kTextSub)),
          ),
        if (referred != null && referred.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text("Referred to: $referred",
                style: const TextStyle(fontSize: 12.5, color: kTextSub)),
          ),
      ]),
    );
  }

  String _visitorTermLine(Map<String, String> e) {
    final year = (e["academicYear"] ?? '').trim();
    final sem = (e["semester"] ?? '').trim();
    if (year.isNotEmpty || sem.isNotEmpty) {
      return academicTermLabel(year, sem);
    }
    final profile =
        PatientDirectory.instance.byId((e["personId"] ?? e["id"] ?? '').trim());
    if (profile != null &&
        (profile.academicYear.isNotEmpty || profile.semester.isNotEmpty)) {
      return academicTermLabel(profile.academicYear, profile.semester);
    }
    return (e["year"] ?? "").trim();
  }

  List<String> _bookletHeaders(String? type) {
    switch (type) {
      case 'Student':
        return const [
          'VISITOR',
          'INSTITUTE',
          'PROGRAM',
          'REASON / COMPLAINT',
          'SERVICES',
          'DATE & TIME',
        ];
      case 'Faculty':
        return const [
          'VISITOR',
          'INSTITUTE',
          'REASON / COMPLAINT',
          'SERVICES',
          'DATE & TIME'
        ];
      case 'Staff':
        return const [
          'VISITOR',
          'DEPARTMENT / POSITION',
          'REASON / COMPLAINT',
          'SERVICES',
          'DATE & TIME',
        ];
      default:
        return const [
          'VISITOR',
          'TYPE',
          'REASON / COMPLAINT',
          'SERVICES',
          'DATE & TIME'
        ];
    }
  }

  Widget _affiliationCell(String main, [String sub = '']) {
    final m = main.trim();
    final s = sub.trim();
    if (m.isEmpty && s.isEmpty) {
      return const Align(
          alignment: Alignment.centerLeft,
          child: Text('-', style: TextStyle(color: kTextSub)));
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(m.isEmpty ? '-' : m,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: m.isEmpty
                ? const TextStyle(fontSize: 14, color: kTextSub)
                : const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: kPrimary)),
        if (s.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(s,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: kTextSub)),
        ],
      ],
    );
  }

  Widget _typePill(String t) {
    Color bg, fg;
    switch (t) {
      case "Student":
        bg = const Color(0xFFDBEAFE);
        fg = kStudentColor;
        break;
      case "Faculty":
        bg = const Color(0xFFFEF3C7);
        fg = kFacultyColor;
        break;
      default:
        if (t == "Staff") {
          bg = const Color(0xFFEDE9FE);
          fg = kStaffColor;
        } else {
          bg = const Color(0xFFEEF1F5);
          fg = kTextSub;
        }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(t,
          style:
              TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.bold)),
    );
  }

  static const double _servicesColWidth = 230;

  Widget _serviceCell(List<String> names, {required double maxWidth}) {
    if (names.isEmpty) {
      return const Text('-', style: TextStyle(color: kTextSub));
    }
    const maxShown = 3;
    final shown = names.take(maxShown).toList();
    final hidden = names.length - shown.length;
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (final n in shown)
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxWidth),
            child: _serviceChip(n),
          ),
        if (hidden > 0)
          Tooltip(
            message: names.skip(maxShown).join(', '),
            triggerMode: TooltipTriggerMode.longPress,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFFEEF1F5),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text('+$hidden',
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: kTextSub)),
            ),
          ),
      ],
    );
  }

  Widget _serviceChip(String name) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: kPrimary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: kPrimary.withValues(alpha: 0.18)),
      ),
      child: Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
            fontSize: 12.5, fontWeight: FontWeight.w600, color: kPrimaryDk),
      ),
    );
  }

  Widget _statusPill(_VisitState s) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: s.color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6)),
      child: Text(
        s.label,
        style: TextStyle(
            color: s.color, fontSize: 12.5, fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _buildTable(String? type) {
    // Filtering + grouping is cached, so switching tabs or rebuilding the
    // page does not repeat the work.
    final allGroups = _groupsFor(type);

    // Only the first page of rows is drawn; "Show more" adds another page.
    final sig = '$type|$_filterSig';
    if (_shownSig != sig) {
      _shownSig = sig;
      _shown = _pageSize;
    }
    final filtered = allGroups.take(_shown).toList();

    // Services/procedures are fetched only for the rows on screen.
    _lastShownIds = [
      for (final g in filtered)
        for (final r in g)
          if ((r["visitId"] ?? '').trim().isNotEmpty) (r["visitId"] ?? '').trim(),
    ];
    final idsToLoad = _lastShownIds;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _ensureDetails(idsToLoad);
    });
    // Wait for the services of the visible rows, so they appear together
    // with the table instead of popping in later.
   /* if (_lastShownIds.any((i) => !_detailsDone.contains(i))) {
      return const Center(child: CircularProgressIndicator(strokeWidth: 3));
    }*/
    final isAll = type == null;
    final isStudent = type == 'Student';
    final isFaculty = type == 'Faculty';
    final isStaff = !isAll && !isStudent && !isFaculty;
    if (!_everLoaded && _loadError == null) return const SizedBox.shrink();
    if (allGroups.isEmpty) {
      if (_loadError != null) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: kDanger.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kDanger.withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            const Icon(Icons.cloud_off_rounded, color: kDanger, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(_loadError!,
                  style: const TextStyle(
                      color: kDanger, fontSize: 13.5, height: 1.4)),
            ),
            IconButton(
              onPressed: _reloadRecords,
              icon: const Icon(Icons.refresh_rounded, color: kDanger, size: 20),
              tooltip: 'Try again',
            ),
          ]),
        );
      }
      final String emptyText = selectedFilter == 'Academic Year'
          ? 'No record yet for AY $selectedAcadYear'
              '${selectedSemester.isEmpty ? '' : ' · $selectedSemester'}'
          : 'No records found';
      return Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.search_off_rounded, size: 48, color: AppColors.borderStrong),
        const SizedBox(height: 8),
        Text(emptyText,
            style: const TextStyle(color: kTextSub, fontSize: 14.5)),
      ]));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_loadError != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: kDanger.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: kDanger.withValues(alpha: 0.28)),
            ),
            child: Row(children: [
              const Icon(Icons.cloud_off_rounded, color: kDanger, size: 17),
              const SizedBox(width: 10),
              Expanded(
                child: Text(_loadError!,
                    style: const TextStyle(
                        color: kDanger, fontSize: 13, height: 1.35)),
              ),
              IconButton(
                onPressed: _reloadRecords,
                icon:
                    const Icon(Icons.refresh_rounded, color: kDanger, size: 18),
                visualDensity: VisualDensity.compact,
                tooltip: 'Try again',
              ),
            ]),
          ),
          const SizedBox(height: 10),
        ],
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kBorder),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: .04),
                      blurRadius: 10,
                      offset: const Offset(0, 2))
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: LayoutBuilder(builder: (context, constraints) {
                  const visitorWidth = 200.0;
                  const typeWidth = 96.0;
                  const instituteWidth = 150.0;
                  const programWidth = 158.0;
                  const reasonWidth = 190.0;
                  const servicesWidth = _servicesColWidth;
                  const dateWidth = 200.0;

                  return SingleChildScrollView(
                    child: Column(
                      children: [
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: ConstrainedBox(
                            constraints:
                                BoxConstraints(minWidth: constraints.maxWidth),
                            child: DataTable(
                              headingRowHeight: 52,
                              dataRowMinHeight: 64,
                              dataRowMaxHeight: 100,
                              showCheckboxColumn: false,
                              headingRowColor: WidgetStateProperty.all(
                                  const Color(0xFFF8FAFC)),
                              headingTextStyle: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: kTextDark,
                                  fontSize: 12.5,
                                  letterSpacing: 0.6),
                              dataTextStyle: const TextStyle(
                                  color: kTextMain, fontSize: 15),
                              columnSpacing: 24,
                              horizontalMargin: 20,
                              dividerThickness: 1,
                              border: const TableBorder(
                                horizontalInside:
                                    BorderSide(color: kBorder, width: 0.8),
                              ),
                              columns: [
                                for (final h in _bookletHeaders(type))
                                  DataColumn(label: Center(child: Text(h))),
                              ],
                              rows: filtered.asMap().entries.map((entry) {
                                final group = entry.value;
                                final e = group.first;
                                final even = entry.key % 2 == 0;
                                final rowType = ((e["type"] ?? '').trim());
                                final isStudentRow = rowType == 'Student';

                                final yearLine =
                                    isStudentRow ? _visitorTermLine(e) : '';
                                final cells = <DataCell>[
                                  DataCell(SizedBox(
                                    width: visitorWidth - 8,
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(e["name"] ?? '',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontWeight: FontWeight.w700,
                                                fontSize: 15,
                                                color: kTextMain)),
                                        const SizedBox(height: 2),
                                        Text(e["id"] ?? '',
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color: kTextSub,
                                                fontWeight: FontWeight.w500)),
                                        if (yearLine.isNotEmpty) ...[
                                          const SizedBox(height: 2),
                                          Text(yearLine,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: const TextStyle(
                                                  fontSize: 12,
                                                  color: kTextSub)),
                                        ],
                                      ],
                                    ),
                                  )),
                                ];
                                if (isAll) {
                                  cells.add(DataCell(SizedBox(
                                    width: typeWidth - 8,
                                    child: Center(child: _typePill(rowType)),
                                  )));
                                } else if (isStudent) {
                                  cells.add(DataCell(SizedBox(
                                    width: instituteWidth - 8,
                                    child:
                                        _affiliationCell(e["institute"] ?? ''),
                                  )));
                                  cells.add(DataCell(SizedBox(
                                    width: programWidth - 8,
                                    child: _affiliationCell(e["program"] ?? ''),
                                  )));
                                } else if (isFaculty) {
                                  cells.add(DataCell(SizedBox(
                                    width: instituteWidth - 8,
                                    child: _affiliationCell(
                                      e["institute"] ?? '',
                                      e["position"] ?? '',
                                    ),
                                  )));
                                } else if (isStaff) {
                                  cells.add(DataCell(SizedBox(
                                    width: instituteWidth - 8,
                                    child: _affiliationCell(
                                      e["department"] ?? '',
                                      e["position"] ?? '',
                                    ),
                                  )));
                                }

                                final reasonText = _mergedReason(group);

                                cells.add(DataCell(SizedBox(
                                  width: reasonWidth - 8,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: reasonText.isEmpty
                                        ? const Text('-',
                                            style: TextStyle(color: kTextSub))
                                        : Tooltip(
                                            message: reasonText,
                                            child: Text(reasonText,
                                                maxLines: 2,
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(
                                                    fontSize: 13.5,
                                                    height: 1.3,
                                                    color: kTextMain)),
                                          ),
                                  ),
                                )));
                                cells.add(DataCell(SizedBox(
                                  width: servicesWidth - 8,
                                  child: Align(
                                    alignment: Alignment.centerLeft,
                                    child: _serviceCell(
                                        _mergedServiceNames(group),
                                        maxWidth: servicesWidth - 8),
                                  ),
                                )));
                                cells.add(DataCell(SizedBox(
                                  width: dateWidth - 8,
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(_fmtDisplayDate(e["date"] ?? ''),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontSize: 14,
                                              fontWeight: FontWeight.w600,
                                              color: kTextMain)),
                                      const SizedBox(height: 2),
                                      for (final r in group)
                                        Text(_sessionTimes(r),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                                fontSize: 12,
                                                color: kTextSub)),
                                    ],
                                  ),
                                )));
                                return DataRow(
                                  color:
                                      WidgetStateProperty.resolveWith((s) {
                                    if (s.contains(WidgetState.hovered)) {
                                      return kPrimary.withValues(alpha: 0.04);
                                    }
                                    return even
                                        ? Colors.white
                                        : const Color(0xFFFAFCFD);
                                  }),
                                  onSelectChanged: (_) =>
                                      _showDetailDialog(group),
                                  cells: cells,
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                        if (allGroups.length > filtered.length)
                          Padding(
                            padding: const EdgeInsets.all(12),
                            child: TextButton.icon(
                              onPressed: () async {
                                final next = [
                                  for (final g
                                      in allGroups.skip(_shown).take(_pageSize))
                                    for (final r in g)
                                      if ((r["visitId"] ?? '').trim().isNotEmpty)
                                        (r["visitId"] ?? '').trim(),
                                ];
                                await _ensureDetails(next);
                                if (mounted) {
                                  setState(() => _shown += _pageSize);
                                }
                              },
                              icon: const Icon(Icons.expand_more_rounded,
                                  color: kPrimary),
                              label: Text(
                                  'Show more (${allGroups.length - filtered.length} left)',
                                  style: const TextStyle(color: kPrimary)),
                            ),
                          ),
                      ],
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BookletPrintSheet extends StatefulWidget {
  const _BookletPrintSheet({
    required this.title,
    required this.fileName,
    required this.buildPdf,
    required this.prepare,
  });

  final String title;
  final String fileName;

  final Future<Uint8List> Function(PdfPageFormat format) buildPdf;

  /// Loads whatever the report still needs (runs while the spinner shows).
  final Future<void> Function() prepare;

  @override
  State<_BookletPrintSheet> createState() => _BookletPrintSheetState();
}

class _BookletPrintSheetState extends State<_BookletPrintSheet> {
  bool _printing = false;
  bool _ready = false;
  late Future<void> _prep;
  final Map<String, Future<Uint8List>> _pdfCache = {};

  PdfPageFormat get _format => PdfPageFormat.letter;

  @override
  void initState() {
    super.initState();
    _start();
  }

  void _start() {
    _ready = false;
    _prep = widget.prepare().then((_) {
      if (mounted) setState(() => _ready = true);
    });
  }

  /// Same paper size = same PDF, so Print does not rebuild what the
  /// preview already built.
  Future<Uint8List> _build(PdfPageFormat paper) {
    final key = '${paper.width}x${paper.height}';
    return _pdfCache.putIfAbsent(key, () {
      final f = widget.buildPdf(paper);
      f.catchError((_) {
        _pdfCache.remove(key);
        return Uint8List(0);
      });
      return f;
    });
  }

  Future<void> _print() async {
    if (_printing || !_ready) return;
    setState(() => _printing = true);

    final messenger = ScaffoldMessenger.of(context);
    try {
      await Printing.layoutPdf(
        name: '${widget.fileName}.pdf',
        format: _format,
        dynamicLayout: true,
        onLayout: (paper) => _build(paper),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not print the report: $e')),
      );
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog.fullscreen(
      child: Scaffold(
        backgroundColor: AppColors.bgAlt,
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: AppColors.textMain,
          elevation: 0.5,
          titleSpacing: 20,
          title: Text(
            widget.title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Close preview',
            onPressed: () => Navigator.pop(context),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.print),
              tooltip: 'Print',
              onPressed: (_printing || !_ready) ? null : _print,
            ),
            const SizedBox(width: 12),
          ],
        ),
        body: FutureBuilder<void>(
          future: _prep,
          builder: (context, snap) {
            if (snap.hasError) {
              return Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Could not load the visit details:\n${snap.error}',
                        textAlign: TextAlign.center),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => setState(_start),
                      child: const Text('Try again'),
                    ),
                  ],
                ),
              );
            }
            if (snap.connectionState != ConnectionState.done) {
              return const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(strokeWidth: 3),
                    SizedBox(height: 14),
                    Text('Preparing report…',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                  ],
                ),
              );
            }
            return PdfPreviewCustom(
              pageFormat: _format,
              build: _build,
              pagesBuilder: _fitPages,
            );
          },
        ),
      ),
    );
  }

  Widget _fitPages(BuildContext context, List<PdfPreviewPageData> pages) {
    const gap = 16.0;
    const pad = 16.0;
    if (pages.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(builder: (context, constraints) {
      final availW =
          (constraints.maxWidth.isFinite ? constraints.maxWidth : 800.0) -
              2 * pad;
      final availH =
          (constraints.maxHeight.isFinite ? constraints.maxHeight : 600.0) -
              2 * pad;
      if (availW <= 0 || availH <= 0) return const SizedBox.shrink();

      final n = pages.length;
      var cols = 1;
      while (cols * cols < n) {
        cols++;
      }
      final rows = (n + cols - 1) ~/ cols;

      var cellW = (availW - gap * (cols - 1)) / cols;
      var cellH = cellW / pages.first.aspectRatio;
      final rowH = (availH - gap * (rows - 1)) / rows;
      if (cellH > rowH) {
        cellH = rowH;
        cellW = cellH * pages.first.aspectRatio;
      }
      if (cellW <= 0 || cellH <= 0) return const SizedBox.shrink();

      return Center(
        child: Padding(
          padding: const EdgeInsets.all(pad),
          child: Wrap(
            alignment: WrapAlignment.center,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final page in pages)
                Container(
                  width: cellW,
                  height: cellH,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: const Color(0xFFDADADA)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x33000000),
                        offset: Offset(0, 3),
                        blurRadius: 5,
                      ),
                    ],
                  ),
                  child: InteractiveViewer(
                    maxScale: 5,
                    child: Image(
                      image: page.image,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox.expand(),
                    ),
                  ),
                ),
            ],
          ),
        ),
      );
    });
  }
}