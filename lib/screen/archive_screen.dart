import 'package:flutter/material.dart';
import 'app_colors.dart';

// ── COLORS (single source of truth: app_colors.dart) ────────────────────────
const Color kPrimary = AppColors.primary;
const Color kPrimaryDk = AppColors.primaryDark;
const Color kCard = AppColors.surface;
const Color kBorder = AppColors.border;
const Color kTextMain = AppColors.textMain;
const Color kTextSub = AppColors.textSub;
const Color kDanger = AppColors.danger;

// ─────────────────────────────────────────────────────────────────────────────
//  ArchiveScreen — presentation only.
//
//  This page is a UI prototype: every row comes from the sample data declared
//  below, and Restore / Delete just mutate that list plus show a confirmation.
//  Nothing here touches Supabase. It follows the same layout language as the
//  Individual Record and Records Booklet pages (header, segmented tabs,
//  DataTable chrome, row-click detail dialog) so it reads as part of the same
//  app.
// ─────────────────────────────────────────────────────────────────────────────

class ArchiveScreen extends StatefulWidget {
  /// True while the Archive tab is the active dashboard page. Kept so the
  /// dashboard's `IndexedStack` contract is unchanged.
  final bool isActive;

  const ArchiveScreen({super.key, this.isActive = false});

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

// ── SAMPLE MODELS ────────────────────────────────────────────────────────────

class _ArchivedPerson {
  final String id;
  final String name;
  final String category; // Student / Faculty / Staff
  final String archivedDate;
  final String reason;
  final String archivedBy;
  final String academicYear;
  final String semester;

  // personal
  final String sex;
  final String birthDate;
  final String contact;
  final String email;
  final String address;

  // affiliation — only the ones that apply to the category are filled
  final String institute;
  final String program;
  final String yearLevel;
  final String department;
  final String position;

  const _ArchivedPerson({
    required this.id,
    required this.name,
    required this.category,
    required this.archivedDate,
    required this.reason,
    required this.archivedBy,
    required this.academicYear,
    required this.semester,
    this.sex = '',
    this.birthDate = '',
    this.contact = '',
    this.email = '',
    this.address = '',
    this.institute = '',
    this.program = '',
    this.yearLevel = '',
    this.department = '',
    this.position = '',
  });

  bool get isStudent => category == 'Student';
  bool get isFaculty => category == 'Faculty';

  /// The "institute · program" (student), "institute · position" (faculty) or
  /// "department · position" (staff) line shown under the name.
  String get affiliationLabel {
    if (isStudent) return '$institute · $program';
    if (isFaculty) return '$institute · $position';
    return '$department · $position';
  }
}

class _ArchivedMedicine {
  final String name;
  final int lastStock;
  final String archivedDate;

  const _ArchivedMedicine({
    required this.name,
    required this.lastStock,
    required this.archivedDate,
  });
}

class _ArchivedVisit {
  final String id;
  final String patient;
  final String category;
  final String complaint;
  final String medicine;
  final int qty;
  final String visitDate;
  final String archivedDate;

