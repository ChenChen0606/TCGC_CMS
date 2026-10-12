import 'package:flutter/material.dart';
import '../services/data_tracker.dart';
import '../services/medicine_service.dart';
import '../services/visit_service.dart';
import 'app_colors.dart';

// ---------------------------------------------------------------------------
// COLORS (single source of truth: app_colors.dart)
// ---------------------------------------------------------------------------
const kTeal = AppColors.primary;
const kBg = AppColors.bg;
const kBorder = AppColors.border;
const kTextMuted = AppColors.textSub;
const kTextDark = AppColors.textDark;

// ---------------------------------------------------------------------------
// SCREEN
//
// Reports is a read-only projection of what the clinic's system actually
// records. Every number below comes from a table the app writes to:
//
//   * `clinic_visits`, joined to the person who made it (`individual_records`),
//     their affiliation (`individual_academic_records`) and the services done
//     (`clinic_visit_services` -> `service_types`) — the same joined read the
//     Overview uses, so both screens say the same thing about the same visit.
//   * `medicines`, for the inventory alert.
//
// There is deliberately no Procedure Summary and no Dispensed Medicines card:
// the live database has no `procedures` table (reads 404) and `clinic_visits`
// stores no medicine, so both would render as permanent empty boxes. The work
// those cards were reaching for is carried by the services data instead.
// ---------------------------------------------------------------------------
class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen> {
  // ---- period selector ----
  String _selectedView = 'Daily';
  DateTimeRange?
      _insightsCustomRange; // used only when _selectedView == 'Custom'

  // ---- live inventory (fetched from Supabase) ----
  List<Medicine> _medicines = [];

