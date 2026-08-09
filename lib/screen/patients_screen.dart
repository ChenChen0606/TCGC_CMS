import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// ── DATA MODEL ────────────────────────────────────────────────────────────────

class Patient {
  String id;
  String last;
  String first;
  String mi;
  String field1;
  String field2;
  String category;

  Patient({
    required this.id,
    required this.last,
    required this.first,
    required this.mi,
    required this.field1,
    required this.field2,
    required this.category,
  });
}

class PatientData {
  static List<Patient> patients = [];

  static String nextFacultyId() {
    int maxF = 0;
    for (final p in patients) {
      if (p.category == 'Faculty') {
        final num = int.tryParse(p.id.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        if (num > maxF) maxF = num;
      }
    }
    return 'F${(maxF + 1).toString().padLeft(3, '0')}';
  }

  static String nextStaffId() {
    int maxS = 0;
    for (final p in patients) {
      if (p.category == 'Staff') {
        final num = int.tryParse(p.id.replaceAll(RegExp(r'[^0-9]'), '')) ?? 0;
        if (num > maxS) maxS = num;
      }
    }
    return 'S${(maxS + 1).toString().padLeft(3, '0')}';
  }
}

// ── SCREEN ────────────────────────────────────────────────────────────────────

class PatientsScreen extends StatefulWidget {
  const PatientsScreen({super.key});

  @override
  State<PatientsScreen> createState() => _PatientsScreenState();
}

class _PatientsScreenState extends State<PatientsScreen>
    with TickerProviderStateMixin {
  String filter = 'Student';
  final TextEditingController search = TextEditingController();
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  static const Color kPrimary   = Color(0xFF008080);
  static const Color kPrimaryDk = Color(0xFF0F766E);
  static const Color kCard      = Colors.white;
  static const Color kBorder    = Color(0xFFE2E8F0);
  static const Color kTextMain  = Color(0xFF0F172A);
  static const Color kTextSub   = Color(0xFF64748B);
  static const Color kDanger    = Color(0xFFEF4444);

  final List<String> courses = [
    'BSCS', 'BSIT', 'BSCrim', 'BSISM', 'BS Midwifery', 'IBFS', 'IAS',
  ];
  final List<String> years = [
    '1st Year', '2nd Year', '3rd Year', '4th Year',
  ];
  final List<String> institutes = [
    'Institute of Computer Studies',
    'Institute of Teacher Education',
    'Institute of Health Sciences',
    'Institute of Criminal Justice Education',
    'Bachelor of Science in Industrial Security Management',
    'Bachelor of Arts in English',
    'Institute of Arts and Sciences',
    'Bachelor of Science in Business Administration',
    'Bachelor of Science in Office Administration',
    'Library', 'Clinic', 'Registrar', 'Finance', 'HR Department',
  ];
  final List<String> positions = [
    'Instructor', 'Dean', 'Librarian', 'Nurse',
    'Security Guard', 'Janitor',
  ];

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);
    _fadeCtrl.forward();

