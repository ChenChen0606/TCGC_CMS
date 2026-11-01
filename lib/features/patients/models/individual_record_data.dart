import 'package:clinicmanagementsystem/features/patients/models/patient_directory.dart'
    as terms;

const String kPersonStatusActive = 'Active';
const String kPersonStatusArchived = 'Archived';

const String kRecordStatusActive = 'Active';
const String kRecordStatusInactive = 'Inactive';
const String kRecordStatusArchived = 'Archived';

bool isActiveStatus(String status) => status == kRecordStatusActive;

const List<String> kPersonCategories = ['Student', 'Faculty', 'Staff'];

String canonicalCategory(Object? value) {
  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty) return kPersonCategories.first;
  final q = raw.toLowerCase();
  for (final c in kPersonCategories) {
    if (c.toLowerCase() == q) return c;
  }
  return raw;
}

String personTypeForStorage(String category) => canonicalCategory(category);

class IndividualRecord {
  String? uuid;
  String id;
  String category;

  String firstName;
  String middleName;
  String lastName;
  String suffix;
  String sex;
  DateTime? birthDate;
  String contact;
  String email;
  String address;

  String personStatus;

  String? academicRecordId;

  String? academicPeriodId;

  String academicYear;
  String semester;

  String? instituteId;
  String institute;

  String? programId;
  String program;

  String yearLevel;

  String? departmentOfficeId;
  String department;

  String? positionId;
  String position;

  String status;

  DateTime? createdAt;
  String? createdBy;

  IndividualRecord({
    this.uuid,
    required this.id,
    required this.category,
    this.firstName = '',
    this.middleName = '',
    this.lastName = '',
    this.suffix = '',
    this.sex = '',
    this.birthDate,
    this.contact = '',
    this.email = '',
    this.address = '',
    this.personStatus = kPersonStatusActive,
    this.academicRecordId,
    this.academicPeriodId,
    this.academicYear = '',
    this.semester = '',
    this.instituteId,
    this.institute = '',
    this.programId,
    this.program = '',
    this.yearLevel = '',
    this.departmentOfficeId,
    this.department = '',
    this.positionId,
    this.position = '',
    this.status = kRecordStatusActive,
    this.createdAt,
    this.createdBy,
  });

  bool get isStudent => category == 'Student';

  bool get isActive =>
      isActiveStatus(status) && personStatus == kPersonStatusActive;

  bool get isArchived =>
      personStatus == kPersonStatusArchived || status == kRecordStatusArchived;

  String get fullName {
    final parts = [firstName, middleName, lastName, suffix]
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return parts.isEmpty ? '—' : parts.join(' ');
  }

  String get programLabel {
    if (isStudent) {
      return program.isEmpty ? '—' : program;
    }
    if (category == 'Faculty') return institute.isEmpty ? '—' : institute;
    return department.isEmpty ? '—' : department;
  }

  String get affiliationLabel {
    if (isStudent) return program.isEmpty ? '—' : program;
    final base = category == 'Faculty' ? institute : department;
    final parts = [base, position]
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return parts.isEmpty ? '—' : parts.join(' · ');
  }

  String get dbKey => '$personKey|$academicPeriodId';

  String get personKey => '$category|$id';

  bool get isCurrentTerm => terms.isCurrentTerm(academicYear, semester);

  IndividualRecord clone() => IndividualRecord(
        uuid: uuid,
        id: id,
        category: category,
        firstName: firstName,
        middleName: middleName,
        lastName: lastName,
        suffix: suffix,
        sex: sex,
        birthDate: birthDate,
        contact: contact,
        email: email,
        address: address,
        personStatus: personStatus,
        academicRecordId: academicRecordId,
        academicPeriodId: academicPeriodId,
        academicYear: academicYear,
        semester: semester,
        instituteId: instituteId,
        institute: institute,
        programId: programId,
        program: program,
        yearLevel: yearLevel,
        departmentOfficeId: departmentOfficeId,
        department: department,
        positionId: positionId,
        position: position,
        status: status,
        createdAt: createdAt,
        createdBy: createdBy,
      );

  factory IndividualRecord.fromSupabase(Map<String, dynamic> m) {
    final embeddedPerson = m['person'];
    final person = embeddedPerson is Map<String, dynamic> ? embeddedPerson : m;

    final academic = embeddedPerson is Map<String, dynamic>
        ? m
        : (m['academic'] is Map<String, dynamic>
            ? m['academic'] as Map<String, dynamic>
            : null);

    String? asString(Object? v) {
      if (v == null) return null;
      final s = '$v';
      return s.isEmpty ? null : s;
    }

    String text(Object? v) {
      if (v == null) return '';
      final s = '$v';
      return s == 'null' ? '' : s;
    }

    String joined(Object? ref, String key) {
      if (ref is Map) return text(ref[key]);
      return '';
    }

    final academicStatus = asString(academic?['status']);

    return IndividualRecord(
      uuid: asString(person['person_id']),
      id: asString(person['person_id']) ?? '',
      category: canonicalCategory(person['person_type']),
      firstName: text(person['fn']),
      middleName: text(person['mn']),
      lastName: text(person['ln']),
      suffix: text(person['suffix']),
      sex: text(person['sex']),
      birthDate: _parseTs(person['date_of_birth']),
      contact: text(person['contact_number']),
      email: text(person['email']),
      address: text(person['address']),
      personStatus: academicStatus == kRecordStatusArchived
          ? kPersonStatusArchived
          : kPersonStatusActive,
      academicRecordId: asString(academic?['academic_record_id']),
      academicPeriodId: asString(academic?['academic_period_id']),
      academicYear: joined(academic?['period'], 'acad_year'),
      semester: joined(academic?['period'], 'semester'),
      instituteId: asString(academic?['institute_id']),
      institute: joined(academic?['institute'], 'code'),
      programId: asString(academic?['program_id']),
      program: joined(academic?['program_ref'], 'code'),
      yearLevel: text(academic?['year_level']),
      departmentOfficeId: asString(academic?['department_office_id']),
      department: joined(academic?['department_ref'], 'name'),
      positionId: asString(academic?['position_id']),
      position: joined(academic?['position_ref'], 'name'),
      status: academicStatus ?? kRecordStatusActive,
      createdAt: _parseTs(person['created_at']),
      createdBy: asString(person['created_by']),
    );
  }

