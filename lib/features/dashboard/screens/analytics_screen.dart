import 'package:flutter/material.dart';
import 'package:clinicmanagementsystem/core/config/supabase_config.dart';
import 'package:clinicmanagementsystem/core/services/data_tracker.dart';
import 'package:clinicmanagementsystem/features/inventory/services/medicine_service.dart';
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
  final String reason;
  final String instituteCode;
  final String programCode;
  final List<String> services;

  /// Every (school year, semester) the patient has an academic record in.
  final List<({String year, String semester})> periods;

  const _ReportVisit({
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

  String _selectedView = 'Daily';
  DateTimeRange? _insightsCustomRange;

  String _selectedAcadYear = 'All';
  String _selectedSemester = 'All';
  String _selectedService = 'All';
  bool _showAllServices = false;
  final Set<String> _expandedTypes = {};

  List<Medicine> _medicines = [];

  List<_ReportVisit> _visits = [];
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
        for (final s in _asList(row['clinic_visit_services'])) {
          final st = _asMap(s['service_types']);
          final n = '${st['service_name'] ?? st['service_code'] ?? ''}'.trim();
          if (n.isNotEmpty && !services.contains(n)) services.add(n);
        }

        final name = [
          '${person['fn'] ?? ''}'.trim(),
          '${person['mn'] ?? ''}'.trim(),
          '${person['ln'] ?? ''}'.trim(),
        ].where((e) => e.isNotEmpty).join(' ');

        return _ReportVisit(
          visitId: '${row['visit_id'] ?? ''}',
          personId: '${row['person_id'] ?? ''}',
          name: name,
          personType: '${person['person_type'] ?? ''}'.trim(),
          visitDate: DateTime.tryParse('${row['visit_date'] ?? ''}'),
          visitTime: '${row['visit_time'] ?? ''}'.trim(),
          reason: '${row['reason_for_visit'] ?? ''}'.trim(),
          instituteCode: '${institute['code'] ?? ''}'.trim(),
          programCode: '${program['code'] ?? ''}'.trim(),
          services: services,
          periods: vPeriods,
        );
      }).toList();

      if (!mounted) return;
      setState(() {
        _visits = visits;
        _periodOptions = periods;
        _loadingVisits = false;
        if (_selectedService != 'All' &&
            !_availableServices.contains(_selectedService)) {
          _selectedService = 'All';
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

  String _fmtDate(DateTime d) {
    const months = [
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
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

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
    String base;
    switch (_selectedView) {
      case 'Custom':
        base = _insightsCustomRange != null
            ? '${_fmtDate(_insightsCustomRange!.start)} - ${_fmtDate(_insightsCustomRange!.end)}'
            : 'Custom range - pick dates';
        break;
      case 'School Year':
        if (_selectedAcadYear == 'All') {
          base = 'all school years';
        } else {
          base = 'A.Y. $_selectedAcadYear';
          if (_selectedSemester != 'All') base += ' - $_semesterLabel';
        }
        break;
      default:
        base = _selectedView;
    }
    if (_selectedService != 'All') base += ' · $_selectedService';
    return base;
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

  bool _hasService(_ReportVisit v) =>
      _selectedService == 'All' || v.services.contains(_selectedService);

  List<_ReportVisit> _visitsInRange() =>
      _visits.where((v) => _inPeriod(v) && _hasService(v)).toList();

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

  String _mostCommonReasonFor(String category) {
    final counts = <String, int>{};
    for (final v in _visitsInRange()) {
      if (v.personType != category) continue;
      final r = v.reason.trim();
      if (r.isEmpty) continue;
      counts[r] = (counts[r] ?? 0) + 1;
    }
    if (counts.isEmpty) return '';
    return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
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
      if (d == null || !_hasService(v)) return false;
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
                  _buildDemographicCard(),
                  const SizedBox(height: 18),
                  _servicesReasonsCard(),
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

  // ── Filters: view selector + school year/semester + service ───────────

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
            }),
          ),
          // Semester only shows once a specific school year is picked.
          if (_selectedAcadYear != 'All')
            _filterDropdown(
              icon: Icons.calendar_view_month_rounded,
              value: _selectedSemester,
              options: ['All', ..._availableSemesters],
              allLabel: 'All Semesters',
              onChanged: (v) => setState(() => _selectedSemester = v),
            ),
        ],
        _filterDropdown(
          icon: Icons.medical_services_outlined,
          value: _selectedService,
          options: ['All', ..._availableServices],
          allLabel: 'All Services',
          onChanged: (v) => setState(() => _selectedService = v),
        ),
      ],
    );
  }

  Widget _filterDropdown({
    required IconData icon,
    required String value,
    required List<String> options,
    required String allLabel,
    required ValueChanged<String> onChanged,
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
                      child: Text(o == 'All' ? allLabel : o,
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
                setState(() => _selectedView = view);
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

  // ── Patient breakdown (with full record lists) ────────────────────────

  Widget _buildDemographicCard() {
    final currentData = _currentViewData;
    final total = currentData['Total'] ?? 0;

    return _sectionCard(
      icon: Icons.donut_large_rounded,
      title: 'Patient Breakdown',
      subtitle:
          'Tap a group to see every record for this period and filter',
      child: Column(
        children: [
          _breakdownTile(
              'Student',
              'Students',
              currentData['Students']!.toInt(),
              total,
              _mostCommonReasonFor('Student'),
              AppColors.student,
              Icons.school_outlined),
          _breakdownTile(
              'Faculty',
              'Faculty',
              currentData['Faculty']!.toInt(),
              total,
              _mostCommonReasonFor('Faculty'),
              AppColors.faculty,
              Icons.co_present_outlined),
          _breakdownTile(
              'Staff',
              'Staff',
              currentData['Staff']!.toInt(),
              total,
              _mostCommonReasonFor('Staff'),
              AppColors.staff,
              Icons.badge_outlined),
        ],
      ),
    );
  }

  List<_ReportVisit> _recordsFor(String personType) {
    final list =
        _visitsInRange().where((v) => v.personType == personType).toList();
    list.sort((a, b) {
      final da = a.visitDate;
      final db = b.visitDate;
      if (da == null && db == null) return 0;
      if (da == null) return 1;
      if (db == null) return -1;
      final c = db.compareTo(da);
      return c != 0 ? c : b.visitTime.compareTo(a.visitTime);
    });
    return list;
  }

  Widget _breakdownTile(String personType, String title, int count,
      double total, String mostCommon, Color color, IconData icon) {
    final double pct = total <= 0 ? 0 : (count / total).clamp(0, 1);
    final String subtitle = mostCommon.isEmpty
        ? 'No visits logged for this group'
        : 'Most common: $mostCommon';
    final expanded = _expandedTypes.contains(personType);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: expanded ? color : kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() {
              if (expanded) {
                _expandedTypes.remove(personType);
              } else {
                _expandedTypes.add(personType);
              }
            }),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(9),
                        decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(11)),
                        child: Icon(icon, color: color, size: 18),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 15,
                                    color: kTextDark)),
                            const SizedBox(height: 2),
                            Text(subtitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textMuted)),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('$count',
                              style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: color,
                                  fontSize: 20)),
                          const Text('cases',
                              style:
                                  TextStyle(fontSize: 11, color: kTextMuted)),
                        ],
                      ),
                      const SizedBox(width: 6),
                      Icon(
                          expanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          color: kTextMuted),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: pct.toDouble(),
                      minHeight: 7,
                      backgroundColor: kBorder,
                      valueColor: AlwaysStoppedAnimation<Color>(color),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                      '${(pct * 100).toStringAsFixed(1)}% of total visits this period',
                      style: const TextStyle(
                          fontSize: 11,
                          color: kTextMuted,
                          fontWeight: FontWeight.w600)),
                ],
              ),
            ),
          ),
          if (expanded) _recordsPanel(personType, color),
        ],
      ),
    );
  }

  Widget _recordsPanel(String personType, Color color) {
    final records = _recordsFor(personType);

    // How many times each service was done for this group.
    final serviceCounts = <String, int>{};
    for (final v in records) {
      for (final s in v.services) {
        serviceCounts[s] = (serviceCounts[s] ?? 0) + 1;
      }
    }
    final svc = serviceCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    // One entry per patient; `records` is already newest-first, so patients
    // are ordered by their latest visit.
    final byPerson = <String, List<_ReportVisit>>{};
    for (final v in records) {
      final key = v.personId.isNotEmpty ? v.personId : v.displayName;
      byPerson.putIfAbsent(key, () => <_ReportVisit>[]).add(v);
    }
    final people = byPerson.values.toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1, color: kBorder),
          const SizedBox(height: 12),
          Text('SERVICES DONE (${records.length} RECORD${records.length == 1 ? '' : 'S'})',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: color,
                  letterSpacing: 0.6)),
          const SizedBox(height: 8),
          if (svc.isEmpty)
            const Text('No services recorded.',
                style: TextStyle(fontSize: 12.5, color: kTextMuted))
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final e in svc) _countChip(e.key, e.value, color),
              ],
            ),
          const SizedBox(height: 14),
          Text('ALL RECORDS BY PATIENT',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: color,
                  letterSpacing: 0.6)),
          const SizedBox(height: 8),
          if (records.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('No records for the current filter.',
                  style: TextStyle(fontSize: 12.5, color: kTextMuted)),
            )
          else
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 560),
              child: ListView.separated(
                primary: false,
                shrinkWrap: true,
                itemCount: people.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, i) => _personCard(people[i], color),
              ),
            ),
        ],
      ),
    );
  }

  Widget _countChip(String label, int n, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text('$label  $n',
          style: TextStyle(
              fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
    );
  }

  String _fmtLongDate(DateTime d) {
    const days = [
      'Monday',
      'Tuesday',
      'Wednesday',
      'Thursday',
      'Friday',
      'Saturday',
      'Sunday'
    ];
    return '${days[d.weekday - 1]}, ${_fmtDate(d)}';
  }

  /// One container per patient: every record that matches the current
  /// filters, grouped under a highlighted date heading (any year / month).
  Widget _personCard(List<_ReportVisit> visits, Color color) {
    final first = visits.first;

    // Group this patient's visits by day (visits are newest-first).
    final days = <String, List<_ReportVisit>>{};
    final dayOrder = <String>[];
    for (final v in visits) {
      final d = v.visitDate;
      final key = d == null ? 'none' : '${d.year}-${d.month}-${d.day}';
      if (!days.containsKey(key)) dayOrder.add(key);
      days.putIfAbsent(key, () => <_ReportVisit>[]).add(v);
    }

    final initial =
        first.displayName.isNotEmpty ? first.displayName[0].toUpperCase() : '?';
    final meta = [
      if (first.personId.isNotEmpty) 'ID: ${first.personId}',
      if (first.personType.isNotEmpty) first.personType,
    ].join('  ·  ');

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(initial,
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: color)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(first.displayName,
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w800,
                            color: kTextDark)),
                    if (meta.isNotEmpty)
                      Text(meta,
                          style: const TextStyle(
                              fontSize: 13, color: kTextMuted)),
                    if (first.affiliation.isNotEmpty)
                      Text(first.affiliation,
                          style: const TextStyle(
                              fontSize: 13,
                              color: kTextMuted,
                              fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                    '${visits.length} record${visits.length == 1 ? '' : 's'}',
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w800,
                        color: color)),
              ),
            ],
          ),
          for (final key in dayOrder) ...[
            const SizedBox(height: 14),
            _dateHeading(days[key]!.first.visitDate, days[key]!.length, color),
            const SizedBox(height: 8),
            for (final v in days[key]!) ...[
              _visitDetail(v, color),
              if (v != days[key]!.last) const SizedBox(height: 8),
            ],
          ],
        ],
      ),
    );
  }

  Widget _dateHeading(DateTime? date, int count, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border(left: BorderSide(color: color, width: 4)),
      ),
      child: Row(
        children: [
          Icon(Icons.event_rounded, size: 17, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(date == null ? 'No date' : _fmtLongDate(date),
                style: TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w800,
                    color: color)),
          ),
          Text('$count visit${count == 1 ? '' : 's'}',
              style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700, color: color)),
        ],
      ),
    );
  }

  Widget _visitDetail(_ReportVisit v, Color color) {
    Widget label(String t) => Text(t.toUpperCase(),
        style: const TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            color: kTextMuted,
            letterSpacing: 0.6));

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.schedule_rounded, size: 15, color: kTextMuted),
              const SizedBox(width: 6),
              Text(v.visitTime.isEmpty ? 'Time not recorded' : v.visitTime,
                  style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: kTextDark)),
            ],
          ),
          const SizedBox(height: 10),
          label('Reason for visit'),
          const SizedBox(height: 3),
          Text(v.reason.isEmpty ? 'Not recorded' : v.reason,
              style: const TextStyle(fontSize: 14, color: kTextDark)),
          const SizedBox(height: 10),
          label('Services'),
          const SizedBox(height: 5),
          if (v.services.isEmpty)
            const Text('No services recorded',
                style: TextStyle(fontSize: 14, color: kTextMuted))
          else
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final s in v.services)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(s,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                            color: color)),
                  ),
              ],
            ),
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
      subtitle: 'What was done and what was logged this period',
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
        final narrow = constraints.maxWidth < 620;
        final left = _miniRanked(
          'Services performed',
          Icons.medical_services_outlined,
          kTeal,
          services,
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
      List<MapEntry<String, int>> entries) {
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
        _rankedList(entries: entries, unitLabel: 'visits', color: color),
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
        return Padding(
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