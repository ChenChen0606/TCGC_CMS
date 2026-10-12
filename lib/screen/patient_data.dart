// ─────────────────────────────────────────────────────────────────────────────
//  patient_data.dart
//  Shared Patient model + in-memory PatientData store.
//  Imported by the screens that need patient records. Swap PatientData with a
//  Firestore/API layer later without
//  touching the UI — screens only read/write `PatientData.patients`.
// ─────────────────────────────────────────────────────────────────────────────

class Patient {
  String? uuid; // Supabase row id (null when not persisted yet)
  String id; // display ID (Student ID / Faculty ID / Staff ID) → DB patient_no
  String last;
  String first;
  String mi;
  String field1; // Student → Program | Faculty/Staff → Position
  String field2; // Student → Year Level | Faculty/Staff → Office / Department
  String category; // 'Student' | 'Faculty' | 'Staff'
  String contact;
  String emergencyName;
  String emergencyContact;

  // ── Audit trail (maintained server-side by DB triggers) ──────────────
  DateTime? createdAt;
  DateTime? updatedAt;
  String? createdBy; // useraccount.user_id (uuid)
  String? updatedBy;

  Patient({
    this.uuid,
    required this.id,
    required this.last,
    required this.first,
    this.mi = '',
    this.field1 = '',
    this.field2 = '',
    required this.category,
    this.contact = '',
    this.emergencyName = '',
    this.emergencyContact = '',
    this.createdAt,
    this.updatedAt,
    this.createdBy,
    this.updatedBy,
  });

  String get fullName => '$first${mi.isNotEmpty ? ' $mi.' : ''} $last';

  /// Build a Patient from a `patients` row returned by Supabase.
  factory Patient.fromSupabase(Map<String, dynamic> m) {
    final String category = m['category'] as String? ?? 'Student';
    final bool isStudent = category == 'Student';
    return Patient(
      uuid: m['id'] as String?,
      id: m['patient_no'] as String? ?? '',
      last: m['last_name'] as String? ?? '',
      first: m['first_name'] as String? ?? '',
      mi: m['middle_initial'] as String? ?? '',
      field1: isStudent
          ? (m['institute'] as String? ?? '')
          : (m['position'] as String? ?? ''),
      field2: isStudent
          ? (m['year_level'] as String? ?? '')
          : (m['office_department'] as String? ?? ''),
      category: category,
      contact: m['contact'] as String? ?? '',
      emergencyName: m['emergency_name'] as String? ?? '',
      emergencyContact: m['emergency_contact'] as String? ?? '',
      createdAt: _parseTs(m['created_at']),
      updatedAt: _parseTs(m['updated_at']),
      createdBy: m['created_by'] as String?,
      updatedBy: m['updated_by'] as String?,
    );
  }

  /// Payload for INSERT/UPDATE. Category-specific columns use NULL when they
  /// don't apply so the `patients_category_fields` check constraint passes.
  Map<String, dynamic> toSupabase() {
    final bool isStudent = category == 'Student';
    return {
      'patient_no': id,
      'category': category,
      'last_name': last,
      'first_name': first,
      'middle_initial': mi,
      'institute': isStudent ? field1 : null,
      'year_level': isStudent ? field2 : null,
      'position': isStudent ? null : field1,
      'office_department': isStudent ? null : field2,
      'contact': contact,
      'emergency_name': emergencyName,
      'emergency_contact': emergencyContact,
    };
  }

  static DateTime? _parseTs(Object? v) {
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }
}

/// In-memory singleton store (no database yet).
/// Mirrors the same static-store pattern used by `user_store.dart`.
class PatientData {
  PatientData._();

  static final List<Patient> patients = [
    Patient(
        id: '234567',
        last: 'Delacruz',
        first: 'Cresa',
        mi: 'S',
        field1: 'ICS',
        field2: '2nd Year',
        category: 'Student',
        contact: '09171234567',
        emergencyName: 'Maria Delacruz',
        emergencyContact: '09179876543'),
    Patient(
        id: '234889',
        last: 'Doe',
        first: 'John',
        mi: 'A',
        field1: 'ITE',
        field2: '3rd Year',
        category: 'Student',
        contact: '09201234567',
        emergencyName: 'Anna Doe',
        emergencyContact: '09209876543'),
    Patient(
        id: 'F001',
        last: 'Smith',
        first: 'Jane',
        mi: '',
        field1: 'Dean',
        field2: 'IAS',
        category: 'Faculty',
        contact: '09151234567',
        emergencyName: '',
        emergencyContact: ''),
    Patient(
        id: 'F002',
        last: 'Garcia',
        first: 'Ramon',
        mi: '',
        field1: 'Instructor',
        field2: 'ICS',
        category: 'Faculty',
        contact: '09161234567',
        emergencyName: '',
        emergencyContact: ''),
    Patient(
        id: 'S001',
        last: 'Lee',
        first: 'Mark',
        mi: '',
        field1: 'Security Guard',
        field2: 'Registrar',
        category: 'Staff',
        contact: '09181234567',
        emergencyName: '',
        emergencyContact: ''),
    Patient(
        id: 'S002',
        last: 'Navarro',
        first: 'Rosa',
        mi: '',
        field1: 'Librarian',
        field2: 'Library',
        category: 'Staff',
        contact: '09191234567',
        emergencyName: '',
        emergencyContact: ''),
  ];

  /// Next available Faculty ID in the F### format (F001, F002, ...).
  static String nextFacultyId() => _nextSequentialId('Faculty', 'F');

  /// Next available Staff ID in the S### format (S001, S002, ...).
  static String nextStaffId() => _nextSequentialId('Staff', 'S');

  static String _nextSequentialId(String category, String prefix) {
    final ids = patients
        .where((p) => p.category == category)
        .map((p) => p.id)
        .where((id) =>
            id.startsWith(prefix) &&
            RegExp(r'^\d+$').hasMatch(id.substring(prefix.length)))
        .map((id) => int.tryParse(id.substring(prefix.length)) ?? 0)
        .toList();

    final int next =
        ids.isEmpty ? 1 : (ids.reduce((a, b) => a > b ? a : b) + 1);
    return '$prefix${next.toString().padLeft(3, '0')}';
  }
}
