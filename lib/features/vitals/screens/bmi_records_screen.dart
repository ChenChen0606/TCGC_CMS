// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import 'package:clinicmanagementsystem/features/vitals/models/vitals.dart';
import 'package:clinicmanagementsystem/core/services/data_tracker.dart';
import 'package:clinicmanagementsystem/core/services/reference_data_service.dart';
import 'package:clinicmanagementsystem/core/config/supabase_config.dart';
import 'package:clinicmanagementsystem/core/theme/app_colors.dart';
import 'package:clinicmanagementsystem/shared/printing/document_template.dart';
import 'package:clinicmanagementsystem/shared/widgets/zoomable_pdf_pages.dart';

class AcadPeriod {
  final String acadYear;
  final String semester;
  final String id;
  final String status;
  const AcadPeriod(this.acadYear, this.semester,
      {this.id = '', this.status = ''});
}

class BmiRecord {
  final String bmiRecordId;
  final String visitServiceId;
  final double? heightCm;
  final double? weightKg;
  final double? bmi;
  final String classification;
  final String notes;
  final String visitId;
  final String personId;
  final DateTime? visitDate;
  final String visitTime;
  final String personType;
  final String fn;
  final String mn;
  final String ln;
  final String suffix;
  final DateTime? dateOfBirth;
  final String sex;
  final String instituteName;
  final String programName;
  final String yearLevel;
  final String departmentOffice;
  final String position;
  final String acadYear;
  final String semester;
  final int? age;

  const BmiRecord({
    required this.bmiRecordId,
    required this.visitServiceId,
    this.heightCm,
    this.weightKg,
    this.bmi,
    this.classification = '',
    this.notes = '',
    required this.visitId,
    required this.personId,
    this.visitDate,
    this.visitTime = '',
    this.personType = '',
    this.fn = '',
    this.mn = '',
    this.ln = '',
    this.suffix = '',
    this.dateOfBirth,
    this.sex = '',
    this.instituteName = '',
    this.programName = '',
    this.yearLevel = '',
    this.departmentOffice = '',
    this.position = '',
    this.acadYear = '',
    this.semester = '',
    this.age,
  });

  factory BmiRecord.fromSupabase(Map<String, dynamic> row) {
    final dob = _parseTs(row['date_of_birth'] as String?);

    int? age;

    if (dob != null) {
      final now = DateTime.now();
      age = now.year - dob.year;
      if (now.month < dob.month ||
          (now.month == dob.month && now.day < dob.day)) {
        age--;
      }
    }

    return BmiRecord(
      bmiRecordId: row['bmi_record_id'] as String? ?? '',
      visitServiceId: row['visit_service_id'] as String? ?? '',
      heightCm: (row['height_cm'] as num?)?.toDouble(),
      weightKg: (row['weight_kg'] as num?)?.toDouble(),
      bmi: (row['bmi'] as num?)?.toDouble(),
      classification: (row['classification'] as String?)?.trim() ?? '',
      notes: (row['notes'] as String?)?.trim() ?? '',
      visitId: row['visit_id'] as String? ?? '',
      personId: row['person_id'] as String? ?? '',
      visitDate: _parseTs(row['visit_date'] as String?),
      visitTime: (row['visit_time'] as String?)?.trim() ?? '',
      personType: (row['person_type'] as String?)?.trim() ?? '',
      fn: (row['fn'] as String?)?.trim() ?? '',
      mn: (row['mn'] as String?)?.trim() ?? '',
      ln: (row['ln'] as String?)?.trim() ?? '',
      suffix: (row['suffix'] as String?)?.trim() ?? '',
      dateOfBirth: dob,
      sex: (row['sex'] as String?)?.trim() ?? '',
      instituteName: (row['institute_name'] as String?)?.trim() ??
          (row['institute'] as String?)?.trim() ??
          '',
      programName: (row['program_name'] as String?)?.trim() ??
          (row['program'] as String?)?.trim() ??
          '',
      yearLevel: (row['year_level'] as String?)?.trim() ?? '',
      departmentOffice: (row['dept_office'] as String?)?.trim() ??
          (row['department_office'] as String?)?.trim() ??
          '',
      position: (row['position'] as String?)?.trim() ?? '',
      acadYear: (row['acad_year'] as String?)?.trim() ?? '',
      semester: (row['semester'] as String?)?.trim() ?? '',
      age: age,
    );
  }

  double get computedBmi {
    if (bmi != null && bmi!.isFinite) return bmi!;
    final h = heightCm;
    final w = weightKg;
    if (h == null || w == null || h <= 0 || w <= 0) return double.nan;
    final m = h / 100;
    return w / (m * m);
  }

  String get indicator {
    final value = computedBmi;
    if (!value.isFinite) return 'Unknown';
    final b = VitalsThresholds.resolve(VitalsThresholds.instance.bmi, value);
    return b.label.isEmpty ? 'Unknown' : b.label;
  }

  String get fullName {
  final given =
      <String>[fn, mn, suffix].where((p) => p.isNotEmpty).join(' ');
  if (ln.isEmpty) return given;
  return given.isEmpty ? ln : '$ln, $given';
}

  static DateTime? _parseTs(String? s) {
    if (s == null || s.trim().isEmpty) return null;
    try {
      return DateTime.tryParse(s);
    } catch (_) {
      return null;
    }
  }
}

/// One row of a summary table. [sub] is the second label column
/// (Position) used by the Faculty & Staff summary.
class BmiSummaryRow {
  final String label;
  final String sub;
  final int underweight;
  final int normal;
  final int overweight;
  final int obese;
  final int total;

  const BmiSummaryRow({
    required this.label,
    this.sub = '',
    required this.underweight,
    required this.normal,
    required this.overweight,
    required this.obese,
    required this.total,
  });
}

class _SummaryBlock {
  const _SummaryBlock(this.title, this.subtitle, this.first, this.rows,
      {this.second});
  final String title;
  final String subtitle;
  final String first;
  final String? second;
  final List<BmiSummaryRow> rows;
}

class BmiRecordsScreen extends StatefulWidget {
  const BmiRecordsScreen({super.key});

  @override
  State<BmiRecordsScreen> createState() => _BmiRecordsScreenState();
}

