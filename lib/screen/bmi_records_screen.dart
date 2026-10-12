// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../core/vitals.dart';
import '../services/data_tracker.dart';
import '../services/reference_data_service.dart';
import '../services/supabase_config.dart';
import 'app_colors.dart';
import 'document_template.dart';

// ── MODEL ────────────────────────────────────────────────────────────────

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
      age: age,
    );
  }

  // Body mass index computed when the stored number is missing.
  double get computedBmi {
    if (bmi != null && bmi!.isFinite) return bmi!;
    final h = heightCm;
    final w = weightKg;
    if (h == null || w == null || h <= 0 || w <= 0) return double.nan;
    final m = h / 100;
    return w / (m * m);
  }

  // The word used by the clinic threshold table (vitals.dart), not the
  // unvalidated string stored at capture time.
  String get indicator {
    final value = computedBmi;
    if (!value.isFinite) return 'Unknown';
    final b = VitalsThresholds.resolve(VitalsThresholds.instance.bmi, value);
    return b.label.isEmpty ? 'Unknown' : b.label;
  }

  String get fullName {
    final parts =
        <String>[ln, fn, mn, suffix].where((p) => p.isNotEmpty).toList();
    if (parts.isNotEmpty) return parts.join(', ');
    return '$fn $mn $ln $suffix'.trim();
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

class BmiSummaryByInstitute {
  final String institute;
  final int underweight;
  final int normal;
  final int overweight;
  final int obese;
  final int total;

  const BmiSummaryByInstitute({
    required this.institute,
    required this.underweight,
    required this.normal,
    required this.overweight,
    required this.obese,
    this.total = 0,
  });
}

class BmiSummaryByProgram {
  final String institute;
  final String program;
  final int underweight;
  final int normal;
  final int overweight;
  final int obese;
  final int total;

  const BmiSummaryByProgram({
    required this.institute,
    required this.program,
    required this.underweight,
    required this.normal,
    required this.overweight,
    required this.obese,
    this.total = 0,
  });
}

// ── SCREEN ───────────────────────────────────────────────────────────────

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

  bool _isLoading = true;
  List<BmiRecord> _allRecords = [];
  List<BmiRecord> _filteredRecords = [];
  List<BmiSummaryByInstitute> _instituteSummaries = [];
  List<BmiSummaryByProgram> _programSummaries = [];
  List<String> _institutes = [];

  // True when the database had nothing to show and the screen is painting the
  // built-in demo roster so every table, filter and summary can still be seen.
  bool _usingSampleData = false;

  String _selectedInstitute = 'All';
  // Multi-select: empty means "All Programs".
  final Set<String> _selectedPrograms = <String>{};
  String _selectedClassification = 'All';

  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;
  VoidCallback? _dataListener;

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

  // ── DATA ───────────────────────────────────────────────────────────────

  Future<void> _loadRecords() async {
    if (mounted) setState(() => _isLoading = true);
    // Make sure the Institute/Program dropdowns are fed from the database
    // reference tables before we decide what to show. A no-op once loaded.
    await ReferenceCatalog.loadQuietly();
    try {
      // PostgREST can only embed through a direct foreign key. `bmi_records`
      // points at `clinic_visit_services`, which points at `clinic_visits`,
      // which points at `individual_records`; the person's academic/reference
      // detail hangs off `individual_records`. So the embeds must be NESTED
      // through that chain — asking for `clinic_visits` or `individual_records`
      // at the top level of `bmi_records` is rejected (PGRST200).
      final response = await supabaseClient.from('bmi_records').select('''
        bmi_record_id, visit_service_id, height_cm, weight_kg, bmi, classification, notes,
        clinic_visit_services!inner(
          visit_id, service_type_id,
          clinic_visits!inner(
            visit_id, person_id, visit_date, visit_time,
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
          final ir = _firstMap(cv['individual_records']);
          final iar = _firstMap(ir['individual_academic_records']);
          final inst = _firstMap(iar['institutes']);
          final prg = _firstMap(iar['program']);
          final dpt = _firstMap(iar['departments_offices']);
          final pos = _firstMap(iar['positions']);

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
          records.add(BmiRecord.fromSupabase(flat));
        } catch (_) {}
      }

      if (!mounted) return;
      // With RLS on, or before the visit tables exist, the read comes back
      // empty. Rather than show a blank screen, fall back to the demo roster so
      // the summaries, filters and detail table all have something to render.
      if (records.isEmpty) {
        setState(() {
          _allRecords = _sampleRecords();
          _usingSampleData = true;
          _buildFilterOptions();
          _applyFilters();
          _isLoading = false;
        });
        return;
      }
      setState(() {
        _allRecords = records;
        _usingSampleData = false;
        _buildFilterOptions();
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      // A missing table or a dropped connection still leaves a usable screen:
      // the demo roster stands in and a quiet banner says so.
      setState(() {
        _allRecords = _sampleRecords();
        _usingSampleData = true;
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
            'Showing sample data — live BMI records could not be loaded: $e',
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

  void _buildFilterOptions() {
    final institutes = <String>{};
    for (final r in _allRecords) {
      if (r.instituteName.isNotEmpty) institutes.add(r.instituteName);
    }
    // The database is authoritative: whatever the reference tables hold is
    // offered even before a single BMI row exists for it.
    for (final e in ReferenceCatalog.institutes) {
      if (e.name.isNotEmpty) institutes.add(e.name);
    }
    _institutes = institutes.toList()..sort();
    if (_selectedInstitute != 'All' &&
        !institutes.contains(_selectedInstitute)) {
      _selectedInstitute = 'All';
    }
    // Drop any program selection that the current institute no longer offers.
    final valid = _programOptions.toSet();
    _selectedPrograms.removeWhere((p) => !valid.contains(p));
  }

  /// Program codes offered by the current institute selection, read from the
  /// database catalog first and topped up with whatever the records mention.
  List<String> get _programOptions {
    final programs = <String>{};
    if (_selectedInstitute == 'All') {
      for (final r in _allRecords) {
        if (r.programName.isNotEmpty) programs.add(r.programName);
      }
      for (final p in ReferenceCatalog.programs) {
        if (p.code.isNotEmpty) programs.add(p.code);
      }
    } else {
      for (final r in _allRecords) {
        if (r.instituteName == _selectedInstitute && r.programName.isNotEmpty) {
          programs.add(r.programName);
        }
      }
      for (final e in ReferenceCatalog.institutes) {
        if (e.name == _selectedInstitute) {
          programs.addAll(ReferenceCatalog.programsOf(e.id));
        }
      }
    }
    return programs.toList()..sort();
  }

  void _applyFilters() {
    final q = _searchQuery.trim().toLowerCase();
    final filtered = _allRecords.where((r) {
      if (_selectedInstitute != 'All' &&
          r.instituteName != _selectedInstitute) {
        return false;
      }
      if (_selectedPrograms.isNotEmpty &&
          !_selectedPrograms.contains(r.programName)) {
        return false;
      }
      if (_selectedClassification != 'All' &&
          r.indicator != _selectedClassification) {
        return false;
      }
      if (q.isNotEmpty) {
        final hay = [
          r.personId,
          r.fullName,
          r.ln,
          r.fn,
          r.instituteName,
          r.programName,
        ].join(' ').toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();

    _filteredRecords = filtered;
    _instituteSummaries = _summarizeByInstitute(filtered);
    _programSummaries = _summarizeByProgram(filtered);
  }

  List<BmiSummaryByInstitute> _summarizeByInstitute(List<BmiRecord> records) {
    final groups = <String, List<BmiRecord>>{};
    for (final r in records) {
      final key = r.instituteName.isEmpty ? 'Unknown' : r.instituteName;
      groups.putIfAbsent(key, () => <BmiRecord>[]).add(r);
    }
    final keys = groups.keys.toList()..sort();
    return [
      for (final k in keys)
        BmiSummaryByInstitute(
          institute: k,
          underweight:
              groups[k]!.where((r) => r.indicator == 'Underweight').length,
          normal: groups[k]!.where((r) => r.indicator == 'Normal').length,
          overweight:
              groups[k]!.where((r) => r.indicator == 'Overweight').length,
          obese: groups[k]!.where((r) => r.indicator == 'Obese').length,
          total: groups[k]!.length,
        ),
    ];
  }

  List<BmiSummaryByProgram> _summarizeByProgram(List<BmiRecord> records) {
    final groups = <String, BmiSummaryByProgram>{};
    for (final r in records) {
      final inst = r.instituteName.isEmpty ? 'Unknown' : r.instituteName;
      final prog = r.programName.isEmpty ? 'Unknown' : r.programName;
      final key = '$inst\x00$prog';
      final summary = groups.putIfAbsent(
        key,
        () => BmiSummaryByProgram(
          institute: inst,
          program: prog,
          underweight: 0,
          normal: 0,
          overweight: 0,
          obese: 0,
          total: 0,
        ),
      );
      // immutable model: rebuild the counter row.
      groups[key] = BmiSummaryByProgram(
        institute: inst,
        program: prog,
        underweight:
            summary.underweight + (r.indicator == 'Underweight' ? 1 : 0),
        normal: summary.normal + (r.indicator == 'Normal' ? 1 : 0),
        overweight: summary.overweight + (r.indicator == 'Overweight' ? 1 : 0),
        obese: summary.obese + (r.indicator == 'Obese' ? 1 : 0),
        total: summary.total + 1,
      );
    }
    final list = groups.values.toList();
    list.sort((a, b) {
      final byInstitute = a.institute.compareTo(b.institute);
      return byInstitute != 0 ? byInstitute : a.program.compareTo(b.program);
    });
    return list;
  }

  // ── HELPERS FOR DISPLAY ───────────────────────────────────────────────

  String _fmtDate(DateTime? d) =>
      d == null ? '—' : DateFormat('MMM d, yyyy').format(d);

  String _fmtNum(double? v) =>
      v == null || !v.isFinite ? '—' : v.toStringAsFixed(1);

  String get _coverageLabel {
    final parts = <String>[];
    if (_selectedInstitute != 'All') parts.add(_selectedInstitute);
    if (_selectedPrograms.isNotEmpty) {
      parts.add(_selectedPrograms.length == 1
          ? _selectedPrograms.first
          : '${_selectedPrograms.length} programs');
    }
    if (_selectedClassification != 'All') parts.add(_selectedClassification);
    return parts.isEmpty ? 'All Students' : parts.join(' • ');
  }

  // ── SAMPLE DATA (UI PREVIEW ONLY) ─────────────────────────────────────
  //
  // The `bmi_records` table is empty behind RLS, so nothing would ever show.
  // These rows let every summary, filter and column be seen and judged while
  // the live schema is still being finished. They are never written anywhere
  // and are dropped the moment a real record loads.

  List<BmiRecord> _sampleRecords() {
    final drafts = <({
      String id,
      String inst,
      String prog,
      String yr,
      String fn,
      String ln,
      String sex,
      String dob,
      int age,
      double h,
      double w
    })>[
      (
        id: 'F001',
        inst: 'Institute of Computer Science',
        prog: 'BSCS',
        yr: '1st Year',
        fn: 'Ana',
        ln: 'Reyes',
        sex: 'Female',
        dob: '2005-03-12',
        age: 20,
        h: 162,
        w: 49,
      ),
      (
        id: 'F002',
        inst: 'Institute of Computer Science',
        prog: 'BSCS',
        yr: '2nd Year',
        fn: 'Mark',
        ln: 'Santos',
        sex: 'Male',
        dob: '2004-08-01',
        age: 21,
        h: 174,
        w: 68,
      ),
      (
        id: 'F003',
        inst: 'Institute of Computer Science',
        prog: 'BSIT',
        yr: '1st Year',
        fn: 'Jessa',
        ln: 'Cruz',
        sex: 'Female',
        dob: '2006-01-22',
        age: 19,
        h: 158,
        w: 88,
      ),
      (
        id: 'F004',
        inst: 'Institute of Business and Finance',
        prog: 'BSBA-HRM',
        yr: '3rd Year',
        fn: 'Paolo',
        ln: 'Garcia',
        sex: 'Male',
        dob: '2003-11-05',
        age: 22,
        h: 170,
        w: 80,
      ),
      (
        id: 'F005',
        inst: 'Institute of Business and Finance',
        prog: 'BSOA',
        yr: '2nd Year',
        fn: 'Liza',
        ln: 'Mendoza',
        sex: 'Female',
        dob: '2004-06-18',
        age: 21,
        h: 160,
        w: 55,
      ),
      (
        id: 'F006',
        inst: 'Institute of Teacher Education',
        prog: 'BEED',
        yr: '4th Year',
        fn: 'Karen',
        ln: 'Villanueva',
        sex: 'Female',
        dob: '2002-02-14',
        age: 24,
        h: 155,
        w: 60,
      ),
      (
        id: 'F007',
        inst: 'Institute of Teacher Education',
        prog: 'BSED-MATH',
        yr: '1st Year',
        fn: 'Nico',
        ln: 'Torres',
        sex: 'Male',
        dob: '2006-09-30',
        age: 18,
        h: 168,
        w: 50,
      ),
      (
        id: 'F008',
        inst: 'Institute of Health Sciences',
        prog: 'GEN. MIDWIFERY',
        yr: '2nd Year',
        fn: 'Grace',
        ln: 'Lim',
        sex: 'Female',
        dob: '2004-04-09',
        age: 21,
        h: 157,
        w: 66,
      ),
      (
        id: 'F009',
        inst: 'Institute of Health Sciences',
        prog: 'GEN. MIDWIFERY',
        yr: '3rd Year',
        fn: 'Arnel',
        ln: 'Bautista',
        sex: 'Male',
        dob: '2003-07-27',
        age: 22,
        h: 165,
        w: 92,
      ),
      (
        id: 'F010',
        inst: 'Institute of Arts and Sciences',
        prog: 'AB POLSCI',
        yr: '1st Year',
        fn: 'Sheila',
        ln: 'Ramos',
        sex: 'Female',
        dob: '2005-12-02',
        age: 20,
        h: 163,
        w: 52,
      ),
      (
        id: 'F011',
        inst: 'Institute of Arts and Sciences',
        prog: 'AB ENGLISH',
        yr: '4th Year',
        fn: 'James',
        ln: 'Aquino',
        sex: 'Male',
        dob: '2002-05-15',
        age: 24,
        h: 178,
        w: 74,
      ),
      (
        id: 'F012',
        inst: 'Institute of Criminal Justice Education',
        prog: 'BSCRIM',
        yr: '2nd Year',
        fn: 'Diana',
        ln: 'Flores',
        sex: 'Female',
        dob: '2004-10-11',
        age: 21,
        h: 166,
        w: 58,
      ),
    ];

    final now = DateTime.now();
    return [
      for (final d in drafts)
        BmiRecord(
          bmiRecordId: 'SAMPLE-${d.id}',
          visitServiceId: 'SAMPLE-VS-${d.id}',
          heightCm: d.h,
          weightKg: d.w,
          visitId: 'SAMPLE-V-${d.id}',
          personId: d.id,
          visitDate: now.subtract(Duration(days: 3 + d.age % 27)),
          visitTime: '09:${(d.age * 3) % 60}',
          personType: 'Student',
          fn: d.fn,
          ln: d.ln,
          dateOfBirth: DateTime.tryParse(d.dob),
          sex: d.sex,
          instituteName: d.inst,
          programName: d.prog,
          yearLevel: d.yr,
          age: d.age,
        ),
    ];
  }

  // ── BUILD ──────────────────────────────────────────────────────────────

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
                          _summarySection(),
                          const SizedBox(height: 24),
                          _detailsSection(),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  /// Title block only — the header carries no colour of its own, so the page
  /// reads the same as the Records Booklet and the Reports page.
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
              children: [
                Row(
                  children: [
                    const Text('BMI Records',
                        style: TextStyle(
                            color: kTextDark,
                            fontWeight: FontWeight.w800,
                            fontSize: 22)),
                    if (_usingSampleData) ...[
                      const SizedBox(width: 10),
                      _sampleChip(),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                const Text('Body mass index records for students',
                    style: TextStyle(color: kTextSub, fontSize: 13)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sampleChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: kPrimary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kPrimary.withValues(alpha: 0.30)),
      ),
      child: const Text(
        'SAMPLE DATA',
        style: TextStyle(
            color: kPrimary,
            fontSize: 9.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8),
      ),
    );
  }

  /// The print action floats at the bottom-right, exactly like the Records
  /// Booklet: an icon with its label beneath it, always one tap away.
  Widget _printFab() {
    return Tooltip(
      message: 'Print BMI Records',
      child: Material(
        color: kPrimary,
        borderRadius: BorderRadius.circular(16),
        elevation: 6,
        child: InkWell(
          onTap: _showPrintDialog,
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
    final total = _filteredRecords.length;
    int count(String c) =>
        _filteredRecords.where((r) => r.indicator == c).length;
    final stats = <({String label, int value, Color color, IconData icon})>[
      (
        label: 'Total Students',
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
      // Five boxes that fill the row edge to edge — no dead space on the
      // right. On a narrow page they fold into the same expandable grid.
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

  Widget _filterRow() {
    return LayoutBuilder(builder: (context, constraints) {
      final isNarrow = constraints.maxWidth < 640;
      final search = _searchField();
      final indicator = _indicatorFilter();
      if (isNarrow) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            search,
            const SizedBox(height: 10),
            Align(alignment: Alignment.centerLeft, child: indicator),
          ],
        );
      }
      return Row(
        children: [
          Expanded(child: search),
          const SizedBox(width: 14),
          indicator,
        ],
      );
    });
  }

  /// Short and wide — it stretches to take all the room the BMI indicator
  /// filter does not, instead of the old fixed 260px stub.
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
            const EdgeInsets.symmetric(vertical: 11, horizontal: 12),
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

  Widget _indicatorFilter() {
    const options = ['All', 'Underweight', 'Normal', 'Overweight', 'Obese'];
    final safe = options.contains(_selectedClassification)
        ? _selectedClassification
        : 'All';
    return Container(
      height: 44,
      padding: const EdgeInsets.only(left: 14, right: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(
            color: _selectedClassification == 'All' ? kBorder : kPrimary),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: safe,
          isDense: true,
          borderRadius: BorderRadius.circular(12),
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              size: 18, color: kTextSub),
          style: const TextStyle(
              fontSize: 12.5, fontWeight: FontWeight.w600, color: kTextMain),
          items: [
            for (final o in options)
              DropdownMenuItem(
                value: o,
                child: Text(o == 'All' ? 'BMI Indicator: All' : o),
              ),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() {
              _selectedClassification = v;
              _applyFilters();
            });
          },
        ),
      ),
    );
  }

  Widget _summarySection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(
          'Summary by Institute',
          'Student count per BMI classification, grouped by institute',
          icon: Icons.apartment_rounded,
          trailing: _instituteSelector(),
        ),
        const SizedBox(height: 10),
        _summaryTable(
          headers: const [
            'Institute',
            'Underweight',
            'Normal',
            'Overweight',
            'Obese',
            'Total'
          ],
          rows: [
            for (final s in _instituteSummaries)
              [
                s.institute,
                '${s.underweight}',
                '${s.normal}',
                '${s.overweight}',
                '${s.obese}',
                '${s.total}',
              ],
          ],
        ),
        const SizedBox(height: 22),
        _sectionHeader(
          'Summary by Program',
          'Student count per BMI classification, grouped by program',
          icon: Icons.school_rounded,
          trailing: _programSelector(),
        ),
        const SizedBox(height: 10),
        _summaryTable(
          headers: const [
            'Institute',
            'Program',
            'Underweight',
            'Normal',
            'Overweight',
            'Obese',
            'Total'
          ],
          rows: [
            for (final s in _programSummaries)
              [
                s.institute,
                s.program,
                '${s.underweight}',
                '${s.normal}',
                '${s.overweight}',
                '${s.obese}',
                '${s.total}',
              ],
          ],
        ),
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

  /// Institute filter, shown beside the "Summary by Institute" heading. Reads
  /// its options from the database catalog, topped up with anything already
  /// present on a BMI record.
  Widget _instituteSelector() {
    final options = <String>['All', ..._institutes];
    final safe =
        options.contains(_selectedInstitute) ? _selectedInstitute : 'All';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: _selectedInstitute == 'All' ? kBorder : kPrimary),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: safe,
          isDense: true,
          borderRadius: BorderRadius.circular(12),
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              size: 18, color: kTextSub),
          style: const TextStyle(
              fontSize: 12.5, fontWeight: FontWeight.w600, color: kTextMain),
          items: [
            for (final o in options)
              DropdownMenuItem(
                value: o,
                child: Text(o == 'All' ? 'All Institutes' : o),
              ),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() {
              _selectedInstitute = v;
              _selectedPrograms.clear();
              _buildFilterOptions();
              _applyFilters();
            });
          },
        ),
      ),
    );
  }

  /// Program filter, shown beside the "Summary by Program" heading. Narrowed to
  /// the chosen institute and multi-selectable; an empty set means "All".
  Widget _programSelector() {
    final options = _programOptions;
    final enabled = options.isNotEmpty;
    final label = _selectedPrograms.isEmpty
        ? 'All Programs'
        : _selectedPrograms.length == 1
            ? _selectedPrograms.first
            : '${_selectedPrograms.length} programs';
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: enabled ? _openProgramPicker : null,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
                color: _selectedPrograms.isEmpty ? kBorder : kPrimary),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.filter_list_rounded,
                  size: 16, color: enabled ? kPrimary : kTextSub),
              const SizedBox(width: 8),
              Text(
                label,
                style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: enabled ? kTextMain : kTextSub),
              ),
              const SizedBox(width: 6),
              const Icon(Icons.keyboard_arrow_down_rounded,
                  size: 18, color: kTextSub),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openProgramPicker() async {
    final options = _programOptions;
    final selected = <String>{..._selectedPrograms};
    await showDialog<void>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: const Row(
            children: [
              Icon(Icons.filter_list_rounded, color: kPrimary, size: 20),
              SizedBox(width: 10),
              Expanded(
                child: Text('Select Programs',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
            ],
          ),
          contentPadding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          content: SizedBox(
            width: 380,
            child: options.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('No programs available.',
                        style: TextStyle(color: kTextSub)),
                  )
                : SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final o in options)
                          CheckboxListTile(
                            value: selected.contains(o),
                            dense: true,
                            controlAffinity: ListTileControlAffinity.leading,
                            activeColor: kPrimary,
                            title:
                                Text(o, style: const TextStyle(fontSize: 13.5)),
                            onChanged: (v) => setDialogState(() {
                              if (v == true) {
                                selected.add(o);
                              } else {
                                selected.remove(o);
                              }
                            }),
                          ),
                      ],
                    ),
                  ),
          ),
          actions: [
            TextButton(
              onPressed: () => setDialogState(selected.clear),
              child: const Text('Clear'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                setState(() {
                  _selectedPrograms
                    ..clear()
                    ..addAll(selected);
                  _applyFilters();
                });
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                foregroundColor: Colors.white,
                elevation: 0,
              ),
              child: const Text('Apply'),
            ),
          ],
        ),
      ),
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

  /// The booklet's white rounded table shell, edge to edge: min width pinned to
  /// the viewport so a short table still fills the page, scrolling sideways
  /// only when the columns genuinely cannot fit.
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

  Widget _detailsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _sectionHeader(
          'Student BMI Details',
          '${_filteredRecords.length} record${_filteredRecords.length == 1 ? '' : 's'} matching the current filter',
          icon: Icons.list_alt_rounded,
        ),
        const SizedBox(height: 10),
        if (_filteredRecords.isEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kBorder),
            ),
            child: const Center(
              child: Text(
                'No students match the current filter.',
                style: TextStyle(color: kTextSub),
              ),
            ),
          )
        else
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
              columns: const [
                DataColumn(label: Text('Student ID')),
                DataColumn(label: Text('Name')),
                DataColumn(label: Text('Program')),
                DataColumn(label: Text('Age')),
                DataColumn(label: Text('Sex')),
                DataColumn(label: Text('Birthdate')),
                DataColumn(label: Text('BMI')),
                DataColumn(label: Text('BMI Indicator')),
              ],
              rows: [
                for (final (i, r) in _filteredRecords.indexed)
                  DataRow(
                    color: WidgetStateProperty.resolveWith((s) {
                      if (s.contains(WidgetState.hovered)) {
                        return kPrimary.withValues(alpha: 0.04);
                      }
                      return i.isEven ? Colors.white : const Color(0xFFFAFCFD);
                    }),
                    cells: [
                      DataCell(Text(r.personId)),
                      DataCell(
                        Text(r.fullName, overflow: TextOverflow.ellipsis),
                      ),
                      DataCell(
                          Text(r.programName.isEmpty ? '—' : r.programName)),
                      DataCell(Text(r.age?.toString() ?? '—')),
                      DataCell(Text(r.sex.isEmpty ? '—' : r.sex)),
                      DataCell(Text(_fmtBirthdate(r.dateOfBirth))),
                      DataCell(
                        Text(
                          r.computedBmi.isFinite
                              ? r.computedBmi.toStringAsFixed(1)
                              : '—',
                        ),
                      ),
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

  // ── PRINT ──────────────────────────────────────────────────────────────

  Future<void> _showPrintDialog() async {
    String paperKey = 'A4';
    bool landscape = true;

    final ({PdfPageFormat format})? result =
        await showDialog<({PdfPageFormat format})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return Dialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
            ),
            backgroundColor: Colors.white,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 400, maxWidth: 400),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Icon(Icons.print_outlined, color: kPrimary, size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Print BMI Records',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: kTextMain,
                          ),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    const Text(
                      'Output includes the institute and program summaries plus the '
                      'detailed student BMI list for the current filter.',
                      style: TextStyle(
                          fontSize: 12.5, color: kTextSub, height: 1.4),
                    ),
                    const SizedBox(height: 14),
                    PaperFormatPicker(
                      paperKey: paperKey,
                      landscape: landscape,
                      onPaper: (key) => setDialogState(() => paperKey = key),
                      onOrientation: (value) =>
                          setDialogState(() => landscape = value),
                    ),
                    const SizedBox(height: 16),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: kBorder),
                            foregroundColor: kTextSub,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(
                            ctx,
                            (
                              format:
                                  PaperFormat.formatFor(paperKey, landscape),
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kPrimary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text(
                            'Review & Print',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
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
    await _showPrintPreview(initialFormat: result.format);
  }

  Future<void> _showPrintPreview({required PdfPageFormat initialFormat}) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
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
          ),
          body: PdfPreview(
            pdfFileName: 'TCGC_BMI_Records.pdf',
            initialPageFormat: initialFormat,
            pageFormats: const <String, PdfPageFormat>{
              'A4': PdfPageFormat.a4,
              'Letter': PdfPageFormat.letter,
              'Legal': PdfPageFormat.legal,
            },
            canChangePageFormat: true,
            canChangeOrientation: true,
            canDebug: false,
            allowSharing: false,
            build: (format) async =>
                (await _buildDocument(pageFormat: format)).save(),
          ),
        ),
      ),
    );
  }

  Future<pw.Document> _buildDocument(
      {required PdfPageFormat pageFormat}) async {
    final doc = pw.Document();
    final records = _filteredRecords;
    final byInstitute = _summarizeByInstitute(records);
    final byProgram = _summarizeByProgram(records);

    final tcgcLogo = await _loadLogo('asset/tcgc.png');
    final clinicLogo = await _loadLogo('asset/cliniclogo.png');
    final isLandscape = pageFormat.width > pageFormat.height;
    final margin = isLandscape
        ? const pw.EdgeInsets.fromLTRB(26, 30, 26, 30)
        : const pw.EdgeInsets.fromLTRB(30, 34, 30, 32);

    doc.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        margin: margin,
        header: (pw.Context context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                tcgcLogo,
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text(
                      'TANGUB CITY GLOBAL COLLEGE',
                      style: pw.TextStyle(
                        fontSize: isLandscape ? 13 : 12,
                        fontWeight: pw.FontWeight.bold,
                        letterSpacing: 0.6,
                      ),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'School Clinic System',
                      style: const pw.TextStyle(
                        fontSize: 10,
                        color: PdfColors.grey700,
                      ),
                    ),
                  ],
                ),
                clinicLogo,
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Divider(color: PdfColors.teal, thickness: 1.2),
            pw.SizedBox(height: 8),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'BMI RECORDS',
                  style: pw.TextStyle(
                    fontSize: 12,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.teal800,
                  ),
                ),
                pw.Text(
                  'Generated ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())} · $_coverageLabel',
                  style: const pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.grey700,
                  ),
                ),
              ],
            ),
            pw.SizedBox(height: 10),
          ],
        ),
        footer: (pw.Context context) => pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Maloro, Tangub City',
              style: pw.TextStyle(
                fontSize: 8,
                fontStyle: pw.FontStyle.italic,
                color: PdfColors.grey600,
              ),
            ),
            pw.Text(
              'Page ${context.pageNumber} of ${context.pagesCount}',
              style: const pw.TextStyle(
                fontSize: 8,
                color: PdfColors.grey600,
              ),
            ),
          ],
        ),
        build: (pw.Context context) => [
          _printSectionTitle('SUMMARY BY INSTITUTE'),
          pw.SizedBox(height: 6),
          _printTable(
            headers: const [
              'Institute',
              'Underweight',
              'Normal',
              'Overweight',
              'Obese',
              'Total'
            ],
            rows: [
              for (final s in byInstitute)
                [
                  s.institute,
                  '${s.underweight}',
                  '${s.normal}',
                  '${s.overweight}',
                  '${s.obese}',
                  '${s.total}',
                ],
            ],
          ),
          pw.SizedBox(height: 16),
          _printSectionTitle('SUMMARY BY PROGRAM'),
          pw.SizedBox(height: 6),
          _printTable(
            headers: const [
              'Institute',
              'Program',
              'Underweight',
              'Normal',
              'Overweight',
              'Obese',
              'Total'
            ],
            rows: [
              for (final s in byProgram)
                [
                  s.institute,
                  s.program,
                  '${s.underweight}',
                  '${s.normal}',
                  '${s.overweight}',
                  '${s.obese}',
                  '${s.total}',
                ],
            ],
          ),
          pw.SizedBox(height: 16),
          _printSectionTitle('STUDENT BMI DETAILS'),
          pw.SizedBox(height: 6),
          _printTable(
            headers: const [
              'Student ID',
              'Name',
              'Age',
              'Sex',
              'Birthdate',
              'Institute',
              'Program',
              'Year Level',
              'Height',
              'Weight',
              'BMI',
              'Indicator',
              'Date',
            ],
            rows: [
              for (final r in records)
                [
                  r.personId,
                  r.fullName,
                  r.age?.toString() ?? '—',
                  r.sex.isEmpty ? '—' : r.sex,
                  _fmtDate(r.dateOfBirth),
                  r.instituteName,
                  r.programName,
                  r.yearLevel.isEmpty ? '—' : r.yearLevel,
                  _fmtNum(r.heightCm),
                  _fmtNum(r.weightKg),
                  r.computedBmi.isFinite
                      ? r.computedBmi.toStringAsFixed(1)
                      : '—',
                  r.indicator,
                  _fmtDate(r.visitDate),
                ],
            ],
          ),
          pw.SizedBox(height: 18),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Prepared by:',
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 24),
                  pw.Container(width: 180, height: 0.6, color: PdfColors.black),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    '(Signature over printed name)',
                    style: pw.TextStyle(
                      fontSize: 8,
                      color: PdfColors.grey600,
                    ),
                  ),
                ],
              ),
              pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.end,
                children: [
                  pw.Text(
                    'Noted by:',
                    style: pw.TextStyle(
                      fontSize: 9,
                      fontWeight: pw.FontWeight.bold,
                    ),
                  ),
                  pw.SizedBox(height: 24),
                  pw.Container(width: 180, height: 0.6, color: PdfColors.black),
                  pw.SizedBox(height: 4),
                  pw.Text(
                    '(Signature)',
                    style: pw.TextStyle(
                      fontSize: 8,
                      color: PdfColors.grey600,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
    return doc;
  }

  pw.Widget _printSectionTitle(String title) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Align(
          alignment: pw.Alignment.centerLeft,
          child: pw.Text(
            title,
            style: pw.TextStyle(
              fontSize: 11,
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.teal800,
            ),
          ),
        ),
        pw.SizedBox(height: 3),
        pw.Divider(color: PdfColors.teal, thickness: 0.6),
      ],
    );
  }

  pw.Widget _printTable({
    required List<String> headers,
    required List<List<String>> rows,
  }) {
    final data =
        rows.isEmpty ? [List<String>.filled(headers.length, '')] : rows;
    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: data,
      headerDecoration: const pw.BoxDecoration(color: PdfColors.teal50),
      headerStyle: pw.TextStyle(
        fontSize: 8.5,
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.teal900,
      ),
      cellStyle: pw.TextStyle(
        fontSize: 8.5,
        lineSpacing: 1.6,
        color: PdfColors.grey900,
      ),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
      border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.4),
    );
  }

  Future<pw.Widget> _loadLogo(String assetPath) async {
    try {
      final bytes = (await rootBundle.load(assetPath)).buffer.asUint8List();
      return pw.Image(
        pw.MemoryImage(bytes),
        width: 42,
        height: 42,
        fit: pw.BoxFit.contain,
      );
    } catch (_) {
      return pw.SizedBox(width: 42, height: 42);
    }
  }
}
