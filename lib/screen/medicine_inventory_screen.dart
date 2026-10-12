import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../services/archive_service.dart';
import '../services/data_tracker.dart';
import '../services/medicine_service.dart';
import 'app_colors.dart';

class MedicineInventoryScreen extends StatefulWidget {
  const MedicineInventoryScreen({super.key});

  @override
  State<MedicineInventoryScreen> createState() =>
      _MedicineInventoryScreenState();
}

class _MedicineInventoryScreenState extends State<MedicineInventoryScreen>
    with SingleTickerProviderStateMixin {
  // ── DESIGN TOKENS (single source of truth: app_colors.dart) ────────────
  static const Color kPrimary = AppColors.primary;
  static const Color kPrimaryDk = AppColors.primaryDark;
  static const Color kCard = AppColors.surface;
  static const Color kBorder = AppColors.border;
  static const Color kTextMain = AppColors.textMain;
  static const Color kTextSub = AppColors.textSub;
  static const Color kDanger = AppColors.danger;
  static const Color kBg = AppColors.bgAlt;

  // ── STATE ─────────────────────────────────────────────────────────────
  bool _isLoading = true;
  Medicine? _editingMedicine;

  List<Medicine> _allMedicines = [];
  List<Medicine> _foundMedicines = [];

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _stockController = TextEditingController();
  final TextEditingController _maxController = TextEditingController();

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
    _dataListener = () => _loadMedicines();
    DataTracker.listen(_dataListener!);
  }

  Future<void> _loadMedicines() async {
    setState(() => _isLoading = true);
    try {
      final meds = await MedicineService.fetchAll();
      meds.sort((a, b) {
        final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return byName != 0 ? byName : (a.id ?? 0).compareTo(b.id ?? 0);
      });
      setState(() {
        _allMedicines = meds;
        _foundMedicines = List.from(_allMedicines);
        _isLoading = false;
      });
    } catch (e) {
      setState(() => _isLoading = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          backgroundColor: kDanger,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          content: Text('Failed to load medicines: $e',
              style: const TextStyle(color: Colors.white)),
          duration: const Duration(seconds: 3),
        ));
      }
    }
  }

  @override
  void dispose() {
    if (_dataListener != null) DataTracker.unlisten(_dataListener!);
    _fadeCtrl.dispose();
    _nameController.dispose();
    _stockController.dispose();
    _maxController.dispose();
    super.dispose();
  }

  // ── HELPERS ───────────────────────────────────────────────────────────

  void _runFilter(String kw) {
    setState(() {
      _foundMedicines = _allMedicines
          .where((m) => m.name.toLowerCase().contains(kw.toLowerCase()))
          .toList();
    });
  }

  int get _totalItems => _allMedicines.length;
  int get _lowOrOut => _allMedicines.where((m) => m.stock <= 15).length;
  int get _outOfStock => _allMedicines.where((m) => m.stock == 0).length;

  // ── SNACKBAR ──────────────────────────────────────────────────────────

  void _showSuccess(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: kPrimary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      content: Row(children: [
        const Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
        const SizedBox(width: 10),
        Text(msg, style: const TextStyle(color: Colors.white)),
      ]),
      duration: const Duration(seconds: 2),
    ));
  }

  // ── ADD / EDIT DIALOG ─────────────────────────────────────────────────

  void _showAddDialog() {
    final isEdit = _editingMedicine != null;
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        backgroundColor: kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Container(
          width: 440,
          padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header
                Row(children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: kPrimary.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      isEdit ? Icons.edit_outlined : Icons.add_circle_outline,
                      color: kPrimary,
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        isEdit ? 'Edit Medicine' : 'Add New Medicine',
                        style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                            color: kTextMain),
                      ),
                      Text(
                        isEdit
                            ? 'Update inventory entry'
                            : 'Add entry to inventory',
                        style: const TextStyle(fontSize: 15, color: kTextSub),
                      ),
                    ],
                  )),
                  IconButton(
                    onPressed: () => Navigator.pop(ctx),
                    icon: const Icon(Icons.close_rounded, color: kTextSub),
                    iconSize: 20,
                  ),
                ]),

                const SizedBox(height: 18),
                const Divider(color: kBorder, height: 1),
                const SizedBox(height: 18),

                // Medicine Name
                _dlabel('Medicine Name'),
                TextFormField(
                  controller: _nameController,
                  style: const TextStyle(fontSize: 16, color: kTextMain),
                  validator: (v) => v == null || v.isEmpty
                      ? 'Medicine name is required'
                      : null,
                  decoration: _fieldDeco('e.g. Paracetamol',
                      prefixIcon: Icons.medication_outlined),
                ),
                const SizedBox(height: 12),

                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  // Stock
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        _dlabel('Current Stock'),
                        TextFormField(
                          controller: _stockController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          style:
                              const TextStyle(fontSize: 16, color: kTextMain),
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Required';
                            if (int.tryParse(v) == null)
                              return 'Must be a number';
                            return null;
                          },
                          decoration: _fieldDeco('e.g. 50',
                              prefixIcon: Icons.inventory_2_outlined),
                        ),
                      ])),
                  const SizedBox(width: 12),
                  // Max
                  Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                        _dlabel('Max Capacity'),
                        TextFormField(
                          controller: _maxController,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly
                          ],
                          style:
                              const TextStyle(fontSize: 16, color: kTextMain),
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'Required';
                            if (int.tryParse(v) == null)
                              return 'Must be a number';
                            return null;
                          },
                          decoration: _fieldDeco('e.g. 200',
                              prefixIcon: Icons.bar_chart_outlined),
                        ),
                      ])),
                ]),

                const SizedBox(height: 24),
                const Divider(color: kBorder, height: 1),
                const SizedBox(height: 16),

                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  OutlinedButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: kBorder),
                      foregroundColor: kTextSub,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () {
                      if (!formKey.currentState!.validate()) return;
                      Navigator.pop(ctx);
                      _saveNewMedicine();
                    },
                    icon: Icon(isEdit ? Icons.save_outlined : Icons.add,
                        size: 16),
                    label: Text(isEdit ? 'Update' : 'Add Medicine',
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── SAVE ──────────────────────────────────────────────────────────────

  void _saveNewMedicine() async {
    final String name = _nameController.text.trim();
    final int? stock = int.tryParse(_stockController.text);
    final int? max = int.tryParse(_maxController.text);
    if (name.isEmpty || stock == null || max == null) return;

    final bool isEditing = _editingMedicine != null;

    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Colors.white,
        child: SizedBox(
          width: 300,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: kPrimary.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isEditing ? Icons.save_outlined : Icons.add_circle_outline,
                  color: kPrimary,
                  size: 22,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                isEditing ? 'Update Medicine' : 'Add Medicine',
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: kTextMain),
              ),
              const SizedBox(height: 6),
              Text(
                isEditing
                    ? 'Are you sure you want to save changes to this entry?'
                    : 'Are you sure you want to add "$name" to the inventory?',
                textAlign: TextAlign.center,
                style:
                    const TextStyle(fontSize: 15, color: kTextSub, height: 1.5),
              ),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                    child: OutlinedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _showAddDialog();
                  },
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: kBorder),
                    foregroundColor: kTextSub,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: const Text('Cancel', style: TextStyle(fontSize: 15)),
                )),
                const SizedBox(width: 10),
                Expanded(
                    child: ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    try {
                      if (isEditing) {
                        await MedicineService.update(Medicine(
                          id: _editingMedicine!.id,
                          name: name,
                          stock: stock,
                          maxCapacity: max,
                        ));
                      } else {
                        // If a medicine with the same name exists, increment stock
                        final existing = _allMedicines.firstWhere(
                          (m) => m.name.toLowerCase() == name.toLowerCase(),
                          orElse: () => const Medicine(
                              name: '', stock: 0, maxCapacity: 0),
                        );
                        if (existing.id != null) {
                          await MedicineService.update(Medicine(
                            id: existing.id,
                            name: existing.name,
                            stock: existing.stock + stock,
                            maxCapacity: existing.maxCapacity,
                          ));
                        } else {
                          await MedicineService.create(
                            name: name,
                            stock: stock,
                            maxCapacity: max,
                          );
                        }
                      }
                      _editingMedicine = null;
                      _nameController.clear();
                      _stockController.clear();
                      _maxController.clear();
                      await _loadMedicines();
                      if (mounted) {
                        _showSuccess(isEditing
                            ? 'Medicine updated successfully.'
                            : 'Medicine added successfully.');
                      }
                    } catch (e) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          backgroundColor: kDanger,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          content: Text('Error: $e',
                              style: const TextStyle(color: Colors.white)),
                        ));
                      }
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: Text(
                    isEditing ? 'Yes, Update' : 'Yes, Add',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 15),
                  ),
                )),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  // ── EDIT ──────────────────────────────────────────────────────────────

  void _editMedicine(int index) {
    final med = _foundMedicines[index];
    _nameController.text = med.name;
    _stockController.text = med.stock.toString();
    _maxController.text = med.maxCapacity.toString();
    _editingMedicine = med;
    _showAddDialog();
  }

  // ── DELETE (soft-archive to Trash) ───────────────────────────────────

  void _deleteMedicine(int index) {
    final med = _foundMedicines[index];
    String selectedReason = 'Discontinued';
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Colors.white,
        child: SizedBox(
          width: 340,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: kDanger.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.delete_outline_rounded,
                        color: kDanger, size: 22),
                  ),
                  const SizedBox(height: 12),
                  const Text('Archive Medicine',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: kTextMain)),
                  const SizedBox(height: 6),
                  Text(
                    'Move "${med.name}" to the Trash instead of deleting it? '
                    'Past dispense history referencing it stays intact and it can be restored later.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 14, color: kTextSub, height: 1.5),
                  ),
                  const SizedBox(height: 16),
                  const Text('Reason (optional)',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: kTextSub)),
                  const SizedBox(height: 6),
                  DropdownButtonFormField<String>(
                    initialValue: selectedReason,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: const Color(0xFFF8FAFC),
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                    ),
                    items: const [
                      'Discontinued',
                      'Recalled',
                      'Expired',
                      'Obsolete',
                      'Other'
                    ]
                        .map((r) => DropdownMenuItem(value: r, child: Text(r)))
                        .toList(),
                    onChanged: (v) => selectedReason = v ?? 'Discontinued',
                  ),
                  const SizedBox(height: 20),
                  Row(children: [
                    Expanded(
                        child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: kBorder),
                        foregroundColor: kTextSub,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      child:
                          const Text('Cancel', style: TextStyle(fontSize: 15)),
                    )),
                    const SizedBox(width: 10),
                    Expanded(
                        child: ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(context);
                        try {
                          await ArchiveService.archiveMedicine(
                              med.id!, med.name, med.stock,
                              reason: selectedReason);
                          await _loadMedicines();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              backgroundColor: kDanger,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              content: const Row(children: [
                                Icon(Icons.check_circle_outline,
                                    color: Colors.white, size: 18),
                                SizedBox(width: 10),
                                Text('Medicine moved to Trash.',
                                    style: TextStyle(color: Colors.white)),
                              ]),
                              duration: const Duration(seconds: 2),
                            ));
                          }
                        } catch (e) {
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                              backgroundColor: kDanger,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10)),
                              content: Text('Error archiving: $e',
                                  style: const TextStyle(color: Colors.white)),
                            ));
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kDanger,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                      child: const Text('Archive',
                          style: TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 15)),
                    )),
                  ]),
                ]),
          ),
        ),
      ),
    );
  }

  // ── BUILD ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: Scaffold(
        backgroundColor: kBg,
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            _editingMedicine = null;
            _nameController.clear();
            _stockController.clear();
            _maxController.clear();
            _showAddDialog();
          },
          backgroundColor: kPrimary,
          child: const Icon(Icons.add, color: Colors.white),
        ),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHeader(),
              const SizedBox(height: 24),
              _buildQuickStats(),
              const SizedBox(height: 18),
              _buildSearchSection(),
              const SizedBox(height: 14),
              Expanded(
                  child: _isLoading
                      ? const Center(
                          child: CircularProgressIndicator(color: kPrimary))
                      : _buildTable()),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  // ── HEADER ────────────────────────────────────────────────────────────

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

  // ── QUICK STATS ───────────────────────────────────────────────────────

  Widget _buildQuickStats() {
    return Row(children: [
      _statCard(
          Icons.medication_rounded, 'Total Items', '$_totalItems', kPrimary),
      const SizedBox(width: 12),
      _statCard(Icons.warning_amber_rounded, 'Low / Out', '$_lowOrOut',
          AppColors.warning),
      const SizedBox(width: 12),
      _statCard(
          Icons.remove_circle_outline, 'Out of Stock', '$_outOfStock', kDanger),
    ]);
  }

  Widget _statCard(IconData icon, String label, String value, Color color) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: kCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: kBorder),
          boxShadow: [
            BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 18),
          ),
          const SizedBox(width: 12),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(value,
                style: TextStyle(
                    fontSize: 21, fontWeight: FontWeight.w800, color: color)),
            Text(label,
                style: const TextStyle(
                    fontSize: 14,
                    color: kTextSub,
                    fontWeight: FontWeight.w500)),
          ]),
        ]),
      ),
    );
  }

  // ── SEARCH ────────────────────────────────────────────────────────────

  Widget _buildSearchSection() {
    return TextField(
      onChanged: _runFilter,
      style: const TextStyle(fontSize: 16, color: kTextMain),
      decoration: InputDecoration(
        hintText: 'Search medicine...',
        hintStyle: const TextStyle(color: kTextSub, fontSize: 16),
        prefixIcon: const Icon(Icons.search_rounded, color: kTextSub, size: 20),
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

  // ── TABLE ─────────────────────────────────────────────────────────────

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
                  dataRowMinHeight: 58,
                  dataRowMaxHeight: 68,
                  headingRowColor:
                      WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                  headingTextStyle: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: kTextSub,
                      fontSize: 15,
                      letterSpacing: 0.5),
                  dataTextStyle:
                      const TextStyle(color: kTextMain, fontSize: 16),
                  columnSpacing: 28,
                  horizontalMargin: 20,
                  dividerThickness: 1,
                  border: const TableBorder(
                    horizontalInside: BorderSide(color: kBorder, width: 0.8),
                  ),
                  columns: const [
                    DataColumn(label: Text('ID')),
                    DataColumn(label: Text('MEDICINE')),
                    DataColumn(label: Text('STOCK')),
                    DataColumn(label: Text('CAPACITY')),
                    DataColumn(label: Text('STATUS')),
                    DataColumn(label: Text('ACTIONS')),
                  ],
                  rows: _foundMedicines.asMap().entries.map((entry) {
                    final i = entry.key;
                    final med = entry.value;
                    final even = i % 2 == 0;

                    final bool isOut = med.stock == 0;
                    final bool isLow = med.stock <= 15 && med.stock > 0;

                    final double pct =
                        med.maxCapacity > 0 ? med.stock / med.maxCapacity : 0;

                    return DataRow(
                      color: WidgetStateProperty.all(
                          even ? kCard : const Color(0xFFFAFCFD)),
                      cells: [
                        // ID
                        DataCell(_idBadge(med.id?.toString() ?? '—')),
                        // Name
                        DataCell(Text(med.name,
                            style: const TextStyle(
                                fontWeight: FontWeight.w600, fontSize: 16))),
                        // Stock
                        DataCell(Text('${med.stock}',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              color: isOut
                                  ? kDanger
                                  : isLow
                                      ? AppColors.warning
                                      : kPrimary,
                            ))),
                        // Capacity bar
                        DataCell(SizedBox(
                          width: 110,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('${med.stock} / ${med.maxCapacity}',
                                  style: const TextStyle(
                                      fontSize: 14, color: kTextSub)),
                              const SizedBox(height: 4),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: pct.clamp(0.0, 1.0),
                                  minHeight: 6,
                                  backgroundColor: const Color(0xFFE2E8F0),
                                  valueColor: AlwaysStoppedAnimation<Color>(
                                    isOut
                                        ? kDanger
                                        : isLow
                                            ? AppColors.warning
                                            : kPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )),
                        // Status badge
                        DataCell(_statusBadge(isOut, isLow)),
                        // Actions
                        DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                          _actionBtn(
                            icon: Icons.edit_outlined,
                            color: kPrimary,
                            tooltip: 'Edit',
                            onTap: () => _editMedicine(i),
                          ),
                          const SizedBox(width: 4),
                          _actionBtn(
                            icon: Icons.delete_outline_rounded,
                            color: kDanger,
                            tooltip: 'Delete',
                            onTap: () => _deleteMedicine(i),
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

  // ── WIDGETS ───────────────────────────────────────────────────────────

  Widget _idBadge(String id) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      //    decoration: BoxDecoration(
      //    color: kPrimary.withValues(alpha: 0.08),
      //   borderRadius: BorderRadius.circular(6),
      //   border: Border.all(color: kPrimary.withValues(alpha: 0.2)),
      // ),
      child: Text(id,
          style: const TextStyle(
              fontSize: 15, fontWeight: FontWeight.w700, color: kPrimary)),
    );
  }

  Widget _statusBadge(bool isOut, bool isLow) {
    final Color bg = isOut
        ? const Color(0xFFFEF2F2)
        : isLow
            ? const Color(0xFFFFFBEB)
            : const Color(0xFFF0FDF4);
    final Color border = isOut
        ? const Color(0xFFFECACA)
        : isLow
            ? const Color(0xFFFDE68A)
            : const Color(0xFFBBF7D0);
    final Color text = isOut
        ? kDanger
        : isLow
            ? const Color(0xFFD97706)
            : const Color(0xFF16A34A);
    final String label = isOut
        ? 'OUT'
        : isLow
            ? 'LOW'
            : 'GOOD';
    final IconData icon = isOut
        ? Icons.remove_circle_outline
        : isLow
            ? Icons.warning_amber_outlined
            : Icons.check_circle_outline;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 11, color: text),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                color: text, fontSize: 14, fontWeight: FontWeight.w700)),
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
      prefixIcon: prefixIcon != null
          ? Icon(prefixIcon, size: 18, color: kTextSub)
          : null,
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
}