class _BmiRecordsScreenState extends State<BmiRecordsScreen>
    with SingleTickerProviderStateMixin {
  static const Color kPrimary = AppColors.primary;
  static const Color kCard = AppColors.surface;
  static const Color kBorder = AppColors.border;
  static const Color kTextMain = AppColors.textMain;
  static const Color kTextDark = AppColors.textDark;
  static const Color kTextSub = AppColors.textSub;
  static const Color kDanger = AppColors.danger;
  static const Color kBg = AppColors.bgAlt;

  static const PdfColor _sheetGreen = PdfColor.fromInt(0xFF0E6B47);

  /// Record groups: students, and faculty + staff combined.
  static const List<String> _groups = ['Student', 'Employee'];

  bool _isLoading = true;
  List<BmiRecord> _allRecords = [];

  /// Records after every filter EXCEPT the BMI indicator filter.
  List<BmiRecord> _scopeRecords = [];

  /// Records after ALL filters (including the BMI indicator filter).
  List<BmiRecord> _filteredRecords = [];

  List<String> _institutes = [];
  List<AcadPeriod> _periods = [];

  /// From the `institutes` table: lower-cased name -> code (ICS, IBFS...).
  Map<String, String> _instituteCodeByName = {};
  Set<String> _dbInstituteNames = {};

  String _selectedType = 'All'; // All | Student | Employee (faculty & staff)
  String _selectedInstitute = 'All';
  String _selectedClassification = 'All';
  String _selectedSex = 'All';
  String _selectedAge = 'All';
  DateTimeRange? _birthRange;

  /// "Today" is first so the page opens on today's records.
  static const List<String> _dateFilterModes = [
    'Today',
    'This Week',
    'This Month',
    'Academic Year',
    'Date Range',
    'Pick Date',
    'All',
  ];
  String _selectedDateFilter = 'Today';
  String _selectedAcadYear = 'All';
  String _selectedSemester = 'All';
  DateTimeRange? _pickedRange;
  DateTime? _pickedDate;

  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;
  VoidCallback? _dataListener;

  bool get _singleIndicator => _selectedClassification != 'All';

  /// "Institute of Health Sciences" -> "IHS" (falls back to the name).
  String _instCode(String name) {
    final code = _instituteCodeByName[name.trim().toLowerCase()];
    return (code == null || code.isEmpty) ? name : code;
  }

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);
    _fadeCtrl.forward();
    _loadRecords();
    _dataListener = () => _loadRecords();
    DataTracker.listen(_dataListener!);
  }

  @override
  void dispose() {
    if (_dataListener != null) DataTracker.unlisten(_dataListener!);
    _fadeCtrl.dispose();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadRecords() async {
    if (mounted) setState(() => _isLoading = true);

    await ReferenceCatalog.loadQuietly();

    // Academic periods: the Academic Year / Semester filter lists these.
    final periods = <AcadPeriod>[];
    try {
      final rows = await supabaseClient
          .from('academic_periods')
          .select('academic_period_id, acad_year, semester, status');
      for (final row in (rows as List)) {
        final m = Map<String, dynamic>.from(row as Map);
        final y = (m['acad_year'] as String?)?.trim() ?? '';
        final s = (m['semester'] as String?)?.trim() ?? '';
        if (y.isNotEmpty) {
          periods.add(AcadPeriod(
            y,
            s,
            id: (m['academic_period_id'] as String?)?.trim() ?? '',
            status: (m['status'] as String?)?.trim() ?? '',
          ));
        }
      }
    } catch (_) {}
    final periodById = <String, AcadPeriod>{
      for (final p in periods)
        if (p.id.isNotEmpty) p.id: p,
    };

    // Institutes table: gives the short codes (ICS, IBFS, ...).
    final codeByName = <String, String>{};
    final instNames = <String>{};
    try {
      final rows =
          await supabaseClient.from('institutes').select('code, name');
      for (final row in (rows as List)) {
        final m = Map<String, dynamic>.from(row as Map);
        final code = (m['code'] as String?)?.trim() ?? '';
        final name = (m['name'] as String?)?.trim() ?? '';
        if (name.isEmpty) continue;
        instNames.add(name);
        if (code.isNotEmpty) codeByName[name.toLowerCase()] = code;
      }
    } catch (_) {}
    _instituteCodeByName = codeByName;
    _dbInstituteNames = instNames;

    try {
      final response = await supabaseClient.from('bmi_records').select('''
        bmi_record_id, visit_service_id, height_cm, weight_kg, bmi, classification, notes,
        clinic_visit_services!inner(
          visit_id, service_type_id,
          clinic_visits!inner(
            visit_id, person_id, visit_date, visit_time, academic_period_id,
            individual_records!inner(
              person_id, person_type, fn, mn, ln, suffix, date_of_birth, sex,
              individual_academic_records!left(
                academic_record_id, person_id, academic_period_id, institute_id, program_id, year_level, department_office_id, position_id, status,
                academic_periods!left(academic_period_id, acad_year, semester, status),
                institutes!left(institute_id, name),
                program!left(program_id, name, code),
                departments_offices!left(department_office_id, name),
                positions!left(position_id, name)
              )
            )
          )
        )
      ''');

      final records = <BmiRecord>[];
      for (final row in (response as List)) {
        try {
          final flat = Map<String, dynamic>.from(row);
          final cvs = _firstMap(flat['clinic_visit_services']);
          final cv = _firstMap(cvs['clinic_visits']);
          final periodId = '${cv['academic_period_id'] ?? ''}'.trim();
          final ir = _firstMap(cv['individual_records']);
          final iar = _academicFor(ir['individual_academic_records'], periodId);
          final inst = _firstMap(iar['institutes']);
          final prg = _firstMap(iar['program']);
          final dpt = _firstMap(iar['departments_offices']);
          final pos = _firstMap(iar['positions']);
          final per = _firstMap(iar['academic_periods']);

          flat['visit_date'] = cv['visit_date'];
          flat['visit_time'] = cv['visit_time'];
          flat['visit_id'] = cv['visit_id'] ?? flat['visit_id'];
          flat['person_id'] = ir['person_id'] ?? flat['person_id'];
          flat['person_type'] = ir['person_type'];
          flat['fn'] = ir['fn'];
          flat['mn'] = ir['mn'];
          flat['ln'] = ir['ln'];
          flat['suffix'] = ir['suffix'];
          flat['date_of_birth'] = ir['date_of_birth'];
          flat['sex'] = ir['sex'];
          flat['institute_name'] = inst['name'];
          flat['program_name'] = prg['code'] ?? prg['name'];
          flat['year_level'] = iar['year_level'];
          flat['dept_office'] = dpt['name'];
          flat['position'] = pos['name'];

          // The visit's own academic period wins over the person's.
          final vp = periodById[periodId];
          flat['acad_year'] = vp?.acadYear ?? per['acad_year'];
          flat['semester'] = vp?.semester ?? per['semester'];
          records.add(BmiRecord.fromSupabase(flat));
        } catch (_) {}
      }

      if (!mounted) return;

      setState(() {
        _periods = periods;
        _allRecords = records;
        _buildFilterOptions();
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _periods = periods;
        _buildFilterOptions();
        _applyFilters();
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: kDanger,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          content: Text(
            'BMI records could not be loaded: $e',
            style: const TextStyle(color: Colors.white),
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  static Map<String, dynamic> _firstMap(Object? value) {
    if (value is List) {
      if (value.isNotEmpty && value.first is Map) {
        return Map<String, dynamic>.from(value.first as Map);
      }
      return <String, dynamic>{};
    }
    if (value is Map) return Map<String, dynamic>.from(value);
    return <String, dynamic>{};
  }

  /// Picks the person's academic record that belongs to the visit's period.
  static Map<String, dynamic> _academicFor(Object? value, String periodId) {
    if (value is List && periodId.isNotEmpty) {
      for (final e in value) {
        if (e is Map && '${e['academic_period_id']}' == periodId) {
          return Map<String, dynamic>.from(e);
        }
      }
    }
    return _firstMap(value);
  }

  void _buildFilterOptions() {
    final institutes = <String>{..._dbInstituteNames};
    for (final r in _allRecords) {
      if (r.instituteName.isNotEmpty) institutes.add(r.instituteName);
    }
    _institutes = institutes.toList()
      ..sort((a, b) => _instCode(a).compareTo(_instCode(b)));
    if (_selectedInstitute != 'All' &&
        !institutes.contains(_selectedInstitute)) {
      _selectedInstitute = 'All';
    }
  }
      int _compareBmi(BmiRecord a, BmiRecord b) {
        int s(String x, String y) => x.toLowerCase().compareTo(y.toLowerCase());
        var c = s(a.ln, b.ln);
        if (c != 0) return c;
        c = s(a.fn, b.fn);
        if (c != 0) return c;
        c = s(a.mn, b.mn);
        if (c != 0) return c;
        c = a.personId.compareTo(b.personId);
        if (c != 0) return c;
        final da = a.visitDate, db = b.visitDate;
        if (da == null || db == null) return da == null ? (db == null ? 0 : 1) : -1;
        return db.compareTo(da); // same person: newest first
      }

  void _applyFilters() {
    final q = _searchQuery.trim().toLowerCase();

    // Everything except the BMI indicator filter.
    final scope = _allRecords.where((r) {
      if (_selectedType != 'All' && !_inGroup(r, _selectedType)) return false;
      if (_selectedInstitute != 'All' &&
          r.instituteName != _selectedInstitute) {
        return false;
      }
      if (_selectedSex != 'All' &&
          r.sex.toLowerCase() != _selectedSex.toLowerCase()) {
        return false;
      }
      if (_selectedAge != 'All' && r.age?.toString() != _selectedAge) {
        return false;
      }
      if (!_matchesBirthFilter(r)) return false;
      if (!_matchesDateFilter(r)) return false;
      if (q.isNotEmpty) {
        final hay = [
          r.personId,
          r.fullName,
          r.personType,
          r.instituteName,
          r.programName,
          r.departmentOffice,
          r.position,
        ].join(' ').toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();
    scope.sort(_compareBmi);
    _scopeRecords = scope;
    _filteredRecords = _selectedClassification == 'All'
        ? scope
        : scope.where((r) => r.indicator == _selectedClassification).toList();
  }

  bool _matchesBirthFilter(BmiRecord r) {
    final range = _birthRange;
    if (range == null) return true;
    final b = r.dateOfBirth;
    if (b == null) return false;
    final d = DateTime(b.year, b.month, b.day);
    final s = DateTime(range.start.year, range.start.month, range.start.day);
    final e = DateTime(range.end.year, range.end.month, range.end.day);
    return !d.isBefore(s) && !d.isAfter(e);
  }

  bool _matchesDateFilter(BmiRecord r) {
    final date = r.visitDate;
    switch (_selectedDateFilter) {
      case 'Today':
        if (date == null) return false;
        final now = DateTime.now();
        return date.year == now.year &&
            date.month == now.month &&
            date.day == now.day;
      case 'This Week':
        if (date == null) return false;
        final now = DateTime.now();

        final start = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: now.weekday - 1));
        final end = start.add(const Duration(days: 7));
        return !date.isBefore(start) && date.isBefore(end);
      case 'This Month':
        if (date == null) return false;
        final now = DateTime.now();
        return date.year == now.year && date.month == now.month;
      case 'Academic Year':
        if (_selectedAcadYear != 'All' && r.acadYear != _selectedAcadYear) {
          return false;
        }
        if (_selectedAcadYear != 'All' &&
            _selectedSemester != 'All' &&
            r.semester != _selectedSemester) {
          return false;
        }
        return true;
      case 'Date Range':
        final range = _pickedRange;
        if (range == null || date == null) return false;
        final start =
            DateTime(range.start.year, range.start.month, range.start.day);
        final end = DateTime(range.end.year, range.end.month, range.end.day)
            .add(const Duration(days: 1));
        return !date.isBefore(start) && date.isBefore(end);
      case 'Pick Date':
        final day = _pickedDate;
        if (day == null || date == null) return false;
        return date.year == day.year &&
            date.month == day.month &&
            date.day == day.day;
      default:
        return true;
    }
  }

  // ── Grouping helpers ───────────────────────────────────────────────────

  bool _inGroup(BmiRecord r, String group) => group == 'Student'
      ? r.personType == 'Student'
      : r.personType != 'Student';

  List<String> get _visibleGroups =>
      _selectedType == 'All' ? _groups : [_selectedType];

  List<BmiRecord> _ofGroup(List<BmiRecord> list, String group) =>
      list.where((r) => _inGroup(r, group)).toList();

  String _groupTitle(String g) => g == 'Student' ? 'Students' : 'Faculty & Staff';

  IconData _groupIcon(String g) =>
      g == 'Student' ? Icons.school_rounded : Icons.badge_outlined;

  String get _totalLabel => _selectedType == 'All'
      ? 'Total Records'
      : 'Total ${_groupTitle(_selectedType)}';

  /// Institute for faculty, office/department for staff.
  String _unitOf(BmiRecord r) {
    final inst = r.instituteName.trim();
    final office = r.departmentOffice.trim();
    if (r.personType == 'Staff') return office.isNotEmpty ? office : inst;
    return inst.isNotEmpty ? inst : office;
  }

  List<BmiSummaryRow> _summarize(
      List<BmiRecord> records, String Function(BmiRecord) keyOf) {
    final groups = <String, List<BmiRecord>>{};
    for (final r in records) {
      final k = keyOf(r).trim();
      groups.putIfAbsent(k.isEmpty ? 'Unknown' : k, () => <BmiRecord>[]).add(r);
    }
    final keys = groups.keys.toList()..sort();
    return [
      for (final k in keys) _summaryRowOf(k, '', groups[k]!),
    ];
  }

  /// Faculty & staff: one row per Institute/Office + Position.
  List<BmiSummaryRow> _summarizeUnitPosition(List<BmiRecord> records) {
    const sep = '\u0001';
    final groups = <String, List<BmiRecord>>{};
    for (final r in records) {
      final unit = _unitOf(r).trim();
      final pos = r.position.trim();
      final key = '${unit.isEmpty ? 'Unknown' : unit}$sep${pos.isEmpty ? '-' : pos}';
      groups.putIfAbsent(key, () => <BmiRecord>[]).add(r);
    }
    final keys = groups.keys.toList()..sort();
    return [
      for (final k in keys)
        _summaryRowOf(k.split(sep).first, k.split(sep).last, groups[k]!),
    ];
  }

  BmiSummaryRow _summaryRowOf(String label, String sub, List<BmiRecord> l) {
    int c(String s) => l.where((r) => r.indicator == s).length;
    return BmiSummaryRow(
      label: label,
      sub: sub,
      underweight: c('Underweight'),
      normal: c('Normal'),
      overweight: c('Overweight'),
      obese: c('Obese'),
      total: l.length,
    );
  }

  List<_SummaryBlock> _summaryBlocksFor(String group, List<BmiRecord> recs) {
    if (group == 'Student') {
      return [
        if (_selectedInstitute == 'All')
          _SummaryBlock(
              'Summary by Institute',
              'Student count per BMI classification, grouped by institute',
              'Institute',
              _summarize(recs, (r) => r.instituteName)),
        _SummaryBlock(
            'Summary by Program',
            _selectedInstitute == 'All'
                ? 'Student count per BMI classification, grouped by program'
                : 'Student count per BMI classification — ${_instCode(_selectedInstitute)}',
            'Program',
            _summarize(recs, (r) => r.programName)),
      ];
    }
    return [
      _SummaryBlock(
        'Summary by Institute / Office',
        'Faculty and staff count per BMI classification, grouped by institute / office and position',
        'Institute / Office',
        _summarizeUnitPosition(recs),
        second: 'Position',
      ),
    ];
  }

  // ── Summary table helpers (indicator-aware) ────────────────────────────

  List<String> _summaryHeaders(String first,
          {required bool withTotal, String? second}) =>
      [
        first,
        if (second != null) second,
        if (_singleIndicator)
          _selectedClassification
        else ...[
          'Underweight',
          'Normal',
          'Overweight',
          'Obese',
        ],
        if (withTotal && !_singleIndicator) 'Total',
      ];

  List<String> _summaryCells(
    String name,
    int underweight,
    int normal,
    int overweight,
    int obese,
    int total, {
    required bool withTotal,
    String? sub,
  }) {
    if (_singleIndicator) {
      final v = switch (_selectedClassification) {
        'Underweight' => underweight,
        'Normal' => normal,
        'Overweight' => overweight,
        _ => obese,
      };
      return [name, if (sub != null) sub, '$v'];
    }
    return [
      name,
      if (sub != null) sub,
      '$underweight',
      '$normal',
      '$overweight',
      '$obese',
      if (withTotal) '$total',
    ];
  }

  List<String> _blockCells(_SummaryBlock b, BmiSummaryRow s,
          {required bool withTotal}) =>
      _summaryCells(s.label, s.underweight, s.normal, s.overweight, s.obese,
          s.total,
          withTotal: withTotal, sub: b.second == null ? null : s.sub);

  // ── Detail table columns ───────────────────────────────────────────────

  String _dash(String s) => s.isEmpty ? '—' : s;

  String _bmiText(BmiRecord r) =>
      r.computedBmi.isFinite ? r.computedBmi.toStringAsFixed(1) : '—';

  String _detailsTitle(String g) =>
      g == 'Student' ? 'Student BMI Details' : 'Faculty & Staff BMI Details';

  List<String> _detailHeaders(String g) => g == 'Student'
      ? const [
          'Student ID', 'Name', 'Program', 'Age', 'Sex', 'Birthdate', 'BMI',
          'BMI Indicator'
        ]
      : const [
          'Name', 'Institute / Office', 'Age', 'Sex', 'Birthdate', 'BMI',
          'BMI Indicator'
        ];

  /// Every column except the last one (the indicator pill).
  List<String> _detailCells(String g, BmiRecord r) {
    final tail = [
      r.age?.toString() ?? '—',
      _dash(r.sex),
      _fmtBirthdate(r.dateOfBirth),
      _bmiText(r),
    ];
    if (g == 'Student') {
      return [r.personId, r.fullName, _dash(r.programName), ...tail];
    }
    return [r.fullName, _dash(_unitOf(r)), ...tail];
  }

  List<String> _printDetailHeaders(String g) => g == 'Student'
      ? [
          'Student ID', 'Name', 'Age', 'Sex', 'Birthdate', 'Program',
          'Year Level', 'Height', 'Weight', 'BMI', 'Indicator'
        ]
      : [
          'Name', 'Institute / Office', 'Age', 'Sex', 'Birthdate', 'BMI',
          'BMI Indicator'
        ];

  List<String> _printDetailCells(String g, BmiRecord r) {
    if (g == 'Student') {
      return [
        r.personId,
        r.fullName,
        r.age?.toString() ?? '—',
        _dash(r.sex),
        _fmtDate(r.dateOfBirth),
        _dash(r.programName),
        _dash(r.yearLevel),
        _fmtNum(r.heightCm),
        _fmtNum(r.weightKg),
        _bmiText(r),
        r.indicator,
      ];
    }
    return [
      r.fullName,
      _dash(_unitOf(r)),
      r.age?.toString() ?? '—',
      _dash(r.sex),
      _fmtDate(r.dateOfBirth),
      _bmiText(r),
      r.indicator,
    ];
  }

  String _printDetailsTitle(String g) =>
      g == 'Student' ? 'STUDENT BMI DETAILS' : 'FACULTY AND STAFF BMI DETAILS';

  // ── Academic year / semester helpers ───────────────────────────────────

  static int _semRank(String s) {
    final t = s.toLowerCase();
    if (t.contains('summer')) return 3;
    if (t.contains('1') || t.contains('first')) return 1;
    if (t.contains('2') || t.contains('second')) return 2;
    return 9;
  }

  /// Every school year in the academic_periods table.
  List<String> get _availableAcadYears {
    final years = <String>{
      for (final p in _periods)
        if (p.acadYear.isNotEmpty) p.acadYear,
    };
    return years.toList()..sort((a, b) => b.compareTo(a));
  }

  /// Every semester of the picked year, from the academic_periods table.
  List<String> get _availableSemesters {
    final sems = <String>{
      for (final p in _periods)
        if (p.acadYear == _selectedAcadYear && p.semester.isNotEmpty)
          p.semester,
    };
    final list = sems.toList();
    list.sort((a, b) {
      final c = _semRank(a).compareTo(_semRank(b));
      return c != 0 ? c : a.compareTo(b);
    });
    return list;
  }

  bool _hasRecordsFor(String year, [String? sem]) => _allRecords.any((r) =>
      r.acadYear == year &&
      (sem == null || sem == 'All' || r.semester == sem));

  List<String> get _availableAges {
    final ages = <int>{
      for (final r in _allRecords)
        if (r.age != null) r.age!,
    };
    return (ages.toList()..sort()).map((a) => '$a').toList();
  }

  String _fmtDate(DateTime? d) =>
      d == null ? '—' : DateFormat('MMM d, yyyy').format(d);

  String _fmtNum(double? v) =>
      v == null || !v.isFinite ? '—' : v.toStringAsFixed(1);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      floatingActionButton: _isLoading ? null : _printFab(),
      body: FadeTransition(
        opacity: _fadeAnim,
        child: _isLoading && _allRecords.isEmpty
            ? const Center(
                child: CircularProgressIndicator(color: kPrimary),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _header(),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(24, 18, 24, 40),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _statStrip(),
                          const SizedBox(height: 18),
                          _filterRow(),
                          const SizedBox(height: 18),
                          _resultsSection(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _header() {
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
                  colors: [kPrimary, AppColors.primaryDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.monitor_weight_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: const [
                Text('BMI Records',
                    style: TextStyle(
                        color: kTextDark,
                        fontWeight: FontWeight.w800,
                        fontSize: 22)),
                SizedBox(height: 2),
                Text('Body mass index records for students, faculty and staff',
                    style: TextStyle(color: kTextSub, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
    );
  }

  Widget _printFab() {
    return Tooltip(
      message: 'Print BMI Records',
      child: Material(
        color: kPrimary,
        borderRadius: BorderRadius.circular(16),
        elevation: 6,
        child: InkWell(
          onTap: _showPrintPreview,
          borderRadius: BorderRadius.circular(16),
          child: const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.print_outlined, color: Colors.white, size: 24),
                SizedBox(height: 2),
                Text('Print',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statStrip() {
    final records = _filteredRecords;
    final total = records.length;
    int count(String c) => records.where((r) => r.indicator == c).length;
    final stats = <({String label, int value, Color color, IconData icon})>[
      (
        label: _totalLabel,
        value: total,
        color: kPrimary,
        icon: Icons.groups_rounded
      ),
      (
        label: 'Underweight',
        value: count('Underweight'),
        color: const Color(0xFF0369A1),
        icon: Icons.trending_down_rounded
      ),
      (
        label: 'Normal',
        value: count('Normal'),
        color: const Color(0xFF15803D),
        icon: Icons.check_circle_rounded
      ),
      (
        label: 'Overweight',
        value: count('Overweight'),
        color: const Color(0xFFB45309),
        icon: Icons.trending_up_rounded
      ),
      (
        label: 'Obese',
        value: count('Obese'),
        color: const Color(0xFFB91C1C),
        icon: Icons.warning_amber_rounded
      ),
    ];
    return LayoutBuilder(builder: (context, constraints) {
      if (constraints.maxWidth < 620) {
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final s in stats)
              SizedBox(
                width: (constraints.maxWidth - 10) / 2,
                child: _statCard(
                  label: s.label,
                  value: s.value,
                  color: s.color,
                  icon: s.icon,
                ),
              ),
          ],
        );
      }
      return Row(
        children: [
          for (var i = 0; i < stats.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(
              child: _statCard(
                label: stats[i].label,
                value: stats[i].value,
                color: stats[i].color,
                icon: stats[i].icon,
              ),
            ),
          ],
        ],
      );
    });
  }

  Widget _statCard({
    required String label,
    required int value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
        boxShadow: const [
          BoxShadow(
              color: Color(0x0A0F172A), blurRadius: 16, offset: Offset(0, 6)),
        ],
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('$value',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        color: kTextMain)),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: kTextSub)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Filters ────────────────────────────────────────────────────────────

  /// Search on top; below it the filter chips on the left and the
  /// All / Students / Faculty & Staff switch on the right.
  Widget _filterRow() {
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
            children: [
              _dateFilterControls(),
              _instituteSelector(),
              _indicatorFilter(),
              _sexFilter(),
              _ageFilter(),
              _birthdateFilter(),
              if (_hasExtraFilters)
                _clearButton(
                  tooltip: 'Clear filters',
                  onTap: () => setState(() {
                    _selectedInstitute = 'All';
                    _selectedClassification = 'All';
                    _selectedSex = 'All';
                    _selectedAge = 'All';
                    _birthRange = null;
                    _applyFilters();
                  }),
                ),
            ],
          );
          if (constraints.maxWidth < 1180) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                controls,
                const SizedBox(height: 10),
                _typeFilterBar(),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: controls),
              const SizedBox(width: 16),
              _typeFilterBar(),
            ],
          );
        }),
      ],
    );
  }

  Widget _searchField() {
    return TextField(
      controller: _searchController,
      onChanged: (value) => setState(() {
        _searchQuery = value;
        _applyFilters();
      }),
      style: const TextStyle(fontSize: 13, color: kTextMain),
      decoration: InputDecoration(
        hintText: 'Search name, ID, program…',
        hintStyle: const TextStyle(color: kTextSub, fontSize: 13),
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

  /// One look for every filter control: white chip, soft border, icon in
  /// front. When a filter is active the chip turns green.
  BoxDecoration _filterDeco(bool active) => BoxDecoration(
        color: active ? kPrimary.withValues(alpha: 0.07) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: active ? kPrimary : kBorder, width: active ? 1.2 : 1),
      );

  Widget _filterDropdown({
    required String value,
    required List<DropdownMenuItem<String>> items,
    required ValueChanged<String?> onChanged,
    required IconData icon,
    bool active = false,
  }) {
    return Container(
      height: 40,
      padding: const EdgeInsets.only(left: 12, right: 6),
      decoration: _filterDeco(active),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: active ? kPrimary : kTextSub),
          const SizedBox(width: 8),
          DropdownButtonHideUnderline(
            child: DropdownButton<String>(
              value: value,
              isDense: true,
              dropdownColor: Colors.white,
              borderRadius: BorderRadius.circular(12),
              icon: Icon(Icons.keyboard_arrow_down_rounded,
                  size: 18, color: active ? kPrimary : kTextSub),
              style: const TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: kTextMain),
              items: items,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  /// Dropdown over a list of options. options.first must be 'All'.
  Widget _pillDropdown({
    required String value,
    required List<String> options,
    required String Function(String) labelFor,
    required ValueChanged<String> onChanged,
    required IconData icon,
  }) {
    final safe = options.contains(value) ? value : options.first;
    return _filterDropdown(
      value: safe,
      icon: icon,
      active: safe != options.first,
      items: [
        for (final o in options)
          DropdownMenuItem(value: o, child: Text(labelFor(o))),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }

  Widget _clearButton({required VoidCallback onTap, String tooltip = 'Clear'}) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
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

  /// Narrow: shows the code (ICS, IBFS, IHS...) from the institutes table.
  Widget _instituteSelector() => _pillDropdown(
        icon: Icons.apartment_rounded,
        value: _selectedInstitute,
        options: ['All', ..._institutes],
        labelFor: (o) => o == 'All' ? 'All Institutes' : _instCode(o),
        onChanged: (v) => setState(() {
          _selectedInstitute = v;
          _buildFilterOptions();
          _applyFilters();
        }),
      );

  Widget _indicatorFilter() => _pillDropdown(
        icon: Icons.monitor_weight_outlined,
        value: _selectedClassification,
        options: const ['All', 'Underweight', 'Normal', 'Overweight', 'Obese'],
        labelFor: (o) => o == 'All' ? 'All BMI' : o,
        onChanged: (v) => setState(() {
          _selectedClassification = v;
          _applyFilters();
        }),
      );

  Widget _sexFilter() => _pillDropdown(
        icon: Icons.wc_rounded,
        value: _selectedSex,
        options: const ['All', 'Male', 'Female'],
        labelFor: (o) => o == 'All' ? 'All Sexes' : o,
        onChanged: (v) => setState(() {
          _selectedSex = v;
          _applyFilters();
        }),
      );

  Widget _ageFilter() => _pillDropdown(
        icon: Icons.person_outline_rounded,
        value: _selectedAge,
        options: ['All', ..._availableAges],
        labelFor: (o) => o == 'All' ? 'All Ages' : '$o yrs',
        onChanged: (v) => setState(() {
          _selectedAge = v;
          _applyFilters();
        }),
      );

  Widget _birthdateFilter() {
    final r = _birthRange;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _dateValueButton(
          icon: Icons.cake_outlined,
          label: r == null ? 'Birthdate' : _compactRangeLabel(r),
          active: r != null,
          onTap: _pickBirthRange,
        ),
        if (r != null) ...[
          const SizedBox(width: 6),
          _clearButton(
            tooltip: 'Clear birthdate',
            onTap: () => setState(() {
              _birthRange = null;
              _applyFilters();
            }),
          ),
        ],
      ],
    );
  }

  Future<void> _pickBirthRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(1940),
      lastDate: DateTime.now(),
      initialDateRange: _birthRange,
      helpText: 'BIRTHDATE RANGE',
      cancelText: 'Cancel',
      confirmText: 'Apply',
      builder: (context, child) => Dialog(
        child: SizedBox(width: 480, height: 520, child: child),
      ),
    );
    if (!mounted || range == null) return;
    setState(() {
      _birthRange = range;
      _applyFilters();
    });
  }

  bool get _hasExtraFilters =>
      _selectedInstitute != 'All' ||
      _selectedClassification != 'All' ||
      _selectedSex != 'All' ||
      _selectedAge != 'All' ||
      _birthRange != null;

  /// All / Students / Faculty & Staff
  Widget _typeFilterBar() {
    const options = {
      'All': 'All',
      'Student': 'Students',
      'Employee': 'Faculty & Staff',
    };
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2F6),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final e in options.entries)
            InkWell(
              borderRadius: BorderRadius.circular(9),
              onTap: () => setState(() {
                _selectedType = e.key;
                _applyFilters();
              }),
              child: Container(
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: _selectedType == e.key ? kPrimary : Colors.transparent,
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  e.value,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: _selectedType == e.key ? Colors.white : kTextSub,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _dateFilterControls() {
    final children = <Widget>[_dateModeDropdown()];
    Widget? extra;
    switch (_selectedDateFilter) {
      case 'Academic Year':
        extra = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _acadYearDropdown(),
            // Semester only appears once a specific academic year is picked.
            if (_selectedAcadYear != 'All') ...[
              const SizedBox(width: 10),
              _semesterDropdown(),
            ],
          ],
        );
        break;
      case 'Date Range':
        final range = _pickedRange;
        extra = _dateValueButton(
          icon: Icons.date_range_rounded,
          label: range == null ? 'Pick a range' : _compactRangeLabel(range),
          onTap: _changeRange,
        );
        break;
      case 'Pick Date':
        final day = _pickedDate;
        extra = _dateValueButton(
          icon: Icons.calendar_today_rounded,
          label: day == null
              ? 'Pick a date'
              : DateFormat('MMM d, yyyy').format(day),
          onTap: _changeDate,
        );
        break;
    }
    if (extra != null) children.addAll([const SizedBox(width: 10), extra]);
    if (_selectedDateFilter != 'Today') {
      children.addAll([
        const SizedBox(width: 6),
        _clearButton(
          tooltip: 'Reset to today',
          onTap: () => setState(() {
            _selectedDateFilter = 'Today';
            _selectedAcadYear = 'All';
            _selectedSemester = 'All';
            _pickedRange = null;
            _pickedDate = null;
            _applyFilters();
          }),
        ),
      ]);
    }
    return Row(mainAxisSize: MainAxisSize.min, children: children);
  }

  String _compactRangeLabel(DateTimeRange range) {
    if (range.start.year == range.end.year) {
      return '${DateFormat('MMM d').format(range.start)} – '
          '${DateFormat('MMM d, yyyy').format(range.end)}';
    }
    return '${DateFormat('MMM d, yyyy').format(range.start)} – '
        '${DateFormat('MMM d, yyyy').format(range.end)}';
  }

  Widget _dateModeDropdown() {
    final safe = _dateFilterModes.contains(_selectedDateFilter)
        ? _selectedDateFilter
        : 'Today';
    return _filterDropdown(
      value: safe,
      icon: Icons.calendar_month_outlined,
      active: _selectedDateFilter != 'Today',
      items: [
        for (final o in _dateFilterModes)
          DropdownMenuItem(value: o, child: Text(o)),
      ],
      onChanged: _onDateModeChanged,
    );
  }

  Future<void> _onDateModeChanged(String? v) async {
    if (v == null || v == _selectedDateFilter) return;
    if (v == 'Date Range') {
      final range = await _pickDateRange();
      if (!mounted) return;
      setState(() {
        if (range != null) {
          _pickedRange = range;
          _selectedDateFilter = 'Date Range';
        } else if (_pickedRange == null) {
          // Cancelled with nothing picked before: keep the previous mode.
        } else {
          _selectedDateFilter = 'Date Range';
        }
        _applyFilters();
      });
      return;
    }
    if (v == 'Pick Date') {
      final day = await _pickSingleDate();
      if (!mounted) return;
      setState(() {
        if (day != null) {
          _pickedDate = day;
          _selectedDateFilter = 'Pick Date';
        } else if (_pickedDate != null) {
          _selectedDateFilter = 'Pick Date';
        }
        _applyFilters();
      });
      return;
    }
    setState(() {
      _selectedDateFilter = v;
      if (v == 'Academic Year') {
        // Open on the current period from the academic_periods table.
        final cur = ReferenceCatalog.currentPeriod;
        _selectedAcadYear =
            (cur?.acadYear ?? '').isEmpty ? 'All' : cur!.acadYear;
        _selectedSemester =
            (cur?.semester ?? '').isEmpty ? 'All' : cur!.semester;
      }
      _applyFilters();
    });
  }

  Future<DateTimeRange?> _pickDateRange() {
    final now = DateTime.now();
    return showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 10, 1, 1),
      lastDate: now,
      initialDateRange: _pickedRange,
      helpText: 'BMI RECORD DATE RANGE',
      cancelText: 'Cancel',
      confirmText: 'Apply',
      builder: (context, child) => Dialog(
        child: SizedBox(
          width: 480,
          height: 520,
          child: child,
        ),
      ),
    );
  }

  Future<DateTime?> _pickSingleDate() {
    final now = DateTime.now();
    return showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 10, 1, 1),
      lastDate: now,
      initialDate: _pickedDate ?? now,
      helpText: 'BMI RECORD DATE',
      cancelText: 'Cancel',
      confirmText: 'Apply',
    );
  }

  Future<void> _changeRange() async {
    final range = await _pickDateRange();
    if (!mounted || range == null) return;
    setState(() {
      _pickedRange = range;
      _applyFilters();
    });
  }

  Future<void> _changeDate() async {
    final day = await _pickSingleDate();
    if (!mounted || day == null) return;
    setState(() {
      _pickedDate = day;
      _applyFilters();
    });
  }

  Widget _whiteDropdown({
    required String value,
    required List<String> options,
    required String allLabel,
    required ValueChanged<String> onChanged,
    required IconData icon,
    String Function(String)? labelFor,
  }) {
    final safe = options.contains(value) ? value : 'All';
    return _filterDropdown(
      value: safe,
      icon: icon,
      active: safe != 'All',
      items: [
        for (final o in options)
          DropdownMenuItem(
            value: o,
            child: Text(o == 'All' ? allLabel : (labelFor?.call(o) ?? o)),
          ),
      ],
      onChanged: (v) {
        if (v != null) onChanged(v);
      },
    );
  }

  Widget _acadYearDropdown() {
    return _whiteDropdown(
      icon: Icons.school_outlined,
      value: _selectedAcadYear,
      options: ['All', ..._availableAcadYears],
      allLabel: 'All Years',
      labelFor: (o) => 'SY $o${_hasRecordsFor(o) ? '' : ''}',
      onChanged: (v) => setState(() {
        _selectedAcadYear = v;
        _selectedSemester = 'All';
        _applyFilters();
      }),
    );
  }

  Widget _semesterDropdown() {
    return _whiteDropdown(
      icon: Icons.event_note_outlined,
      value: _selectedSemester,
      options: ['All', ..._availableSemesters],
      allLabel: 'All Semesters',
      labelFor: (o) =>
          '$o${_hasRecordsFor(_selectedAcadYear, o) ? '' : ' s'}',
      onChanged: (v) => setState(() {
        _selectedSemester = v;
        _applyFilters();
      }),
    );
  }

  Widget _dateValueButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool active = true,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 250),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: _filterDeco(active),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: active ? kPrimary : kTextSub),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: kTextMain),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Results (Students, then Faculty & Staff) ───────────────────────────

  Widget _resultsSection() {
    if (_filteredRecords.isEmpty) return _emptyState();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final g in _visibleGroups)
          if (_ofGroup(_filteredRecords, g).isNotEmpty) ...[
            _groupSection(g),
            const SizedBox(height: 28),
          ],
      ],
    );
  }

  String _emptyMessage() {
    if (_selectedDateFilter == 'Academic Year' && _selectedAcadYear != 'All') {
      final sem = _selectedSemester == 'All' ? '' : ' · $_selectedSemester';
      return 'No records yet for SY $_selectedAcadYear$sem.';
    }
    return 'No BMI records found for the current filter.';
  }

  Widget _emptyState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.inbox_outlined, size: 40, color: kTextSub),
          const SizedBox(height: 10),
          Text(_emptyMessage(),
              textAlign: TextAlign.center,
              style: const TextStyle(color: kTextSub, fontSize: 14)),
        ],
      ),
    );
  }

  Widget _groupSection(String group) {
    final recs = _ofGroup(_filteredRecords, group);
    final blocks = _summaryBlocksFor(group, recs);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: kPrimary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kPrimary.withValues(alpha: 0.25)),
          ),
          child: Row(children: [
            Icon(_groupIcon(group), size: 18, color: kPrimary),
            const SizedBox(width: 10),
            Text(_groupTitle(group),
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: kPrimary)),
            const Spacer(),
            Text('${recs.length} record${recs.length == 1 ? '' : 's'}',
                style: const TextStyle(fontSize: 12.5, color: kTextSub)),
          ]),
        ),
        const SizedBox(height: 14),
        for (final b in blocks) ...[
          _sectionHeader(b.title, b.subtitle,
              icon: b.first == 'Program'
                  ? Icons.school_rounded
                  : Icons.apartment_rounded),
          const SizedBox(height: 10),
          _summaryTable(
            headers:
                _summaryHeaders(b.first, withTotal: true, second: b.second),
            rows: [
              for (final s in b.rows) _blockCells(b, s, withTotal: true),
            ],
          ),
          const SizedBox(height: 22),
        ],
        _detailsSection(group, recs),
      ],
    );
  }

  Widget _sectionHeader(
    String title,
    String subtitle, {
    required IconData icon,
    Widget? trailing,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: kPrimary.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: kPrimary),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: kTextDark,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(fontSize: 12, color: kTextSub),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 12), trailing],
      ],
    );
  }

  Widget _summaryTable(
      {required List<String> headers, required List<List<String>> rows}) {
    if (rows.isEmpty) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kBorder),
        ),
        child: const Text(
          'No BMI records found for the current filter.',
          style: TextStyle(color: kTextSub),
        ),
      );
    }
    return _tableShell(
      DataTable(
        headingRowHeight: 48,
        dataRowMinHeight: 44,
        dataRowMaxHeight: 50,
        headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
        headingTextStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            color: kTextSub,
            fontSize: 12,
            letterSpacing: 0.9),
        dataTextStyle: const TextStyle(color: kTextMain, fontSize: 14),
        columnSpacing: 24,
        horizontalMargin: 20,
        dividerThickness: 1,
        border: const TableBorder(
          horizontalInside: BorderSide(color: kBorder, width: 0.8),
        ),
        columns: [for (final h in headers) DataColumn(label: Text(h))],
        rows: [
          for (final (i, r) in rows.indexed)
            DataRow(
              color: WidgetStateProperty.resolveWith((s) {
                if (s.contains(WidgetState.hovered)) {
                  return kPrimary.withValues(alpha: 0.04);
                }
                return i.isEven ? Colors.white : const Color(0xFFFAFCFD);
              }),
              cells: [for (final c in r) DataCell(Text(c))],
            ),
        ],
      ),
    );
  }

  Widget _tableShell(Widget table) {
    return Container(
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
          return SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: table,
            ),
          );
        }),
      ),
    );
  }

  Widget _detailsSection(String group, List<BmiRecord> recs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(
          _detailsTitle(group),
          '${recs.length} record${recs.length == 1 ? '' : 's'} matching the current filter',
          icon: Icons.list_alt_rounded,
        ),
        const SizedBox(height: 10),
        _tableShell(
          DataTable(
            headingRowHeight: 48,
            dataRowMinHeight: 44,
            dataRowMaxHeight: 52,
            headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
            headingTextStyle: const TextStyle(
                fontWeight: FontWeight.w800,
                color: kTextSub,
                fontSize: 12,
                letterSpacing: 0.9),
            dataTextStyle: const TextStyle(color: kTextMain, fontSize: 14),
            columnSpacing: 24,
            horizontalMargin: 20,
            dividerThickness: 1,
            border: const TableBorder(
              horizontalInside: BorderSide(color: kBorder, width: 0.8),
            ),
            columns: [
              for (final h in _detailHeaders(group))
                DataColumn(label: Text(h)),
            ],
            rows: [
              for (final (i, r) in recs.indexed)
                DataRow(
                  color: WidgetStateProperty.resolveWith((s) {
                    if (s.contains(WidgetState.hovered)) {
                      return kPrimary.withValues(alpha: 0.04);
                    }
                    return i.isEven ? Colors.white : const Color(0xFFFAFCFD);
                  }),
                  cells: [
                    for (final c in _detailCells(group, r)) DataCell(Text(c)),
                    DataCell(_indicatorPill(r.indicator)),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }

  String _fmtBirthdate(DateTime? d) =>
      d == null ? '—' : DateFormat('MMM d, yyyy').format(d);

  Widget _indicatorPill(String indicator) {
    final (bg, fg) = switch (indicator) {
      'Underweight' => (const Color(0xFFE0F2FE), const Color(0xFF0369A1)),
      'Normal' => (const Color(0xFFDCFCE7), const Color(0xFF15803D)),
      'Overweight' => (const Color(0xFFFEF3C7), const Color(0xFFB45309)),
      'Obese' => (const Color(0xFFFEE2E2), const Color(0xFFB91C1C)),
      _ => (const Color(0xFFF1F5F9), const Color(0xFF64748B)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        indicator,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: FontWeight.w700,
          color: fg,
        ),
      ),
    );
  }

  // ── Print preview ──────────────────────────────────────────────────────

  Future<void> _showPrintPreview() async {
    await showDialog<void>(
      context: context,
      builder: (ctx) {
        var printing = false;
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            final format = PaperFormat.formatFor('Letter', false);

            Future<void> printSheet() async {
              if (printing) return;
              setDialogState(() => printing = true);
              final messenger = ScaffoldMessenger.of(context);
              try {
                await Printing.layoutPdf(
                  name: 'TCGC_BMI_Records.pdf',
                  format: format,
                  dynamicLayout: true,
                  onLayout: (paper) async =>
                      (await _buildDocument(pageFormat: paper)).save(),
                );
              } catch (e) {
                messenger.showSnackBar(
                  SnackBar(
                    content: Text('Could not print the BMI records: $e'),
                  ),
                );
              } finally {
                if (ctx.mounted) setDialogState(() => printing = false);
              }
            }

            return Dialog.fullscreen(
              child: Scaffold(
                backgroundColor: kBg,
                appBar: AppBar(
                  backgroundColor: Colors.white,
                  foregroundColor: kTextMain,
                  elevation: 0.5,
                  titleSpacing: 20,
                  title: const Text(
                    'Print Preview — BMI Records',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  leading: IconButton(
                    icon: const Icon(Icons.close),
                    tooltip: 'Close preview',
                    onPressed: () => Navigator.pop(ctx),
                  ),
                  actions: [
                    IconButton(
                      icon: const Icon(Icons.print),
                      tooltip: 'Print',
                      onPressed: printing ? null : printSheet,
                    ),
                    const SizedBox(width: 12),
                  ],
                ),
                body: PdfPreviewCustom(
                  pageFormat: format,
                  build: (paper) async =>
                      (await _buildDocument(pageFormat: paper)).save(),
                  pagesBuilder: zoomablePagesBuilder,
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── Print: date label ──────────────────────────────────────────────────

  String _rangeText(DateTime a, DateTime b) {
    final sameDay = a.year == b.year && a.month == b.month && a.day == b.day;
    if (sameDay) return _fmtDate(a);
    return _compactRangeLabel(DateTimeRange(start: a, end: b));
  }

  /// "Nov 2, 2026" for a single day, "Jan 1 – Nov 2, 2026" for a range.
  String _printDateLabel(List<BmiRecord> records) {
    final now = DateTime.now();
    switch (_selectedDateFilter) {
      case 'Today':
        return _fmtDate(now);
      case 'This Week':
        final start = DateTime(now.year, now.month, now.day)
            .subtract(Duration(days: now.weekday - 1));
        return _rangeText(start, start.add(const Duration(days: 6)));
      case 'This Month':
        return _rangeText(DateTime(now.year, now.month, 1),
            DateTime(now.year, now.month + 1, 0));
      case 'Date Range':
        final r = _pickedRange;
        return r == null ? '' : _rangeText(r.start, r.end);
      case 'Pick Date':
        final d = _pickedDate;
        return d == null ? '' : _fmtDate(d);
      case 'Academic Year':
        if (_selectedAcadYear != 'All') {
          var label = 'A.Y. $_selectedAcadYear';
          if (_selectedSemester != 'All') {
            final t = _selectedSemester.toLowerCase();
            final sem = (t.contains('sem') || t.contains('summer'))
                ? _selectedSemester
                : '$_selectedSemester Semester';
            label += ' – $sem';
          }
          return label;
        }
        break;
    }
    final dates = [
      for (final r in records)
        if (r.visitDate != null) r.visitDate!
    ]..sort();
    if (dates.isEmpty) return '';
    return _rangeText(dates.first, dates.last);
  }

  String _printFilterLine() => [
        if (_selectedSex != 'All') 'Sex: $_selectedSex',
        if (_selectedAge != 'All') 'Age: $_selectedAge',
        if (_birthRange != null)
          'Birthdate: ${_rangeText(_birthRange!.start, _birthRange!.end)}',
      ].join('  |  ').replaceAll('—', '-').replaceAll('–', '-');

  // ── Print: document ────────────────────────────────────────────────────

  Future<pw.Document> _buildDocument(
      {required PdfPageFormat pageFormat}) async {
    final doc = pw.Document();
    final records = _filteredRecords;
    final dateLabel =
        _printDateLabel(records).replaceAll('—', '-').replaceAll('–', '-');
    final filterLine = _printFilterLine();
    final groups = [
      for (final g in _visibleGroups)
        if (_ofGroup(records, g).isNotEmpty) g,
    ];

    final DocMetrics metrics = DocMetrics(pageFormat);
    final String headerSvg = await loadSheetHeaderSvg();
    final String footerSvg = await loadSheetFooterSvg();
    final bool isLandscape = pageFormat.width > pageFormat.height;
    final double hang = isLandscape ? 26 : 30;
    final pw.EdgeInsets margin = pw.EdgeInsets.fromLTRB(hang, 0, hang, 0);

    doc.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        margin: margin,
        theme: serifTheme(),
        header: (pw.Context context) => sheetHeader(metrics, headerSvg, hang),
        footer: (pw.Context context) => sheetFooter(metrics, footerSvg, hang),
        build: (pw.Context context) => [
          pw.SizedBox(height: 6),
          _printTitleBlock(context, pageFormat.width),
          pw.SizedBox(height: 10),
          _printInfoBlock(''),
          pw.SizedBox(height: 10),
          if (groups.isEmpty) ...[
            if (dateLabel.isNotEmpty || filterLine.isNotEmpty)
              _printDateLine(dateLabel, filterLine),
            pw.SizedBox(height: 16),
            pw.Center(child: pw.Text(_emptyMessage())),
          ],
          // Students first; faculty & staff start on their own page.
          for (var i = 0; i < groups.length; i++) ...[
            if (i > 0) pw.NewPage(),
            ..._printGroup(
              groups[i],
              _ofGroup(records, groups[i]),
              dateLabel,
              filterLine,
            ),
          ],
        ],
      ),
    );
    return doc;
  }

  List<pw.Widget> _printGroup(
    String group,
    List<BmiRecord> recs,
    String dateLabel,
    String filterLine,
  ) {
    final blocks = _summaryBlocksFor(group, recs);
    return [
      _printStatStrip(recs, group),
      if (dateLabel.isNotEmpty || filterLine.isNotEmpty) ...[
        pw.SizedBox(height: 8),
        _printDateLine(dateLabel, filterLine),
      ],
      pw.SizedBox(height: 16),
      for (final b in blocks) ...[
        _printSectionTitle(b.title.toUpperCase()),
        pw.SizedBox(height: 6),
        _printTable(
          headers: _summaryHeaders(b.first, withTotal: false, second: b.second),
          rows: [
            for (final s in b.rows) _blockCells(b, s, withTotal: false),
          ],
        ),
        pw.SizedBox(height: 16),
      ],
      _printSectionTitle(_printDetailsTitle(group)),
      pw.SizedBox(height: 6),
      _printTable(
        headers: _printDetailHeaders(group),
        rows: [for (final r in recs) _printDetailCells(group, r)],
      ),
    ];
  }

  pw.Widget _printSectionTitle(String title) {
    return pw.Align(
      alignment: pw.Alignment.centerLeft,
      child: pw.Text(
        title,
        style: pw.TextStyle(
          fontSize: 11,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.black,
        ),
      ),
    );
  }

  /// Institute name centered under the "BMI RECORDS" title (only when an
  /// institute is selected).
  pw.Widget _printInfoBlock(String dateLabel) {
    final inst = _selectedInstitute == 'All' ? '' : _selectedInstitute;
    if (inst.isEmpty && dateLabel.isEmpty) return pw.SizedBox();

    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        if (inst.isNotEmpty)
          pw.Align(
            alignment: pw.Alignment.center,
            child: pw.Text(
              inst,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(
                font: pw.Font.timesBold(),
                fontWeight: pw.FontWeight.bold,
                fontSize: 17,
                color: _sheetGreen,
              ),
            ),
          ),
        if (inst.isNotEmpty && dateLabel.isNotEmpty) pw.SizedBox(height: 8),
        if (dateLabel.isNotEmpty)
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.RichText(
              text: pw.TextSpan(
                style: const pw.TextStyle(fontSize: 9, color: PdfColors.black),
                children: [
                  pw.TextSpan(
                    text: 'Date: ',
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.black,
                    ),
                  ),
                  pw.TextSpan(text: dateLabel),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// Filters on the left (only when used), date on the right.
  pw.Widget _printDateLine(String dateLabel, [String filters = '']) {
    pw.Widget labeled(String label, String value) => pw.RichText(
          text: pw.TextSpan(
            style: const pw.TextStyle(fontSize: 9, color: PdfColors.black),
            children: [
              pw.TextSpan(
                text: '$label: ',
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColors.black,
                ),
              ),
              pw.TextSpan(text: value),
            ],
          ),
        );
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        filters.isEmpty ? pw.SizedBox() : labeled('Filters', filters),
        dateLabel.isEmpty ? pw.SizedBox() : labeled('Date', dateLabel),
      ],
    );
  }

  pw.Widget _printTitleBlock(pw.Context context, double pageWidth) {
    final double unit = pageWidth / 1545;
    final regular = pw.Font.times();
    final bold = pw.Font.timesBold();

    double filled(pw.Font font, String text, double width) {
      final em = font.getFont(context).stringMetrics(text).width;
      if (text.isEmpty || em <= 0 || !em.isFinite) return 15;
      return (width / em).clamp(1, 200).toDouble();
    }

    pw.Widget line(String text, {required bool isBold, required double units}) {
      final font = isBold ? bold : regular;
      return pw.Text(
        text,
        softWrap: false,
        textAlign: pw.TextAlign.center,
        style: pw.TextStyle(
          font: font,
          fontWeight: isBold ? pw.FontWeight.bold : pw.FontWeight.normal,
          fontSize: filled(font, text, units * unit),
          color: _sheetGreen,
        ),
      );
    }

    return pw.Align(
      alignment: pw.Alignment.center,
      child: pw.Column(
        mainAxisSize: pw.MainAxisSize.min,
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          line('MEDICAL AND DENTAL CLINIC OFFICE', isBold: true, units: 737),
          pw.SizedBox(height: 6),
          line('Maloro, Tangub City', isBold: false, units: 279),
          pw.SizedBox(height: 44),
          line('BMI RECORDS', isBold: true, units: 530),
        ],
      ),
    );
  }

  pw.Widget _printStatStrip(List<BmiRecord> records, String group) {
    int count(String c) => records.where((r) => r.indicator == c).length;
    final allStats =
        <({String label, int value, PdfColor tint, PdfColor ink})>[
      (
        label: 'Total ${_groupTitle(group)}',
        value: records.length,
        tint: PdfColor.fromInt(0xFFF1F5F9),
        ink: PdfColor.fromInt(0xFF334155),
      ),
      (
        label: 'Underweight',
        value: count('Underweight'),
        tint: PdfColor.fromInt(0xFFE0F2FE),
        ink: PdfColor.fromInt(0xFF0369A1),
      ),
      (
        label: 'Normal',
        value: count('Normal'),
        tint: PdfColor.fromInt(0xFFDCFCE7),
        ink: PdfColor.fromInt(0xFF15803D),
      ),
      (
        label: 'Overweight',
        value: count('Overweight'),
        tint: PdfColor.fromInt(0xFFFFF7ED),
        ink: PdfColor.fromInt(0xFFB45309),
      ),
      (
        label: 'Obese',
        value: count('Obese'),
        tint: PdfColor.fromInt(0xFFFEE2E2),
        ink: PdfColor.fromInt(0xFFB91C1C),
      ),
    ];
    // When one BMI indicator is selected, print only that indicator's count.
    final stats = _singleIndicator
        ? allStats.where((s) => s.label == _selectedClassification).toList()
        : allStats;
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.center,
      children: [
        for (final s in stats)
          pw.Padding(
            padding: const pw.EdgeInsets.symmetric(horizontal: 3),
            child: pw.Container(
              padding:
                  const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: pw.BoxDecoration(
                color: s.tint,
                borderRadius: pw.BorderRadius.circular(5),
              ),
              child: pw.Row(
                mainAxisSize: pw.MainAxisSize.min,
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Text(
                    '${s.value}',
                    style: pw.TextStyle(
                      fontSize: 12,
                      fontWeight: pw.FontWeight.bold,
                      color: s.ink,
                    ),
                  ),
                  pw.SizedBox(width: 5),
                  pw.Text(
                    s.label,
                    style: pw.TextStyle(fontSize: 7.5, color: s.ink),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  pw.Widget _printTable({
    required List<String> headers,
    required List<List<String>> rows,
  }) {
    // The PDF Times font has no en/em dash glyph (it prints as a box), so
    // use a plain hyphen in the printout.
    String safe(String s) => s.replaceAll('—', '-').replaceAll('–', '-');
    final data = rows.isEmpty
        ? [List<String>.filled(headers.length, '')]
        : [
            for (final r in rows) [for (final c in r) safe(c)],
          ];
    return pw.Container(
      foregroundDecoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.black, width: 0.7),
      ),
      child: pw.TableHelper.fromTextArray(
        headers: headers,
        data: data,
        headerDecoration: const pw.BoxDecoration(color: PdfColors.white),
        headerAlignment: pw.Alignment.center,
        cellAlignment: pw.Alignment.center,
        headerStyle: pw.TextStyle(
          fontSize: 8.5,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.black,
        ),
        cellStyle: pw.TextStyle(
          fontSize: 8.5,
          lineSpacing: 1.6,
          color: PdfColors.black,
        ),
        cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
        border: pw.TableBorder.symmetric(
          inside: const pw.BorderSide(color: PdfColors.black, width: 0.6),
        ),
      ),
    );
  }
}