    if (PatientData.patients.isEmpty) {
      PatientData.patients.addAll([
        Patient(id: '234567', last: 'Delacruz', first: 'Cresa', mi: 'S', field1: 'BSCS',     field2: '2nd Year',   category: 'Student'),
        Patient(id: '234889', last: 'Doe',      first: 'John',  mi: 'A', field1: 'BSIT',     field2: '3rd Year',   category: 'Student'),
        Patient(id: 'F001',   last: 'Smith',    first: 'Jane',  mi: '',  field1: 'Institute of Computer Studies', field2: 'Dean',       category: 'Faculty'),
        Patient(id: 'F002',   last: 'Garcia',   first: 'Ramon', mi: '',  field1: 'Institute of Computer Studies', field2: 'Instructor', category: 'Faculty'),
        Patient(id: 'S001',   last: 'Lee',      first: 'Mark',  mi: '',  field1: 'Registrar', field2: 'Clerk',      category: 'Staff'),
        Patient(id: 'S002',   last: 'Navarro',  first: 'Rosa',  mi: '',  field1: 'Library',   field2: 'Librarian',  category: 'Staff'),
      ]);
    }
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    search.dispose();
    super.dispose();
  }

  String get _idLabel  => filter == 'Student' ? 'Student ID' : filter == 'Faculty' ? 'Faculty ID' : 'Staff ID';
  String get _label1   => filter == 'Student' ? 'Course' : 'Institute / Department';
  String get _label2   => filter == 'Student' ? 'Year Level' : 'Position';

  List<Patient> get _filtered {
    final q = search.text.toLowerCase();
    return PatientData.patients
        .where((p) => p.category == filter)
        .where((p) =>
            q.isEmpty ||
            p.id.toLowerCase().contains(q) ||
            p.last.toLowerCase().contains(q) ||
            p.first.toLowerCase().contains(q) ||
            p.field1.toLowerCase().contains(q) ||
            p.field2.toLowerCase().contains(q))
        .toList();
  }

  // ── COMPACT DELETE CONFIRMATION ───────────────────────────────────────

  Future<bool> _confirmDelete(Patient p) async {
  return await showDialog<bool>(
        context: context,
        builder: (_) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          backgroundColor: Colors.white,
          // ← constrains the dialog to a compact width
          child: SizedBox(
            width: 300,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 48, height: 48,   // ← fits the icon properly
                  decoration: BoxDecoration(
                    color: kDanger.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.delete_outline_rounded, color: kDanger, size: 22),
                ),
                const SizedBox(height: 12),
                const Text('Delete Patient',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: kTextMain)),
                const SizedBox(height: 6),
                const Text(
                  'Are you sure you want to delete this patient?',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: kTextSub, height: 1.5),
                ),
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: kBorder),
                      foregroundColor: kTextSub,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: const Text('Cancel', style: TextStyle(fontSize: 15)),
                  )),
                  const SizedBox(width: 10),
                  Expanded(child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kDanger,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    child: const Text('Delete',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                  )),
                ]),
              ]),
            ),
          ),
        ),
      ) ??
      false;
}

  // ── SUCCESS SNACKBAR ──────────────────────────────────────────────────

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

  void _openDialog({Patient? editPatient}) {
    final formKey = GlobalKey<FormState>();
    final isEdit  = editPatient != null;

    String autoId = '';
    if (!isEdit) {
      if (filter == 'Faculty') autoId = PatientData.nextFacultyId();
      if (filter == 'Staff')   autoId = PatientData.nextStaffId();
    }

    final idCtrl    = TextEditingController(text: isEdit ? editPatient.id    : autoId);
    final lastCtrl  = TextEditingController(text: isEdit ? editPatient.last  : '');
    final firstCtrl = TextEditingController(text: isEdit ? editPatient.first : '');
    final miCtrl    = TextEditingController(text: isEdit ? editPatient.mi    : '');

    final f1List = filter == 'Student' ? courses    : institutes;
    final f2List = filter == 'Student' ? years      : positions;

    String? selectedF1 = (isEdit && f1List.contains(editPatient.field1)) ? editPatient.field1 : null;
    String? selectedF2 = (isEdit && f2List.contains(editPatient.field2)) ? editPatient.field2 : null;

    bool existsWarning = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) {
          void checkDuplicate() {
            bool dup = false;
            if (filter == 'Student') {
              dup = PatientData.patients.any(
                (p) => p.id == idCtrl.text.trim() && p != editPatient,
              );
            } else {
              final inputLast  = lastCtrl.text.trim().toLowerCase();
              final inputFirst = firstCtrl.text.trim().toLowerCase();
              if (inputLast.isNotEmpty && inputFirst.isNotEmpty) {
                dup = PatientData.patients.any(
                  (p) =>
                      p.category == filter &&
                      p.last.toLowerCase()  == inputLast &&
                      p.first.toLowerCase() == inputFirst &&
                      p != editPatient,
                );
              }
            }
            setLocal(() => existsWarning = dup);
          }

          return LayoutBuilder(builder: (context, constraints) {
            final w = constraints.maxWidth < 560
                ? constraints.maxWidth * 0.96
                : 480.0;

            return Dialog(
              backgroundColor: kCard,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              child: Container(
                width: w,
                padding: const EdgeInsets.fromLTRB(28, 24, 28, 24),
                child: Form(
                  key: formKey,
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header
                        Row(children: [
                          Container(
                            width: 40, height: 40,
                            decoration: BoxDecoration(
                              color: kPrimary.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Icon(
                              isEdit ? Icons.edit_outlined : Icons.person_add_outlined,
                              color: kPrimary, size: 20,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                isEdit ? 'Update Patient' : 'Add New Patient',
                                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: kTextMain),
                              ),
                              Text('$filter Information',
                                  style: const TextStyle(fontSize: 15, color: kTextSub)),
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

                        // Duplicate warning
                        if (existsWarning)
                          Container(
                            margin: const EdgeInsets.only(bottom: 12),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFFF7ED),
                              border: Border.all(color: const Color(0xFFFED7AA)),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(children: [
                              const Icon(Icons.warning_amber_rounded, color: Color(0xFFF97316), size: 16),
                              const SizedBox(width: 8),
                              Expanded(child: Text(
                                filter == 'Student'
                                    ? 'A patient with this Student ID already exists.'
                                    : 'A $filter with the same name already exists in the system.',
                                style: const TextStyle(color: Color(0xFF9A3412), fontSize: 15),
                              )),
                            ]),
                          ),

                        // ID field
                        _dlabel(_idLabel),
                        TextFormField(
                          controller: idCtrl,
                          readOnly: (filter != 'Student') || isEdit,
                          onChanged: (_) => checkDuplicate(),
                          keyboardType: filter == 'Student'
                              ? TextInputType.number
                              : TextInputType.text,
                          inputFormatters: filter == 'Student'
                              ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)]
                              : [],
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'ID is required';
                            if (filter == 'Student' && v.length != 6) return 'Must be exactly 6 digits';
                            if (filter == 'Student') {
                              final dup = PatientData.patients
                                  .any((p) => p.id == v.trim() && p != editPatient);
                              if (dup) return 'This Student ID already exists';
                            }
                            return null;
                          },
                          style: TextStyle(
                            color: (filter != 'Student' || isEdit) ? kTextSub : kTextMain,
                            fontWeight: FontWeight.w500,
                            fontSize: 17,
                          ),
                          decoration: _ideco(
                            _idLabel,
                            prefixIcon: Icons.badge_outlined,
                            readOnly: (filter != 'Student') || isEdit,
                            suffix: (filter != 'Student' && !isEdit)
                                ? Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: kPrimary.withOpacity(0.1),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: const Text('Auto',
                                        style: TextStyle(fontSize: 13, color: kPrimary, fontWeight: FontWeight.w600)),
                                  )
                                : null,
                          ),
                        ),
                        const SizedBox(height: 12),

                        // Name row
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            _dlabel('Last Name'),
                            TextFormField(
                              controller: lastCtrl,
                              onChanged: filter != 'Student' ? (_) => checkDuplicate() : null,
                              validator: (v) => v == null || v.isEmpty ? 'This field is required' : null,
                              style: const TextStyle(fontSize: 17, color: kTextMain),
                              decoration: _ideco('e.g. Dela Cruz', prefixIcon: Icons.person_outline),
                            ),
                          ])),
                          const SizedBox(width: 10),
                          Expanded(flex: 3, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            _dlabel('First Name'),
                            TextFormField(
                              controller: firstCtrl,
                              onChanged: filter != 'Student' ? (_) => checkDuplicate() : null,
                              validator: (v) => v == null || v.isEmpty ? 'This field is required' : null,
                              style: const TextStyle(fontSize: 17, color: kTextMain),
                              decoration: _ideco('e.g. Maria', prefixIcon: Icons.person_outline),
                            ),
                          ])),
                          const SizedBox(width: 10),
                          Expanded(flex: 1, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            _dlabel('M.I.'),
                            TextFormField(
                              controller: miCtrl,
                              maxLength: 1,
                              textCapitalization: TextCapitalization.characters,
                              style: const TextStyle(fontSize: 17, color: kTextMain),
                              decoration: _ideco('M.I.').copyWith(counterText: ''),
                            ),
                          ])),
                        ]),
                        const SizedBox(height: 12),

                        // Field 1
                        _dlabel(_label1),
                        DropdownButtonFormField<String>(
                          value: selectedF1,
                          isExpanded: true,
                          validator: (v) => v == null ? '$_label1 is required' : null,
                          onChanged: (v) => setLocal(() => selectedF1 = v),
                          decoration: _ideco('Select $_label1',
                              prefixIcon: filter == 'Student' ? Icons.school_outlined : Icons.business_outlined),
                          items: f1List
                              .map((e) => DropdownMenuItem(
                                  value: e, child: Text(e, style: const TextStyle(fontSize: 16))))
                              .toList(),
                        ),
                        const SizedBox(height: 12),

                        // Field 2
                        _dlabel(_label2),
                        DropdownButtonFormField<String>(
                          value: selectedF2,
                          isExpanded: true,
                          validator: (v) => v == null ? '$_label2 is required' : null,
                          onChanged: (v) => setLocal(() => selectedF2 = v),
                          decoration: _ideco('Select $_label2',
                              prefixIcon: filter == 'Student' ? Icons.calendar_today_outlined : Icons.work_outline),
                          items: f2List
                              .map((e) => DropdownMenuItem(
                                  value: e, child: Text(e, style: const TextStyle(fontSize: 16))))
                              .toList(),
                        ),

                        const SizedBox(height: 24),
                        const Divider(color: kBorder, height: 1),
                        const SizedBox(height: 16),

                        // Actions
                        Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                          OutlinedButton(
                            onPressed: () => Navigator.pop(ctx),
                            style: OutlinedButton.styleFrom(
                              side: const BorderSide(color: kBorder),
                              foregroundColor: kTextSub,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                            ),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 12),
                          ElevatedButton.icon(
                            onPressed: () async {
                              checkDuplicate();
                              if (!formKey.currentState!.validate()) return;
                              if (existsWarning) return;

                              final confirmed = await showDialog<bool>(
                                    context: context,
                                    builder: (_) => _ConfirmDialog(
                                      icon: isEdit ? Icons.save_outlined : Icons.person_add_outlined,
                                      iconColor: kPrimary,
                                      iconBg: kPrimary.withOpacity(0.1),
                                      title: isEdit ? 'Update Patient' : 'Add Patient',
                                      message: isEdit
                                          ? 'Save changes to ${firstCtrl.text} ${lastCtrl.text}\'s record?'
                                          : 'Add ${firstCtrl.text} ${lastCtrl.text} as a new $filter patient?',
                                      confirmLabel: isEdit ? 'Update' : 'Add Patient',
                                      confirmColor: kPrimary,
                                    ),
                                  ) ??
                                  false;

                              if (!confirmed) return;

                              setState(() {
                                if (isEdit) {
                                  editPatient.last   = lastCtrl.text.trim();
                                  editPatient.first  = firstCtrl.text.trim();
                                  editPatient.mi     = miCtrl.text.trim();
                                  editPatient.field1 = selectedF1!;
                                  editPatient.field2 = selectedF2!;
                                } else {
                                  PatientData.patients.add(Patient(
                                    id:       idCtrl.text.trim(),
                                    last:     lastCtrl.text.trim(),
                                    first:    firstCtrl.text.trim(),
                                    mi:       miCtrl.text.trim(),
                                    field1:   selectedF1!,
                                    field2:   selectedF2!,
                                    category: filter,
                                  ));
                                }
                              });

                              if (context.mounted) Navigator.pop(ctx);
                              _showSuccess(isEdit
                                  ? 'Patient updated successfully.'
                                  : 'New patient added successfully.');
                            },
                            icon: Icon(isEdit ? Icons.save_outlined : Icons.add, size: 16),
                            label: Text(isEdit ? 'Update' : 'Add Patient'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: kPrimary,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                              elevation: 0,
                            ),
                          ),
                        ]),
                      ],
                    ),
                  ),
                ),
              ),
            );
          });
        },
      ),
    );
  }

  // ── BUILD ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    return FadeTransition(
      opacity: _fadeAnim,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          // Header
          Row(children: [
            Container(
              width: 44, height: 44,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [kPrimary, kPrimaryDk],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(Icons.people_outline_rounded, color: Colors.white, size: 22),
            ),
            const SizedBox(width: 14),
            const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Patient Information',
                  style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800, color: kTextMain)),
              Text('Manage student, faculty & staff records',
                  style: TextStyle(fontSize: 15, color: kTextSub)),
            ]),
          ]),

          const SizedBox(height: 24),

          // Search + Add
          LayoutBuilder(builder: (ctx, con) {
            final isMobile = con.maxWidth < 640;
            final searchField = TextField(
              controller: search,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 17, color: kTextMain),
              decoration: InputDecoration(
                hintText: 'Search by ID, name, course…',
                hintStyle: const TextStyle(color: kTextSub, fontSize: 16),
                prefixIcon: const Icon(Icons.search_rounded, color: kTextSub, size: 20),
                filled: true,
                fillColor: kCard,
                contentPadding: const EdgeInsets.symmetric(vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBorder)),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBorder)),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kPrimary, width: 1.5)),
              ),
            );
            final addBtn = ElevatedButton.icon(
              onPressed: () => _openDialog(),
              icon: const Icon(Icons.person_add_outlined, size: 16),
              label: Text('Add $filter'),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
                elevation: 0,
              ),
            );
            if (isMobile) {
              return Column(children: [
                searchField,
                const SizedBox(height: 10),
                SizedBox(width: double.infinity, child: addBtn),
              ]);
            }
            return Row(children: [
              Expanded(child: searchField),
              const SizedBox(width: 14),
              addBtn,
            ]);
          }),

          const SizedBox(height: 18),
          _buildTabs(),
          const SizedBox(height: 14),
          _buildSummary(list),
          const SizedBox(height: 14),
          Expanded(child: _buildTable(list)),
        ]),
      ),
    );
  }

  Widget _buildTabs() {
    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2F6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: ['Student', 'Faculty', 'Staff'].map((tab) {
          final sel = filter == tab;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() {
                filter = tab;
                search.clear();
                _fadeCtrl
                  ..reset()
                  ..forward();
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: sel ? kPrimary : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: sel
                      ? [BoxShadow(color: kPrimary.withOpacity(0.3), blurRadius: 8, offset: const Offset(0, 2))]
                      : [],
                ),
                child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(
                    tab == 'Student'
                        ? Icons.school_outlined
                        : tab == 'Faculty'
                            ? Icons.person_outlined
                            : Icons.badge_outlined,
                    size: 15,
                    color: sel ? Colors.white : kTextSub,
                  ),
                  const SizedBox(width: 6),
                  Text(tab,
                      style: TextStyle(
                        color: sel ? Colors.white : kTextSub,
                        fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                        fontSize: 16,
                      )),
                ]),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildSummary(List<Patient> list) {
    final total = PatientData.patients.where((p) => p.category == filter).length;
    return Row(children: [
      _chip(Icons.people_alt_outlined, '$total Total', kPrimary),
    ]);
  }

  Widget _chip(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 13, color: color),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 15, color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _buildTable(List<Patient> list) {
    return Container(
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 2))],
      ),
      child: list.isEmpty
          ? _emptyState()
          : ClipRRect(
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
                        headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                        headingTextStyle: const TextStyle(
                            fontWeight: FontWeight.w700, color: kTextSub, fontSize: 15, letterSpacing: 0.5),
                        dataTextStyle: const TextStyle(color: kTextMain, fontSize: 16),
                        columnSpacing: 24,
                        horizontalMargin: 20,
                        dividerThickness: 1,
                        border: const TableBorder(
                          horizontalInside: BorderSide(color: kBorder, width: 0.8),
                        ),
                        columns: [
                          DataColumn(label: Text(_idLabel.toUpperCase())),
                          const DataColumn(label: Text('NAME')),
                          DataColumn(label: Text(_label1.toUpperCase())),
                          DataColumn(label: Text(_label2.toUpperCase())),
                          const DataColumn(label: Text('ACTIONS')),
                        ],
                        rows: list.asMap().entries.map((entry) {
                          final p    = entry.value;
                          final even = entry.key % 2 == 0;
                          return DataRow(
                            color: WidgetStateProperty.all(even ? kCard : const Color(0xFFFAFCFD)),
                            cells: [
                              DataCell(_idBadge(p.id, p.category)),
                              DataCell(Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    '${p.first}${p.mi.isNotEmpty ? ' ${p.mi}.' : ''} ${p.last}',
                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                                  ),
                                ],
                              )),
                              DataCell(Text(p.field1, style: const TextStyle(fontSize: 15))),
                              DataCell(_badge(p.field2, kPrimary)),
                              DataCell(Row(mainAxisSize: MainAxisSize.min, children: [
                                _actionBtn(
                                  icon: Icons.edit_outlined,
                                  color: kPrimary,
                                  tooltip: 'Edit',
                                  onTap: () => _openDialog(editPatient: p),
                                ),
                                const SizedBox(width: 4),
                                _actionBtn(
                                  icon: Icons.delete_outline_rounded,
                                  color: kDanger,
                                  tooltip: 'Delete',
                                  onTap: () async {
                                    final ok = await _confirmDelete(p);
                                    if (ok) {
                                      setState(() => PatientData.patients.remove(p));
                                      _showSuccess('Patient removed successfully.');
                                    }
                                  },
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

 /* Widget _idBadge(String id, String category) {
    final color = category == 'Student'
        ? const Color(0xFF3B82F6)
        : category == 'Faculty'
            ? const Color(0xFF8B5CF6)
            : const Color(0xFF10B981);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Text(id, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: color)),
    );  static const Color kPrimary   = Color(0xFF008080);
  }*/

  Widget _idBadge(String id, String category) {
  final color = category == 'Student'
      ? const Color(0xFF008080)
      : category == 'Faculty'
          ? const Color(0xFF008080)
          : const Color(0xFF008080);
  return Text(id, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color));
}
/*
  Widget _badge(String val, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(val, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: color)),
    );
  }*/
  Widget _badge(String val, Color color) {
  return Text(val, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: color));
}

  Widget _actionBtn({required IconData icon, required Color color, required String tooltip, required VoidCallback onTap}) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 32, height: 32,
          decoration: BoxDecoration(color: color.withOpacity(0.08), borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: color, size: 16),
        ),
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.search_off_rounded, size: 48, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          Text(
            search.text.isEmpty
                ? 'No $filter patients added yet.'
                : 'No results for "${search.text}".',
            style: const TextStyle(color: kTextSub, fontSize: 17),
          ),
        ]),
      ),
    );
  }

  Widget _dlabel(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(label,
            style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: kTextSub)),
      );

  InputDecoration _ideco(String hint,
      {IconData? prefixIcon, bool readOnly = false, Widget? suffix}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: kTextSub, fontSize: 16),
      filled: true,
      fillColor: readOnly ? const Color(0xFFF1F5F9) : const Color(0xFFFAFCFE),
      prefixIcon: prefixIcon != null ? Icon(prefixIcon, size: 18, color: kTextSub) : null,
      suffixIcon: suffix,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBorder)),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBorder)),
      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kPrimary, width: 1.5)),
      errorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kDanger)),
      focusedErrorBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kDanger, width: 1.5)),
    );
  }
}

// ── CONFIRM DIALOG (for Add/Update) ──────────────────────────────────────────

class _ConfirmDialog extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBg;
  final String title;
  final String message;
  final String confirmLabel;
  final Color confirmColor;

  const _ConfirmDialog({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.confirmColor,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      backgroundColor: Colors.white,
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(icon, color: iconColor, size: 26),
          ),
          const SizedBox(height: 16),
          Text(title,
              style: const TextStyle(
                  fontSize: 20, fontWeight: FontWeight.w700, color: Color(0xFF0F172A))),
          const SizedBox(height: 8),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16, color: Color(0xFF64748B), height: 1.5)),
          const SizedBox(height: 24),
          Row(children: [
            Expanded(child: OutlinedButton(
              onPressed: () => Navigator.pop(context, false),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: Color(0xFFE2E8F0)),
                foregroundColor: const Color(0xFF64748B),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              child: const Text('Cancel'),
            )),
            const SizedBox(width: 12),
            Expanded(child: ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: confirmColor,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
              child: Text(confirmLabel,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
            )),
          ]),
        ]),
      ),
    );
  }
}