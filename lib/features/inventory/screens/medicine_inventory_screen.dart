import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:clinicmanagementsystem/core/services/data_tracker.dart';
import 'package:clinicmanagementsystem/features/inventory/services/medicine_service.dart';
import 'package:clinicmanagementsystem/core/theme/app_colors.dart';

const Color kPrimary = AppColors.primary;
const Color kPrimaryDk = AppColors.primaryDark;
const Color kCard = AppColors.surface;
const Color kBorder = AppColors.border;
const Color kTextMain = AppColors.textMain;
const Color kTextSub = AppColors.textSub;
const Color kDanger = AppColors.danger;
const Color kBg = AppColors.bgAlt;
const Color kWarn = AppColors.warning;
const Color kExpiring = Color(0xFFEA580C);
const Color kGood = Color(0xFF16A34A);

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
];
String fmtDate(DateTime d) => '${_months[d.month - 1]} ${d.day}, ${d.year}';

String _expiryHint(int? d) {
  if (d == null) return '';
  if (d < 0) return 'Expired ${-d} day${-d == 1 ? '' : 's'} ago';
  if (d == 0) return 'Expires today';
  if (d < 31) return 'in $d day${d == 1 ? '' : 's'}';
  return 'in ${(d / 30).round()} months';
}

Color _batchColor(MedicineBatch b) => b.isExpired
    ? kDanger
    : b.isExpiringSoon
        ? kExpiring
        : kTextSub;

String _errMsg(Object e) => (e is DuplicateMedicineException ||
        e is MedicineInUseException)
    ? e.toString()
    : 'Error: $e';

enum _Filter { all, low, out, expiring, expired }

/// Overall status. Priority: expired > out > expiring > low > good.
class _Status {
  final String label;
  final Color color, bg, border;
  final IconData icon;
  const _Status(this.label, this.color, this.bg, this.border, this.icon);
}

_Status _statusOf(Medicine m) {
  if (m.hasExpiredStock) {
    return const _Status('EXPIRED', kDanger, Color(0xFFFEF2F2),
        Color(0xFFFECACA), Icons.event_busy_rounded);
  }
  if (m.isOutOfStock) {
    return const _Status('OUT', kDanger, Color(0xFFFEF2F2), Color(0xFFFECACA),
        Icons.remove_circle_outline);
  }
  if (m.isExpiringSoon) {
    return const _Status('EXPIRING', kExpiring, Color(0xFFFFF7ED),
        Color(0xFFFED7AA), Icons.schedule_rounded);
  }
  if (m.isLowStock) {
    return const _Status('LOW', Color(0xFFD97706), Color(0xFFFFFBEB),
        Color(0xFFFDE68A), Icons.warning_amber_outlined);
  }
  return const _Status('GOOD', kGood, Color(0xFFF0FDF4), Color(0xFFBBF7D0),
      Icons.check_circle_outline);
}

// =============================================================================
//  SCREEN
// =============================================================================
class MedicineInventoryScreen extends StatefulWidget {
  const MedicineInventoryScreen({super.key});

  @override
  State<MedicineInventoryScreen> createState() =>
      _MedicineInventoryScreenState();
}

