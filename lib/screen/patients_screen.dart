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
  // NEW — contact details. These matter a lot for a clinic system: if a
  // patient needs to be followed up on, or in an emergency, staff need a
  // fast way to reach them or their guardian.
  String contact;          // patient's own mobile / contact number
  String emergencyName;    // guardian / emergency contact person
  String emergencyContact; // guardian / emergency contact number

  Patient({
    required this.id,
    required this.last,
    required this.first,
    required this.mi,
    required this.field1,
    required this.field2,
    required this.category,
    this.contact = '',
    this.emergencyName = '',
    this.emergencyContact = '',
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

  // Category-specific accent colors — reused for the summary chips, ID
  // badges, and detail dialog so a category reads consistently everywhere.
  static const Color kStudentColor = Color(0xFF2563EB);
  static const Color kFacultyColor = Color(0xFFD97706);
  static const Color kStaffColor   = Color(0xFF7C3AED);

  final List<String> insti_ = [
    'IBFS', 'ITE', 'ICJE', 'ICS', 'IAS', 'IHS', // --> INSTITUTE
  ];
  final List<String> years = [
    '1st Year', '2nd Year', '3rd Year', '4th Year',
  ];
  final List<String> department = [
    'IBFS', 'ITE', 'ICJE', 'ICS', 'IAS', 'IHS', // for teachers
    'Library', 'Clinic', 'Registrar', 'Finance', 'HR Department', // --> Department / Office
  ];
  final List<String> positions = [
    'Instructor', 'Dean', 'Librarian', 'Nurse',
    'Security Guard',
  ];

  // Which dropdown list feeds field1 / field2 for a given category.
  // Student  → Institute, then Year Level
  // Faculty/Staff → Position, then Office / Department
  List<String> _f1ListFor(String cat) => cat == 'Student' ? insti_ : positions;
  List<String> _f2ListFor(String cat) => cat == 'Student' ? years : department;
  String _label1For(String cat) => cat == 'Student' ? 'Institute' : 'Position';
  String _label2For(String cat) => cat == 'Student' ? 'Year Level' : 'Office / Department';
  String _idLabelFor(String cat) =>
      cat == 'Student' ? 'Student ID' : cat == 'Faculty' ? 'Faculty ID' : 'Staff ID';

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);
    _fadeCtrl.forward();

    if (PatientData.patients.isEmpty) {
      PatientData.patients.addAll([
        Patient(id: '234567', last: 'Delacruz', first: 'Cresa', mi: 'S', field1: 'ICS',     field2: '2nd Year',   category: 'Student', contact: '09171234567', emergencyName: 'Maria Delacruz', emergencyContact: '09179876543'),
        Patient(id: '234889', last: 'Doe',      first: 'John',  mi: 'A', field1: 'ITE',     field2: '3rd Year',   category: 'Student', contact: '09201234567', emergencyName: 'Anna Doe', emergencyContact: '09209876543'),
        Patient(id: 'F001',   last: 'Smith',    first: 'Jane',  mi: '',  field1: 'Dean', field2: 'IAS',       category: 'Faculty', contact: '09151234567', emergencyName: '', emergencyContact: ''),
        Patient(id: 'F002',   last: 'Garcia',   first: 'Ramon', mi: '',  field1: 'Instructor', field2: 'ICS', category: 'Faculty', contact: '09161234567', emergencyName: '', emergencyContact: ''),
        Patient(id: 'S001',   last: 'Lee',      first: 'Mark',  mi: '',  field1: 'Security Guard', field2: 'Registrar', category: 'Staff', contact: '09181234567', emergencyName: '', emergencyContact: ''),
        Patient(id: 'S002',   last: 'Navarro',  first: 'Rosa',  mi: '',  field1: 'Librarian', field2: 'Library',   category: 'Staff', contact: '09191234567', emergencyName: '', emergencyContact: ''),
      ]);
    }
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    search.dispose();
    super.dispose();
  }

  String get _idLabel  => _idLabelFor(filter);
  String get _label1   => _label1For(filter);
  String get _label2   => _label2For(filter);

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
            p.field2.toLowerCase().contains(q) ||
            p.contact.toLowerCase().contains(q))
        .toList();
  }

  // ── COMPACT DELETE CONFIRMATION ───────────────────────────────────────

  Future<bool> _confirmDelete(Patient p) async {
  return await showDialog<bool>(
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
                  width: 48, height: 48,
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
  // Category is now chosen INSIDE the dialog via a dropdown, so you no
  // longer have to switch tabs before adding a Faculty/Staff record.
  // The dropdown defaults to whichever tab is currently active, but can
  // be changed freely while adding. While editing, category is locked
  // (shown read-only) since the ID format is tied to it.

  void _openDialog({Patient? editPatient}) {
    final formKey = GlobalKey<FormState>();
    final isEdit  = editPatient != null;

    String selectedCategory = isEdit ? editPatient.category : filter;

    String autoId = '';
    if (!isEdit) {
      if (selectedCategory == 'Faculty') autoId = PatientData.nextFacultyId();
      if (selectedCategory == 'Staff')   autoId = PatientData.nextStaffId();
    }

    final idCtrl        = TextEditingController(text: isEdit ? editPatient.id    : autoId);
    final lastCtrl       = TextEditingController(text: isEdit ? editPatient.last  : '');
    final firstCtrl      = TextEditingController(text: isEdit ? editPatient.first : '');
    final miCtrl          = TextEditingController(text: isEdit ? editPatient.mi    : '');
    final contactCtrl     = TextEditingController(text: isEdit ? editPatient.contact : '');
    final emNameCtrl       = TextEditingController(text: isEdit ? editPatient.emergencyName : '');
    final emContactCtrl    = TextEditingController(text: isEdit ? editPatient.emergencyContact : '');

    String? selectedF1 = (isEdit && _f1ListFor(selectedCategory).contains(editPatient.field1))
        ? editPatient.field1
        : null;
    String? selectedF2 = (isEdit && _f2ListFor(selectedCategory).contains(editPatient.field2))
        ? editPatient.field2
        : null;

    bool existsWarning = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final f1List = _f1ListFor(selectedCategory);
          final f2List = _f2ListFor(selectedCategory);
          final label1 = _label1For(selectedCategory);
          final label2 = _label2For(selectedCategory);
          final idLabel = _idLabelFor(selectedCategory);

          void checkDuplicate() {
            bool dup = false;
            if (selectedCategory == 'Student') {
              dup = PatientData.patients.any(
                (p) => p.id == idCtrl.text.trim() && p != editPatient,
              );
            } else {
              final inputLast  = lastCtrl.text.trim().toLowerCase();
              final inputFirst = firstCtrl.text.trim().toLowerCase();
              if (inputLast.isNotEmpty && inputFirst.isNotEmpty) {
                dup = PatientData.patients.any(
                  (p) =>
                      p.category == selectedCategory &&
                      p.last.toLowerCase()  == inputLast &&
                      p.first.toLowerCase() == inputFirst &&
                      p != editPatient,
                );
              }
            }
            setLocal(() => existsWarning = dup);
          }

          void onCategoryChanged(String? v) {
            if (v == null || v == selectedCategory) return;
            setLocal(() {
              selectedCategory = v;
              selectedF1 = null;
              selectedF2 = null;
              existsWarning = false;
              if (!isEdit) {
                if (v == 'Faculty') {
                  idCtrl.text = PatientData.nextFacultyId();
                } else if (v == 'Staff') {
                  idCtrl.text = PatientData.nextStaffId();
                } else {
                  idCtrl.text = '';
                }
              }
            });
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
                              Text('$selectedCategory Information',
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
                                selectedCategory == 'Student'
                                    ? 'A patient with this Student ID already exists.'
                                    : 'A $selectedCategory with the same name already exists in the system.',
                                style: const TextStyle(color: Color(0xFF9A3412), fontSize: 15),
                              )),
                            ]),
                          ),

                        // Category dropdown — pick Student / Faculty / Staff here
                        // instead of needing to switch tabs first.
                        _dlabel('Patient Category'),
                        DropdownButtonFormField<String>(
                          value: selectedCategory,
                          isExpanded: true,
                          onChanged: isEdit ? null : onCategoryChanged,
                          decoration: _ideco(
                            'Select category',
                            prefixIcon: Icons.category_outlined,
                            readOnly: isEdit,
                          ),
                          style: const TextStyle(fontSize: 16, color: kTextMain),
                          items: const ['Student', 'Faculty', 'Staff']
                              .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                              .toList(),
                        ),
                        const SizedBox(height: 12),

                        // ID field
                        _dlabel(idLabel),
                        TextFormField(
                          controller: idCtrl,
                          readOnly: (selectedCategory != 'Student') || isEdit,
                          onChanged: (_) => checkDuplicate(),
                          keyboardType: selectedCategory == 'Student'
                              ? TextInputType.number
                              : TextInputType.text,
                          inputFormatters: selectedCategory == 'Student'
                              ? [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)]
                              : [],
                          validator: (v) {
                            if (v == null || v.isEmpty) return 'ID is required';
                            if (selectedCategory == 'Student' && v.length != 6) return 'Must be exactly 6 digits';
                            if (selectedCategory == 'Student') {
                              final dup = PatientData.patients
                                  .any((p) => p.id == v.trim() && p != editPatient);
                              if (dup) return 'This Student ID already exists';
                            }
                            return null;
                          },
                          style: TextStyle(
                            color: (selectedCategory != 'Student' || isEdit) ? kTextSub : kTextMain,
                            fontWeight: FontWeight.w500,
                            fontSize: 17,
                          ),
                          decoration: _ideco(
                            idLabel,
                            prefixIcon: Icons.badge_outlined,
                            readOnly: (selectedCategory != 'Student') || isEdit,
                            suffix: (selectedCategory != 'Student' && !isEdit)
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
                              onChanged: selectedCategory != 'Student' ? (_) => checkDuplicate() : null,
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
                              onChanged: selectedCategory != 'Student' ? (_) => checkDuplicate() : null,
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

                        // Contact number — lets the clinic reach the patient directly.
                        _dlabel('Contact Number'),
                        TextFormField(
                          controller: contactCtrl,
                          keyboardType: TextInputType.phone,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)],
                          style: const TextStyle(fontSize: 17, color: kTextMain),
                          decoration: _ideco('e.g. 09171234567', prefixIcon: Icons.phone_outlined),
                        ),
                        const SizedBox(height: 12),

                        // Field 1 (Institute for Student / Position for Faculty & Staff)
                        _dlabel(label1),
                        DropdownButtonFormField<String>(
                          key: ValueKey('f1-$selectedCategory'),
                          value: selectedF1,
                          isExpanded: true,
                          validator: (v) => v == null ? '$label1 is required' : null,
                          onChanged: (v) => setLocal(() => selectedF1 = v),
                          decoration: _ideco('Select $label1',
                              prefixIcon: selectedCategory == 'Student' ? Icons.school_outlined : Icons.work_outline),
                          items: f1List
                              .map((e) => DropdownMenuItem(
                                  value: e, child: Text(e, style: const TextStyle(fontSize: 16))))
                              .toList(),
                        ),
                        const SizedBox(height: 12),

                        // Field 2 (Year Level for Student / Office-Department for Faculty & Staff)
                        _dlabel(label2),
                        DropdownButtonFormField<String>(
                          key: ValueKey('f2-$selectedCategory'),
                          value: selectedF2,
                          isExpanded: true,
                          validator: (v) => v == null ? '$label2 is required' : null,
                          onChanged: (v) => setLocal(() => selectedF2 = v),
                          decoration: _ideco('Select $label2',
                              prefixIcon: selectedCategory == 'Student' ? Icons.calendar_today_outlined : Icons.business_outlined),
                          items: f2List
                              .map((e) => DropdownMenuItem(
                                  value: e, child: Text(e, style: const TextStyle(fontSize: 16))))
                              .toList(),
                        ),
                        const SizedBox(height: 12),

                        // Emergency contact — optional, but critical for a clinic:
                        // who to call if the patient needs to be sent home or to
                        // a hospital. Especially relevant for students (guardian).
                        _dlabel('Emergency Contact (optional)'),
                        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Expanded(flex: 3, child: TextFormField(
                            controller: emNameCtrl,
                            style: const TextStyle(fontSize: 16, color: kTextMain),
                            decoration: _ideco('Contact person name', prefixIcon: Icons.contact_emergency_outlined),
                          )),
                          const SizedBox(width: 10),
                          Expanded(flex: 2, child: TextFormField(
                            controller: emContactCtrl,
                            keyboardType: TextInputType.phone,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(11)],
                            style: const TextStyle(fontSize: 16, color: kTextMain),
                            decoration: _ideco('Contact number'),
                          )),
                        ]),

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
                                          : 'Add ${firstCtrl.text} ${lastCtrl.text} as a new $selectedCategory patient?',
                                      confirmLabel: isEdit ? 'Update' : 'Add Patient',
                                      confirmColor: kPrimary,
                                    ),
                                  ) ??
                                  false;

                              if (!confirmed) return;

                              setState(() {
                                if (isEdit) {
                                  editPatient.last             = lastCtrl.text.trim();
                                  editPatient.first             = firstCtrl.text.trim();
                                  editPatient.mi                = miCtrl.text.trim();
                                  editPatient.field1            = selectedF1!;
                                  editPatient.field2             = selectedF2!;
                                  editPatient.contact           = contactCtrl.text.trim();
                                  editPatient.emergencyName      = emNameCtrl.text.trim();
                                  editPatient.emergencyContact   = emContactCtrl.text.trim();
                                } else {
                                  PatientData.patients.add(Patient(
                                    id:              idCtrl.text.trim(),
                                    last:            lastCtrl.text.trim(),
                                    first:           firstCtrl.text.trim(),
                                    mi:              miCtrl.text.trim(),
                                    field1:          selectedF1!,
                                    field2:          selectedF2!,
                                    category:        selectedCategory,
                                    contact:         contactCtrl.text.trim(),
                                    emergencyName:    emNameCtrl.text.trim(),
                                    emergencyContact: emContactCtrl.text.trim(),
                                  ));
                                  // Jump the active tab to match, so the new
                                  // record is immediately visible in the table.
                                  filter = selectedCategory;
                                  search.clear();
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

  // ── PATIENT DETAIL DIALOG ────────────────────────────────────────────
  // The table stays scannable (name, category-specific fields, contact),
  // full details — including emergency contact — live behind this view.

  void _showPatientDetail(Patient p) {
    final color = _categoryColor(p.category);
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: kCard,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    width: 46, height: 46,
                    decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)),
                    child: const Icon(Icons.person_outline_rounded, color: Colors.white, size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('${p.first}${p.mi.isNotEmpty ? ' ${p.mi}.' : ''} ${p.last}',
                          style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: kTextMain)),
                      const SizedBox(height: 4),
                      Row(children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(color: color.withOpacity(0.12), borderRadius: BorderRadius.circular(6)),
                          child: Text(p.category, style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color)),
                        ),
                        const SizedBox(width: 8),
                        Text(p.id, style: const TextStyle(fontSize: 13, color: kTextSub)),
                      ]),
                    ],
                  )),
                  IconButton(onPressed: () => Navigator.pop(ctx), icon: const Icon(Icons.close_rounded, color: kTextSub), iconSize: 20),
                ]),
                const SizedBox(height: 18),
                const Divider(color: kBorder, height: 1),
                const SizedBox(height: 14),
                _detailRow(p.category == 'Student' ? Icons.school_outlined : Icons.work_outline, _label1For(p.category), p.field1),
                _detailRow(p.category == 'Student' ? Icons.calendar_today_outlined : Icons.business_outlined, _label2For(p.category), p.field2),
                _detailRow(Icons.phone_outlined, 'Contact Number', p.contact.isEmpty ? 'Not on file' : p.contact),
                _detailRow(Icons.contact_emergency_outlined, 'Emergency Contact',
                    p.emergencyName.isEmpty ? 'Not on file' : '${p.emergencyName} · ${p.emergencyContact}'),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(child: OutlinedButton.icon(
                    onPressed: () { Navigator.pop(ctx); _openDialog(editPatient: p); },
                    icon: const Icon(Icons.edit_outlined, size: 16, color: kPrimary),
                    label: const Text('Edit', style: TextStyle(color: kPrimary)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: kBorder),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  )),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 32, height: 32,
          decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(9)),
          child: Icon(icon, size: 15, color: kTextSub),
        ),
        const SizedBox(width: 12),
        Expanded(child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, color: kTextSub, fontWeight: FontWeight.w600)),
            const SizedBox(height: 2),
            Text(value, style: const TextStyle(fontSize: 15, color: kTextMain, fontWeight: FontWeight.w600)),
          ],
        )),
      ]),
    );
  }

  Color _categoryColor(String cat) => cat == 'Student'
      ? kStudentColor
      : cat == 'Faculty'
          ? kFacultyColor
          : kStaffColor;

  // ── BUILD ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final list = _filtered;
    return FadeTransition(
      opacity: _fadeAnim,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

          _buildHeaderRow(),

          const SizedBox(height: 20),

          // Search + Add
          LayoutBuilder(builder: (ctx, con) {
            final isMobile = con.maxWidth < 640;
            final searchField = TextField(
              controller: search,
              onChanged: (_) => setState(() {}),
              style: const TextStyle(fontSize: 17, color: kTextMain),
              decoration: InputDecoration(
                hintText: 'Search by ID, name, institute, contact...',
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
              label: const Text('Add Patient'),
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
          Expanded(child: _buildTable(list)),
        ]),
      ),
    );
  }

  // Title on the left, compact All/Student/Faculty/Staff counts on the
  // right — same idea as the Medical Records page, just smaller since
  // this page doesn't need the counts to dominate the header.
  Widget _buildHeaderRow() {
    return LayoutBuilder(builder: (context, constraints) {
      final bool isNarrow = constraints.maxWidth < 700;

      final titleBlock = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
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
        ],
      );

      final chips = _buildCategorySummary();

      if (isNarrow) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [titleBlock, const SizedBox(height: 12), chips],
        );
      }
      return Row(children: [titleBlock, const Spacer(), chips]);
    });
  }

  Widget _buildCategorySummary() {
    final all      = PatientData.patients.length;
    final students  = PatientData.patients.where((p) => p.category == 'Student').length;
    final faculty   = PatientData.patients.where((p) => p.category == 'Faculty').length;
    final staff     = PatientData.patients.where((p) => p.category == 'Staff').length;

    return Wrap(spacing: 8, runSpacing: 8, children: [
      _summaryChip('All', all, kPrimary, Icons.groups_rounded),
      _summaryChip('Students', students, kStudentColor, Icons.school_outlined),
      _summaryChip('Faculty', faculty, kFacultyColor, Icons.co_present_outlined),
      _summaryChip('Staff', staff, kStaffColor, Icons.badge_outlined),
    ]);
  }

  // Compact — icon, count, label all on one line. Deliberately smaller
  // than the big stat cards on the Medical Records page.
  Widget _summaryChip(String label, int count, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text('$count', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(fontSize: 13, color: color, fontWeight: FontWeight.w600)),
      ]),
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
                        showCheckboxColumn: false,
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
                          const DataColumn(label: Text('CONTACT')),
                          const DataColumn(label: Text('ACTIONS')),
                        ],
                        rows: list.asMap().entries.map((entry) {
                          final p    = entry.value;
                          final even = entry.key % 2 == 0;
                          return DataRow(
                            color: WidgetStateProperty.all(even ? kCard : const Color(0xFFFAFCFD)),
                            onSelectChanged: (_) => _showPatientDetail(p),
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
                              DataCell(Text(p.contact.isEmpty ? '—' : p.contact,
                                  style: const TextStyle(fontSize: 15, color: kTextSub))),
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

  Widget _idBadge(String id, String category) {
    final color = _categoryColor(category);
    return Text(id, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color));
  }

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