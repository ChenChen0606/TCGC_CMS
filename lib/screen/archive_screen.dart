import 'package:flutter/material.dart';

// ── COLORS (same palette as the rest of the app) ────────────────────────────
const Color kPrimary   = Color(0xFF008080);
const Color kPrimaryDk = Color(0xFF0F766E);
const Color kCard      = Colors.white;
const Color kBg        = Color(0xFFF8FAFC);
const Color kBorder    = Color(0xFFE2E8F0);
const Color kTextMain  = Color(0xFF0F172A);
const Color kTextSub   = Color(0xFF64748B);
const Color kDanger    = Color(0xFFEF4444);
const Color kWarn      = Color(0xFFD97706);
const Color kSuccess   = Color(0xFF10B981);

// ── DATA MODELS ─────────────────────────────────────────────────────────────

class ArchivedPatient {
  final String id, name, department, position, archivedDate, reason, archivedBy, category;
  ArchivedPatient({
    required this.id, required this.name, required this.department, required this.position,
    required this.archivedDate, required this.reason, required this.archivedBy, required this.category,
  });
}

class ArchivedMedicine {
  final String name, archivedDate, reason, archivedBy;
  final int lastStock;
  ArchivedMedicine({
    required this.name, required this.lastStock, required this.archivedDate,
    required this.reason, required this.archivedBy,
  });
}

class ArchivedRecord {
  final String patient, type, complaint, medicine, visitDate, status, category;
  final int qty;
  ArchivedRecord({
    required this.patient, required this.type, required this.complaint, required this.medicine,
    required this.qty, required this.visitDate, required this.status, required this.category,
  });
}

// ── MOCK DATA — plain hardcoded data, no database, no role checks ──────────

class ArchiveData {
  static List<ArchivedPatient> patients = [
    ArchivedPatient(id: '234567', name: 'Mikaela Reyes S.', department: 'BSCS', position: '2nd Year',
      archivedDate: '2026-01-20', reason: 'Graduated', archivedBy: 'Anna Gonzaga', category: 'Student'),
    ArchivedPatient(id: '234890', name: 'John Rafael T.', department: 'BSIT', position: '4th Year',
      archivedDate: '2025-12-15', reason: 'Graduated', archivedBy: 'Anna Gonzaga', category: 'Student'),
    ArchivedPatient(id: 'F009', name: 'Prof. Liza Marquez', department: 'ICS', position: 'Instructor',
      archivedDate: '2026-02-10', reason: 'Resigned', archivedBy: 'Anna Gonzaga', category: 'Faculty'),
  ];

  static List<ArchivedMedicine> medicines = [
    ArchivedMedicine(name: 'Amoxicillin 250mg (old formulation)', lastStock: 0,
      archivedDate: '2026-06-18', reason: 'Discontinued', archivedBy: 'Anna Gonzaga'),
  ];

  static List<ArchivedRecord> records = [
    ArchivedRecord(patient: 'Mikaela Reyes S.', type: 'Student', complaint: 'Fever', medicine: 'Paracetamol',
      qty: 1, visitDate: '2026-01-14', status: 'Graduated', category: 'Student'),
    ArchivedRecord(patient: 'Mikaela Reyes S.', type: 'Student', complaint: 'Migraine', medicine: 'Biogesic',
      qty: 2, visitDate: '2025-11-03', status: 'Graduated', category: 'Student'),
    ArchivedRecord(patient: 'Prof. Liza Marquez', type: 'Faculty', complaint: 'Headache', medicine: 'Paracetamol',
      qty: 1, visitDate: '2026-02-01', status: 'Resigned', category: 'Faculty'),
  ];
}

// ── SCREEN ───────────────────────────────────────────────────────────────
// Responsive breakpoints:
//   < 800px  -> "mobile" layout: stacked cards instead of a table, biggest
//               text, tabs/search stacked vertically for easy tapping.
//   800–1199 -> "tablet": table view with flexible (percentage-based)
//               columns so nothing ever needs horizontal scrolling.
//   >= 1200  -> "desktop": same flexible table, slightly smaller scale.
// All text sizes are scaled up from the original for readability.

class ArchiveScreen extends StatefulWidget {
  const ArchiveScreen({super.key});