class _MedicineInventoryScreenState extends State<MedicineInventoryScreen>
    with SingleTickerProviderStateMixin {
  bool _isLoading = true;

  List<Medicine> _allMedicines = [];
  List<Medicine> _foundMedicines = [];

  final TextEditingController _searchCtrl = TextEditingController();
  _Filter _filter = _Filter.all;
  bool _sortByExpiry = false;

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
    _loadMedicines();
    _dataListener = () => _loadMedicines(showSpinner: false);
    DataTracker.listen(_dataListener!);
  }

  @override
  void dispose() {
    if (_dataListener != null) DataTracker.unlisten(_dataListener!);
    _fadeCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------- data
  Future<void> _loadMedicines({bool showSpinner = true}) async {
    if (showSpinner && mounted) setState(() => _isLoading = true);
    try {
      final meds = await MedicineService.fetchAll();
      meds.sort((a, b) {
        final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return byName != 0 ? byName : (a.id ?? 0).compareTo(b.id ?? 0);
      });
      if (!mounted) return;
      setState(() {
        _allMedicines = meds;
        _applyFilter();
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showError('Failed to load medicines: $e');
    }
  }

  void _applyFilter() {
    final kw = _searchCtrl.text.trim().toLowerCase();
    final list = _allMedicines.where((m) {
      if (kw.isNotEmpty &&
          !m.name.toLowerCase().contains(kw) &&
          !m.category.toLowerCase().contains(kw)) {
        return false;
      }
      switch (_filter) {
        case _Filter.all:
          return true;
        case _Filter.low:
          return !m.isOutOfStock && m.isLowStock;
        case _Filter.out:
          return m.isOutOfStock;
        case _Filter.expiring:
          return m.isExpiringSoon;
        case _Filter.expired:
          return m.hasExpiredStock;
      }
    }).toList();

    if (_sortByExpiry) {
      list.sort((a, b) {
        final ae = a.nextExpiry, be = b.nextExpiry;
        if (ae == null && be == null) return 0;
        if (ae == null) return 1; // no expiry goes last
        if (be == null) return -1;
        return ae.compareTo(be);
      });
    }
    _foundMedicines = list;
  }

  void _setFilter(_Filter f) => setState(() {
        _filter = f;
        _applyFilter();
      });

  int get _totalItems => _allMedicines.length;
  int get _lowCount =>
      _allMedicines.where((m) => !m.isOutOfStock && m.isLowStock).length;
  int get _outCount => _allMedicines.where((m) => m.isOutOfStock).length;
  int get _expiringCount => _allMedicines.where((m) => m.isExpiringSoon).length;
  int get _expiredCount => _allMedicines.where((m) => m.hasExpiredStock).length;

  // ------------------------------------------------------------ snackbars
  void _showSuccess(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: kPrimary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      content: Row(children: [
        const Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(msg, style: const TextStyle(color: Colors.white))),
      ]),
      duration: const Duration(seconds: 2),
    ));
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: kDanger,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      content: Text(msg, style: const TextStyle(color: Colors.white)),
      duration: const Duration(seconds: 4),
    ));
  }

  // -------------------------------------------------------------- actions
  Future<void> _addMedicine() async {
    final r = await showDialog<_FormResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _MedicineFormDialog(existing: _allMedicines),
    );
    if (r == null) return;
    try {
      await MedicineService.create(
        name: r.name,
        maxCapacity: r.maxCapacity,
        category: r.category,
        unit: r.unit,
        initialQty: r.initialQty,
        expiryDate: r.expiry,
        batchNo: r.batchNo,
      );
      await _loadMedicines(showSpinner: false);
      _showSuccess('Medicine added successfully.');
    } catch (e) {
      _showError(_errMsg(e));
    }
  }

  Future<void> _editMedicine(Medicine med) async {
    final r = await showDialog<_FormResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _MedicineFormDialog(existing: _allMedicines, editing: med),
    );
    if (r == null || !mounted) return;

    final ok = await _confirmDialog(
      context,
      icon: Icons.save_outlined,
      color: kPrimary,
      title: 'Update Medicine',
      message: 'Save changes to "${r.name}"?',
      yesLabel: 'Yes, Update',
    );
    if (!ok) return;

    try {
      await MedicineService.update(Medicine(
        id: med.id,
        name: r.name,
        stock: med.stock,
        maxCapacity: r.maxCapacity,
        category: r.category,
        unit: r.unit,
      ));
      await _loadMedicines(showSpinner: false);
      _showSuccess('Medicine updated successfully.');
    } catch (e) {
      _showError(_errMsg(e));
    }
  }

  Future<void> _restockMedicine(Medicine med) async {
    final r = await showDialog<_RestockResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _RestockDialog(med: med),
    );
    if (r == null) return;
    try {
      await MedicineService.restock(
        med: med,
        quantity: r.quantity,
        expiry: r.expiry,
        batchNo: r.batchNo,
      );
      await _loadMedicines(showSpinner: false);
      _showSuccess('Added ${r.quantity} ${med.unit} to ${med.name}.');
    } catch (e) {
      _showError(_errMsg(e));
    }
  }

  Future<void> _openBatches(Medicine med) async {
    await showDialog(
      context: context,
      builder: (_) => _BatchesDialog(med: med),
    );
    await _loadMedicines(showSpinner: false);
  }

  /// DELETE
  ///  - Medicine already used in a clinic visit record: it is NOT deleted and
  ///    a "sorry, cannot be deleted" message is shown.
  ///  - Medicine never used: a confirmation message is shown first, then it
  ///    is deleted (its batches go with it).
  Future<void> _deleteMedicine(Medicine med) async {
    if (med.id == null) return;

    bool used;
    try {
      used = await MedicineService.isUsed(med.id!);
    } catch (e) {
      _showError('Could not check "${med.name}": $e');
      return;
    }
    if (!mounted) return;

    if (used) {
      await _infoDialog(
        context,
        icon: Icons.block_rounded,
        color: kDanger,
        title: 'Cannot Delete',
        message: 'Sorry, "${med.name}" cannot be deleted because it has '
            'already been used in a clinic visit record. Medicine given to '
            'a visitor must stay in the records.',
      );
      return;
    }

    final stockNote = med.stock > 0
        ? '\n\nIt still has ${med.stock} ${med.unit} in stock, which will '
            'be removed too.'
        : '';
    final ok = await _confirmDialog(
      context,
      icon: Icons.delete_outline_rounded,
      color: kDanger,
      title: 'Delete Medicine',
      message: 'Delete "${med.name}" from the inventory? This cannot be '
          'undone.$stockNote',
      yesLabel: 'Yes, Delete',
    );
    if (!ok || !mounted) return;

    try {
      await MedicineService.deleteUnused(med.id!, med.name);
      await _loadMedicines(showSpinner: false);
      _showSuccess('"${med.name}" was deleted.');
    } on MedicineInUseException catch (e) {
      // Someone used it a moment ago: the database refused the delete.
      if (!mounted) return;
      await _infoDialog(
        context,
        icon: Icons.block_rounded,
        color: kDanger,
        title: 'Cannot Delete',
        message: e.toString(),
      );
    } catch (e) {
      _showError('Could not delete: $e');
    }
  }

  // ---------------------------------------------------------------- build
  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: Scaffold(
        backgroundColor: kBg,
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _addMedicine,
          backgroundColor: kPrimary,
          icon: const Icon(Icons.add, color: Colors.white),
          label: const Text('New Medicine',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
        ),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 20),
              _buildQuickStats(),
              if (_expiredCount > 0) ...[
                const SizedBox(height: 12),
                _buildExpiredBanner(),
              ],
              const SizedBox(height: 16),
              _buildSearchSection(),
              const SizedBox(height: 10),
              _buildFilterChips(),
              const SizedBox(height: 12),
              Expanded(
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(color: kPrimary))
                      : _buildTable()),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Row(children: [
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
        child: const Icon(Icons.medication_outlined,
            color: Colors.white, size: 22),
      ),
      const SizedBox(width: 14),
      const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Medicine Inventory',
            style: TextStyle(
                fontSize: 23, fontWeight: FontWeight.w800, color: kTextMain)),
        Text('TCGC Clinic Management',
            style: TextStyle(fontSize: 15, color: kTextSub)),
      ]),
    ]);
  }

  Widget _buildQuickStats() {
    return Row(children: [
      _statCard(Icons.medication_rounded, 'Total Items', _totalItems, kPrimary,
          _Filter.all),
      const SizedBox(width: 10),
      _statCard(Icons.warning_amber_rounded, 'Low Stock', _lowCount, kWarn,
          _Filter.low),
      const SizedBox(width: 10),
      _statCard(Icons.remove_circle_outline, 'Out of Stock', _outCount, kDanger,
          _Filter.out),
      const SizedBox(width: 10),
      _statCard(Icons.schedule_rounded, 'Expiring ≤$kExpiringSoonDays d',
          _expiringCount, kExpiring, _Filter.expiring),
      const SizedBox(width: 10),
      _statCard(Icons.event_busy_rounded, 'Has Expired', _expiredCount, kDanger,
          _Filter.expired),
    ]);
  }

  Widget _statCard(
      IconData icon, String label, int value, Color color, _Filter f) {
    final selected = _filter == f && f != _Filter.all;
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _setFilter(_filter == f ? _Filter.all : f),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: kCard,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
                color: selected ? color : kBorder, width: selected ? 1.5 : 1),
            boxShadow: [
              BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 2))
            ],
          ),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('$value',
                        style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            color: color)),
                    Text(label,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 13,
                            color: kTextSub,
                            fontWeight: FontWeight.w500)),
                  ]),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _buildExpiredBanner() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFEF2F2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFFECACA)),
      ),
      child: Row(children: [
        const Icon(Icons.error_outline_rounded, color: kDanger, size: 20),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '$_expiredCount medicine${_expiredCount == 1 ? ' has' : 's have'} '
            'expired batches on the shelf. They are excluded from usable stock. '
            'Remove them, then open Batches and Discard them.',
            style: const TextStyle(
                color: kDanger, fontWeight: FontWeight.w600, fontSize: 14.5),
          ),
        ),
        TextButton(
          onPressed: () => _setFilter(_Filter.expired),
          child: const Text('View'),
        ),
      ]),
    );
  }

  Widget _buildSearchSection() {
    return TextField(
      controller: _searchCtrl,
      onChanged: (_) => setState(_applyFilter),
      style: const TextStyle(fontSize: 16, color: kTextMain),
      decoration: InputDecoration(
        hintText: 'Search by medicine name or category...',
        hintStyle: const TextStyle(color: kTextSub, fontSize: 16),
        prefixIcon: const Icon(Icons.search_rounded, color: kTextSub, size: 20),
        suffixIcon: _searchCtrl.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () => setState(() {
                  _searchCtrl.clear();
                  _applyFilter();
                }),
              ),
        filled: true,
        fillColor: kCard,
        contentPadding: const EdgeInsets.symmetric(vertical: 13),
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

  Widget _buildFilterChips() {
    Widget chip(String label, _Filter f) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: ChoiceChip(
            label: Text(label),
            selected: _filter == f,
            onSelected: (_) => _setFilter(f),
            selectedColor: kPrimary.withValues(alpha: 0.15),
            labelStyle: TextStyle(
                color: _filter == f ? kPrimary : kTextSub,
                fontWeight: FontWeight.w600),
            side: BorderSide(color: _filter == f ? kPrimary : kBorder),
            backgroundColor: kCard,
          ),
        );

    return Row(children: [
      Expanded(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            chip('All', _Filter.all),
            chip('Low stock', _Filter.low),
            chip('Out of stock', _Filter.out),
            chip('Expiring soon', _Filter.expiring),
            chip('Has expired', _Filter.expired),
          ]),
        ),
      ),
      FilterChip(
        label: const Text('Sort: earliest expiry'),
        selected: _sortByExpiry,
        onSelected: (v) => setState(() {
          _sortByExpiry = v;
          _applyFilter();
        }),
        selectedColor: kPrimary.withValues(alpha: 0.15),
        checkmarkColor: kPrimary,
        backgroundColor: kCard,
        side: BorderSide(color: _sortByExpiry ? kPrimary : kBorder),
      ),
    ]);
  }

  Widget _buildTable() {
    if (_foundMedicines.isEmpty) {
      return Container(
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kBorder),
        ),
        child: Center(
            child:
                Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.search_off_rounded,
              size: 48, color: AppColors.borderStrong),
          const SizedBox(height: 8),
          const Text('No medicines found',
              style: TextStyle(color: kTextSub, fontSize: 17)),
        ])),
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
        child: SingleChildScrollView(
          child: LayoutBuilder(builder: (ctx, con) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: con.maxWidth),
                child: DataTable(
                  headingRowHeight: 52,
                  dataRowMinHeight: 62,
                  dataRowMaxHeight: 72,
                  headingRowColor:
                      WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                  headingTextStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: kTextSub,
                      fontSize: 15,
                      letterSpacing: 0.5),
                  dataTextStyle:
                      const TextStyle(color: kTextMain, fontSize: 16),
                  columnSpacing: 26,
                  horizontalMargin: 20,
                  dividerThickness: 1,
                  border: const TableBorder(
                    horizontalInside: BorderSide(color: kBorder, width: 0.8),
                  ),
                  columns: const [
                    DataColumn(label: Text('ID')),
                    DataColumn(label: Text('MEDICINE')),
                    DataColumn(label: Text('USABLE STOCK')),
                    DataColumn(label: Text('LEVEL')),
                    DataColumn(label: Text('NEXT EXPIRY')),
                    DataColumn(label: Text('STATUS')),
                    DataColumn(label: Text('ACTIONS')),
                  ],
                  rows: _foundMedicines.asMap().entries.map((entry) {
                    final even = entry.key % 2 == 0;
                    final med = entry.value;
                    final st = _statusOf(med);
                    final pct = med.maxCapacity > 0
                        ? med.usableStock / med.maxCapacity
                        : 0.0;
                    final stockColor = med.isOutOfStock
                        ? kDanger
                        : med.isLowStock
                            ? kWarn
                            : kPrimary;
                    final nb = med.nextExpiryBatch;
                    final nBatches = med.batches.length;

                    return DataRow(
                      color: WidgetStateProperty.all(med.hasExpiredStock
                          ? const Color(0xFFFFF5F5)
                          : even
                              ? kCard
                              : const Color(0xFFFAFCFD)),
                      cells: [
                        DataCell(Text(med.id?.toString() ?? '—',
                            style: const TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color: kPrimary))),
                        DataCell(Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(med.name,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600, fontSize: 16)),
                            Text(med.category,
                                style: const TextStyle(
                                    fontSize: 13, color: kTextSub)),
                          ],
                        )),
                        DataCell(Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('${med.usableStock} ${med.unit}',
                                style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 16,
                                    color: stockColor)),
                            if (med.hasExpiredStock)
                              Text('+ ${med.expiredStock} expired',
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      color: kDanger,
                                      fontWeight: FontWeight.w600)),
                          ],
                        )),
                        DataCell(SizedBox(
                          width: 120,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${med.usableStock} / ${med.maxCapacity}',
                                  style: const TextStyle(
                                      fontSize: 13.5, color: kTextSub)),
                              const SizedBox(height: 4),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: pct.clamp(0.0, 1.0),
                                  minHeight: 6,
                                  backgroundColor: const Color(0xFFE2E8F0),
                                  valueColor:
                                      AlwaysStoppedAnimation<Color>(stockColor),
                                ),
                              ),
                            ],
                          ),
                        )),
                        DataCell(nb == null
                            ? Text(
                                nBatches == 0
                                    ? '—'
                                    : 'No expiry · $nBatches batch${nBatches == 1 ? '' : 'es'}',
                                style: const TextStyle(
                                    fontSize: 14, color: kTextSub))
                            : Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(fmtDate(nb.expiryDate!),
                                      style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w600,
                                          color: _batchColor(nb))),
                                  Text(
                                      '${_expiryHint(nb.daysToExpiry)} · $nBatches batch${nBatches == 1 ? '' : 'es'}',
                                      style: TextStyle(
                                          fontSize: 12.5,
                                          color: _batchColor(nb))),
                                ],
                              )),
                        DataCell(_statusBadge(st)),
                        DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                          _actionBtn(
                            icon: Icons.add_box_outlined,
                            color: kGood,
                            tooltip: 'Restock (new delivery)',
                            onTap: () => _restockMedicine(med),
                          ),
                          const SizedBox(width: 4),
                          _actionBtn(
                            icon: Icons.layers_outlined,
                            color: kExpiring,
                            tooltip: 'Batches',
                            onTap: () => _openBatches(med),
                          ),
                          const SizedBox(width: 4),
                          _actionBtn(
                            icon: Icons.edit_outlined,
                            color: kPrimary,
                            tooltip: 'Edit details',
                            onTap: () => _editMedicine(med),
                          ),
                          const SizedBox(width: 4),
                          _actionBtn(
                            icon: Icons.delete_outline_rounded,
                            color: kDanger,
                            tooltip: 'Delete',
                            onTap: () => _deleteMedicine(med),
                          ),
                        ])),
                      ],
                    );
                  }).toList(),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _statusBadge(_Status s) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: s.bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: s.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(s.icon, size: 12, color: s.color),
        const SizedBox(width: 4),
        Text(s.label,
            style: TextStyle(
                color: s.color, fontSize: 13.5, fontWeight: FontWeight.w700)),
      ]),
    );
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
}

