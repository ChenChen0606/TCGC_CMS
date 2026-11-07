import 'dart:math';

import 'package:clinicmanagementsystem/core/services/reference_data_service.dart';

const List<String> kSemesters = ['1st Semester', '2nd Semester', 'Summer'];
const String kDefaultSemester = '1st Semester';
const List<String> kSexes = ['Male', 'Female'];
const List<String> kYearLevels = [
  '1st Year',
  '2nd Year',
  '3rd Year',
  '4th Year',
];

List<({String year, String semester})> get kAcademicTerms => [
      for (final p in ReferenceCatalog.periodsNewestFirst)
        (year: p.acadYear, semester: p.semester),
    ];

String get kCurrentAcademicYear =>
    ReferenceCatalog.currentPeriod?.acadYear ?? '';
String get kCurrentSemester =>
    ReferenceCatalog.currentPeriod?.semester ?? kDefaultSemester;

String? get kCurrentAcademicPeriodId => ReferenceCatalog.currentPeriod?.id;

String academicTermLabel(String year, String semester) => '$year · $semester';

bool isCurrentTerm(String year, String semester) {
  final active = ReferenceCatalog.activePeriod;
  if (active == null) {
    return year == kCurrentAcademicYear && semester == kCurrentSemester;
  }
  return year == active.acadYear && semester == active.semester;
}

({String year, String semester}) termOf(String year, String semester) {
  if (year.trim().isEmpty) {
    return (year: kCurrentAcademicYear, semester: kCurrentSemester);
  }
  return (year: year.trim(), semester: semester.trim());
}

Map<String, List<String>> get kProgramCatalog {
  final map = <String, List<String>>{};
  for (final e in ReferenceCatalog.institutes) {
    map[e.code] = ReferenceCatalog.programsOf(e.id);
  }
  return Map<String, List<String>>.unmodifiable(map);
}

List<String> get kInstitutes => ReferenceCatalog.instituteCodes;

List<String> programsOf(String? instituteCode) {
  final inst = ReferenceCatalog.instituteByCode(instituteCode) ??
      ReferenceCatalog.instituteById(instituteCode);
  return ReferenceCatalog.programsOf(inst?.id);
}

String? instituteOfProgram(String? programCode) {
  final id = ReferenceCatalog.instituteIdOfProgram(programCode);
  return id == null ? null : ReferenceCatalog.instituteCodeOf(id);
}

List<String> departmentOptionsFor(String? category) =>
    ReferenceCatalog.departmentNames;

List<String> positionOptionsFor(String? category) =>
    ReferenceCatalog.positionNames;

List<String> get kFacultyPositions => ReferenceCatalog.positionNames;

List<String> get kStaffPositions => ReferenceCatalog.positionNames;

List<String> get kStaffDepartments => ReferenceCatalog.departmentNames;

class ClinicProfile {
  String? uuid;

  String id;
  String category;

  String firstName;
  String middleName;
  String lastName;
  String suffix;
  String sex;
  String birthDate;
  String contact;
  String email;
  String address;

  String academicYear;
  String semester;
  String institute;
  String program;
  String yearLevel;
  String department;
  String position;

  String emergencyName;
  String emergencyContact;

  String status;

  DateTime? createdAt;
  String? createdBy;
  DateTime? updatedAt;
  String? updatedBy;

  ClinicProfile({
    this.uuid,
    required this.id,
    required this.category,
    this.firstName = '',
    this.middleName = '',
    this.lastName = '',
    this.suffix = '',
    this.sex = '',
    this.birthDate = '',
    this.contact = '',
    this.email = '',
    this.address = '',
    this.academicYear = '',
    this.semester = '',
    this.institute = '',
    this.program = '',
    this.yearLevel = '',
    this.department = '',
    this.position = '',
    this.emergencyName = '',
    this.emergencyContact = '',
    this.status = 'Active',
    this.createdAt,
    this.createdBy,
    this.updatedAt,
    this.updatedBy,
  });

  bool get isStudent => category == 'Student';
  bool get isFaculty => category == 'Faculty';
  bool get isStaff => category == 'Staff';

  bool get isActive => status == 'Active';

  String get fullName {
    final mid = middleName.trim().isEmpty ? '' : ' $middleName';
    return '$firstName$mid $lastName'.trim();
  }

  String get middleInitial {
    final m = middleName.trim();
    return m.isEmpty ? '' : '${m[0]}.';
  }

  String get programLabel => isStudent
      ? (program.isEmpty ? '-' : program)
      : (position.isEmpty ? '-' : position);