  @override
  State<ArchiveScreen> createState() => _ArchiveScreenState();
}

class _ArchiveScreenState extends State<ArchiveScreen> {
  // Order requested: Medical Records -> Medicines -> Patients
  String mainTab = 'Medical Records';
  String subTab = 'Faculty';     // Student / Faculty / Staff
  final TextEditingController search = TextEditingController();

  // Set once per build by the LayoutBuilder below.
  bool _isMobile = false;
  bool _isTablet = false;
  double _scale = 1.0;

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  double _sp(double base) => base * _scale;

  List<ArchivedPatient> get _filteredPatients {
    final q = search.text.toLowerCase();
    return ArchiveData.patients.where((p) => p.category == subTab).where((p) =>
        q.isEmpty || p.id.toLowerCase().contains(q) || p.name.toLowerCase().contains(q)).toList();
  }

  List<ArchivedMedicine> get _filteredMedicines {
    final q = search.text.toLowerCase();
    return ArchiveData.medicines.where((m) => q.isEmpty || m.name.toLowerCase().contains(q)).toList();
  }

  List<ArchivedRecord> get _filteredRecords {
    final q = search.text.toLowerCase();
    return ArchiveData.records.where((r) => r.category == subTab).where((r) =>
        q.isEmpty || r.patient.toLowerCase().contains(q) || r.complaint.toLowerCase().contains(q)).toList();
  }

