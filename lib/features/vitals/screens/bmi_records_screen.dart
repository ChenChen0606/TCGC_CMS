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
  final String program;
  final int underweight;
  final int normal;
  final int overweight;
  final int obese;
  final int total;

  const BmiSummaryByProgram({
    required this.program,
    required this.underweight,
    required this.normal,
    required this.overweight,
    required this.obese,
    this.total = 0,
  });
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

  bool _isLoading = true;
  List<BmiRecord> _allRecords = [];
  List<BmiRecord> _filteredRecords = [];
  List<BmiSummaryByInstitute> _instituteSummaries = [];
  List<BmiSummaryByProgram> _programSummaries = [];
  List<String> _institutes = [];

  String _selectedInstitute = 'All';
  String _selectedClassification = 'All';

  static const List<String> _dateFilterModes = [
    'All',
    'Today',
    'This Week',
    'This Month',
    'Year',
    'Date Range',
    'Pick Date',
  ];
  String _selectedDateFilter = 'All';
  int? _selectedYear;
  DateTimeRange? _pickedRange;
  DateTime? _pickedDate;

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

  Future<void> _loadRecords() async {
    if (mounted) setState(() => _isLoading = true);

    await ReferenceCatalog.loadQuietly();
    try {
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

      records.removeWhere((r) => r.personType != 'Student');
      setState(() {
        _allRecords = records;
        _buildFilterOptions();
        _applyFilters();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
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

  void _buildFilterOptions() {
    final institutes = <String>{};
    for (final r in _allRecords) {
      if (r.instituteName.isNotEmpty) institutes.add(r.instituteName);
    }

    for (final e in ReferenceCatalog.institutes) {
      if (e.name.isNotEmpty) institutes.add(e.name);
    }
    _institutes = institutes.toList()..sort();
    if (_selectedInstitute != 'All' &&
        !institutes.contains(_selectedInstitute)) {
      _selectedInstitute = 'All';
    }
  }

  void _applyFilters() {
    final q = _searchQuery.trim().toLowerCase();
    final filtered = _allRecords.where((r) {
      if (r.personType != 'Student') return false;
      if (_selectedInstitute != 'All' &&
          r.instituteName != _selectedInstitute) {
        return false;
      }
      if (_selectedClassification != 'All' &&
          r.indicator != _selectedClassification) {
        return false;
      }
      if (!_matchesDateFilter(r.visitDate)) return false;
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

  bool _matchesDateFilter(DateTime? date) {
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
      case 'Year':
        if (date == null) return false;
        return date.year == (_selectedYear ?? DateTime.now().year);
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
      final prog = r.programName.isEmpty ? 'Unknown' : r.programName;
      final summary = groups.putIfAbsent(
        prog,
        () => BmiSummaryByProgram(
          program: prog,
          underweight: 0,
          normal: 0,
          overweight: 0,
          obese: 0,
          total: 0,
        ),
      );

      groups[prog] = BmiSummaryByProgram(
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
    list.sort((a, b) => a.program.compareTo(b.program));
    return list;
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
                  ],
                ),
                const SizedBox(height: 2),
                const Text('Body mass index records for students',
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
      final isNarrow = constraints.maxWidth < 860;
      final search = _searchField();
      final date = _dateFilterControls();
      final indicator = _indicatorFilter();
      if (isNarrow) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            search,
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [date, indicator],
            ),
          ],
        );
      }
      return Row(
        children: [
          Expanded(child: search),
          const SizedBox(width: 14),
          date,
          const SizedBox(width: 10),
          indicator,
        ],
      );
    });
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

  Widget _dateFilterControls() {
    final children = <Widget>[_dateModeDropdown()];
    Widget? extra;
    switch (_selectedDateFilter) {
      case 'Year':
        extra = _yearDropdown();
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
    if (_selectedDateFilter != 'All') {
      children.addAll([
        const SizedBox(width: 6),
        Tooltip(
          message: 'Clear date filter',
          child: InkWell(
            onTap: () => setState(() {
              _selectedDateFilter = 'All';
              _selectedYear = null;
              _pickedRange = null;
              _pickedDate = null;
              _applyFilters();
            }),
            borderRadius: BorderRadius.circular(20),
            child: Container(
              width: 30,
              height: 30,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                shape: BoxShape.circle,
                border: Border.all(color: kBorder),
              ),
              child: const Icon(Icons.close_rounded, size: 15, color: kTextSub),
            ),
          ),
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
        : 'All';
    return Container(
      height: 44,
      padding: const EdgeInsets.only(left: 14, right: 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(
            color: _selectedDateFilter == 'All' ? kBorder : kPrimary),
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
            for (final o in _dateFilterModes)
              DropdownMenuItem(
                value: o,
                child: Text(o == 'All' ? 'Date: All' : o),
              ),
          ],
          onChanged: _onDateModeChanged,
        ),
      ),
    );
  }

  Future<void> _onDateModeChanged(String? v) async {
    if (v == null || v == _selectedDateFilter) return;
    if (v == 'Date Range') {
      final range = await _pickDateRange();
      if (!mounted) return;
      setState(() {
        if (range != null) {
          _selectedDateFilter = 'Date Range';
        } else if (_pickedRange == null) {
          _selectedDateFilter = 'All';
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
          _selectedDateFilter = 'Pick Date';
        } else if (_pickedDate == null) {
          _selectedDateFilter = 'All';
        }
        _applyFilters();
      });
      return;
    }
    setState(() {
      _selectedDateFilter = v;
      if (v == 'Year' && _selectedYear == null) {
        _selectedYear = DateTime.now().year;
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

  List<int> get _availableYears {
    final years = <int>{};
    for (final r in _allRecords) {
      final d = r.visitDate;
      if (d != null) years.add(d.year);
    }
    years.add(DateTime.now().year);
    return years.toList()..sort((a, b) => b.compareTo(a));
  }

  Widget _yearDropdown() {
    final years = _availableYears;
    final safe =
        years.contains(_selectedYear) ? _selectedYear : DateTime.now().year;
    return Container(
      height: 44,
      padding: const EdgeInsets.only(left: 14, right: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kPrimary),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: safe,
          isDense: true,
          borderRadius: BorderRadius.circular(12),
          icon: const Icon(Icons.keyboard_arrow_down_rounded,
              size: 18, color: kTextSub),
          style: const TextStyle(
              fontSize: 12.5, fontWeight: FontWeight.w600, color: kTextMain),
          items: [
            for (final y in years)
              DropdownMenuItem(value: y, child: Text('$y')),
          ],
          onChanged: (v) {
            if (v == null) return;
            setState(() {
              _selectedYear = v;
              _applyFilters();
            });
          },
        ),
      ),
    );
  }

  Widget _dateValueButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 250),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kPrimary),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 17, color: kPrimary),
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
        ),
        const SizedBox(height: 10),
        _summaryTable(
          headers: const [
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
              _buildFilterOptions();
              _applyFilters();
            });
          },
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
                  pagesBuilder: _fitPages,
                ),
              ),
            );
          },
        );
      },
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

  Future<pw.Document> _buildDocument(
      {required PdfPageFormat pageFormat}) async {
    final doc = pw.Document();
    final records = _filteredRecords;
    final byInstitute = _summarizeByInstitute(records);
    final byProgram = _summarizeByProgram(records);

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
          pw.SizedBox(height: 16),
          _printStatStrip(records),
          pw.SizedBox(height: 16),
          _printSectionTitle('SUMMARY BY INSTITUTE'),
          pw.SizedBox(height: 6),
          _printTable(
            headers: const [
              'Institute',
              'Underweight',
              'Normal',
              'Overweight',
              'Obese',
            ],
            rows: [
              for (final s in byInstitute)
                [
                  s.institute,
                  '${s.underweight}',
                  '${s.normal}',
                  '${s.overweight}',
                  '${s.obese}',
                ],
            ],
          ),
          pw.SizedBox(height: 16),
          _printSectionTitle('SUMMARY BY PROGRAM'),
          pw.SizedBox(height: 6),
          _printTable(
            headers: const [
              'Program',
              'Underweight',
              'Normal',
              'Overweight',
              'Obese',
            ],
            rows: [
              for (final s in byProgram)
                [
                  s.program,
                  '${s.underweight}',
                  '${s.normal}',
                  '${s.overweight}',
                  '${s.obese}',
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
              'Program',
              'Year Level',
              'Height',
              'Weight',
              'BMI',
              'Indicator',
            ],
            rows: [
              for (final r in records)
                [
                  r.personId,
                  r.fullName,
                  r.age?.toString() ?? '—',
                  r.sex.isEmpty ? '—' : r.sex,
                  _fmtDate(r.dateOfBirth),
                  r.programName,
                  r.yearLevel.isEmpty ? '—' : r.yearLevel,
                  _fmtNum(r.heightCm),
                  _fmtNum(r.weightKg),
                  r.computedBmi.isFinite
                      ? r.computedBmi.toStringAsFixed(1)
                      : '—',
                  r.indicator,
                ],
            ],
          ),
        ],
      ),
    );
    return doc;
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

  pw.Widget _printStatStrip(List<BmiRecord> records) {
    int count(String c) => records.where((r) => r.indicator == c).length;
    final stats = <({String label, int value, PdfColor tint, PdfColor ink})>[
      (
        label: 'Total Students',
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
    final data =
        rows.isEmpty ? [List<String>.filled(headers.length, '')] : rows;
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