  const _ArchivedVisit({
    required this.id,
    required this.patient,
    required this.category,
    required this.complaint,
    required this.medicine,
    required this.qty,
    required this.visitDate,
    required this.archivedDate,
  });
}

// ── SAMPLE DATA (UI only) ────────────────────────────────────────────────────

const List<_ArchivedPerson> _kSamplePeople = [
  _ArchivedPerson(
    id: 'STU-2023-0451',
    name: 'Maria L. Santos',
    category: 'Student',
    archivedDate: '2026-09-28',
    reason: 'Discontinued',
    archivedBy: 'Clinic Head',
    academicYear: '2025-2026',
    semester: '1st Semester',
    sex: 'Female',
    birthDate: 'March 14, 2004',
    contact: '0917 555 0198',
    email: 'maria.santos@student.tcgc.edu.ph',
    address: 'Brgy. Matapang, City',
    institute: 'Institute of Engineering and Technology',
    program: 'BS Information Technology',
    yearLevel: '3rd Year',
  ),
  _ArchivedPerson(
    id: 'STU-2022-0110',
    name: 'John Paul R. Dela Cruz',
    category: 'Student',
    archivedDate: '2026-07-15',
    reason: 'Graduated',
    archivedBy: 'Nurse Anna',
    academicYear: '2024-2025',
    semester: '2nd Semester',
    sex: 'Male',
    birthDate: 'August 22, 2003',
    contact: '0918 555 0452',
    email: 'jp.delacruz@student.tcgc.edu.ph',
    address: 'Brgy. San Roque, City',
    institute: 'College of Education',
    program: 'Bachelor of Secondary Education',
    yearLevel: '4th Year',
  ),
  _ArchivedPerson(
    id: 'STU-2024-0088',
    name: 'Alyssa M. Reyes',
    category: 'Student',
    archivedDate: '2026-10-01',
    reason: 'Recalled',
    archivedBy: 'Staff Leo',
    academicYear: '2025-2026',
    semester: '2nd Semester',
    sex: 'Female',
    birthDate: 'January 9, 2006',
    contact: '0920 555 0117',
    email: 'alyssa.reyes@student.tcgc.edu.ph',
    address: 'Brgy. Sta. Cruz, City',
    institute: 'Institute of Engineering and Technology',
    program: 'BS Information Technology',
    yearLevel: '1st Year',
  ),
  _ArchivedPerson(
    id: 'F2019-0032',
    name: 'Engr. Roberto C. Villanueva',
    category: 'Faculty',
    archivedDate: '2026-09-12',
    reason: 'Resigned',
    archivedBy: 'Clinic Head',
    academicYear: '2025-2026',
    semester: '1st Semester',
    sex: 'Male',
    birthDate: 'June 30, 1987',
    contact: '0916 555 0274',
    email: 'rc.villanueva@tcgc.edu.ph',
    address: 'San Isidro, City',
    institute: 'Institute of Engineering and Technology',
    position: 'Instructor III',
  ),
  _ArchivedPerson(
    id: 'F2020-0076',
    name: 'Prof. Carmela D. Bautista',
    category: 'Faculty',
    archivedDate: '2026-08-03',
    reason: 'Resigned',
    archivedBy: 'Nurse Anna',
    academicYear: '2024-2025',
    semester: '2nd Semester',
    sex: 'Female',
    birthDate: 'November 5, 1982',
    contact: '0917 555 0338',
    email: 'cd.bautista@tcgc.edu.ph',
    address: 'Brgy. Balete, City',
    institute: 'College of Education',
    position: 'Assistant Professor',
  ),
  _ArchivedPerson(
    id: 'S2021-0015',
    name: 'Ramon T. Aquino',
    category: 'Staff',
    archivedDate: '2026-09-30',
    reason: 'Resigned',
    archivedBy: 'Clinic Head',
    academicYear: '2025-2026',
    semester: '1st Semester',
    sex: 'Male',
    birthDate: 'April 18, 1990',
    contact: '0915 555 0602',
    email: 'rt.aquino@tcgc.edu.ph',
    address: 'Brgy. Ilaya, City',
    department: "Registrar's Office",
    position: 'Records Officer',
  ),
  _ArchivedPerson(
    id: 'S2022-0044',
    name: 'Jenny B. Flores',
    category: 'Staff',
    archivedDate: '2026-06-20',
    reason: 'Recalled',
    archivedBy: 'Staff Leo',
    academicYear: '2024-2025',
    semester: '1st Semester',
    sex: 'Female',
    birthDate: 'September 27, 1995',
    contact: '0919 555 0146',
    email: 'jb.flores@tcgc.edu.ph',
    address: 'Brgy. River, City',
    department: 'Finance Office',
    position: 'Cashier',
  ),
];

const List<_ArchivedMedicine> _kSampleMedicines = [
  _ArchivedMedicine(
      name: 'Paracetamol 500mg', lastStock: 0, archivedDate: '2026-09-29'),
  _ArchivedMedicine(
      name: 'Amoxicillin 500mg', lastStock: 12, archivedDate: '2026-07-11'),
  _ArchivedMedicine(
      name: 'Cetirizine 10mg', lastStock: 3, archivedDate: '2026-10-02'),
  _ArchivedMedicine(
      name: 'Mefenamic Acid 500mg', lastStock: 0, archivedDate: '2026-08-18'),
];

const List<_ArchivedVisit> _kSampleVisits = [
  _ArchivedVisit(
    id: 'R-2026-0042',
    patient: 'Maria L. Santos',
    category: 'Student',
    complaint: 'Headache',
    medicine: 'Paracetamol',
    qty: 1,
    visitDate: '2026-09-20',
    archivedDate: '2026-09-28',
  ),
  _ArchivedVisit(
    id: 'R-2026-0031',
    patient: 'Engr. Roberto C. Villanueva',
    category: 'Faculty',
    complaint: 'Hypertension follow-up',
    medicine: 'Amlodipine',
    qty: 2,
    visitDate: '2026-09-05',
    archivedDate: '2026-09-12',
  ),
  _ArchivedVisit(
    id: 'R-2026-0018',
    patient: 'Jenny B. Flores',
    category: 'Staff',
    complaint: 'Cough and colds',
    medicine: 'Cetirizine',
    qty: 1,
    visitDate: '2026-06-18',
    archivedDate: '2026-06-20',
  ),
];

// ── SCREEN STATE ─────────────────────────────────────────────────────────────

class _ArchiveScreenState extends State<ArchiveScreen> {
  static const String _kIndividuals = 'Individual Records';
  static const String _kMedicines = 'Medicines';
  static const String _kBooklet = 'Record Booklet';