// =============================================================================
//  SHARED UI HELPERS
// =============================================================================
Widget _iconCircle(IconData icon, Color color) => Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: Icon(icon, color: color, size: 22),
    );

ButtonStyle _outlinedStyle() => OutlinedButton.styleFrom(
      side: const BorderSide(color: kBorder),
      foregroundColor: kTextSub,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    );

ButtonStyle _filledStyle(Color bg) => ElevatedButton.styleFrom(
      backgroundColor: bg,
      foregroundColor: Colors.white,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
    );

Widget _dlabel(String label) => Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(label,
          style: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w600, color: kTextSub)),
    );

InputDecoration _fieldDeco(String hint, {IconData? prefixIcon}) {
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: kTextSub, fontSize: 16),
    filled: true,
    fillColor: const Color(0xFFFAFCFE),
    prefixIcon:
        prefixIcon != null ? Icon(prefixIcon, size: 18, color: kTextSub) : null,
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
    border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kBorder)),
    enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kBorder)),
    focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        borderSide: BorderSide(color: kPrimary, width: 1.5)),
    errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: kDanger)),
    focusedErrorBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(10)),
        borderSide: BorderSide(color: kDanger, width: 1.5)),
  );
}

Widget _dialogHeader(
    BuildContext ctx, IconData icon, String title, String subtitle) {
  return Row(children: [
    Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: kPrimary.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, color: kPrimary, size: 20),
    ),
    const SizedBox(width: 12),
    Expanded(
        child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: const TextStyle(
                fontSize: 20, fontWeight: FontWeight.w700, color: kTextMain)),
        Text(subtitle,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 15, color: kTextSub)),
      ],
    )),
    IconButton(
      onPressed: () => Navigator.pop(ctx),
      icon: const Icon(Icons.close_rounded, color: kTextSub),
      iconSize: 20,
    ),
  ]);
}

