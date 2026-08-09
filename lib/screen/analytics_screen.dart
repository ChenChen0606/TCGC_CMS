import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:printing/printing.dart';
import 'package:pdf/widgets.dart' as pw;

// ---------------------------------------------------------------------------
// COLORS
// ---------------------------------------------------------------------------
const kTeal = Color(0xFF008080);
const kBg = Color(0xFFF1F5F9);
const kBorder = Color(0xFFE2E8F0);
const kTextMuted = Color(0xFF64748B);
const kTextDark = Color(0xFF1E293B);
const kHeading = Color(0xFF334155);

// ---------------------------------------------------------------------------
// MODELS
// ---------------------------------------------------------------------------
enum ReportType { patients, medicine, visits, full }

class PatientRecord {
  final String id, fullName, type, dept, yearOrPosition;
  const PatientRecord(this.id, this.fullName, this.type, this.dept, this.yearOrPosition);
}

class MedicineRecord {
  final int id;
  final String name;
  final int stock, capacity;
  final String status; // Good, Low, Out
  const MedicineRecord(this.id, this.name, this.stock, this.capacity, this.status);
}

class VisitRecord {
  final String id, fullName, type, complaint, medicine, date, time;
  final int qty;
  const VisitRecord(this.id, this.fullName, this.type, this.complaint, this.medicine, this.qty, this.date, this.time);
}