  Future<bool> _confirmRestore(String label) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Restore Record', style: TextStyle(fontSize: _sp(19))),
        content: Text('Restore "$label" to the active list?', style: TextStyle(fontSize: _sp(15.5))),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('Cancel', style: TextStyle(fontSize: _sp(14.5))),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            ),
            child: Text('Restore', style: TextStyle(fontSize: _sp(14.5))),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: TextStyle(fontSize: _sp(14))),
      backgroundColor: kPrimary,
    ));
  }

  void _viewRecord(ArchivedRecord r) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Archived Visit Record', style: TextStyle(fontSize: _sp(18))),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Patient: ${r.patient}', style: TextStyle(fontSize: _sp(15))),
          const SizedBox(height: 6),
          Text('Type: ${r.type}', style: TextStyle(fontSize: _sp(15))),
          const SizedBox(height: 6),
          Text('Complaint: ${r.complaint}', style: TextStyle(fontSize: _sp(15))),
          const SizedBox(height: 6),
          Text('Medicine: ${r.medicine} (x${r.qty})', style: TextStyle(fontSize: _sp(15))),
          const SizedBox(height: 6),
          Text('Visit Date: ${r.visitDate}', style: TextStyle(fontSize: _sp(15))),
          const SizedBox(height: 6),
          Text('Status: ${r.status}', style: TextStyle(fontSize: _sp(15))),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text('Close', style: TextStyle(fontSize: _sp(14.5)))),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final width = constraints.maxWidth;
      _isMobile = width < 800;
      _isTablet = width >= 800 && width < 1200;
      _scale = _isMobile ? 1.25 : (_isTablet ? 1.12 : 1.05);
      final pad = _isMobile ? 14.0 : (_isTablet ? 20.0 : 26.0);

      return Container(
        color: kBg,
        width: double.infinity,
        height: double.infinity,
        child: SingleChildScrollView(
          padding: EdgeInsets.all(pad),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _buildHeader(),
            SizedBox(height: pad),
            _buildMainTabs(),
            SizedBox(height: pad * 0.7),
            if (mainTab != 'Medicines') ...[_buildSubTabs(), SizedBox(height: pad * 0.7)],
            _buildSearchRow(),
            SizedBox(height: pad * 0.7),
            _buildTable(),
            if (mainTab != 'Medical Records') ...[SizedBox(height: pad * 0.7)],
          ]),
        ),
      );
    });
  }

  Widget _buildHeader() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const SizedBox(height: 10),
      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: _sp(44), height: _sp(44),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [kPrimary, kPrimaryDk], begin: Alignment.topLeft, end: Alignment.bottomRight),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(Icons.delete_outline, color: Colors.white, size: _sp(24)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Trash', style: TextStyle(fontSize: _sp(24), fontWeight: FontWeight.w800, color: kTextMain)),
            const SizedBox(height: 4),
            Text(
              'Deleted items are stored here and can be restored or permanently removed. Head-only access.',
              style: TextStyle(fontSize: _sp(14), color: kTextSub, height: 1.5),
            ),
          ]),
        ),
      ]),
    ]);
  }

  Widget _buildMainTabs() {
    // Order requested: Medical Records -> Medicines -> Patients
    final tabs = ['Medical Records', 'Medicines', 'Patients'];
    return Wrap(
      spacing: 6,
      runSpacing: 10,
      children: tabs.map((t) {
        final sel = mainTab == t;
        return GestureDetector(
          onTap: () => setState(() {
            mainTab = t;
            search.clear();
          }),
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: _sp(18), vertical: _sp(12)),
            decoration: BoxDecoration(color: sel ? kPrimary : Colors.transparent, borderRadius: BorderRadius.circular(12)),
            child: Text(t, style: TextStyle(
              fontSize: _sp(14.5),
              fontWeight: sel ? FontWeight.w700 : FontWeight.w600,
              color: sel ? Colors.white : kTextSub,
            )),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildSubTabs() {
    return Container(
      height: _sp(46),
      padding: const EdgeInsets.all(4),
      constraints: BoxConstraints(maxWidth: _sp(360)),
      decoration: BoxDecoration(color: const Color(0xFFEEF2F6), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: ['Student', 'Faculty', 'Staff'].map((tab) {
          final sel = subTab == tab;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() {
                subTab = tab;
                search.clear();
              }),
              child: Container(
                alignment: Alignment.center,
                decoration: BoxDecoration(color: sel ? kPrimary : Colors.transparent, borderRadius: BorderRadius.circular(9)),
                child: Text(tab, style: TextStyle(
                  color: sel ? Colors.white : kTextSub,
                  fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                  fontSize: _sp(14),
                )),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSearchRow() {
    final count = mainTab == 'Patients' ? _filteredPatients.length
        : mainTab == 'Medicines' ? _filteredMedicines.length : _filteredRecords.length;
    final hint = mainTab == 'Patients' ? 'Search deleted patients by ID or name…'
        : mainTab == 'Medicines' ? 'Search deleted medicines…' : 'Search deleted visit records…';

    final field = TextField(
      controller: search,
      onChanged: (_) => setState(() {}),
      style: TextStyle(fontSize: _sp(14.5)),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontSize: _sp(13.5)),
        prefixIcon: Icon(Icons.search_rounded, color: kTextSub, size: _sp(21)),
        filled: true,
        fillColor: kCard,
        contentPadding: EdgeInsets.symmetric(vertical: _sp(13), horizontal: 12),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBorder)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBorder)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kPrimary, width: 1.5)),
      ),
    );

    final badge = Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 14, vertical: _sp(11)),
      alignment: Alignment.center,
      decoration: BoxDecoration(color: kPrimary.withOpacity(0.08), borderRadius: BorderRadius.circular(20), border: Border.all(color: kPrimary.withOpacity(0.2))),
      child: Text('$count deleted', textAlign: TextAlign.center, style: TextStyle(fontSize: _sp(13), color: kPrimary, fontWeight: FontWeight.w700)),
    );

    if (_isMobile) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [field, const SizedBox(height: 10), badge]);
    }
    return Row(children: [
      Expanded(child: field),
      const SizedBox(width: 14),
      SizedBox(width: 160, child: badge),
    ]);
  }

  Widget _buildTable() {
    if (mainTab == 'Patients') return _isMobile ? _patientCardList() : _patientsTable();
    if (mainTab == 'Medicines') return _isMobile ? _medicineCardList() : _medicinesTable();
    return _isMobile ? _recordCardList() : _recordsTable();
  }

  // ── Table mode (tablet / desktop) — flex-based columns always fill the
  //    full width exactly, so there's never horizontal scroll or leftover
  //    empty space, no matter the screen size. ─────────────────────────────

  Widget _tableShell({required bool isEmpty, required String emptyLabel, required List<String> headers, required List<int> flexes, required List<Widget> rows}) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: kBorder)),
      child: isEmpty
          ? Padding(
              padding: EdgeInsets.all(_sp(36)),
              child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.inbox_outlined, size: _sp(40), color: Colors.grey.shade300),
                const SizedBox(height: 12),
                Text(emptyLabel, style: TextStyle(color: kTextSub, fontSize: _sp(14))),
              ])),
            )
          : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: double.infinity,
                padding: EdgeInsets.symmetric(horizontal: _sp(14), vertical: _sp(13)),
                decoration: const BoxDecoration(color: kBg, borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
                child: Row(
                  children: List.generate(headers.length, (i) => Expanded(
                    flex: flexes[i],
                    child: Text(headers[i], style: TextStyle(fontWeight: FontWeight.w700, color: kTextSub, fontSize: _sp(11.5), letterSpacing: 0.4)),
                  )),
                ),
              ),
              ...rows,
            ]),
    );
  }

  Widget _dataRow(List<Widget> cells, List<int> flexes, bool even) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: _sp(14), vertical: _sp(14)),
      decoration: BoxDecoration(color: even ? kCard : const Color(0xFFFAFCFD), border: const Border(top: BorderSide(color: kBorder, width: 0.8))),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: List.generate(cells.length, (i) => Expanded(
          flex: flexes[i],
          child: Padding(padding: const EdgeInsets.only(right: 6), child: cells[i]),
        )),
      ),
    );
  }

  Widget _patientsTable() {
    final list = _filteredPatients;
    const flexes = [2, 3, 2, 2, 2, 2, 2, 2];
    return _tableShell(
      isEmpty: list.isEmpty,
      emptyLabel: search.text.isEmpty ? 'No archived $subTab patients yet.' : 'No results for "${search.text}".',
      headers: const ['ID', 'NAME', 'DEPT.', 'POSITION', 'ARCHIVED', 'BY', 'ACTION'],
      flexes: flexes,
      rows: list.asMap().entries.map((e) {
        final p = e.value;
        return _dataRow([
          Text(p.id, style: TextStyle(fontWeight: FontWeight.w700, color: kPrimary, fontSize: _sp(13.5)), overflow: TextOverflow.ellipsis),
          Text(p.name, style: TextStyle(fontWeight: FontWeight.w600, fontSize: _sp(13.5)), overflow: TextOverflow.ellipsis, maxLines: 2),
          Text(p.department, style: TextStyle(fontSize: _sp(12.5)), overflow: TextOverflow.ellipsis),
          Text(p.position, style: TextStyle(fontSize: _sp(12.5)), overflow: TextOverflow.ellipsis),
          Text(p.archivedDate, style: TextStyle(fontSize: _sp(12.5), color: kTextSub)),
         
          Text(p.archivedBy, style: TextStyle(fontSize: _sp(12.5)), overflow: TextOverflow.ellipsis),
          _restoreBtn(() async {
            final ok = await _confirmRestore(p.name);
            if (ok) { setState(() => ArchiveData.patients.remove(p)); _showSuccess('${p.name} restored.'); }
          }),
        ], flexes, e.key % 2 == 0);
      }).toList(),
    );
  }

  Widget _medicinesTable() {
    final list = _filteredMedicines;
    const flexes = [3, 2, 2, 2, 2, 2];
    return _tableShell(
      isEmpty: list.isEmpty,
      emptyLabel: search.text.isEmpty ? 'No archived medicines yet.' : 'No results for "${search.text}".',
      headers: const ['MEDICINE', 'LAST STOCK', 'ARCHIVED', 'BY', 'ACTION'],
      flexes: flexes,
      rows: list.asMap().entries.map((e) {
        final m = e.value;
        return _dataRow([
          Text(m.name, style: TextStyle(fontWeight: FontWeight.w600, fontSize: _sp(13.5)), overflow: TextOverflow.ellipsis, maxLines: 2),
          Text('${m.lastStock}', style: TextStyle(fontSize: _sp(12.5), color: kTextSub)),
          Text(m.archivedDate, style: TextStyle(fontSize: _sp(12.5), color: kTextSub)),
       
          Text(m.archivedBy, style: TextStyle(fontSize: _sp(12.5)), overflow: TextOverflow.ellipsis),
          _restoreBtn(() async {
            final ok = await _confirmRestore(m.name);
            if (ok) { setState(() => ArchiveData.medicines.remove(m)); _showSuccess('${m.name} restored.'); }
          }),
        ], flexes, e.key % 2 == 0);
      }).toList(),
    );
  }

  Widget _recordsTable() {
    final list = _filteredRecords;
    const flexes = [3, 2, 2, 2, 1, 2, 2, 2];
    return _tableShell(
      isEmpty: list.isEmpty,
      emptyLabel: search.text.isEmpty ? 'No archived visit records for $subTab yet.' : 'No results for "${search.text}".',
      headers: const ['PATIENT', 'TYPE', 'COMPLAINT', 'MEDICINE', 'QTY', 'VISIT DATE', 'ACTION'],
      flexes: flexes,
      rows: list.asMap().entries.map((e) {
        final r = e.value;
        return _dataRow([
          Text(r.patient, style: TextStyle(fontWeight: FontWeight.w600, fontSize: _sp(13.5)), overflow: TextOverflow.ellipsis, maxLines: 2),
          Text(r.type, style: TextStyle(color: kPrimary, fontWeight: FontWeight.w600, fontSize: _sp(12.5)), overflow: TextOverflow.ellipsis),
          Text(r.complaint, style: TextStyle(fontSize: _sp(12.5)), overflow: TextOverflow.ellipsis),
          Text(r.medicine, style: TextStyle(fontSize: _sp(12.5)), overflow: TextOverflow.ellipsis),
          Text('${r.qty}', style: TextStyle(fontSize: _sp(12.5))),
          Text(r.visitDate, style: TextStyle(fontSize: _sp(12.5), color: kTextSub)),
          _restoreBtn(() async {
            ///???restore feedback here
          }),
        ], flexes, e.key % 2 == 0);
      }).toList(),
    );
  }

  // ── Card mode (mobile) — one record per card, stacked full-width, with
  //    large text and a full-width action button so it's easy to tap. ─────

  Widget _emptyCard(String label) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(_sp(36)),
      decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(16), border: Border.all(color: kBorder)),
      child: Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.inbox_outlined, size: _sp(40), color: Colors.grey.shade300),
        const SizedBox(height: 12),
        Text(label, style: TextStyle(color: kTextSub, fontSize: _sp(14)), textAlign: TextAlign.center),
      ])),
    );
  }

  Widget _patientCardList() {
    final list = _filteredPatients;
    if (list.isEmpty) {
      return _emptyCard(search.text.isEmpty ? 'No archived $subTab patients yet.' : 'No results for "${search.text}".');
    }
    return Column(children: list.map((p) => Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(_sp(16)),
      decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(14), border: Border.all(color: kBorder)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(p.name, style: TextStyle(fontWeight: FontWeight.w700, fontSize: _sp(16.5), color: kTextMain))),
          const SizedBox(width: 8),
          _reasonBadge(p.reason),
        ]),
        const SizedBox(height: 6),
        Text('ID: ${p.id}', style: TextStyle(fontSize: _sp(13.5), color: kPrimary, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Text('${p.department} • ${p.position}', style: TextStyle(fontSize: _sp(14), color: kTextSub)),
        const SizedBox(height: 4),
        Text('Archived ${p.archivedDate} by ${p.archivedBy}', style: TextStyle(fontSize: _sp(13), color: kTextSub)),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: _restoreBtn(() async {
          final ok = await _confirmRestore(p.name);
          if (ok) { setState(() => ArchiveData.patients.remove(p)); _showSuccess('${p.name} restored.'); }
        })),
      ]),
    )).toList());
  }

  Widget _medicineCardList() {
    final list = _filteredMedicines;
    if (list.isEmpty) {
      return _emptyCard(search.text.isEmpty ? 'No archived medicines yet.' : 'No results for "${search.text}".');
    }
    return Column(children: list.map((m) => Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(_sp(16)),
      decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(14), border: Border.all(color: kBorder)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(m.name, style: TextStyle(fontWeight: FontWeight.w700, fontSize: _sp(16), color: kTextMain))),
          const SizedBox(width: 8),
          _reasonBadge(m.reason),
        ]),
        const SizedBox(height: 6),
        Text('Last known stock: ${m.lastStock}', style: TextStyle(fontSize: _sp(14), color: kTextSub)),
        const SizedBox(height: 4),
        Text('Archived ${m.archivedDate} by ${m.archivedBy}', style: TextStyle(fontSize: _sp(13), color: kTextSub)),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: _restoreBtn(() async {
          final ok = await _confirmRestore(m.name);
          if (ok) { setState(() => ArchiveData.medicines.remove(m)); _showSuccess('${m.name} restored.'); }
        })),
      ]),
    )).toList());
  }

  Widget _recordCardList() {
    final list = _filteredRecords;
    if (list.isEmpty) {
      return _emptyCard(search.text.isEmpty ? 'No archived visit records for $subTab yet.' : 'No results for "${search.text}".');
    }
    return Column(children: list.map((r) => Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: EdgeInsets.all(_sp(16)),
      decoration: BoxDecoration(color: kCard, borderRadius: BorderRadius.circular(14), border: Border.all(color: kBorder)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: Text(r.patient, style: TextStyle(fontWeight: FontWeight.w700, fontSize: _sp(16), color: kTextMain))),
          const SizedBox(width: 8),
          _reasonBadge(r.status),
        ]),
        const SizedBox(height: 4),
        Text(r.type, style: TextStyle(fontSize: _sp(13.5), color: kPrimary, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        Text('${r.complaint} • ${r.medicine} (x${r.qty})', style: TextStyle(fontSize: _sp(14), color: kTextSub)),
        const SizedBox(height: 4),
        Text('Visit date: ${r.visitDate}', style: TextStyle(fontSize: _sp(13), color: kTextSub)),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: _viewBtn(() => _viewRecord(r))),
      ]),
    )).toList());
  }

  Widget _reasonBadge(String reason) {
    Color color;
    Color bg;
    switch (reason) {
      case 'Graduated': color = kSuccess; bg = const Color(0xFFD1FAE5); break;
      case 'Resigned': color = kWarn; bg = const Color(0xFFFEF3C7); break;
      case 'Discontinued': color = kDanger; bg = const Color(0xFFFEE2E2); break;
      case 'Recalled': color = const Color(0xFFB91C1C); bg = const Color(0xFFFEE2E2); break;
      default: color = kTextSub; bg = const Color(0xFFF1F5F9);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(reason, style: TextStyle(fontSize: _sp(12), fontWeight: FontWeight.w700, color: color)),
    );
  }

  Widget _restoreBtn(VoidCallback onTap) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(Icons.restore_rounded, size: _sp(17)),
      label: Text('Restore', style: TextStyle(fontSize: _sp(14), fontWeight: FontWeight.w600)),
      style: OutlinedButton.styleFrom(
        foregroundColor: kPrimary,
        side: const BorderSide(color: kPrimary, width: 1.4),
        padding: EdgeInsets.symmetric(horizontal: 12, vertical: _sp(12)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _viewBtn(VoidCallback onTap) {
    return TextButton.icon(
      onPressed: onTap,
      icon: Icon(Icons.visibility_outlined, size: _sp(18)),
      label: Text('View', style: TextStyle(fontSize: _sp(14), fontWeight: FontWeight.w600)),
      style: TextButton.styleFrom(
        foregroundColor: kPrimary,
        padding: EdgeInsets.symmetric(horizontal: 8, vertical: _sp(10)),
      ),
    );
  }

 /* Widget _whyArchiveNote() {
    final text = mainTab == 'Patients'
        ? 'Why archive instead of delete: graduated students and resigned faculty/staff are hidden from active dropdowns and searches, but their profile stays intact for history. Restoring a record returns it to the active list immediately.'
        : 'Why archive instead of delete: discontinued or recalled medicines are removed from the active Inventory list and Issue Medicine picker, but past dispense history referencing them stays intact for audit purposes.';
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(_sp(16)),
      decoration: BoxDecoration(color: kPrimary.withOpacity(0.05), borderRadius: BorderRadius.circular(12), border: Border.all(color: kPrimary.withOpacity(0.15))),
      child: Text(text, style: TextStyle(fontSize: _sp(13.5), color: kTextSub, height: 1.6)),
    );
  }*/
}