String? _requiredInt(String? v, {bool allowZero = true}) {
  if (v == null || v.trim().isEmpty) return 'Required';
  final n = int.tryParse(v);
  if (n == null) return 'Must be a number';
  if (!allowZero && n <= 0) return 'Must be more than 0';
  return null;
}

Future<bool> _confirmDialog(
  BuildContext context, {
  required IconData icon,
  required Color color,
  required String title,
  required String message,
  required String yesLabel,
}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: Colors.white,
      child: SizedBox(
        width: 340,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _iconCircle(icon, color),
            const SizedBox(height: 12),
            Text(title,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: kTextMain)),
            const SizedBox(height: 6),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 15, color: kTextSub, height: 1.5)),
            const SizedBox(height: 20),
            Row(children: [
              Expanded(
                  child: OutlinedButton(
                onPressed: () => Navigator.pop(ctx, false),
                style: _outlinedStyle(),
                child: const Text('Cancel'),
              )),
              const SizedBox(width: 10),
              Expanded(
                  child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: _filledStyle(color),
                child: Text(yesLabel,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              )),
            ]),
          ]),
        ),
      ),
    ),
  );
  return res ?? false;
}

/// A message with a single OK button (for "cannot be deleted" and similar).
Future<void> _infoDialog(
  BuildContext context, {
  required IconData icon,
  required Color color,
  required String title,
  required String message,
  String okLabel = 'OK',
}) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      backgroundColor: Colors.white,
      child: SizedBox(
        width: 340,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            _iconCircle(icon, color),
            const SizedBox(height: 12),
            Text(title,
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: kTextMain)),
            const SizedBox(height: 6),
            Text(message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 15, color: kTextSub, height: 1.5)),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => Navigator.pop(ctx),
                style: _filledStyle(color),
                child: Text(okLabel,
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ),
            ),
          ]),
        ),
      ),
    ),
  );
}

