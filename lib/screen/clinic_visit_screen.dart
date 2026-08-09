import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class ClinicVisitScreen extends StatefulWidget {
  // Who is currently logged in — passed down from ClinicDashboard so every
  // record created on this page can be tagged with who created it.
  final String userName;
  final String userRole;

  const ClinicVisitScreen({
    super.key,
    this.userName = '',
    this.userRole = '',
  });

  @override
  State<ClinicVisitScreen> createState() => _ClinicVisitScreenState();
}

class _ClinicVisitScreenState extends State<ClinicVisitScreen> {
  final _formKey = GlobalKey<FormState>();

  // ── DESIGN TOKENS (matches Patients screen for system-wide consistency) ─
  static const Color kPrimary         = Color(0xFF008080);
  static const Color kPrimaryDk       = Color(0xFF0F766E);
  static const Color kCard            = Colors.white;
  static const Color kBorder          = Color(0xFFE2E8F0);
  static const Color kTextMain        = Color(0xFF0F172A);
  static const Color kTextSub         = Color(0xFF64748B);
  static const Color kDanger          = Color(0xFFEF4444);
  static const Color kInfo            = Color(0xFF2563EB); // neutral informational (not an error)
  static const Color kWarning         = Color(0xFFF59E0B);
  static const Color kFieldFill       = Color(0xFFFAFCFE);
  static const Color kFieldFillReadOnly = Color(0xFFF1F5F9);

