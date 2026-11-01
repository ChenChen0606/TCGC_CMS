class Patient {
  String? uuid;
  String id;
  String last;
  String first;
  String mi;
  String field1;
  String field2;
  String category;
  String contact;
  String emergencyName;
  String emergencyContact;

  DateTime? createdAt;
  DateTime? updatedAt;
  String? createdBy;
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