  String mainTab = _kIndividuals;
  final TextEditingController search = TextEditingController();

  // Mutable copies so Restore / Delete visibly change the page.
  late final List<_ArchivedPerson> _people = [..._kSamplePeople];
  late final List<_ArchivedMedicine> _medicines = [..._kSampleMedicines];
  late final List<_ArchivedVisit> _visits = [..._kSampleVisits];

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  // ── filtering ──────────────────────────────────────────────────────────────

  List<_ArchivedPerson> get _filteredPeople {
    final q = search.text.trim().toLowerCase();
    return _people.where((p) {
      if (q.isEmpty) return true;
      return p.id.toLowerCase().contains(q) || p.name.toLowerCase().contains(q);
    }).toList();
  }

  List<_ArchivedMedicine> get _filteredMedicines {
    final q = search.text.trim().toLowerCase();
    return _medicines
        .where((m) => q.isEmpty || m.name.toLowerCase().contains(q))
        .toList();
  }

  List<_ArchivedVisit> get _filteredVisits {
    final q = search.text.trim().toLowerCase();
    return _visits.where((v) {
      if (q.isEmpty) return true;
      return v.patient.toLowerCase().contains(q) ||
          v.complaint.toLowerCase().contains(q);
    }).toList();
  }

  int get _visibleCount => mainTab == _kIndividuals
      ? _filteredPeople.length
      : mainTab == _kMedicines
          ? _filteredMedicines.length
          : _filteredVisits.length;

  // ── actions (UI only) ──────────────────────────────────────────────────────

  Future<void> _restore(String label, String kind) async {
    final ok = await _confirm(
      title: 'Restore Item',
      message: 'Restore "$label" to the active $kind?',
      confirmLabel: 'Restore',
      confirmColor: kPrimary,
    );
    if (!ok || !mounted) return;
    _snack('$label restored to the active list.', kPrimary);
  }

  Future<void> _deleteForever(String label) async {
    final ok = await _confirm(
      title: 'Delete Permanently',
      message:
          'Permanently delete "$label"? This cannot be undone and the record '
          'will not be recoverable.',
      confirmLabel: 'Delete',
      confirmColor: kDanger,
    );
    if (!ok || !mounted) return;
    _snack('$label was permanently deleted.', kDanger);
  }