  // Readability floor: nothing a user needs to read to act on renders below
  // 14px anywhere on this page. 12px is reserved for pure captions/metadata.
  static const TextStyle kSectionTitleStyle =
      TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: kTextMain);
  static const TextStyle kSectionSubtitleStyle =
      TextStyle(fontSize: 15, color: kTextSub);
  static const TextStyle kFieldLabelStyle =
      TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: kTextSub);
  static const TextStyle kFieldValueStyle =
      TextStyle(fontSize: 16, color: kTextMain);
  static const TextStyle kCaptionStyle =
      TextStyle(fontSize: 14, color: kTextSub);

  // ── STATE FLAGS ───────────────────────────────────────────────────────
  bool patientExists   = false;
  bool savedNewPatient = false;
  bool showSaveButton  = false;

  int _facultyCounter = 4;
  int _staffCounter   = 3;

  // ── COURSE / YEAR EDIT LOCK ────────────────────────────────────────────
  bool _editingCourseField = false;
  bool _editingYearField   = false;

  final List<Map<String, dynamic>> _courseYearAuditLog = [];
  final List<Map<String, dynamic>> _visitRecords = [];

  String get _currentUserName =>
      widget.userName.isNotEmpty ? widget.userName : 'Unknown User';

  Map<String, dynamic>? _lastFieldChange(String patientId, String field) {
    final matches = _courseYearAuditLog
        .where((e) => e['patientId'] == patientId && e['field'] == field)
        .toList()
      ..sort((a, b) => (b['changedAt'] as DateTime).compareTo(a['changedAt'] as DateTime));
    return matches.isEmpty ? null : matches.first;
  }

  // ── SHARED PATIENT DATABASE ───────────────────────────────────────────
  final List<Map<String, dynamic>> _patients = [
    {"id":"234567","last":"Delacruz","first":"Cresa","mi":"S","role":"Student","field1":"BSCS","field2":"2nd Year"},
    {"id":"234889","last":"Doe","first":"John","mi":"A","role":"Student","field1":"BSIT","field2":"3rd Year"},
    {"id":"F001","last":"Smith","first":"Jane","mi":"","role":"Faculty","field1":"ICS","field2":"Dean"},
    {"id":"F002","last":"Garcia","first":"Ramon","mi":"","role":"Faculty","field1":"ICS","field2":"Instructor"},
    {"id":"S001","last":"Lee","first":"Mark","mi":"","role":"Staff","field1":"Registrar","field2":"Staff"},
    {"id":"S002","last":"Navarro","first":"Rosa","mi":"","role":"Staff","field1":"Library","field2":"Staff"},
  ];

  final List<Map<String, dynamic>> _medicines = [
    {"name": "Paracetamol",    "stock": 50},
    {"name": "Amoxicillin",    "stock": 20},
    {"name": "Biogesic",       "stock": 15},
    {"name": "Mefenamic Acid", "stock": 30},
    {"name": "Meclizine",      "stock": 25},
    {"name": "Antacid",        "stock": 40},
    {"name": "Antihistamine",  "stock": 18},
    {"name": "Cough Syrup",    "stock": 12},
    {"name": "Eye Drops",      "stock": 10},
    {"name": "Metoclopramide", "stock": 8},
    {"name": "Amlodipine",     "stock": 15},
    {"name": "Vitamin C",      "stock": 100},
  ];

  // TODO(confirm with registrar): confirm official program codes
  final List<String> courses = [
    'BSCS', 'BSIT', 'BSCrim', 'BS Ind. Security Mgmt.', 'BS Midwifery',
    'BSBA', 'BSOA', 'AB English',
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

  // ── CONTROLLERS ───────────────────────────────────────────────────────
  String selectedRole    = "Student";
  String? selectedMedicine;

  String? _selectedCourse;
  String? _selectedYear;
  String? _selectedInstitute;
  String? _selectedPosition;

  final TextEditingController _searchCtrl    = TextEditingController();
  final TextEditingController _lastNameCtrl  = TextEditingController();
  final TextEditingController _firstNameCtrl = TextEditingController();
  final TextEditingController _miCtrl        = TextEditingController();
  final TextEditingController _idDisplayCtrl = TextEditingController();
  final TextEditingController _instituteCtrl = TextEditingController();
  final TextEditingController _yearCtrl      = TextEditingController();
  final TextEditingController _qtyCtrl       = TextEditingController();
  final TextEditingController _medSearchCtrl = TextEditingController();

  final List<String> symptomOptions = [
    'Fever / Flu', 'Headache', 'Stomach Ache', 'Injury', 'Dizziness',
    'Cough / Cold', 'Allergic Reaction', 'Other',
  ];
  String? _selectedSymptom;
  final TextEditingController _otherSymptomCtrl = TextEditingController();

  String get _complaintText => _selectedSymptom == 'Other'
      ? _otherSymptomCtrl.text.trim()
      : (_selectedSymptom ?? '');

  Map<String, dynamic>? _resolvedPatient;
  List<Map<String, dynamic>> _nameSuggestions = [];

  // ── SEARCH LOGIC ──────────────────────────────────────────────────────

  void _onSearchChanged(String value) {
    final q = value.trim();
    if (q.isEmpty) {
      setState(() {
        patientExists    = false;
        savedNewPatient  = false;
        showSaveButton   = false;
        _nameSuggestions = [];
        _resolvedPatient = null;
      });
      return;
    }

    if (selectedRole == "Student") {
      final match = _patients.where((p) => p["role"] == "Student" && p["id"] == q).toList();
      if (match.isNotEmpty) {
        _fillPatientFields(match.first);
        setState(() {
          patientExists    = true;
          savedNewPatient  = true;
          showSaveButton   = false;
          _nameSuggestions = [];
          _resolvedPatient = match.first;
        });
      } else {
        _clearPatientFields();
        setState(() {
          patientExists    = false;
          savedNewPatient  = false;
          showSaveButton   = true;
          _nameSuggestions = [];
          _resolvedPatient = null;
        });
      }
    } else {
      final ql   = q.toLowerCase();
      final role = selectedRole;
      final suggestions = _patients.where((p) {
        if (p["role"] != role) return false;
        final full  = "${p["first"]} ${p["last"]}".toLowerCase();
        final full2 = "${p["last"]} ${p["first"]}".toLowerCase();
        return full.contains(ql) || full2.contains(ql) ||
            p["first"].toString().toLowerCase().contains(ql) ||
            p["last"].toString().toLowerCase().contains(ql);
      }).toList();

      setState(() {
        _nameSuggestions = suggestions;
        if (suggestions.isEmpty) {
          patientExists    = false;
          savedNewPatient  = false;
          showSaveButton   = true;
          _resolvedPatient = null;
        } else {
          showSaveButton = false;
        }
      });
    }
  }

  void _selectSuggestion(Map<String, dynamic> p) {
    _fillPatientFields(p);
    setState(() {
      patientExists    = true;
      savedNewPatient  = true;
      showSaveButton   = false;
      _nameSuggestions = [];
      _resolvedPatient = p;
      _searchCtrl.text = "${p["first"]} ${p["last"]}";
    });
  }

  void _fillPatientFields(Map<String, dynamic> p) {
    _lastNameCtrl.text  = p["last"];
    _firstNameCtrl.text = p["first"];
    _miCtrl.text        = p["mi"] ?? "";
    _idDisplayCtrl.text = p["id"];
    _instituteCtrl.text = p["field1"];
    _yearCtrl.text      = p["field2"];
  }

  void _clearPatientFields() {
    _lastNameCtrl.clear();
    _firstNameCtrl.clear();
    _miCtrl.clear();
    _idDisplayCtrl.clear();
    _instituteCtrl.clear();
    _yearCtrl.clear();
    _selectedCourse    = null;
    _selectedYear      = null;
    _selectedInstitute = null;
    _selectedPosition  = null;
  }

  void _onRoleChanged(String role) {
    setState(() {
      selectedRole     = role;
      patientExists    = false;
      savedNewPatient  = false;
      showSaveButton   = false;
      _nameSuggestions = [];
      _resolvedPatient = null;
      _searchCtrl.clear();
      _clearPatientFields();
    });
  }

  // ── SAVE NEW PATIENT (with confirmation dialog) ───────────────────────

  void _saveNewPatient() {
    if (!patientExists) {
      if (selectedRole == "Student") {
        _instituteCtrl.text = _selectedCourse   ?? "";
        _yearCtrl.text      = _selectedYear      ?? "";
      } else if (selectedRole == "Faculty") {
        _instituteCtrl.text = _selectedInstitute ?? "";
        _yearCtrl.text      = _selectedPosition  ?? "";
      } else {
        _instituteCtrl.text = _selectedInstitute ?? "";
        _yearCtrl.text      = _selectedPosition  ?? "";
      }
    }

    if (_lastNameCtrl.text.trim().isEmpty || _firstNameCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please fill in First and Last Name first."),
            backgroundColor: Colors.orange, behavior: SnackBarBehavior.floating),
      );
      return;
    }

    final String displayId = selectedRole == "Student"
        ? _searchCtrl.text.trim()
        : selectedRole == "Faculty"
            ? "F-2020${_facultyCounter.toString().padLeft(2, '0')}"
            : "S-3000${_staffCounter.toString().padLeft(2, '0')}";

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: const [
          Icon(Icons.person_add_outlined, color: kPrimary, size: 22),
          SizedBox(width: 8),
          Text("Save New Patient?"),
        ]),
        content: SizedBox(
          width: 340,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text("The following person will be added to the patient list:",
                style: TextStyle(fontSize: 12, color: kTextSub)),
            const SizedBox(height: 12),
            _confirmRow("Name",    "${_firstNameCtrl.text.trim()} ${_lastNameCtrl.text.trim()}"),
            _confirmRow("ID",      displayId),
            _confirmRow("Role",    selectedRole),
            _confirmRow("Dept",    _instituteCtrl.text),
            _confirmRow("Yr/Pos",  _yearCtrl.text),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.pop(context);
              _doSaveNewPatient(displayId);
            },
            child: const Text("Confirm & Save"),
          ),
        ],
      ),
    );
  }

  void _doSaveNewPatient(String newId) {
    if (selectedRole == "Faculty") _facultyCounter++;
    if (selectedRole == "Staff")   _staffCounter++;

    final newPatient = {
      "id":     newId,
      "last":   _lastNameCtrl.text.trim(),
      "first":  _firstNameCtrl.text.trim(),
      "mi":     _miCtrl.text.trim(),
      "role":   selectedRole,
      "field1": _instituteCtrl.text.trim(),
      "field2": _yearCtrl.text.trim(),
    };

    setState(() {
      _patients.add(newPatient);
      _resolvedPatient    = newPatient;
      _idDisplayCtrl.text = newId;
      savedNewPatient     = true;
      showSaveButton      = false;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("$selectedRole saved with ID: $newId"),
        backgroundColor: kPrimary,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── ADD NEW MEDICINE ────────────────────────────────────────────────

  Widget _dlabel(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: kTextSub)),
      );

  InputDecoration _dialogFieldDeco(String hint, {IconData? prefixIcon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: kTextSub, fontSize: 14),
      filled: true,
      fillColor: kFieldFill,
      prefixIcon: prefixIcon != null ? Icon(prefixIcon, size: 18, color: kTextSub) : null,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBorder)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBorder)),
      focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
          borderSide: BorderSide(color: kPrimary, width: 1.5)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kDanger)),
      focusedErrorBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(10)),
          borderSide: BorderSide(color: kDanger, width: 1.5)),
    );
  }

  void _showAddMedicineDialog() {
    final nameCtrl   = TextEditingController();
    final stockCtrl  = TextEditingController();
    final maxCapCtrl = TextEditingController();
    final formKey    = GlobalKey<FormState>();

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
                Row(children: [
                  Container(
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: kPrimary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.add_circle_outline, color: kPrimary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Add New Medicine',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700, color: kTextMain)),
                      Text('Add entry to the medicine list',
                          style: TextStyle(fontSize: 13, color: kTextSub)),
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

                _dlabel('Medicine Name'),
                TextFormField(
                  controller: nameCtrl,
                  textCapitalization: TextCapitalization.words,
                  style: const TextStyle(fontSize: 14, color: kTextMain),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'Medicine name is required';
                    final exists = _medicines.any(
                      (m) => m["name"].toString().toLowerCase() == v.trim().toLowerCase(),
                    );
                    if (exists) return 'Medicine already exists';
                    return null;
                  },
                  decoration: _dialogFieldDeco('e.g. Paracetamol', prefixIcon: Icons.medication_outlined),
                ),
                const SizedBox(height: 12),

                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _dlabel('Initial Stock'),
                    TextFormField(
                      controller: stockCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: const TextStyle(fontSize: 14, color: kTextMain),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Required';
                        if (int.tryParse(v.trim()) == null) return 'Must be a number';
                        return null;
                      },
                      decoration: _dialogFieldDeco('e.g. 50', prefixIcon: Icons.inventory_2_outlined),
                    ),
                  ])),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    _dlabel('Max Capacity'),
                    TextFormField(
                      controller: maxCapCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      style: const TextStyle(fontSize: 14, color: kTextMain),
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'Required';
                        final n = int.tryParse(v.trim());
                        if (n == null) return 'Must be a number';
                        final stock = int.tryParse(stockCtrl.text.trim()) ?? 0;
                        if (n < stock) return '≥ stock';
                        return null;
                      },
                      decoration: _dialogFieldDeco('e.g. 200', prefixIcon: Icons.bar_chart_outlined),
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
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                    ),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton.icon(
                    onPressed: () {
                      if (!formKey.currentState!.validate()) return;
                      final medName  = nameCtrl.text.trim();
                      final medStock = int.parse(stockCtrl.text.trim());
                      Navigator.pop(ctx);
                      setState(() => _medicines.add({"name": medName, "stock": medStock}));
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('"$medName" added to medicine list.'),
                          backgroundColor: kPrimary,
                          behavior: SnackBarBehavior.floating,
                        ),
                      );
                    },
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Add Medicine', style: TextStyle(fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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

  // ── COMPLETE CONSULTATION ─────────────────────────────────────────────

  void _completeConsultation() {
    if (!_formKey.currentState!.validate()) return;

    final String name = "${_lastNameCtrl.text} ${_firstNameCtrl.text} ${_miCtrl.text}".trim();
    final String id   = _idDisplayCtrl.text.isNotEmpty ? _idDisplayCtrl.text : (_resolvedPatient?["id"] ?? "—");
    final String now  = DateFormat("yyyy-MM-dd").format(DateTime.now());
    final String time = DateFormat("hh:mm a").format(DateTime.now());

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: const [
          Icon(Icons.check_circle_outline, color: kPrimary, size: 22),
          SizedBox(width: 8),
          Text("Confirm Consultation"),
        ]),
        content: SizedBox(
          width: 360,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            _confirmRow("Patient",   name),
            _confirmRow("ID",        id),
            _confirmRow("Role",      selectedRole),
            _confirmRow("Dept",      _instituteCtrl.text),
            _confirmRow("Year/Pos",  _yearCtrl.text),
            _confirmRow("Complaint", _complaintText),
            _confirmRow("Medicine",  selectedMedicine ?? "None"),
            _confirmRow("Qty",       selectedMedicine != null ? _qtyCtrl.text : "—"),
            _confirmRow("Date",      now),
            _confirmRow("Time",      time),
            const SizedBox(height: 4),
            _confirmRow("Recorded by", _currentUserName),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.pop(context);

              final nowStamp = DateTime.now();
              _visitRecords.add({
                "patientId":  id,
                "patientName": name,
                "role":       selectedRole,
                "dept":       _instituteCtrl.text,
                "yearPos":    _yearCtrl.text,
                "complaint":  _complaintText,
                "medicine":   selectedMedicine ?? "None",
                "qty":        selectedMedicine != null ? _qtyCtrl.text : "—",
                "createdBy":  _currentUserName,
                "createdAt":  nowStamp,
                "updatedBy":  _currentUserName,
                "updatedAt":  nowStamp,
              });

              _resetForm();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text("Consultation saved by $_currentUserName."),
                  backgroundColor: kPrimary,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Text("Confirm & Save"),
          ),
        ],
      ),
    );
  }

  Widget _confirmRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(width: 90, child: Text("$label:", style: const TextStyle(fontSize: 13, color: kTextSub))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
      ]),
    );
  }

  void _resetForm() {
    setState(() {
      patientExists    = false;
      savedNewPatient  = false;
      showSaveButton   = false;
      _nameSuggestions = [];
      _resolvedPatient = null;
      selectedMedicine = null;
      _selectedCourse    = null;
      _selectedYear      = null;
      _selectedInstitute = null;
      _selectedPosition  = null;
      _searchCtrl.clear();
      _clearPatientFields();
      _selectedSymptom = null;
      _otherSymptomCtrl.clear();
      _qtyCtrl.clear();
      _medSearchCtrl.clear();
    });
  }

  // ── BUILD ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final filteredMeds = _medicines
        .where((m) => m["name"].toString().toLowerCase()
            .contains(_medSearchCtrl.text.toLowerCase()))
        .toList();

    final bool canProceed = patientExists || savedNewPatient;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      bottomNavigationBar: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
        color: const Color(0xFFF1F5F9),
        child: SizedBox(
          height: 50,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: canProceed ? kPrimary : Colors.grey.shade400,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: canProceed ? _completeConsultation : null,
            child: const Text("COMPLETE CONSULTATION",
                style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, letterSpacing: 0.5)),
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                  child: const Icon(Icons.medical_services_outlined, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 14),
                const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Clinic Consultation',
                      style: TextStyle(fontSize: 23, fontWeight: FontWeight.w800, color: kTextMain)),
                  Text('Record a patient visit and issue medicine',
                      style: TextStyle(fontSize: 15, color: kTextSub)),
                ]),
                const SizedBox(width: 14),
                
              ]),
              const SizedBox(height: 20),
              LayoutBuilder(builder: (context, constraints) {
                final isMobile = constraints.maxWidth < 800;
                return isMobile
                    ? Column(children: [
                        _patientSection(),
                        const SizedBox(height: 20),
                        _medicineSection(filteredMeds),
                      ])
                    : IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(flex: 2, child: _patientSection()),
                            const SizedBox(width: 25),
                            Expanded(child: _medicineSection(filteredMeds)),
                          ],
                        ),
                      );
              }),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  // ── PATIENT SECTION ───────────────────────────────────────────────────

  Widget _patientSection() {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        const Text("Patient Classification", style: kSectionTitleStyle),
        const SizedBox(height: 10),
        Container(
          height: 46,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFFEEF2F6),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: ["Student", "Faculty", "Staff"].map((role) {
              final sel = selectedRole == role;
              return Expanded(
                child: GestureDetector(
                  onTap: () => _onRoleChanged(role),
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
                        role == 'Student'
                            ? Icons.school_outlined
                            : role == 'Faculty'
                                ? Icons.person_outlined
                                : Icons.badge_outlined,
                        size: 15,
                        color: sel ? Colors.white : kTextSub,
                      ),
                      const SizedBox(width: 6),
                      Text(role,
                          style: TextStyle(
                              fontSize: 15,
                              fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                              color: sel ? Colors.white : kTextSub)),
                    ]),
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: 18),

        _buildSearchField(),

        if (_nameSuggestions.isNotEmpty) _buildSuggestions(),

        const SizedBox(height: 14),

        if ((patientExists || savedNewPatient) && _idDisplayCtrl.text.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _readOnlyField(_idDisplayCtrl.text,
                label: selectedRole == "Student" ? "Student ID" : "${selectedRole} ID (System)"),
          ),

        _responsiveFieldRow([
          _inputField(_lastNameCtrl,  "Last Name",  readOnly: patientExists),
          _inputField(_firstNameCtrl, "First Name", readOnly: patientExists),
          _inputField(_miCtrl, "M.I", readOnly: patientExists, required: false),
        ]),

        const SizedBox(height: 10),

        _responsiveFieldRow([
          patientExists
              ? _lockableField(
                  fieldKey: 'dept',
                  label: selectedRole == "Student" ? "Course" : "Institute/Dept",
                  controller: _instituteCtrl,
                  options: selectedRole == "Student" ? courses : institutes,
                  isEditing: _editingCourseField,
                  setEditingFlag: (v) => setState(() => _editingCourseField = v),
                )
              : _buildDropdownField(
                  label: selectedRole == "Student" ? "Course" : "Institute/Dept",
                  value: selectedRole == "Student" ? _selectedCourse : _selectedInstitute,
                  items: selectedRole == "Student" ? courses : institutes,
                  controller: _instituteCtrl,
                  onChanged: (v) => setState(() {
                    if (selectedRole == "Student") {
                      _selectedCourse    = v;
                    } else {
                      _selectedInstitute = v;
                    }
                    _instituteCtrl.text = v ?? "";
                  }),
                ),

          patientExists
              ? _lockableField(
                  fieldKey: 'yearpos',
                  label: selectedRole == "Student" ? "Year Level" : "Position",
                  controller: _yearCtrl,
                  options: selectedRole == "Student" ? years : positions,
                  isEditing: _editingYearField,
                  setEditingFlag: (v) => setState(() => _editingYearField = v),
                )
              : _buildDropdownField(
                  label: selectedRole == "Student" ? "Year Level" : "Position",
                  value: selectedRole == "Student" ? _selectedYear : _selectedPosition,
                  items: selectedRole == "Student" ? years : positions,
                  controller: _yearCtrl,
                  onChanged: (v) => setState(() {
                    if (selectedRole == "Student") {
                      _selectedYear     = v;
                    } else {
                      _selectedPosition = v;
                    }
                    _yearCtrl.text = v ?? "";
                  }),
                ),
        ]),

        if (showSaveButton) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: kInfo.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kInfo.withOpacity(0.25)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: const [
                Icon(Icons.info_outline, size: 16, color: kInfo),
                SizedBox(width: 8),
                Expanded(
                  child: Text("No existing record — enter details below to create one.",
                      style: TextStyle(color: kInfo, fontSize: 13, fontWeight: FontWeight.w600)),
                ),
              ]),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 46,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPrimary,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    textStyle: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
                  ),
                  onPressed: _saveNewPatient,
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text("Save Patient Info"),
                ),
              ),
            ]),
          ),
        ],

        const SizedBox(height: 14),

        const Text("Symptoms / Reason for Visit", style: kFieldLabelStyle),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: _selectedSymptom,
          isExpanded: true,
          validator: (v) => v == null ? "Please select a symptom" : null,
          onChanged: (v) => setState(() => _selectedSymptom = v),
          decoration: InputDecoration(
            hintText: "Select symptom",
            hintStyle: const TextStyle(fontSize: 14, color: kTextSub),
            prefixIcon: const Icon(Icons.medical_information_outlined, size: 18, color: kTextSub),
            filled: true,
            fillColor: kFieldFill,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: kPrimary, width: 1.5)),
          ),
          style: const TextStyle(fontSize: 14, color: kTextMain),
          items: symptomOptions
              .map((e) => DropdownMenuItem(value: e, child: Text(e, style: const TextStyle(fontSize: 14))))
              .toList(),
        ),

        if (_selectedSymptom == 'Other') ...[
          const SizedBox(height: 10),
          TextFormField(
            controller: _otherSymptomCtrl,
            maxLines: 2,
            style: const TextStyle(fontSize: 14),
            validator: (v) => (v == null || v.trim().isEmpty)
                ? "Please describe the symptom"
                : null,
            decoration: InputDecoration(
              hintText: "Describe the symptom or reason for visit...",
              hintStyle: const TextStyle(fontSize: 14, color: kTextSub),
              filled: true,
              fillColor: kFieldFill,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: kPrimary, width: 1.5)),
            ),
          ),
        ],
      ]),
    );
  }

  // ── DROPDOWN FIELD ────────────────────────────────────────────────────

  Widget _buildDropdownField({
    required String label,
    required String? value,
    required List<String> items,
    required TextEditingController controller,
    required void Function(String?) onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      validator: (v) => (v == null || v.isEmpty) ? "Required" : null,
      onChanged: onChanged,
      decoration: InputDecoration(
        hintText: label,
        hintStyle: const TextStyle(fontSize: 14, color: kTextSub),
        filled: true,
        fillColor: kFieldFill,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
      style: const TextStyle(fontSize: 14, color: kTextMain),
      items: items
          .map((e) => DropdownMenuItem(
              value: e,
              child: Text(e, style: const TextStyle(fontSize: 14), overflow: TextOverflow.ellipsis)))
          .toList(),
    );
  }

  // ── SEARCH FIELD ──────────────────────────────────────────────────────

  Widget _buildSearchField() {
    final isStudent = selectedRole == "Student";
    return TextField(
      controller: _searchCtrl,
      onChanged: _onSearchChanged,
      decoration: InputDecoration(
        hintText: isStudent
            ? "Enter Student ID to auto-fill..."
            : "Search by name (Last or First)...",
        prefixIcon: Icon(isStudent ? Icons.badge_outlined : Icons.search,
            size: 20, color: kPrimary),
        suffixIcon: patientExists
            ? const Icon(Icons.check_circle, color: kPrimary, size: 20)
            : null,
        filled: true,
        fillColor: patientExists
            ? kPrimary.withOpacity(0.06)
            : kFieldFill,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: patientExists
              ? const BorderSide(color: kPrimary, width: 1.2)
              : BorderSide.none,
        ),
      ),
    );
  }

  // ── SUGGESTION DROPDOWN ───────────────────────────────────────────────

  Widget _buildSuggestions() {
    return Container(
      margin: const EdgeInsets.only(top: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 8,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: _nameSuggestions.map((p) {
          final hasId = (p["id"] as String).isNotEmpty;
          return InkWell(
            onTap: () => _selectSuggestion(p),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Row(children: [
                CircleAvatar(
                  radius: 16,
                  backgroundColor: kPrimary.withOpacity(0.1),
                  child: Text("${p["first"][0]}${p["last"][0]}",
                      style: const TextStyle(
                          fontSize: 12,
                          color: kPrimary,
                          fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 10),
                Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text("${p["first"]} ${p["last"]}",
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  Text("${p["field1"]} · ${p["field2"]}",
                      style: kCaptionStyle),
                ])),
                if (hasId)
                  Text(p["id"], style: kCaptionStyle),
              ]),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── READ-ONLY ID DISPLAY ──────────────────────────────────────────────

  Widget _readOnlyField(String value, {required String label}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: kPrimary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kPrimary.withOpacity(0.25)),
      ),
      child: Row(children: [
        const Icon(Icons.badge_outlined, size: 16, color: kPrimary),
        const SizedBox(width: 8),
        Text("$label: ", style: kCaptionStyle),
        Text(value,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: kPrimary)),
      ]),
    );
  }

  // ── RESPONSIVE ROW ─────────────────────────────────────────────────────
  // Uses MediaQuery (not LayoutBuilder) because this widget is used inside
  // an IntrinsicHeight ancestor on desktop, and LayoutBuilder cannot be a
  // descendant of IntrinsicHeight — that combination renders a blank screen.
  Widget _responsiveFieldRow(List<Widget> children,
      {double spacing = 10, double breakpoint = 380}) {
    final width = MediaQuery.of(context).size.width;
    if (width < breakpoint) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < children.length; i++) ...[
            children[i],
            if (i != children.length - 1) SizedBox(height: spacing),
          ],
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < children.length; i++) ...[
          Expanded(child: children[i]),
          if (i != children.length - 1) SizedBox(width: spacing),
        ],
      ],
    );
  }

  // ── LOCKABLE COURSE/YEAR-POSITION FIELD ────────────────────────────────
  Widget _lockableField({
    required String fieldKey,
    required String label,
    required TextEditingController controller,
    required List<String> options,
    required bool isEditing,
    required void Function(bool) setEditingFlag,
  }) {
    final patientId = (_resolvedPatient?["id"] ?? "").toString();

    if (!isEditing) {
      final lastChange = patientId.isEmpty ? null : _lastFieldChange(patientId, fieldKey);
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(child: _inputField(controller, label, readOnly: true)),
          const SizedBox(width: 6),
          Tooltip(
            message: "Request edit",
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => _requestFieldEdit(
                  label: label, setEditingFlag: setEditingFlag),
              child: Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: kFieldFillReadOnly,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: kBorder),
                ),
                child: const Icon(Icons.edit_outlined, size: 18, color: kTextSub),
              ),
            ),
          ),
        ]),
        if (lastChange != null)
          Padding(
            padding: const EdgeInsets.only(top: 5, left: 2),
            child: Text(
              "Last changed by ${lastChange['changedBy']} on "
              "${DateFormat('MMM d, yyyy').format(lastChange['changedAt'] as DateTime)}",
              style: kCaptionStyle,
            ),
          ),
      ]);
    }

    String? tempValue = options.contains(controller.text) ? controller.text : null;
    return StatefulBuilder(builder: (context, setLocalState) {
      return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        Expanded(
          child: DropdownButtonFormField<String>(
            value: tempValue,
            isExpanded: true,
            items: options
                .map((e) => DropdownMenuItem(
                    value: e,
                    child: Text(e, style: kFieldValueStyle, overflow: TextOverflow.ellipsis)))
                .toList(),
            onChanged: (v) => setLocalState(() => tempValue = v),
            decoration: InputDecoration(
              hintText: label,
              filled: true,
              fillColor: kFieldFill,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: kPrimary, width: 1.2)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: kPrimary, width: 1.2)),
            ),
          ),
        ),
        const SizedBox(width: 6),
        IconButton(
          tooltip: "Cancel",
          icon: const Icon(Icons.close, size: 20, color: kTextSub),
          onPressed: () => setState(() => setEditingFlag(false)),
        ),
        IconButton(
          tooltip: "Confirm change",
          icon: const Icon(Icons.check_circle, size: 22, color: kPrimary),
          onPressed: tempValue == null
              ? null
              : () => _confirmFieldChange(
                    fieldKey: fieldKey,
                    label: label,
                    controller: controller,
                    oldValue: controller.text,
                    newValue: tempValue!,
                    setEditingFlag: setEditingFlag,
                  ),
        ),
      ]);
    });
  }

  void _requestFieldEdit({
    required String label,
    required void Function(bool) setEditingFlag,
  }) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          const Icon(Icons.lock_outline, color: kPrimary, size: 22),
          const SizedBox(width: 8),
          Text("Edit $label?"),
        ]),
        content: const SizedBox(
          width: 340,
          child: Text(
            "Editing this will only update this patient's active profile. "
            "Past medical records already saved under the old value will "
            "keep their original values for historical accuracy. Continue?",
            style: kFieldValueStyle,
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.pop(context);
              setState(() => setEditingFlag(true));
            },
            child: const Text("Continue"),
          ),
        ],
      ),
    );
  }

  void _confirmFieldChange({
    required String fieldKey,
    required String label,
    required TextEditingController controller,
    required String oldValue,
    required String newValue,
    required void Function(bool) setEditingFlag,
  }) {
    final patientId = (_resolvedPatient?["id"] ?? "").toString();
    final lastChange = patientId.isEmpty ? null : _lastFieldChange(patientId, fieldKey);
    final changedRecently = lastChange != null &&
        DateTime.now().difference(lastChange['changedAt'] as DateTime).inDays < 365;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: const [
          Icon(Icons.warning_amber_rounded, color: kWarning, size: 22),
          SizedBox(width: 8),
          Text("Confirm Change"),
        ]),
        content: SizedBox(
          width: 340,
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            _confirmRow(label, "$oldValue  →  $newValue"),
            if (changedRecently) ...[
              const SizedBox(height: 10),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                    color: kWarning.withOpacity(0.08),
                    borderRadius: BorderRadius.circular(10)),
                child: Text(
                  "This was already changed on "
                  "${DateFormat('MMM d, yyyy').format(lastChange!['changedAt'] as DateTime)} "
                  "by ${lastChange['changedBy']}. Changes like this typically "
                  "happen once per academic year unless correcting an error — "
                  "continue anyway?",
                  style: const TextStyle(fontSize: 13, color: kTextMain),
                ),
              ),
            ],
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                controller.text = newValue;
                if (_resolvedPatient != null) {
                  final idx = _patients.indexWhere((p) => p["id"] == _resolvedPatient!["id"]);
                  if (idx != -1) {
                    _patients[idx][fieldKey == 'dept' ? 'field1' : 'field2'] = newValue;
                    _resolvedPatient = _patients[idx];
                  }
                }
                _courseYearAuditLog.add({
                  'patientId': patientId,
                  'field': fieldKey,
                  'oldValue': oldValue,
                  'newValue': newValue,
                  'changedBy': _currentUserName,
                  'changedAt': DateTime.now(),
                });
                setEditingFlag(false);
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text("$label updated."),
                  backgroundColor: kPrimary,
                  behavior: SnackBarBehavior.floating,
                ),
              );
            },
            child: const Text("Confirm & Save"),
          ),
        ],
      ),
    );
  }

  // ── INPUT FIELD ───────────────────────────────────────────────────────

  Widget _inputField(TextEditingController c, String hint,
      {bool readOnly = false, bool required = true}) {
    return TextFormField(
      controller: c,
      readOnly: readOnly,
      validator: required ? (v) => (v == null || v.isEmpty) ? "Required" : null : null,
      style: TextStyle(fontSize: 14, color: readOnly ? kTextSub : kTextMain),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(fontSize: 14, color: kTextSub),
        filled: true,
        fillColor: readOnly ? kFieldFillReadOnly : kFieldFill,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide:
              readOnly ? BorderSide(color: kBorder) : BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      ),
    );
  }

  // ── MEDICINE SECTION ──────────────────────────────────────────────────

  Widget _medicineSection(List filteredMeds) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration:
          BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        Row(children: [
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("Issue Medicine", style: kSectionTitleStyle),
              SizedBox(height: 2),
              Text("Select medication to issue", style: kSectionSubtitleStyle),
            ]),
          ),
          Tooltip(
            message: "Add new medicine",
            child: InkWell(
              onTap: _showAddMedicineDialog,
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: kPrimary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: kPrimary.withOpacity(0.3)),
                ),
                child: Row(mainAxisSize: MainAxisSize.min, children: const [
                  Icon(Icons.add, size: 16, color: kPrimary),
                  SizedBox(width: 4),
                  Text("Add", style: TextStyle(fontSize: 13, color: kPrimary, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ),
        ]),

        const SizedBox(height: 5),
        const Divider(),
        const SizedBox(height: 5),

        TextField(
          controller: _medSearchCtrl,
          onChanged: (v) => setState(() {}),
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: "Search medicine...",
            hintStyle: const TextStyle(fontSize: 14, color: kTextSub),
            prefixIcon: const Icon(Icons.search, size: 18),
            filled: true,
            fillColor: kFieldFill,
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          ),
        ),

        const SizedBox(height: 8),

        SizedBox(
          height: MediaQuery.of(context).size.height * 0.38,
          child: ListView.builder(
            itemCount: filteredMeds.length,
            itemBuilder: (_, i) {
              final med        = filteredMeds[i];
              final isSelected = selectedMedicine == med["name"];
              return Column(children: [
                RadioListTile(
                  dense: true,
                  visualDensity: VisualDensity.compact,
                  activeColor: kPrimary,
                  value: med["name"],
                  groupValue: selectedMedicine,
                  onChanged: (v) =>
                      setState(() { selectedMedicine = v.toString(); _qtyCtrl.clear(); }),
                  title: Text(med["name"], style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  subtitle: Text("Stock: ${med["stock"]}", style: kCaptionStyle),
                ),
                if (isSelected)
                  Padding(
                    padding: const EdgeInsets.only(left: 60, right: 20, bottom: 8),
                    child: TextFormField(
                      controller: _qtyCtrl,
                      keyboardType: TextInputType.number,
                      validator: (v) {
                        if (selectedMedicine != null &&
                            (v == null || v.isEmpty)) return "Enter quantity";
                        final n = int.tryParse(v ?? "");
                        if (n == null || n <= 0) return "Enter a valid quantity";
                        if (n > (med["stock"] as int))
                          return "Exceeds stock (${med["stock"]})";
                        return null;
                      },
                      style: const TextStyle(fontSize: 14),
                      decoration: const InputDecoration(
                        labelText: "Quantity",
                        labelStyle: TextStyle(fontSize: 13),
                      ),
                    ),
                  ),
              ]);
            },
          ),
        ),
      ]),
    );
  }
}