/// Tappable date field that looks like a text field.
class _DateField extends StatelessWidget {
  final DateTime? value;
  final String hint;
  final String? errorText;
  final DateTime firstDate;
  final DateTime lastDate;
  final ValueChanged<DateTime> onPicked;

  const _DateField({
    required this.value,
    required this.hint,
    required this.firstDate,
    required this.lastDate,
    required this.onPicked,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: () async {
        final now = DateTime.now();
        var initial = value ?? DateTime(now.year, now.month + 6, now.day);
        if (initial.isBefore(firstDate)) initial = firstDate;
        if (initial.isAfter(lastDate)) initial = lastDate;
        final picked = await showDatePicker(
          context: context,
          initialDate: initial,
          firstDate: firstDate,
          lastDate: lastDate,
          helpText: 'SELECT EXPIRY DATE',
        );
        if (picked != null) onPicked(picked);
      },
      child: InputDecorator(
        decoration: _fieldDeco(hint, prefixIcon: Icons.event_outlined)
            .copyWith(errorText: errorText),
        child: Text(
          value == null ? hint : fmtDate(value!),
          style: TextStyle(
              fontSize: 16, color: value == null ? kTextSub : kTextMain),
        ),
      ),
    );
  }
}

// =============================================================================
//  NEW / EDIT MEDICINE FORM
//  New  = details + first batch.   Edit = details only (stock lives in batches)
// =============================================================================
class _FormResult {
  final String name, category, unit;
  final int maxCapacity, initialQty;
  final DateTime? expiry;
  final String? batchNo;
  const _FormResult({
    required this.name,
    required this.category,
    required this.unit,
    required this.maxCapacity,
    required this.initialQty,
    this.expiry,
    this.batchNo,
  });
}

class _MedicineFormDialog extends StatefulWidget {
  final List<Medicine> existing;
  final Medicine? editing;
  const _MedicineFormDialog({required this.existing, this.editing});

  @override
  State<_MedicineFormDialog> createState() => _MedicineFormDialogState();
}