  Future<bool> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    required Color confirmColor,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: kCard,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: kTextMain)),
                const SizedBox(height: 10),
                Text(message,
                    style: const TextStyle(
                        fontSize: 14.5, color: kTextSub, height: 1.5)),
                const SizedBox(height: 20),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel',
                        style: TextStyle(fontSize: 14.5, color: kTextSub)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: confirmColor,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 22, vertical: 12),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: Text(confirmLabel,
                        style: const TextStyle(
                            fontSize: 14.5, fontWeight: FontWeight.w600)),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
    return result ?? false;
  }

  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontSize: 14)),
      backgroundColor: color,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      margin: const EdgeInsets.all(16),
    ));
  }

  // ── build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 14, 24, 40),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildMainTabs(),
                  const SizedBox(height: 14),
                  _buildToolbar(),
                  const SizedBox(height: 16),
                  _buildTable(),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── HEADER — same title block as Reports / Records Booklet ─────────────

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
                  colors: [kPrimary, kPrimaryDk],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.archive_outlined,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Archive',
                    style: TextStyle(
                        color: kTextMain,
                        fontWeight: FontWeight.w800,
                        fontSize: 23)),
                SizedBox(height: 2),
                Text('Deleted items — restore them or remove them for good',
                    style: TextStyle(color: kTextSub, fontSize: 15)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── MAIN TABS (the three kinds of archived things) ─────────────────────

  Widget _buildMainTabs() {
    final tabs = [_kIndividuals, _kMedicines, _kBooklet];
    return Container(
      constraints: const BoxConstraints(maxWidth: 540),
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2F6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: tabs.map((t) {
          final sel = mainTab == t;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                if (mainTab == t) return;
                setState(() {
                  mainTab = t;
                  search.clear();
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: sel ? kPrimary : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: sel
                      ? [
                          BoxShadow(
                              color: kPrimary.withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2))
                        ]
                      : [],
                ),
                child: Text(t,
                    style: TextStyle(
                      color: sel ? Colors.white : kTextSub,
                      fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 15,
                    )),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── SEARCH + COUNT (like the Individual Record filter bar) ─────────────

  Widget _buildToolbar() {
    final hint = mainTab == _kIndividuals
        ? 'Search by ID or name…'
        : mainTab == _kMedicines
            ? 'Search deleted medicines…'
            : 'Search archive records…';

    final field = TextField(
      controller: search,
      onChanged: (_) => setState(() {}),
      style: const TextStyle(fontSize: 16, color: kTextMain),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: kTextSub, fontSize: 15),
        prefixIcon: const Icon(Icons.search_rounded, color: kTextSub, size: 20),
        suffixIcon: search.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear',
                icon:
                    const Icon(Icons.close_rounded, color: kTextSub, size: 20),
                onPressed: () => setState(search.clear),
              ),
        filled: true,
        fillColor: kCard,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kBorder)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kBorder)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kPrimary, width: 1.5)),
      ),
    );

    final badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: kPrimary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kPrimary.withValues(alpha: 0.2)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.archive_outlined, size: 15, color: kPrimary),
        const SizedBox(width: 6),
        Text('$_visibleCount archived',
            style: TextStyle(
                fontSize: 13.5, color: kPrimary, fontWeight: FontWeight.w700)),
      ]),
    );

    return LayoutBuilder(builder: (ctx, con) {
      if (con.maxWidth < 780) {
        return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              field,
              const SizedBox(height: 10),
              Align(alignment: Alignment.centerLeft, child: badge),
            ]);
      }
      return Row(children: [
        Expanded(child: field),
        const SizedBox(width: 12),
        badge,
      ]);
    });
  }

  // ── TABLE ────────────────────────────────────────────────────────────────

  Widget _buildTable() {
    final list = mainTab == _kIndividuals
        ? _filteredPeople
        : mainTab == _kMedicines
            ? _filteredMedicines
            : _filteredVisits;

    if (list.isEmpty) {
      return Container(
        width: double.infinity,
        height: 220,
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kBorder),
        ),
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.search_off_rounded,
                size: 44, color: AppColors.borderStrong),
            const SizedBox(height: 10),
            Text(
              search.text.isEmpty
                  ? 'No archived records yet.'
                  : 'No results for "${search.text}".',
              style: const TextStyle(color: kTextSub, fontSize: 14),
            ),
          ]),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2))
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(children: [
          if (mainTab == _kIndividuals)
            _dataTable(_peopleColumns(), _peopleRows())
          else if (mainTab == _kMedicines)
            _dataTable(_medicineColumns(), _medicineRows())
          else
            _dataTable(_visitColumns(), _visitRows()),
        ]),
      ),
    );
  }

  /// The DataTable chrome shared by every tab, styled like the Individual
  /// Record and Records Booklet tables so it reads as the same app.
  Widget _dataTable(List<DataColumn> columns, List<DataRow> rows) {
    return LayoutBuilder(builder: (ctx, con) {
      return SingleChildScrollView(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: con.maxWidth),
            child: DataTable(
              headingRowHeight: 52,
              dataRowMinHeight: 58,
              dataRowMaxHeight: 68,
              showCheckboxColumn: false,
              headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
              headingTextStyle: const TextStyle(
                  fontWeight: FontWeight.w700,
                  color: kTextSub,
                  fontSize: 14,
                  letterSpacing: 0.5),
              dataTextStyle: const TextStyle(color: kTextMain, fontSize: 15),
              columnSpacing: 24,
              horizontalMargin: 20,
              dividerThickness: 1,
              border: const TableBorder(
                horizontalInside: BorderSide(color: kBorder, width: 0.8),
              ),
              columns: columns,
              rows: rows,
            ),
          ),
        ),
      );
    });
  }

  // ── Individual Records table ───────────────────────────────────────────────

  List<DataColumn> _peopleColumns() => const [
        DataColumn(label: Text('ID')),
        DataColumn(label: Text('NAME')),
        // The category is a per-row badge now that all three share one table.
        DataColumn(label: Text('TYPE')),
        DataColumn(label: Text('ARCHIVED')),
        DataColumn(label: Text('ACTION')),
      ];

  List<DataRow> _peopleRows() {
    return _filteredPeople.asMap().entries.map((entry) {
      final p = entry.value;
      final even = entry.key % 2 == 0;
      final color = _categoryColor(p.category);
      return DataRow(
        color: WidgetStateProperty.all(even ? kCard : const Color(0xFFFAFCFD)),
        onSelectChanged: (_) => _showPersonDetail(p),
        cells: [
          DataCell(Text(p.id,
              style: TextStyle(
                  fontSize: 15, fontWeight: FontWeight.w700, color: color))),
          DataCell(Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(p.name,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 15)),
              const SizedBox(height: 2),
              Text(p.affiliationLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 12,
                      color: kPrimary,
                      fontWeight: FontWeight.w500)),
            ],
          )),
          DataCell(_typePill(p.category)),
          DataCell(Text(p.archivedDate,
              style: const TextStyle(fontSize: 14.5, color: kTextSub))),
          DataCell(_actionCell(
              onRestore: () => _restore(p.name, 'individual record'),
              onDelete: () => _deleteForever(p.name))),
        ],
      );
    }).toList();
  }

  // ── Medicines table ─────────────────────────────────────────────────────────

  List<DataColumn> _medicineColumns() => const [
        DataColumn(label: Text('MEDICINE')),
        DataColumn(label: Text('LAST STOCK')),
        DataColumn(label: Text('ARCHIVED')),
        DataColumn(label: Text('ACTION')),
      ];

  List<DataRow> _medicineRows() {
    return _filteredMedicines.asMap().entries.map((entry) {
      final m = entry.value;
      final even = entry.key % 2 == 0;
      return DataRow(
        color: WidgetStateProperty.all(even ? kCard : const Color(0xFFFAFCFD)),
        cells: [
          DataCell(Text(m.name,
              style:
                  const TextStyle(fontWeight: FontWeight.w600, fontSize: 15))),
          DataCell(_stockPill(m.lastStock)),
          DataCell(Text(m.archivedDate,
              style: const TextStyle(fontSize: 14.5, color: kTextSub))),
          DataCell(_actionCell(
              onRestore: () => _restore(m.name, 'medicine list'),
              onDelete: () => _deleteForever(m.name))),
        ],
      );
    }).toList();
  }

  // ── Record Booklet table (VISITOR style like the Records Booklet) ──────────

  List<DataColumn> _visitColumns() => const [
        DataColumn(label: Text('VISITOR')),
        DataColumn(label: Text('TYPE')),
        DataColumn(label: Text('COMPLAINT')),
        DataColumn(label: Text('MEDICINE')),
        DataColumn(label: Text('VISIT DATE')),
        DataColumn(label: Text('ACTION')),
      ];

  List<DataRow> _visitRows() {
    return _filteredVisits.asMap().entries.map((entry) {
      final v = entry.value;
      final even = entry.key % 2 == 0;
      return DataRow(
        color: WidgetStateProperty.all(even ? kCard : const Color(0xFFFAFCFD)),
        onSelectChanged: (_) => _showVisitDetail(v),
        cells: [
          DataCell(SizedBox(
            width: 190,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(v.patient,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: kTextMain)),
                const SizedBox(height: 2),
                Text(v.id,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11.5, color: kTextSub)),
              ],
            ),
          )),
          DataCell(_typePill(v.category)),
          DataCell(Text(v.complaint,
              style: const TextStyle(fontSize: 14.5),
              overflow: TextOverflow.ellipsis)),
          DataCell(Text('${v.medicine}  (x${v.qty})',
              style: const TextStyle(fontSize: 14.5, color: kTextSub),
              overflow: TextOverflow.ellipsis)),
          DataCell(Text(v.visitDate,
              style: const TextStyle(fontSize: 14.5, color: kTextSub))),
          DataCell(_actionCell(
              onRestore: () => _restore(v.patient, 'record list'),
              onDelete: () => _deleteForever(v.patient))),
        ],
      );
    }).toList();
  }

  // ── re-used cells ──────────────────────────────────────────────────────────

  /// Restore + Delete pair, sized like the Individual Record action buttons so
  /// the column has no dead space and the two icons always line up.
  Widget _actionCell({
    required VoidCallback onRestore,
    required VoidCallback onDelete,
  }) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      _actionBtn(
        icon: Icons.restore_rounded,
        color: kPrimary,
        tooltip: 'Restore',
        onTap: onRestore,
      ),
      const SizedBox(width: 4),
      _actionBtn(
        icon: Icons.delete_forever_rounded,
        color: kDanger,
        tooltip: 'Delete permanently',
        onTap: onDelete,
      ),
    ]);
  }

  Widget _actionBtn(
      {required IconData icon,
      required Color color,
      required String tooltip,
      required VoidCallback onTap}) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: color, size: 16),
        ),
      ),
    );
  }

  Widget _stockPill(int stock) {
    final out = stock <= 0;
    final color = out ? kDanger : AppColors.warning;
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(out ? 'Out of stock' : '$stock left',
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: color)),
      ),
    );
  }

  Widget _typePill(String category) {
    final color = _categoryColor(category);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(category,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w700, color: color)),
      ),
    );
  }

  Color _categoryColor(String cat) => cat == 'Student'
      ? AppColors.student
      : cat == 'Faculty'
          ? AppColors.faculty
          : AppColors.staff;

  // ── DETAIL DIALOGS (same shaped as the Individual Record detail) ──────────

  void _showPersonDetail(_ArchivedPerson p) {
    final color = _categoryColor(p.category);
    showDialog(
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
                _dialogHeader(
                  ctx: ctx,
                  icon: p.isStudent
                      ? Icons.person_outline_rounded
                      : Icons.work_outline_rounded,
                  color: color,
                  title: p.name,
                  chips: [
                    _chip(p.category, color),
                    _chip(p.id, kTextSub, bg: const Color(0xFFF1F5F9)),
                    if (p.academicYear.isNotEmpty)
                      Text('AY ${p.academicYear} · ${p.semester}',
                          style:
                              const TextStyle(fontSize: 12.5, color: kTextSub)),
                  ],
                ),
                const SizedBox(height: 6),
                const Divider(color: kBorder, height: 1),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _infoSection('Identity', Icons.person_outline, [
                          _infoRow('Full Name', p.name),
                          _infoRow('Sex', p.sex),
                          _infoRow('Birth Date', p.birthDate),
                          _infoRow('Contact', p.contact),
                          _infoRow('Email', p.email),
                          _infoRow('Address', p.address),
                        ]),
                        _infoSection(
                          p.isStudent
                              ? 'Academic Information'
                              : (p.isFaculty
                                  ? 'Teaching Assignment'
                                  : 'Employment Information'),
                          p.isStudent
                              ? Icons.school_outlined
                              : Icons.work_outline,
                          [
                            _infoRow('School Year', p.academicYear),
                            _infoRow('Semester', p.semester),
                            if (p.isStudent) ...[
                              _infoRow('Institute', p.institute),
                              _infoRow('Program', p.program),
                              _infoRow('Year Level', p.yearLevel),
                            ] else if (p.isFaculty) ...[
                              _infoRow('Institute', p.institute),
                              _infoRow('Position', p.position),
                            ] else ...[
                              _infoRow('Department / Office', p.department),
                              _infoRow('Position', p.position),
                            ],
                          ],
                        ),
                        _infoSection(
                            'Archive Information', Icons.history_rounded, [
                          _infoRow('Archived Date', p.archivedDate),
                          _infoRow('Reason', p.reason),
                          _infoRow('Archived By', p.archivedBy),
                        ]),
                      ],
                    ),
                  ),
                ),
                const Divider(color: kBorder, height: 1),
                const SizedBox(height: 14),
                _dialogFooter(
                  context: ctx,
                  onRestore: () => _restore(p.name, 'individual record'),
                  onDelete: () => _deleteForever(p.name),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showVisitDetail(_ArchivedVisit v) {
    final color = _categoryColor(v.category);
    showDialog(
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
                _dialogHeader(
                  ctx: ctx,
                  icon: Icons.description_outlined,
                  color: color,
                  title: v.patient,
                  initials: true,
                  chips: [
                    _chip(v.category, color),
                    _chip(v.id, kTextSub, bg: const Color(0xFFF1F5F9))
                  ],
                ),
                const SizedBox(height: 6),
                const Divider(color: kBorder, height: 1),
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _infoSection(
                            'Visit Details', Icons.fact_check_outlined, [
                          _infoRow('Record No', v.id),
                          _infoRow('Type', v.category),
                          _infoRow('Complaint', v.complaint),
                          _infoRow('Medicine', v.medicine),
                          _infoRow('Quantity', 'x${v.qty}'),
                          _infoRow('Visit Date', v.visitDate),
                        ]),
                        _infoSection(
                            'Archive Information', Icons.history_rounded, [
                          _infoRow('Archived Date', v.archivedDate),
                          _infoRow('Reason', 'Archived'),
                          _infoRow('Archived By', 'System'),
                        ]),
                      ],
                    ),
                  ),
                ),
                const Divider(color: kBorder, height: 1),
                const SizedBox(height: 14),
                _dialogFooter(
                  context: ctx,
                  onRestore: () => _restore(v.patient, 'record list'),
                  onDelete: () => _deleteForever(v.patient),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _dialogHeader({
    required BuildContext ctx,
    required IconData icon,
    required Color color,
    required String title,
    required List<Widget> chips,
    bool initials = false,
  }) {
    return Row(children: [
      Container(
        width: 46,
        height: 46,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: color, borderRadius: BorderRadius.circular(12)),
        child: initials
            ? Text(_initials(title),
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16))
            : Icon(icon, color: Colors.white, size: 22),
      ),
      const SizedBox(width: 14),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: kTextMain)),
            const SizedBox(height: 5),
            Wrap(spacing: 8, runSpacing: 4, children: chips),
          ],
        ),
      ),
      IconButton(
          onPressed: () => Navigator.pop(ctx),
          icon: const Icon(Icons.close_rounded, color: kTextSub),
          iconSize: 20),
    ]);
  }

  Widget _chip(String text, Color color, {Color? bg}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
          color: bg ?? color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6)),
      child: Text(text,
          style: TextStyle(
              fontSize: 12, fontWeight: FontWeight.bold, color: color)),
    );
  }

  Widget _dialogFooter({
    required BuildContext context,
    required VoidCallback onRestore,
    required VoidCallback onDelete,
  }) {
    return Row(children: [
      Expanded(
        child: OutlinedButton.icon(
          onPressed: () {
            Navigator.pop(context);
            onRestore();
          },
          icon: const Icon(Icons.restore_rounded, size: 16, color: kPrimary),
          label: const Text('Restore', style: TextStyle(color: kPrimary)),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: kBorder),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(vertical: 13),
          ),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: OutlinedButton.icon(
          onPressed: () {
            Navigator.pop(context);
            onDelete();
          },
          icon: const Icon(Icons.delete_forever_rounded,
              size: 16, color: kDanger),
          label: const Text('Delete', style: TextStyle(color: kDanger)),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: kBorder),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(vertical: 13),
          ),
        ),
      ),
    ]);
  }

  Widget _infoSection(String title, IconData icon, List<Widget> rows) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 16, color: kPrimary),
          const SizedBox(width: 8),
          Text(title,
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: kTextMain,
                  letterSpacing: 0.3)),
          const SizedBox(width: 12),
          const Expanded(child: Divider(color: kBorder, height: 1)),
        ]),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, c) {
          final twoCol = c.maxWidth > 460;
          final pairs = <Widget>[];
          for (var i = 0; i < rows.length; i += (twoCol ? 2 : 1)) {
            final end = (i + (twoCol ? 2 : 1)).clamp(0, rows.length);
            pairs.add(Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
      ]),
    );
  }

  Widget _infoRow(String label, String value) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: const TextStyle(
              fontSize: 11.5, color: kTextSub, fontWeight: FontWeight.w600)),
      const SizedBox(height: 2),
      Text(value.isEmpty ? '—' : value,
          style: const TextStyle(
              fontSize: 14.5, color: kTextMain, fontWeight: FontWeight.w600)),
    ]);
  }

  String _initials(String name) {
    final parts = name
        .replaceAll('.', ' ')
        .split(' ')
        .where((s) => s.trim().isNotEmpty)
        .toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}