  Map<String, dynamic> personPayload({bool includeAudit = true}) => {
        if (uuid == null || uuid != id) 'person_id': id,
        'person_type': personTypeForStorage(category),
        'fn': firstName,
        'mn': _nullIfEmpty(middleName),
        'ln': lastName,
        'suffix': _nullIfEmpty(suffix),
        'sex': _nullIfEmpty(sex),
        'date_of_birth': _dateString(birthDate),
        'contact_number': _nullIfEmpty(contact),
        'email': _nullIfEmpty(email),
        'address': _nullIfEmpty(address),
        if (includeAudit && (createdBy ?? '').trim().isNotEmpty) ...{
          'created_by': createdBy,
          'userid': createdBy,
        },
      };

  Map<String, dynamic> academicPayload({bool includeAudit = true}) {
    final student = isStudent;
    final by = (createdBy ?? '').trim();
    return {
      'academic_period_id': academicPeriodId,
      'institute_id':
          student || category == 'Faculty' ? _nullIfEmpty(instituteId) : null,
      'program_id': student ? _nullIfEmpty(programId) : null,
      'year_level': student ? _nullIfEmpty(yearLevel) : null,
      'department_office_id':
          category == 'Staff' ? _nullIfEmpty(departmentOfficeId) : null,
      'position_id': student ? null : _nullIfEmpty(positionId),
      'status': status,
      if (includeAudit && by.isNotEmpty) ...{
        'created_by': createdBy,
        'userid': createdBy,
      },
    };
  }

  Map<String, dynamic> toSupabase() => {
        'person': personPayload(),
        'academic': academicPayload(),
      };

  static String? _nullIfEmpty(String? v) {
    if (v == null) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  static String? _dateString(DateTime? d) =>
      d == null ? null : _dateStringOf(d);

  static String _dateStringOf(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  static DateTime? _parseTs(Object? v) {
    if (v is DateTime) return v;
    if (v is String && v.isNotEmpty) {
      final parsed = DateTime.tryParse(v);
      if (parsed == null) return null;
      if (v.length == 10) {
        return DateTime(parsed.year, parsed.month, parsed.day);
      }
      return parsed.toLocal();
    }
    return null;
  }
}

const String kImportNew = 'New';
const String kImportUpdated = 'Updated';
const String kImportUnchanged = 'Unchanged';

List<IndividualRecord> filterRoster({
  required List<IndividualRecord> rows,
  required String category,
  String query = '',
}) {
  final q = query.trim().toLowerCase();
  return rows
      .where((r) => r.category == category)
      .where((r) =>
          q.isEmpty ||
          r.id.toLowerCase().contains(q) ||
          r.fullName.toLowerCase().contains(q) ||
          _reversedName(r).contains(q) ||
          r.program.toLowerCase().contains(q) ||
          r.institute.toLowerCase().contains(q) ||
          r.department.toLowerCase().contains(q) ||
          r.yearLevel.toLowerCase().contains(q) ||
          r.position.toLowerCase().contains(q) ||
          r.contact.toLowerCase().contains(q) ||
          r.address.toLowerCase().contains(q) ||
          r.email.toLowerCase().contains(q))
      .toList()
    ..sort((a, b) => compareIdNumbers(a.id, b.id));
}

int compareIdNumbers(String a, String b) {
  final aTokens = _idTokens(a);
  final bTokens = _idTokens(b);
  final shared =
      aTokens.length < bTokens.length ? aTokens.length : bTokens.length;
  for (var i = 0; i < shared; i++) {
    final cmp = _idTokenCompare(aTokens[i], bTokens[i]);
    if (cmp != 0) return cmp;
  }
  return aTokens.length.compareTo(bTokens.length);
}

List<String> _idTokens(String value) {
  final tokens = <String>[];
  final re = RegExp(r'\d+|[^\d]+');
  var rest = value.trim().toLowerCase();
  while (rest.isNotEmpty) {
    final m = re.firstMatch(rest);
    if (m == null) break;
    tokens.add(m.group(0)!);
    rest = rest.substring(m.end);
  }
  return tokens;
}

int _idTokenCompare(String a, String b) {
  final aNum = int.tryParse(a);
  final bNum = int.tryParse(b);
  if (aNum != null && bNum != null) return aNum.compareTo(bNum);
  return a.compareTo(b);
}

String _reversedName(IndividualRecord r) {
  final last = r.lastName.trim().toLowerCase();
  if (last.isEmpty) return '';
  final rest = [r.firstName, r.middleName]
      .map((n) => n.trim())
      .where((n) => n.isNotEmpty)
      .join(' ')
      .toLowerCase();
  return rest.isEmpty ? last : '$last, $rest';
}

int countInCategory(List<IndividualRecord> rows, String category) =>
    rows.where((r) => r.category == category).length;