class _MedicineFormDialogState extends State<_MedicineFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _max;
  final _stock = TextEditingController(text: '0');
  final _batch = TextEditingController();
  late String _category;
  late String _unit;
  bool _hasExpiry = true;
  DateTime? _expiry;
  bool _expiryTouched = false;

  bool get _isEdit => widget.editing != null;
  int get _qty => int.tryParse(_stock.text) ?? 0;

  @override
  void initState() {
    super.initState();
    final m = widget.editing;
    _name = TextEditingController(text: m?.name ?? '');
    _max = TextEditingController(text: m?.maxCapacity.toString() ?? '');
    _category = m?.category ?? kMedicineCategories.first;
    _unit = m?.unit ?? kMedicineUnits.first;
  }

  @override
  void dispose() {
    _name.dispose();
    _max.dispose();
    _stock.dispose();
    _batch.dispose();
    super.dispose();
  }

  String _key(String s) => normalizeName(s).toLowerCase();

  bool _isExactDuplicate(String name) {
    final k = _key(name);
    return widget.existing
        .any((m) => m.id != widget.editing?.id && _key(m.name) == k);
  }

  /// A different medicine whose name contains / is contained in this one.
  Medicine? _similar() {
    final n = _key(_name.text);
    if (n.length < 3) return null;
    for (final m in widget.existing) {
      if (m.id == widget.editing?.id) continue;
      final o = _key(m.name);
      if (o == n) continue; // exact match is handled by the validator
      if (o.contains(n) || n.contains(o)) return m;
    }
    return null;
  }

  String? _expiryError() {
    if (!_isEdit && _hasExpiry && _qty > 0 && _expiry == null && _expiryTouched) {
      return 'Expiry date is required';
    }
    return null;
  }

  void _submit() {
    setState(() => _expiryTouched = true);
    if (!_formKey.currentState!.validate()) return;
    if (!_isEdit && _hasExpiry && _qty > 0 && _expiry == null) return;

    Navigator.pop(
      context,
      _FormResult(
        name: normalizeName(_name.text),
        category: _category,
        unit: _unit,
        maxCapacity: int.parse(_max.text),
        initialQty: _isEdit ? 0 : _qty,
        expiry: (!_isEdit && _hasExpiry && _qty > 0) ? _expiry : null,
        batchNo: _batch.text.trim().isEmpty ? null : _batch.text.trim(),
      ),
    );
  }

  Widget _dropdown(String label, String value, List<String> items,
      ValueChanged<String> onChanged) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _dlabel(label),
      DropdownButtonFormField<String>(
        initialValue: value,
        isExpanded: true,
        decoration: _fieldDeco(''),
        items: items
            .map((e) => DropdownMenuItem(value: e, child: Text(e)))
            .toList(),
        onChanged: (v) => onChanged(v ?? value),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final similar = _similar();

    return Dialog(
      backgroundColor: kCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SingleChildScrollView(
        child: Container(
          width: 520,
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _dialogHeader(
                    context,
                    _isEdit ? Icons.edit_outlined : Icons.add_circle_outline,
                    _isEdit ? 'Edit Medicine Details' : 'New Medicine',
                    _isEdit
                        ? 'Name, category, unit and capacity'
                        : 'Only for medicines not yet in the list'),
                const SizedBox(height: 14),
                if (!_isEdit)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF0F9FF),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFFBAE6FD)),
                    ),
                    child: const Text(
                      'Already have this medicine? Close this and use the green '
                      'Restock button on its row instead.',
                      style: TextStyle(fontSize: 13.5, color: Color(0xFF0369A1)),
                    ),
                  ),
                const Divider(color: kBorder, height: 1),
                const SizedBox(height: 16),
                _dlabel('Medicine Name (include strength)'),
                TextFormField(
                  controller: _name,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(fontSize: 16, color: kTextMain),
                  validator: (v) {
                    final n = normalizeName(v ?? '');
                    if (n.isEmpty) return 'Medicine name is required';
                    if (_isExactDuplicate(n)) {
                      return 'Already in inventory. Use Restock to add stock.';
                    }
                    return null;
                  },
                  decoration: _fieldDeco('e.g. Paracetamol 500mg',
                      prefixIcon: Icons.medication_outlined),
                ),
                if (similar != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(
                      'Similar item exists: "${similar.name}". If it is the '
                      'same medicine, restock it instead.',
                      style: const TextStyle(
                          fontSize: 13, color: kExpiring, height: 1.4),
                    ),
                  ),
                const SizedBox(height: 12),
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                      child: _dropdown('Category', _category,
                          kMedicineCategories, (v) => setState(() => _category = v))),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _dropdown('Unit', _unit, kMedicineUnits,
                          (v) => setState(() => _unit = v))),
                ]),
                const SizedBox(height: 12),
                _dlabel('Max Capacity (most you can store)'),
                TextFormField(
                  controller: _max,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(fontSize: 16, color: kTextMain),
                  validator: (v) {
                    final e = _requiredInt(v, allowZero: false);
                    if (e != null) return e;
                    if (_isEdit && int.parse(v!) < widget.editing!.stock) {
                      return 'Less than stock on hand (${widget.editing!.stock})';
                    }
                    return null;
                  },
                  decoration: _fieldDeco('e.g. 200',
                      prefixIcon: Icons.bar_chart_outlined),
                ),
                if (_isEdit)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: Text(
                      'To change stock or expiry, use Restock (new delivery) or '
                      'Batches (corrections).',
                      style: TextStyle(fontSize: 13, color: kTextSub),
                    ),
                  ),
                if (!_isEdit) ...[
                  const SizedBox(height: 18),
                  const Divider(color: kBorder, height: 1),
                  const SizedBox(height: 14),
                  const Text('First batch (optional)',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: kTextMain)),
                  const SizedBox(height: 10),
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          _dlabel('Quantity on hand'),
                          TextFormField(
                            controller: _stock,
                            onChanged: (_) => setState(() {}),
                            keyboardType: TextInputType.number,
                            inputFormatters: [
                              FilteringTextInputFormatter.digitsOnly
                            ],
                            style:
                                const TextStyle(fontSize: 16, color: kTextMain),
                            validator: (v) {
                              final e = _requiredInt(v);
                              if (e != null) return e;
                              final max = int.tryParse(_max.text);
                              if (max != null && int.parse(v!) > max) {
                                return 'More than capacity';
                              }
                              return null;
                            },
                            decoration: _fieldDeco('0',
                                prefixIcon: Icons.inventory_2_outlined),
                          ),
                        ])),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                          _dlabel('Batch / Lot No.'),
                          TextFormField(
                            controller: _batch,
                            style:
                                const TextStyle(fontSize: 16, color: kTextMain),
                            decoration: _fieldDeco('Optional',
                                prefixIcon: Icons.tag_rounded),
                          ),
                        ])),
                  ]),
                  if (_qty > 0) ...[
                    const SizedBox(height: 10),
                    Row(children: [
                      Switch(
                        value: _hasExpiry,
                        activeColor: kPrimary,
                        onChanged: (v) => setState(() => _hasExpiry = v),
                      ),
                      const SizedBox(width: 6),
                      const Expanded(
                        child: Text('This batch has an expiry date',
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: kTextSub)),
                      ),
                    ]),
                    if (_hasExpiry) ...[
                      const SizedBox(height: 8),
                      _dlabel('Expiry Date'),
                      _DateField(
                        value: _expiry,
                        hint: 'Select date',
                        errorText: _expiryError(),
                        firstDate: today, // can't receive already-expired stock
                        lastDate: DateTime(today.year + 10),
                        onPicked: (d) => setState(() {
                          _expiry = d;
                          _expiryTouched = true;
                        }),
                      ),
                    ],
                  ],
                ],
                const SizedBox(height: 22),
                const Divider(color: kBorder, height: 1),
                const SizedBox(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: _outlinedStyle(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: _submit,
                    icon: Icon(_isEdit ? Icons.save_outlined : Icons.add,
                        size: 16),
                    label: Text(_isEdit ? 'Update' : 'Add Medicine',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    style: _filledStyle(kPrimary),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
//  RESTOCK  (new delivery -> new batch)
// =============================================================================
class _RestockResult {
  final int quantity;
  final DateTime? expiry;
  final String? batchNo;
  const _RestockResult(this.quantity, this.expiry, this.batchNo);
}

class _RestockDialog extends StatefulWidget {
  final Medicine med;
  const _RestockDialog({required this.med});

  @override
  State<_RestockDialog> createState() => _RestockDialogState();
}

class _RestockDialogState extends State<_RestockDialog> {
  final _formKey = GlobalKey<FormState>();
  final _qty = TextEditingController();
  final _batch = TextEditingController();
  late bool _hasExpiry;
  DateTime? _expiry;
  bool _expiryTouched = false;

  @override
  void initState() {
    super.initState();
    final b = widget.med.batches;
    // Items that never expire (e.g. bandages) default to "no expiry".
    _hasExpiry = !(b.isNotEmpty && b.every((x) => x.expiryDate == null));
  }

  @override
  void dispose() {
    _qty.dispose();
    _batch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final med = widget.med;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final space = med.maxCapacity - med.stock;

    return Dialog(
      backgroundColor: kCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SingleChildScrollView(
        child: Container(
          width: 440,
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _dialogHeader(
                    context, Icons.add_box_outlined, 'Restock', med.name),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: kBorder),
                  ),
                  child: Text(
                    'On hand: ${med.stock} ${med.unit} of ${med.maxCapacity} '
                    '(${med.batches.length} batch${med.batches.length == 1 ? '' : 'es'})\n'
                    'This delivery will be added as its own batch.',
                    style: const TextStyle(
                        fontSize: 14.5, color: kTextSub, height: 1.5),
                  ),
                ),
                const SizedBox(height: 16),
                _dlabel('Quantity Received'),
                TextFormField(
                  controller: _qty,
                  autofocus: true,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(fontSize: 16, color: kTextMain),
                  validator: (v) {
                    final e = _requiredInt(v, allowZero: false);
                    if (e != null) return e;
                    if (med.maxCapacity > 0 && int.parse(v!) > space) {
                      return space <= 0
                          ? 'At capacity. Discard expired batches first.'
                          : 'Only room for $space more';
                    }
                    return null;
                  },
                  decoration: _fieldDeco('e.g. 100',
                      prefixIcon: Icons.inventory_2_outlined),
                ),
                const SizedBox(height: 12),
                _dlabel('Batch / Lot No. (on the box)'),
                TextFormField(
                  controller: _batch,
                  style: const TextStyle(fontSize: 16, color: kTextMain),
                  decoration:
                      _fieldDeco('Optional', prefixIcon: Icons.tag_rounded),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Switch(
                    value: _hasExpiry,
                    activeColor: kPrimary,
                    onChanged: (v) => setState(() => _hasExpiry = v),
                  ),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text('This batch has an expiry date',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: kTextSub)),
                  ),
                ]),
                if (_hasExpiry) ...[
                  const SizedBox(height: 8),
                  _dlabel('Expiry Date of this Batch'),
                  _DateField(
                    value: _expiry,
                    hint: 'Select date',
                    errorText: (_expiryTouched && _expiry == null)
                        ? 'Expiry date is required'
                        : null,
                    firstDate: today,
                    lastDate: DateTime(today.year + 10),
                    onPicked: (d) => setState(() {
                      _expiry = d;
                      _expiryTouched = true;
                    }),
                  ),
                ],
                const SizedBox(height: 10),
                const Text(
                  'Same batch no. + same expiry as a batch already on hand? '
                  'It is added to that batch, so no duplicate batch is created.',
                  style: TextStyle(fontSize: 12.5, color: kTextSub),
                ),
                const SizedBox(height: 18),
                const Divider(color: kBorder, height: 1),
                const SizedBox(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: _outlinedStyle(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() => _expiryTouched = true);
                      if (!_formKey.currentState!.validate()) return;
                      if (_hasExpiry && _expiry == null) return;
                      Navigator.pop(
                        context,
                        _RestockResult(
                          int.parse(_qty.text),
                          _hasExpiry ? _expiry : null,
                          _batch.text.trim().isEmpty
                              ? null
                              : _batch.text.trim(),
                        ),
                      );
                    },
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add Stock',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    style: _filledStyle(kPrimary),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// =============================================================================
//  BATCHES  (view, correct, discard)
// =============================================================================
class _BatchesDialog extends StatefulWidget {
  final Medicine med;
  const _BatchesDialog({required this.med});

  @override
  State<_BatchesDialog> createState() => _BatchesDialogState();
}

class _BatchesDialogState extends State<_BatchesDialog> {
  late List<MedicineBatch> _batches;
  String? _error;

  @override
  void initState() {
    super.initState();
    _batches = List.of(widget.med.batches);
  }

  int get _total => _batches.fold(0, (s, b) => s + b.quantity);
  int get _expired =>
      _batches.where((b) => b.isExpired).fold(0, (s, b) => s + b.quantity);

  Future<void> _edit(MedicineBatch b) async {
    final updated = await showDialog<MedicineBatch>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _BatchEditDialog(batch: b, unit: widget.med.unit),
    );
    if (updated == null) return;
    try {
      await MedicineService.updateBatch(updated);
      setState(() {
        _error = null;
        final i = _batches.indexWhere((x) => x.id == b.id);
        if (i >= 0) _batches[i] = updated;
      });
    } catch (e) {
      setState(() => _error = _errMsg(e));
    }
  }

  Future<void> _discard(MedicineBatch b) async {
    final ok = await _confirmDialog(
      context,
      icon: Icons.delete_outline_rounded,
      color: kDanger,
      title: 'Discard Batch',
      message: 'Remove ${b.quantity} ${widget.med.unit} '
          '${b.batchNo == null ? '' : '(batch ${b.batchNo}) '}from stock? '
          'Use this for expired, damaged or recalled stock.',
      yesLabel: 'Discard',
    );
    if (!ok) return;
    try {
      await MedicineService.deleteBatch(b.id!);
      setState(() {
        _error = null;
        _batches.removeWhere((x) => x.id == b.id);
      });
    } catch (e) {
      setState(() => _error = _errMsg(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final med = widget.med;
    final sorted = List.of(_batches)
      ..sort((a, b) {
        if (a.expiryDate == null && b.expiryDate == null) return 0;
        if (a.expiryDate == null) return 1;
        if (b.expiryDate == null) return -1;
        return a.expiryDate!.compareTo(b.expiryDate!);
      });

    return Dialog(
      backgroundColor: kCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: 640,
        constraints: const BoxConstraints(maxHeight: 620),
        padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _dialogHeader(context, Icons.layers_outlined, 'Batches', med.name),
            const SizedBox(height: 10),
            Text(
              'Total on hand: $_total ${med.unit}'
              '${_expired > 0 ? '  ·  $_expired expired' : ''}',
              style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  color: _expired > 0 ? kDanger : kTextSub),
            ),
            const SizedBox(height: 4),
            const Text(
              'Dispensing uses the batch that expires first. Expired batches are never used.',
              style: TextStyle(fontSize: 12.5, color: kTextSub),
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: kDanger)),
            ],
            const SizedBox(height: 12),
            const Divider(color: kBorder, height: 1),
            Flexible(
              child: sorted.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 32),
                      child: Center(
                          child: Text('No stock on hand. Use Restock to add a batch.',
                              style: TextStyle(color: kTextSub, fontSize: 15))),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: sorted.length,
                      separatorBuilder: (_, __) =>
                          const Divider(color: kBorder, height: 1),
                      itemBuilder: (_, i) => _batchRow(sorted[i], med.unit),
                    ),
            ),
            const Divider(color: kBorder, height: 1),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton(
                onPressed: () => Navigator.pop(context),
                style: _outlinedStyle(),
                child: const Text('Close'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _batchRow(MedicineBatch b, String unit) {
    final color = _batchColor(b);
    final label = b.isExpired
        ? 'EXPIRED'
        : b.isExpiringSoon
            ? 'EXPIRING'
            : 'OK';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        Expanded(
          flex: 3,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                (b.batchNo == null || b.batchNo!.isEmpty)
                    ? 'No batch no.'
                    : 'Batch ${b.batchNo}',
                style: const TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                    color: kTextMain)),
            Text(
                b.receivedAt == null
                    ? ''
                    : 'Received ${fmtDate(b.receivedAt!.toLocal())}',
                style: const TextStyle(fontSize: 12.5, color: kTextSub)),
          ]),
        ),
        Expanded(
          flex: 2,
          child: Text('${b.quantity} $unit',
              style: const TextStyle(
                  fontSize: 15.5,
                  fontWeight: FontWeight.w700,
                  color: kTextMain)),
        ),
        Expanded(
          flex: 3,
          child: b.expiryDate == null
              ? const Text('No expiry',
                  style: TextStyle(fontSize: 14, color: kTextSub))
              : Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(fmtDate(b.expiryDate!),
                      style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          color: color)),
                  Text(_expiryHint(b.daysToExpiry),
                      style: TextStyle(fontSize: 12.5, color: color)),
                ]),
        ),
        SizedBox(
          width: 82,
          child: Text(label,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: b.isExpired || b.isExpiringSoon ? color : kGood)),
        ),
        IconButton(
          tooltip: 'Correct this batch',
          onPressed: () => _edit(b),
          icon: const Icon(Icons.edit_outlined, size: 18, color: kPrimary),
        ),
        IconButton(
          tooltip: 'Discard this batch',
          onPressed: () => _discard(b),
          icon: const Icon(Icons.delete_outline_rounded,
              size: 18, color: kDanger),
        ),
      ]),
    );
  }
}