// ---------------------------------------------------------------------------
// SCREEN
// ---------------------------------------------------------------------------
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  // ---- top-level tab (Insights vs Print Reports) ----
  bool _showInsights = true;

  // ---- Insights tab state ----
  String _selectedView = 'Daily';
  DateTimeRange? _insightsCustomRange; // used only when _selectedView == 'Custom'
  final Map<String, Map<String, double>> _analyticsData = {
    'Daily': {'Students': 18, 'Faculty': 5, 'Staff': 3, 'Total': 26},
    'Weekly': {'Students': 85, 'Faculty': 22, 'Staff': 15, 'Total': 122},
    'Monthly': {'Students': 320, 'Faculty': 64, 'Staff': 42, 'Total': 426},
  };

  // ---- Print Reports tab state ----
  ReportType _selectedReport = ReportType.patients;
  String _dateRange = 'Today';
  DateTimeRange? _customRange;

  final Set<String> _peopleFilters = {'Students', 'Faculty', 'Staff'};
  final Set<String> _medicineFilters = {'Good', 'Low', 'Out of Stock'};

  final String _preparedBy = 'Anna Gonzaga';

  // ---- sample data (swap these for real data sources) ----
  final List<PatientRecord> _patients = const [
    PatientRecord('234567', 'Cresa S. Delacruz', 'Student', 'BSCS', '2nd Year'),
    PatientRecord('234889', 'John A. Doe', 'Student', 'BSIT', '3rd Year'),
    PatientRecord('F001', 'Jane Smith', 'Faculty', 'ICS', 'Dean'),
    PatientRecord('F002', 'Prof. Ramon Garcia', 'Faculty', 'ICS', 'Instructor'),
    PatientRecord('S001', 'Mark Lee', 'Staff', 'Registrar', '—'),
    PatientRecord('S002', 'Rosa Navarro', 'Staff', 'Library', 'Librarian'),
    PatientRecord('235012', 'Maria T. Santos', 'Student', 'BSN', '1st Year'),
  ];

  final List<MedicineRecord> _medicines = const [
    MedicineRecord(1, 'Paracetamol', 148, 200, 'Good'),
    MedicineRecord(2, 'Amoxicillin', 0, 100, 'Out'),
    MedicineRecord(3, 'Biogesic', 12, 150, 'Low'),
    MedicineRecord(4, 'Cetirizine', 85, 100, 'Good'),
    MedicineRecord(5, 'Mefenamic Acid', 5, 50, 'Low'),
    MedicineRecord(6, 'Ascorbic Acid', 190, 200, 'Good'),
  ];

  final List<VisitRecord> _visits = const [
    VisitRecord('234567', 'Cresa Delacruz S.', 'Student', 'Headache and Dizziness', 'Paracetamol', 1, '2026-05-02', '08:15 AM'),
    VisitRecord('234889', 'John A. Doe', 'Student', 'Fever', 'Biogesic', 2, '2026-05-02', '08:40 AM'),
    VisitRecord('F001', 'Jane Smith', 'Faculty', 'Migraine', 'Paracetamol', 2, '2026-05-02', '08:30 AM'),
    VisitRecord('F002', 'Prof. Ramon Garcia', 'Faculty', 'Headache', 'Paracetamol', 1, '2026-05-02', '09:15 AM'),
    VisitRecord('S001', 'Mark Lee', 'Staff', 'Headache', 'Paracetamol', 1, '2026-05-02', '08:00 AM'),
    VisitRecord('S002', 'Rosa Navarro', 'Staff', 'Fever', 'Biogesic', 2, '2026-05-02', '11:50 AM'),
    VisitRecord('235012', 'Maria T. Santos', 'Student', 'Cough', 'Ascorbic Acid', 1, '2026-05-02', '10:05 AM'),
  ];

  // ---------------------------------------------------------------------
  // FILTER HELPERS
  // ---------------------------------------------------------------------
  List<PatientRecord> get _filteredPatients =>
      _patients.where((p) => _peopleFilters.contains(_pluralType(p.type))).toList();

  List<VisitRecord> get _filteredVisits =>
      _visits.where((v) => _peopleFilters.contains(_pluralType(v.type))).toList();

  List<MedicineRecord> get _filteredMedicines =>
      _medicines.where((m) => _medicineFilters.contains(_statusLabel(m.status))).toList();

  String _pluralType(String type) {
    switch (type) {
      case 'Student':
        return 'Students';
      case 'Faculty':
        return 'Faculty';
      case 'Staff':
        return 'Staff';
      default:
        return type;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'Good':
        return 'Good';
      case 'Low':
        return 'Low';
      case 'Out':
        return 'Out of Stock';
      default:
        return status;
    }
  }

  String get _outOfStockCount =>
      _medicines.where((m) => m.status == 'Out').length.toString();

  String get _coverageText {
    switch (_dateRange) {
      case 'This Week':
        return 'This Week';
      case 'This Month':
        return 'This Month';
      case 'Custom':
        if (_customRange != null) {
          return '${_fmtDate(_customRange!.start)} – ${_fmtDate(_customRange!.end)}';
        }
        return 'Custom range';
      default:
        return 'Today, ${_fmtDate(DateTime.now())}';
    }
  }

  String _fmtDate(DateTime d) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[d.month - 1]} ${d.day}, ${d.year}';
  }

  String _fmtGenerated() {
    final now = DateTime.now();
    final hour = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final ampm = now.hour >= 12 ? 'PM' : 'AM';
    final minute = now.minute.toString().padLeft(2, '0');
    return '$hour:$minute $ampm, ${_fmtDate(now)}';
  }

  // ---------------------------------------------------------------------
  // INSIGHTS TAB DATA HELPERS
  // ---------------------------------------------------------------------

  /// Returns the {Students, Faculty, Staff, Total} numbers for whichever
  /// view (Daily / Weekly / Monthly / Custom) is currently selected.
  /// Daily/Weekly/Monthly use the sample analytics map; Custom is computed
  /// live from the visit records so the picker actually does something.
  Map<String, double> get _currentViewData {
    if (_selectedView == 'Custom') {
      if (_insightsCustomRange == null) {
        return {'Students': 0, 'Faculty': 0, 'Staff': 0, 'Total': 0};
      }
      final start = DateTime(_insightsCustomRange!.start.year, _insightsCustomRange!.start.month, _insightsCustomRange!.start.day);
      final end = DateTime(_insightsCustomRange!.end.year, _insightsCustomRange!.end.month, _insightsCustomRange!.end.day, 23, 59, 59);
      final list = _visits.where((v) {
        final d = DateTime.tryParse(v.date);
        return d != null && !d.isBefore(start) && !d.isAfter(end);
      }).toList();
      final students = list.where((v) => v.type == 'Student').length.toDouble();
      final faculty = list.where((v) => v.type == 'Faculty').length.toDouble();
      final staff = list.where((v) => v.type == 'Staff').length.toDouble();
      return {'Students': students, 'Faculty': faculty, 'Staff': staff, 'Total': students + faculty + staff};
    }
    return _analyticsData[_selectedView] ?? _analyticsData['Daily']!;
  }

  /// Label shown under "Clinic Insights" — shows the picked date range
  /// once Custom has been used.
  String get _selectedViewLabel {
    if (_selectedView == 'Custom') {
      if (_insightsCustomRange != null) {
        return '${_fmtDate(_insightsCustomRange!.start)} – ${_fmtDate(_insightsCustomRange!.end)}';
      }
      return 'Custom range — pick dates';
    }
    return _selectedView;
  }

  // ---------------------------------------------------------------------
  // COMPACT (non-fullscreen) date range picker
  // ---------------------------------------------------------------------
  // showDateRangePicker opens fullscreen by default on narrower layouts.
  // Wrapping it in a Dialog + ConstrainedBox via `builder` keeps it as a
  // small centered popup instead, on every screen size.
  Future<DateTimeRange?> _showCompactDateRangePicker({DateTimeRange? initialRange}) {
    return showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: initialRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).colorScheme.copyWith(primary: kTeal),
          ),
          child: Dialog(
            insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
              child: child,
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickInsightsDateRange() async {
    final range = await _showCompactDateRangePicker(initialRange: _insightsCustomRange);
    if (range != null) {
      setState(() {
        _insightsCustomRange = range;
        _selectedView = 'Custom';
      });
    }
  }

  Future<void> _pickDateRange() async {
    final range = await _showCompactDateRangePicker(initialRange: _customRange);
    if (range != null) {
      setState(() {
        _dateRange = 'Custom';
        _customRange = range;
      });
    }
  }

  // ---------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 20),
            _buildMainTabSelector(),
            const SizedBox(height: 20),
            _showInsights ? _buildInsightsTab() : _buildPrintReportsTab(),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // HEADER
  // ---------------------------------------------------------------------
  Widget _buildHeader() {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: kTeal, borderRadius: BorderRadius.circular(10)),
          child: const Icon(Icons.change_history, color: Colors.white, size: 20),
        ),
        const SizedBox(width: 12),
        const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Reports', style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: kTextDark)),
            Text('Insights & printable records for TCGC Clinic', style: TextStyle(color: kTextMuted, fontSize: 13)),
          ],
        ),
      ],
    );
  }

  Widget _buildMainTabSelector() {
    return Row(
      children: [
        _mainTabButton('Insights', Icons.bar_chart, true),
        const SizedBox(width: 10),
        _mainTabButton('Print Reports', Icons.print, false),
      ],
    );
  }

  Widget _mainTabButton(String label, IconData icon, bool isInsightsButton) {
    final bool selected = isInsightsButton ? _showInsights : !_showInsights;
    return GestureDetector(
      onTap: () => setState(() => _showInsights = isInsightsButton),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? kTeal : Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: selected ? kTeal : kBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: selected ? Colors.white : kTextMuted),
            const SizedBox(width: 8),
            Text(label,
                style: TextStyle(
                    color: selected ? Colors.white : kTextMuted,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal)),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------
  // INSIGHTS TAB (dashboard view)
  // ---------------------------------------------------------------------
  Widget _buildInsightsTab() {
    final currentData = _currentViewData;
    final total = currentData['Total'] ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title on the left, Daily/Weekly/Monthly/Custom selector pinned
        // to the right on wide screens; stacks below the title on narrow
        // screens instead of wrapping unpredictably.
        LayoutBuilder(builder: (context, constraints) {
          final isNarrow = constraints.maxWidth < 640;
          final title = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Clinic Insights',
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold, color: kTextDark)),
              Text('Real-time data for $_selectedViewLabel',
                  style: const TextStyle(color: kTextMuted, fontSize: 15)),
            ],
          );
          final selector = _buildViewSelector();
          if (isNarrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [title, const SizedBox(height: 16), selector],
            );
          }
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [Flexible(child: title), selector],
          );
        }),
        const SizedBox(height: 25),

        // Dashboard-style Visitation Summary + Out of Stock alert
        _buildVisitationSummaryCard(currentData),

        const SizedBox(height: 25),
        _sectionCard(
          title: 'Patient Demographic Breakdown',
          subtitle: "Share of consultations by patient type for this period",
          child: Padding(
            padding: const EdgeInsets.only(top: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _barIndicator('Students', currentData['Students']!, currentData['Total']!, kTeal),
                _barIndicator('Faculty', currentData['Faculty']!, currentData['Total']!, const Color(0xFF00C853)),
                _barIndicator('Staff', currentData['Staff']!, currentData['Total']!, const Color(0xFFFF9800)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 25),
        _sectionCard(
          title: 'Detailed Breakdown',
          subtitle: 'Most common complaint per group today',
          child: Padding(
            padding: const EdgeInsets.only(top: 18),
            child: Column(
              children: [
                _breakdownTile('Students', currentData['Students']!.toInt(), total, 'Most common: Fever/Cough',
                    kTeal, Icons.school_outlined),
                _breakdownTile('Faculty', currentData['Faculty']!.toInt(), total, 'Most common: Hypertension',
                    const Color(0xFF00C853), Icons.co_present_outlined),
                _breakdownTile('Staff', currentData['Staff']!.toInt(), total, 'Most common: First Aid',
                    const Color(0xFFFF9800), Icons.badge_outlined),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildViewSelector() {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), border: Border.all(color: kBorder)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: ['Daily', 'Weekly', 'Monthly', 'Custom'].map((view) {
          bool isSelected = _selectedView == view;
          return GestureDetector(
            onTap: () {
              if (view == 'Custom') {
                _pickInsightsDateRange();
              } else {
                setState(() => _selectedView = view);
              }
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
              decoration: BoxDecoration(
                color: isSelected ? kTeal : Colors.white,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(view,
                  style: TextStyle(
                      fontSize: 15,
                      color: isSelected ? Colors.white : kTextMuted,
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.w600)),
            ),
          );
        }).toList(),
      ),
    );
  }

  /// Mirrors the Dashboard's "VISITATION SUMMARY" card (Total Patients,
  /// Students, Faculty, Staff) so the numbers on Reports look and read the
  /// same as the numbers on the main Dashboard. Also surfaces the
  /// Out-of-Stock alert underneath — kept as its own banner since it's a
  /// different kind of information (an inventory warning, not a headcount)
  /// and easy to overlook if it's buried as a small card.
  Widget _buildVisitationSummaryCard(Map<String, double> data) {
    final total = data['Total'] ?? 0;
    final students = data['Students'] ?? 0;
    final faculty = data['Faculty'] ?? 0;
    final staff = data['Staff'] ?? 0;

    final metrics = <Map<String, dynamic>>[
      {'label': 'Total Patients', 'value': total.toInt(), 'color': kTeal, 'icon': Icons.groups_rounded},
      {'label': 'Students', 'value': students.toInt(), 'color': const Color(0xFF2563EB), 'icon': Icons.school_outlined},
      {'label': 'Faculty', 'value': faculty.toInt(), 'color': const Color(0xFFD97706), 'icon': Icons.co_present_outlined},
      {'label': 'Staff / Others', 'value': staff.toInt(), 'color': const Color(0xFF7C3AED), 'icon': Icons.badge_outlined},
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: kBorder, width: 2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('VISITATION SUMMARY',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: kTeal, letterSpacing: 1.2)),
              const SizedBox(height: 22),
              LayoutBuilder(builder: (context, constraints) {
                bool isSmall = constraints.maxWidth < 700;
                return isSmall
                    ? Column(children: _metricWidgets(metrics, true))
                    : Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: _metricWidgets(metrics, false));
              }),
            ],
          ),
        ),
        const SizedBox(height: 20),
        _outOfStockBanner(),
      ],
    );
  }

  List<Widget> _metricWidgets(List<Map<String, dynamic>> metrics, bool isMobile) {
    return List.generate(metrics.length, (i) {
      final m = metrics[i];
      return Padding(
        padding: EdgeInsets.symmetric(vertical: isMobile ? 14 : 0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: (m['color'] as Color).withOpacity(0.10), borderRadius: BorderRadius.circular(14)),
              child: Icon(m['icon'] as IconData, color: m['color'] as Color, size: 30),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${m['value']}', style: const TextStyle(fontSize: 30, fontWeight: FontWeight.w900, color: kTextDark)),
                Text(m['label'] as String, style: const TextStyle(fontSize: 15, color: kTextMuted, fontWeight: FontWeight.w600)),
              ],
            ),
            if (!isMobile && metrics.last != m)
              Padding(
                padding: const EdgeInsets.only(left: 30),
                child: Container(width: 1.5, height: 48, color: kBorder),
              ),
          ],
        ),
      );
    });
  }

  Widget _outOfStockBanner() {
    final count = int.tryParse(_outOfStockCount) ?? 0;
    final bool hasIssue = count > 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: hasIssue ? const Color(0xFFFCE8E8) : const Color(0xFFE8F5E9),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: hasIssue ? const Color(0xFFF3B4B4) : const Color(0xFFA8D8AC), width: 1.5),
      ),
      child: Row(
        children: [
          Icon(hasIssue ? Icons.warning_amber_rounded : Icons.check_circle_outline,
              color: hasIssue ? const Color(0xFFD32F2F) : const Color(0xFF2E7D32), size: 30),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              hasIssue
                  ? '$count medicine${count > 1 ? 's' : ''} out of stock — please review inventory'
                  : 'All medicines are sufficiently stocked',
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: hasIssue ? const Color(0xFFB91C1C) : const Color(0xFF1B5E20)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _barIndicator(String label, double value, double total, Color color) {
    double percentage = total == 0 ? 0 : (value / total);
    return Column(
      children: [
        Text('${(percentage * 100).toStringAsFixed(1)}%',
            style: TextStyle(fontWeight: FontWeight.bold, color: color, fontSize: 16)),
        const SizedBox(height: 10),
        AnimatedContainer(
          duration: const Duration(milliseconds: 800),
          width: 50,
          height: 150 * percentage + 20,
          decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)),
        ),
        const SizedBox(height: 12),
        Text(label, style: const TextStyle(fontWeight: FontWeight.w700, color: kTextMuted, fontSize: 15)),
      ],
    );
  }

  /// Redesigned breakdown row: icon chip, count + "cases", a percentage
  /// progress bar against the period total, and the "most common"
  /// complaint tag — instead of a flat colored bar with just a number.
  Widget _breakdownTile(String title, int count, double total, String subtitle, Color color, IconData icon) {
    final double pct = total <= 0 ? 0 : (count / total).clamp(0, 1);
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
                child: Icon(icon, color: color, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: kTextDark)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: const TextStyle(fontSize: 13, color: Color(0xFF94A3B8))),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('$count', style: TextStyle(fontWeight: FontWeight.w900, color: color, fontSize: 22)),
                  const Text('cases', style: TextStyle(fontSize: 11, color: kTextMuted)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: LinearProgressIndicator(
              value: pct.toDouble(),
              minHeight: 8,
              backgroundColor: kBorder,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
          const SizedBox(height: 6),
          Text('${(pct * 100).toStringAsFixed(1)}% of total visits this period',
              style: const TextStyle(fontSize: 11, color: kTextMuted, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _sectionCard({required String title, required String subtitle, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(25),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: kBorder)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: kHeading)),
          Text(subtitle, style: const TextStyle(fontSize: 14, color: kTextMuted)),
          child,
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // PRINT REPORTS TAB
  // ---------------------------------------------------------------------
  Widget _buildPrintReportsTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ---- record type picker ----
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: kBorder)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('What do you want to print?', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: kTextDark)),
              const Text('Pick a record type below, set the coverage, then preview and print',
                  style: TextStyle(color: kTextMuted, fontSize: 12)),
              const SizedBox(height: 16),
              Row(
                children: [
                  _recordTypeCard(
                    type: ReportType.patients,
                    icon: Icons.pie_chart,
                    iconColor: const Color(0xFF2563EB),
                    iconBg: const Color(0xFFDBEAFE),
                    title: 'Patient Information',
                    subtitle: 'Full list of registered students, faculty, and staff on file.',
                    badge: '${_patients.length} records',
                  ),
                  const SizedBox(width: 16),
                  _recordTypeCard(
                    type: ReportType.medicine,
                    icon: Icons.description,
                    iconColor: const Color(0xFFEA580C),
                    iconBg: const Color(0xFFFFEDD5),
                    title: 'Medicine Inventory',
                    subtitle: 'Current stock levels, capacity, and status per item.',
                    badge: '${_medicines.length} items',
                  ),
                  const SizedBox(width: 16),
                  _recordTypeCard(
                    type: ReportType.visits,
                    icon: Icons.add,
                    iconColor: const Color(0xFF16A34A),
                    iconBg: const Color(0xFFDCFCE7),
                    title: 'Medical / Visit Records',
                    subtitle: 'Consultation log — who visited, complaint, and medicine given.',
                    badge: '${_visits.length} visits',
                  ),
                  const SizedBox(width: 16),
                  _recordTypeCard(
                    type: ReportType.full,
                    icon: Icons.bar_chart,
                    iconColor: kTeal,
                    iconBg: const Color(0xFFE0F2F1),
                    title: 'Full Clinic Report',
                    subtitle: 'Combined summary: insights + patients + inventory + visits.',
                    badge: 'All sections',
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),

        // ---- filters + preview ----
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20), border: Border.all(color: kBorder)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildFilterBar(),
              const SizedBox(height: 20),
              _buildReportMeta(),
              const Divider(height: 30),
              _buildReportTable(),
              const SizedBox(height: 20),
              _buildActionButtons(),
            ],
          ),
        ),
      ],
    );
  }

  Widget _recordTypeCard({
    required ReportType type,
    required IconData icon,
    required Color iconColor,
    required Color iconBg,
    required String title,
    required String subtitle,
    required String badge,
  }) {
    final bool selected = _selectedReport == type;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _selectedReport = type),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: selected ? kTeal : kBorder, width: selected ? 2 : 1),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(color: iconBg, borderRadius: BorderRadius.circular(8)),
                child: Icon(icon, color: iconColor, size: 18),
              ),
              const SizedBox(height: 10),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: kTextDark)),
              const SizedBox(height: 4),
              Text(subtitle, style: const TextStyle(fontSize: 11, color: kTextMuted), maxLines: 3),
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(6)),
                child: Text(badge, style: const TextStyle(fontSize: 10, color: kTextMuted, fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFilterBar() {
    return Wrap(
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 10,
      runSpacing: 10,
      children: [
        _dateChip('Today'),
        _dateChip('This Week'),
        _dateChip('This Month'),
        _dateChip('Custom'),
        OutlinedButton.icon(
          onPressed: _pickDateRange,
          icon: const Icon(Icons.calendar_today, size: 14),
          label: const Text('Pick Date Range'),
          style: OutlinedButton.styleFrom(foregroundColor: kTextDark, side: const BorderSide(color: kBorder)),
        ),
        const SizedBox(width: 20),
        if (_selectedReport == ReportType.medicine) ...[
          _filterCheckbox('Good', _medicineFilters),
          _filterCheckbox('Low', _medicineFilters),
          _filterCheckbox('Out of Stock', _medicineFilters),
        ] else ...[
          _filterCheckbox('Students', _peopleFilters),
          _filterCheckbox('Faculty', _peopleFilters),
          _filterCheckbox('Staff', _peopleFilters),
        ],
      ],
    );
  }

  Widget _dateChip(String label) {
    final bool selected = _dateRange == label;
    return GestureDetector(
      onTap: () {
        if (label == 'Custom') {
          _pickDateRange();
        } else {
          setState(() => _dateRange = label);
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? kTeal : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? kTeal : kBorder),
        ),
        child: Text(label,
            style: TextStyle(color: selected ? Colors.white : kTextDark, fontWeight: selected ? FontWeight.bold : FontWeight.normal, fontSize: 13)),
      ),
    );
  }

  Widget _filterCheckbox(String label, Set<String> filterSet) {
    final bool checked = filterSet.contains(label);
    return GestureDetector(
      onTap: () => setState(() {
        if (checked) {
          filterSet.remove(label);
        } else {
          filterSet.add(label);
        }
      }),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Checkbox(
            value: checked,
            activeColor: kTeal,
            onChanged: (v) => setState(() {
              if (v == true) {
                filterSet.add(label);
              } else {
                filterSet.remove(label);
              }
            }),
          ),
          Text(label, style: const TextStyle(fontSize: 13, color: kTextDark)),
        ],
      ),
    );
  }

  String get _reportTitle {
    switch (_selectedReport) {
      case ReportType.patients:
        return 'Patient Information Report';
      case ReportType.medicine:
        return 'Medicine Inventory Report';
      case ReportType.visits:
        return 'Medical / Visit Records Report';
      case ReportType.full:
        return 'Full Clinic Report';
    }
  }

  Widget _buildReportMeta() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(_reportTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 19, color: kTextDark)),
            Text('TCGC Clinic Management · Coverage: $_coverageText', style: const TextStyle(fontSize: 13, color: kTextMuted)),
          ],
        ),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text('Prepared by: $_preparedBy', style: const TextStyle(fontSize: 13, color: kTextMuted)),
            Text('Generated: ${_fmtGenerated()}', style: const TextStyle(fontSize: 13, color: kTextMuted)),
          ],
        ),
      ],
    );
  }

  Widget _buildReportTable() {
    switch (_selectedReport) {
      case ReportType.patients:
        return _patientTable(_filteredPatients);
      case ReportType.medicine:
        return _medicineTable(_filteredMedicines);
      case ReportType.visits:
        return _visitTable(_filteredVisits);
      case ReportType.full:
        return _fullReportBody();
    }
  }

  // ---- table builders (font sizes bumped up for readability — elder-friendly) ----
  Widget _tableHeaderRow(List<String> columns, List<int> flexes) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: kBorder, width: 1.5))),
      child: Row(
        children: List.generate(columns.length, (i) {
          return Expanded(
            flex: flexes[i],
            child: Text(columns[i].toUpperCase(),
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: kTextMuted, letterSpacing: 0.3)),
          );
        }),
      ),
    );
  }

  Widget _tableDataRow(List<Widget> cells, List<int> flexes) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Color(0xFFF1F5F9)))),
      child: Row(
        children: List.generate(cells.length, (i) => Expanded(flex: flexes[i], child: cells[i])),
      ),
    );
  }

  Widget _typeBadge(String type) {
    Color bg, fg;
    switch (type) {
      case 'Student':
        bg = const Color(0xFFDBEAFE);
        fg = const Color(0xFF1D4ED8);
        break;
      case 'Faculty':
        bg = const Color(0xFFEDE9FE);
        fg = const Color(0xFF6D28D9);
        break;
      default:
        bg = const Color(0xFFDCFCE7);
        fg = const Color(0xFF15803D);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(type, style: TextStyle(color: fg, fontSize: 14, fontWeight: FontWeight.bold)),
    );
  }

  Widget _statusBadge(String status) {
    Color bg, fg;
    String label;
    switch (status) {
      case 'Good':
        bg = const Color(0xFFDCFCE7);
        fg = const Color(0xFF15803D);
        label = 'Good';
        break;
      case 'Low':
        bg = const Color(0xFFFEF3C7);
        fg = const Color(0xFFB45309);
        label = 'Low';
        break;
      default:
        bg = const Color(0xFFFEE2E2);
        fg = const Color(0xFFB91C1C);
        label = 'Out';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(label, style: TextStyle(color: fg, fontSize: 14, fontWeight: FontWeight.bold)),
    );
  }

  Widget _patientTable(List<PatientRecord> data) {
    final flexes = [2, 3, 2, 2, 2];
    return Column(
      children: [
        _tableHeaderRow(['ID', 'Full Name', 'Type', 'Dept / Office', 'Year / Position'], flexes),
        ...data.map((p) => _tableDataRow([
              Text(p.id, style: const TextStyle(fontSize: 16, color: kTextDark)),
              Text(p.fullName, style: const TextStyle(fontSize: 16, color: kTextDark, fontWeight: FontWeight.w600)),
              _typeBadge(p.type),
              Text(p.dept, style: const TextStyle(fontSize: 16, color: kTextDark)),
              Text(p.yearOrPosition, style: const TextStyle(fontSize: 16, color: kTextDark)),
            ], flexes)),
      ],
    );
  }

  Widget _medicineTable(List<MedicineRecord> data) {
    final flexes = [1, 3, 2, 2, 2];
    return Column(
      children: [
        _tableHeaderRow(['ID', 'Medicine', 'Stock', 'Capacity', 'Status'], flexes),
        ...data.map((m) => _tableDataRow([
              Text('${m.id}', style: const TextStyle(fontSize: 16, color: kTextDark)),
              Text(m.name, style: const TextStyle(fontSize: 16, color: kTextDark, fontWeight: FontWeight.w600)),
              Text('${m.stock}', style: const TextStyle(fontSize: 16, color: kTextDark)),
              Text('${m.stock} / ${m.capacity}', style: const TextStyle(fontSize: 16, color: kTextDark)),
              _statusBadge(m.status),
            ], flexes)),
      ],
    );
  }

  Widget _visitTable(List<VisitRecord> data) {
    final flexes = [2, 3, 2, 3, 2, 1, 2];
    return Column(
      children: [
        _tableHeaderRow(['ID', 'Full Name', 'Type', 'Complaint', 'Medicine', 'Qty', 'Date · Time'], flexes),
        ...data.map((v) => _tableDataRow([
              Text(v.id, style: const TextStyle(fontSize: 16, color: kTextDark)),
              Text(v.fullName, style: const TextStyle(fontSize: 16, color: kTextDark, fontWeight: FontWeight.w600)),
              _typeBadge(v.type),
              Text(v.complaint, style: const TextStyle(fontSize: 16, color: kTextDark)),
              Text(v.medicine, style: const TextStyle(fontSize: 16, color: kTextDark)),
              Text('${v.qty}', style: const TextStyle(fontSize: 16, color: kTextDark)),
              Text('${v.date}\n${v.time}', style: const TextStyle(fontSize: 14, color: kTextMuted)),
            ], flexes)),
      ],
    );
  }

  Widget _fullReportBody() {
    final patients = _filteredPatients;
    final medicines = _filteredMedicines;
    final visits = _filteredVisits;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('1. CONSULTATION SUMMARY', style: TextStyle(fontWeight: FontWeight.bold, color: kTeal, fontSize: 15)),
        const SizedBox(height: 12),
        _buildVisitationSummaryCard(_analyticsData['Daily']!),
        const SizedBox(height: 24),
        Text('2. PATIENT INFORMATION (${patients.length} RECORDS)', style: const TextStyle(fontWeight: FontWeight.bold, color: kTeal, fontSize: 15)),
        const SizedBox(height: 10),
        _patientTable(patients),
        const SizedBox(height: 24),
        Text('3. MEDICINE INVENTORY (${medicines.length} ITEMS)', style: const TextStyle(fontWeight: FontWeight.bold, color: kTeal, fontSize: 15)),
        const SizedBox(height: 10),
        _medicineTable(medicines),
        const SizedBox(height: 24),
        Text('4. MEDICAL / VISIT RECORDS (${visits.length} VISITS)', style: const TextStyle(fontWeight: FontWeight.bold, color: kTeal, fontSize: 15)),
        const SizedBox(height: 10),
        _visitTable(visits),
        const SizedBox(height: 16),
        const Text(
          'Full report continues across additional pages when printed — each section starts on its own page automatically.',
          style: TextStyle(fontSize: 13, color: kTextMuted, fontStyle: FontStyle.italic),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------
  // ACTION BUTTONS: CSV / PDF / PRINT
  // ---------------------------------------------------------------------
  Widget _buildActionButtons() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        OutlinedButton.icon(
          onPressed: _exportCsv,
          icon: const Icon(Icons.file_download_outlined, size: 16),
          label: const Text('Export as CSV'),
          style: OutlinedButton.styleFrom(foregroundColor: kTextDark, side: const BorderSide(color: kBorder)),
        ),
        const SizedBox(width: 12),
        OutlinedButton.icon(
          onPressed: _printReport,
          icon: const Icon(Icons.file_download_outlined, size: 16),
          label: const Text('Export as PDF'),
          style: OutlinedButton.styleFrom(foregroundColor: kTextDark, side: const BorderSide(color: kBorder)),
        ),
        const SizedBox(width: 12),
        ElevatedButton.icon(
          onPressed: _printReport,
          icon: const Icon(Icons.print, size: 16, color: Colors.white),
          label: const Text('Print Report'),
          style: ElevatedButton.styleFrom(backgroundColor: kTeal, foregroundColor: Colors.white),
        ),
      ],
    );
  }

  String _buildCsv() {
    final buffer = StringBuffer();
    switch (_selectedReport) {
      case ReportType.patients:
        buffer.writeln('ID,Full Name,Type,Dept/Office,Year/Position');
        for (final p in _filteredPatients) {
          buffer.writeln('${p.id},${p.fullName},${p.type},${p.dept},${p.yearOrPosition}');
        }
        break;
      case ReportType.medicine:
        buffer.writeln('ID,Medicine,Stock,Capacity,Status');
        for (final m in _filteredMedicines) {
          buffer.writeln('${m.id},${m.name},${m.stock},${m.capacity},${m.status}');
        }
        break;
      case ReportType.visits:
        buffer.writeln('ID,Full Name,Type,Complaint,Medicine,Qty,Date,Time');
        for (final v in _filteredVisits) {
          buffer.writeln('${v.id},${v.fullName},${v.type},${v.complaint},${v.medicine},${v.qty},${v.date},${v.time}');
        }
        break;
      case ReportType.full:
        buffer.writeln('-- Patient Information --');
        buffer.writeln('ID,Full Name,Type,Dept/Office,Year/Position');
        for (final p in _filteredPatients) {
          buffer.writeln('${p.id},${p.fullName},${p.type},${p.dept},${p.yearOrPosition}');
        }
        buffer.writeln();
        buffer.writeln('-- Medicine Inventory --');
        buffer.writeln('ID,Medicine,Stock,Capacity,Status');
        for (final m in _filteredMedicines) {
          buffer.writeln('${m.id},${m.name},${m.stock},${m.capacity},${m.status}');
        }
        buffer.writeln();
        buffer.writeln('-- Medical / Visit Records --');
        buffer.writeln('ID,Full Name,Type,Complaint,Medicine,Qty,Date,Time');
        for (final v in _filteredVisits) {
          buffer.writeln('${v.id},${v.fullName},${v.type},${v.complaint},${v.medicine},${v.qty},${v.date},${v.time}');
        }
        break;
    }
    return buffer.toString();
  }

  Future<void> _exportCsv() async {
    final csv = _buildCsv();
    // NOTE: for an actual file download add `share_plus` + `path_provider`
    // to pubspec.yaml and write `csv` to a temp file, then share it.
    await Clipboard.setData(ClipboardData(text: csv));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('CSV data copied to clipboard')),
      );
    }
  }

  Future<void> _printReport() async {
    final doc = pw.Document();

    switch (_selectedReport) {
      case ReportType.patients:
        doc.addPage(_pdfPage('Patient Information Report', _pdfPatientTable(_filteredPatients)));
        break;
      case ReportType.medicine:
        doc.addPage(_pdfPage('Medicine Inventory Report', _pdfMedicineTable(_filteredMedicines)));
        break;
      case ReportType.visits:
        doc.addPage(_pdfPage('Medical / Visit Records Report', _pdfVisitTable(_filteredVisits)));
        break;
      case ReportType.full:
        doc.addPage(_pdfPage('Patient Information', _pdfPatientTable(_filteredPatients)));
        doc.addPage(_pdfPage('Medicine Inventory', _pdfMedicineTable(_filteredMedicines)));
        doc.addPage(_pdfPage('Medical / Visit Records', _pdfVisitTable(_filteredVisits)));
        break;
    }

    await Printing.layoutPdf(onLayout: (format) => doc.save());
  }

  pw.Page _pdfPage(String heading, pw.Widget table) {
    return pw.Page(
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text('TCGC Clinic — $heading', style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 6),
          pw.Text('Coverage: $_coverageText   ·   Prepared by: $_preparedBy', style: const pw.TextStyle(fontSize: 13)),
          pw.Text('Generated: ${_fmtGenerated()}', style: const pw.TextStyle(fontSize: 13)),
          pw.Divider(),
          pw.SizedBox(height: 10),
          table,
        ],
      ),
    );
  }

  pw.Widget _pdfPatientTable(List<PatientRecord> data) {
    return pw.TableHelper.fromTextArray(
      headers: ['ID', 'Full Name', 'Type', 'Dept/Office', 'Year/Position'],
      data: data.map((p) => [p.id, p.fullName, p.type, p.dept, p.yearOrPosition]).toList(),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
      cellStyle: const pw.TextStyle(fontSize: 12),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8),
    );
  }

  pw.Widget _pdfMedicineTable(List<MedicineRecord> data) {
    return pw.TableHelper.fromTextArray(
      headers: ['ID', 'Medicine', 'Stock', 'Capacity', 'Status'],
      data: data.map((m) => ['${m.id}', m.name, '${m.stock}', '${m.stock}/${m.capacity}', m.status]).toList(),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
      cellStyle: const pw.TextStyle(fontSize: 12),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8),
    );
  }

  pw.Widget _pdfVisitTable(List<VisitRecord> data) {
    return pw.TableHelper.fromTextArray(
      headers: ['ID', 'Full Name', 'Type', 'Complaint', 'Medicine', 'Qty', 'Date', 'Time'],
      data: data.map((v) => [v.id, v.fullName, v.type, v.complaint, v.medicine, '${v.qty}', v.date, v.time]).toList(),
      headerStyle: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 12),
      cellStyle: const pw.TextStyle(fontSize: 12),
      cellPadding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 8),
    );
  }
}