  // ---- live visits, joined to person + affiliation + services ----
  List<DashboardVisit> _visits = [];
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
      final visits = await VisitService.fetchDashboardVisits();
      if (!mounted) return;
      setState(() {
        _visits = visits;
        _loadingVisits = false;
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

  // ---------------------------------------------------------------------
  // PERIOD HELPERS
  // ---------------------------------------------------------------------

  /// Returns the inclusive date window backing a given view.
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

  /// Label shown under the summary heading — shows the picked date range
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

  /// Visits whose date falls inside the currently selected view window.
  List<DashboardVisit> _visitsInRange() {
    final range = _rangeFor(_selectedView);
    if (range == null) return const [];
    return _visits.where((v) {
      final d = v.visitDate;
      return d != null && !d.isBefore(range.start) && !d.isAfter(range.end);
    }).toList();
  }

  // ---------------------------------------------------------------------
  // INSIGHTS DATA HELPERS
  // ---------------------------------------------------------------------

  /// The {Students, Faculty, Staff, Total} numbers for the selected period.
  ///
  /// The category is read from the person (`person_type`), not from the visit:
  /// `clinic_visits` has no category column, which is why the split used to
  /// read zero while the total was right.
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

  /// Reasons for visit ranked by how often they appear in the period, most
  /// frequent first.
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

  /// Services performed in the period, ranked by how many visits used each.
  /// These are the real `clinic_visit_services` rows joined to `service_types`.
  List<MapEntry<String, int>> _topServices({int limit = 5}) {
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
    return sorted.take(limit).toList();
  }

  /// Consultations by the visitor's institute, ranked by count.
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

  /// The single most common reason for a given patient group in the period,
  /// or '' when the group has no logged visits.
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

  /// Visitors who show up more than once in the period — a quick flag for
  /// recurring/chronic cases.
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

  /// The window immediately before the selected one, of the same length, so the
  /// summary can say whether this period is up or down. Null when the view has
  /// no definable predecessor (Custom with no dates picked).
  DateTimeRange? _previousRangeFor(String view) {
    final range = _rangeFor(view);
    if (range == null) return null;
    final days = range.duration.inDays + 1;
    final prevEnd = range.start.subtract(const Duration(days: 1));
    final prevStart = prevEnd.subtract(Duration(days: days - 1));
    return DateTimeRange(start: prevStart, end: prevEnd);
  }

  /// Visits in the equivalent window before the selected one.
  int get _previousTotalVisits {
    final range = _previousRangeFor(_selectedView);
    if (range == null) return 0;
    return _visits.where((v) {
      final d = v.visitDate;
      return d != null && !d.isBefore(range.start) && !d.isAfter(range.end);
    }).length;
  }

  // ---------------------------------------------------------------------
  // COMPACT (non-fullscreen) date range picker
  // ---------------------------------------------------------------------
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

  // ---------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------
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

  // ---------------------------------------------------------------------
  // HEADER — title block only, matching the BMI Records / Records Booklet
  // header so the three pages read the same.
  // ---------------------------------------------------------------------
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

  // ---------------------------------------------------------------------
  // VISITATION SUMMARY (filtered) + out-of-stock alert
  // ---------------------------------------------------------------------
  Widget _buildVisitationSummaryCard() {
    final data = _currentViewData;

    final metrics = <Map<String, dynamic>>[
      {
        'label': 'Total Visits',
        'value': (data['Total'] ?? 0).toInt(),
        'color': kTeal,
        'icon': Icons.groups_rounded,
        'delta': (data['Total'] ?? 0).toInt() - _previousTotalVisits,
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
                final isNarrow = constraints.maxWidth < 640;
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
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('VISITATION SUMMARY',
                            style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: kTeal,
                                letterSpacing: 1.1)),
                        Text('Real-time data for $_selectedViewLabel',
                            style: const TextStyle(
                                fontSize: 12, color: kTextMuted)),
                      ],
                    ),
                  ],
                );
                final selector = _buildViewSelector();
                if (isNarrow) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      title,
                      const SizedBox(height: 12),
                      selector,
                    ],
                  );
                }
                return Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [title, selector],
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

  /// A tiny up/down pill comparing this period's total against the one before.
  /// Flat reads "no change" rather than an arrow, so a quiet period is not
  /// dressed up as a movement.
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
                  ? '$count medicine${count > 1 ? 's' : ''} out of stock — please review inventory'
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
        children: ['Daily', 'Weekly', 'Monthly', 'Custom'].map((view) {
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
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
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

  // ---------------------------------------------------------------------
  // PATIENT BREAKDOWN
  // ---------------------------------------------------------------------
  Widget _buildDemographicCard() {
    final currentData = _currentViewData;
    final total = currentData['Total'] ?? 0;

    return _sectionCard(
      icon: Icons.donut_large_rounded,
      title: 'Patient Breakdown',
      subtitle: 'Share of consultations by patient type for this period',
      child: Column(
        children: [
          _breakdownTile(
              'Students',
              currentData['Students']!.toInt(),
              total,
              _mostCommonReasonFor('Student'),
              AppColors.student,
              Icons.school_outlined),
          _breakdownTile(
              'Faculty',
              currentData['Faculty']!.toInt(),
              total,
              _mostCommonReasonFor('Faculty'),
              AppColors.faculty,
              Icons.co_present_outlined),
          _breakdownTile(
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

  /// One group's row: icon chip, count, a percentage progress bar against the
  /// period total, and the group's most common reason for visiting.
  Widget _breakdownTile(String title, int count, double total,
      String mostCommon, Color color, IconData icon) {
    final double pct = total <= 0 ? 0 : (count / total).clamp(0, 1);
    final String subtitle = mostCommon.isEmpty
        ? 'No visits logged for this group'
        : 'Most common: $mostCommon';
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder),
      ),
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
                            fontSize: 12, color: AppColors.textMuted)),
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
                      style: TextStyle(fontSize: 11, color: kTextMuted)),
                ],
              ),
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
          Text('${(pct * 100).toStringAsFixed(1)}% of total visits this period',
              style: const TextStyle(
                  fontSize: 11,
                  color: kTextMuted,
                  fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------
  // SERVICES & REASONS (one card) / PEAK HOURS
  // ---------------------------------------------------------------------
  //
  // Services and reasons used to be two cards side by side. They read as one
  // idea — "what brought people in and what was done" — and the lists are short,
  // so they now share a single card with a heading over each column instead of
  // two half-empty boxes.
  Widget _servicesReasonsCard() {
    final services = _topServices();
    final reasons = _topReasons();
    return _sectionCard(
      icon: Icons.summarize_outlined,
      title: 'Services & Reasons for Visit',
      subtitle: 'What was done and what was logged this period',
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

  /// A column inside the combined card: a small colour-coded heading over a
  /// ranked list.
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

  /// Medicines that are out of stock or close to it, most critical first.
  ///
  /// "Low" is relative to the shelf's own capacity when it is known — a 5 of
  /// 500 item and a 5 of 10 item are not equally urgent — and falls back to a
  /// flat threshold when `max_capacity` was never set.
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

  // ---------------------------------------------------------------------
  // INSTITUTES / FREQUENT VISITORS
  // ---------------------------------------------------------------------
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
      subtitle: 'Patients with 2 or more visits on file',
      child: _frequentVisitorsList(),
    );
  }

  // ---------------------------------------------------------------------
  // SHARED WIDGETS
  // ---------------------------------------------------------------------

  /// Two cards side by side on wide screens, stacked on narrow ones.
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

  /// Simple ranked list: a numbered row with a proportional bar against the
  /// highest value in the list.
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

/// A thin progress line shown while the visit read is in flight.
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