class _BatchEditDialog extends StatefulWidget {
  final MedicineBatch batch;
  final String unit;
  const _BatchEditDialog({required this.batch, required this.unit});

  @override
  State<_BatchEditDialog> createState() => _BatchEditDialogState();
}

class _BatchEditDialogState extends State<_BatchEditDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _qty;
  late final TextEditingController _batch;
  late bool _hasExpiry;
  DateTime? _expiry;
  bool _touched = false;

  @override
  void initState() {
    super.initState();
    _qty = TextEditingController(text: widget.batch.quantity.toString());
    _batch = TextEditingController(text: widget.batch.batchNo ?? '');
    _expiry = widget.batch.expiryDate;
    _hasExpiry = _expiry != null;
  }

  @override
  void dispose() {
    _qty.dispose();
    _batch.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    return Dialog(
      backgroundColor: kCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SingleChildScrollView(
        child: Container(
          width: 420,
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _dialogHeader(context, Icons.edit_outlined, 'Correct Batch',
                    'Fix a count or date entered by mistake'),
                const SizedBox(height: 16),
                _dlabel('Quantity (${widget.unit})'),
                TextFormField(
                  controller: _qty,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(fontSize: 16, color: kTextMain),
                  validator: (v) {
                    final e = _requiredInt(v, allowZero: false);
                    return e == null
                        ? null
                        : (e == 'Must be more than 0'
                            ? 'Use Discard to remove the batch'
                            : e);
                  },
                  decoration: _fieldDeco('Quantity',
                      prefixIcon: Icons.inventory_2_outlined),
                ),
                const SizedBox(height: 12),
                _dlabel('Batch / Lot No.'),
                TextFormField(
                  controller: _batch,
                  style: const TextStyle(fontSize: 16, color: kTextMain),
                  decoration:
                      _fieldDeco('Optional', prefixIcon: Icons.tag_rounded),
                ),
                const SizedBox(height: 10),
                Row(children: [
                  Switch(
                    value: _hasExpiry,
                    activeColor: kPrimary,
                    onChanged: (v) => setState(() => _hasExpiry = v),
                  ),
                  const SizedBox(width: 6),
                  const Expanded(
                    child: Text('Has an expiry date',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: kTextSub)),
                  ),
                ]),
                if (_hasExpiry) ...[
                  const SizedBox(height: 8),
                  _DateField(
                    value: _expiry,
                    hint: 'Select date',
                    errorText: (_touched && _expiry == null)
                        ? 'Expiry date is required'
                        : null,
                    firstDate: DateTime(2020),
                    lastDate: DateTime(now.year + 10),
                    onPicked: (d) => setState(() => _expiry = d),
                  ),
                ],
                const SizedBox(height: 20),
                const Divider(color: kBorder, height: 1),
                const SizedBox(height: 16),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: _outlinedStyle(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () {
                      setState(() => _touched = true);
                      if (!_formKey.currentState!.validate()) return;
                      if (_hasExpiry && _expiry == null) return;
                      Navigator.pop(
                        context,
                        MedicineBatch(
                          id: widget.batch.id,
                          medicineId: widget.batch.medicineId,
                          quantity: int.parse(_qty.text),
                          batchNo: _batch.text.trim().isEmpty
                              ? null
                              : _batch.text.trim(),
                          expiryDate: _hasExpiry ? _expiry : null,
                          receivedAt: widget.batch.receivedAt,
                        ),
                      );
                    },
                    icon: const Icon(Icons.save_outlined, size: 16),
                    label: const Text('Save',
                        style: TextStyle(fontWeight: FontWeight.w600)),
                    style: _filledStyle(kPrimary),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }
}