  String get affiliationLabel {
    final parts = <String>[
      if (isStudent) institute,
      if (isStudent) program,
      if (isStudent) yearLevel,
      if (!isStudent) institute,
      if (!isStudent) department,
      if (!isStudent) position,
    ];
    return parts.where((e) => e.isNotEmpty).join(' · ');
  }

  String get searchable {
    final instName = ReferenceCatalog.instituteByCode(institute)?.name ?? '';
    final inst = ReferenceCatalog.instituteByCode(institute);
    final progName = ReferenceCatalog.programById(
                ReferenceCatalog.programIdFor(inst?.id, program))
            ?.name ??
        ReferenceCatalog.programByCode(program)?.name ??
        '';
    return [
      id,
      firstName,
      middleName,
      lastName,
      fullName,
      '$lastName, $firstName',
      category,
      institute,
      instName,
      program,
      progName,
      yearLevel,
      department,
      position,
      contact,
    ].join(' ').toLowerCase();
  }

  ClinicProfile clone() => ClinicProfile(
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
        academicYear: academicYear,
        semester: semester,
        institute: institute,
        program: program,
        yearLevel: yearLevel,
        department: department,
        position: position,
        emergencyName: emergencyName,
        emergencyContact: emergencyContact,
        status: status,
        createdAt: createdAt,
        createdBy: createdBy,
        updatedAt: updatedAt,
        updatedBy: updatedBy,
      );
}

class PatientDirectory {
  PatientDirectory._();

  static final PatientDirectory instance = PatientDirectory._();

  static final Random _random = Random();

  final List<ClinicProfile> _all = <ClinicProfile>[];
  final List<void Function()> _listeners = [];

  List<ClinicProfile> get all => List<ClinicProfile>.unmodifiable(_all);

  int get length => _all.length;

  List<ClinicProfile> search(String query, {String? category}) {
    final q = query.trim().toLowerCase();
    final pool = category == null
        ? _all
        : _all.where((p) => p.category == category).toList();
    if (q.isEmpty) {
      final list = List<ClinicProfile>.of(pool)
        ..sort((a, b) => a.lastName.compareTo(b.lastName));
      return list;
    }
    final hits = pool.where((p) => p.searchable.contains(q)).toList();
    hits.sort((a, b) {
      final aExact = a.id.toLowerCase() == q ? 0 : 1;
      final bExact = b.id.toLowerCase() == q ? 0 : 1;
      if (aExact != bExact) return aExact - bExact;
      return a.lastName.compareTo(b.lastName);
    });
    return hits;
  }

  ClinicProfile? byId(String? id) {
    final q = (id ?? '').trim();
    if (q.isEmpty) return null;
    for (final p in _all) {
      if (p.id.toLowerCase() == q.toLowerCase()) return p;
    }
    return null;
  }

  int countFor(String category) =>
      _all.where((p) => p.category == category).length;

  void hydrate(List<ClinicProfile> profiles) {
    _all
      ..clear()
      ..addAll(profiles);
    _notify();
  }

  bool holds(String id) => byId(id) != null;

  ClinicProfile upsert(ClinicProfile profile) {
    final i =
        _all.indexWhere((p) => p.id.toLowerCase() == profile.id.toLowerCase());
    if (i >= 0) {
      profile.updatedAt = DateTime.now();
      _all[i] = profile;
    } else {
      profile.createdAt ??= DateTime.now();
      _all.add(profile);
    }
    _notify();
    return profile;
  }

  ClinicProfile? update(
      String id, void Function(ClinicProfile profile) mutate) {
    final current = byId(id);
    if (current == null) return null;
    final next = current.clone()..id = current.id;
    mutate(next);
    next.updatedAt = DateTime.now();
    return upsert(next);
  }

  bool remove(String id) {
    final before = _all.length;
    _all.removeWhere((p) => p.id.toLowerCase() == id.trim().toLowerCase());
    final changed = _all.length != before;
    if (changed) _notify();
    return changed;
  }

  String nextIdFor(String category, [String academicYear = '']) {
    final letter = category == 'Staff' ? 'S' : 'F';
    final taken = _all.map((p) => p.id.toLowerCase()).toSet();
    final random = _random;
    for (var attempt = 0; attempt < 50; attempt++) {
      final candidate = '$letter${(random.nextInt(900000) + 100000)}';
      if (!taken.contains(candidate.toLowerCase())) return candidate;
    }

    var n = 100000;
    while (taken.contains('$letter$n')) {
      n++;
    }
    return '$letter$n';
  }

  void subscribe(void Function() listener) {
    if (!_listeners.contains(listener)) _listeners.add(listener);
  }

  void unsubscribe(void Function() listener) => _listeners.remove(listener);

  void _notify() {
    for (final l in List<void Function()>.of(_listeners)) {
      l();
    }
  }
}
