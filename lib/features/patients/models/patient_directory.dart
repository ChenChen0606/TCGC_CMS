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

  final List<ClinicProfile> _all = _seedProfiles();
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

  static List<ClinicProfile> _seedProfiles() {
    final seed = <ClinicProfile>[];
    ClinicProfile p({
      required String id,
      required String category,
      required String first,
      String middle = '',
      required String last,
      String sex = 'Male',
      String birth = '',
      String contact = '',
      String email = '',
      String address = '',
      String inst = '',
      String prog = '',
      String year = '',
      String dept = '',
      String pos = '',
      String emName = '',
      String emContact = '',
    }) {
      return ClinicProfile(
        id: id,
        category: category,
        firstName: first,
        middleName: middle,
        lastName: last,
        sex: sex,
        birthDate: birth,
        contact: contact,
        email: email.isEmpty
            ? '${first.toLowerCase()}.${last.toLowerCase()}@tcgc.edu.ph'
            : email,
        address: address,
        institute: inst,
        program: prog,
        yearLevel: year,
        department: dept,
        position: pos,
        emergencyName: emName,
        emergencyContact: emContact,
        createdAt: DateTime(2026, 6, 8, 9, 15),
        createdBy: 'Imported',
      );
    }

    seed.addAll([
      p(
          id: '234567',
          category: 'Student',
          first: 'Cresa',
          middle: 'S',
          last: 'Delacruz',
          sex: 'Female',
          birth: '2005-03-14',
          contact: '09171234567',
          email: 'cresa.delacruz@tcgc.edu.ph',
          address: 'Brgy. San Rafael, Tarlac City',
          inst: 'ICS',
          prog: 'BSCS',
          year: '2nd Year',
          emName: 'Maria Delacruz',
          emContact: '09179876543'),
      p(
          id: '234889',
          category: 'Student',
          first: 'John',
          middle: 'A',
          last: 'Doe',
          sex: 'Male',
          birth: '2004-11-02',
          contact: '09201234567',
          email: 'john.doe@tcgc.edu.ph',
          address: 'Brgy. San Jose, Tarlac City',
          inst: 'ITE',
          prog: 'BSED-MATH',
          year: '3rd Year',
          emName: 'Anna Doe',
          emContact: '09209876543'),
      p(
          id: '234901',
          category: 'Student',
          first: 'Nicole',
          last: 'Reyes',
          sex: 'Female',
          birth: '2006-01-21',
          contact: '09211234567',
          email: 'nicole.reyes@tcgc.edu.ph',
          address: 'Brgy. Cutcut, Tarlac City',
          inst: 'IBFS',
          prog: 'BSBA-HRM',
          year: '1st Year',
          emName: 'Jose Reyes',
          emContact: '09218876543'),
      p(
          id: '234915',
          category: 'Student',
          first: 'Jomar',
          middle: 'L',
          last: 'Villanueva',
          sex: 'Male',
          birth: '2003-08-09',
          contact: '09221234567',
          email: 'jomar.villanueva@tcgc.edu.ph',
          address: 'Brgy. Maya, Tarlac City',
          inst: 'IAS',
          prog: 'AB POLSCI',
          year: '4th Year'),
      p(
          id: '234922',
          category: 'Student',
          first: 'Grace',
          last: 'Lim',
          sex: 'Female',
          birth: '2005-06-30',
          contact: '09231234567',
          email: 'grace.lim@tcgc.edu.ph',
          address: 'Brgy. Sampatoc, Tarlac City',
          inst: 'IHS',
          prog: 'GEN. MIDWIFERY',
          year: '2nd Year'),
      p(
          id: '234938',
          category: 'Student',
          first: 'Paolo',
          middle: 'R',
          last: 'Santos',
          sex: 'Male',
          birth: '2004-02-17',
          contact: '09241234567',
          email: 'paolo.santos@tcgc.edu.ph',
          address: 'Brgy. Tinib, Tarlac City',
          inst: 'ICJE',
          prog: 'BSCRIM',
          year: '3rd Year'),
      p(
          id: 'F001',
          category: 'Faculty',
          first: 'Jane',
          last: 'Smith',
          sex: 'Female',
          birth: '1988-04-11',
          contact: '09151234567',
          email: 'jane.smith@tcgc.edu.ph',
          address: 'Brgy. San Rafael, Tarlac City',
          inst: 'IAS',
          pos: 'Dean'),
      p(
          id: 'F002',
          category: 'Faculty',
          first: 'Ramon',
          last: 'Garcia',
          sex: 'Male',
          birth: '1990-09-25',
          contact: '09161234567',
          email: 'ramon.garcia@tcgc.edu.ph',
          address: 'Brgy. San Jose, Tarlac City',
          inst: 'ICS',
          pos: 'Instructor'),
      p(
          id: 'F003',
          category: 'Faculty',
          first: 'Liza',
          middle: 'C',
          last: 'Bautista',
          sex: 'Female',
          birth: '1992-12-05',
          contact: '09171234511',
          email: 'liza.bautista@tcgc.edu.ph',
          address: 'Brgy. Cutcut, Tarlac City',
          inst: 'ITE',
          pos: 'Instructor'),
      p(
          id: 'F004',
          category: 'Faculty',
          first: 'Marlon',
          last: 'Cruz',
          sex: 'Male',
          birth: '1986-07-19',
          contact: '09181234522',
          email: 'marlon.cruz@tcgc.edu.ph',
          address: 'Brgy. Agopa, Tarlac City',
          inst: 'ICJE',
          pos: 'Instructor'),
      p(
          id: 'S001',
          category: 'Staff',
          first: 'Mark',
          last: 'Lee',
          sex: 'Male',
          birth: '1993-01-08',
          contact: '09181234567',
          email: 'mark.lee@tcgc.edu.ph',
          address: 'Brgy. San Rafael, Tarlac City',
          dept: 'Registrar' 's Office',
          pos: 'Security Personnel'),
      p(
          id: 'S002',
          category: 'Staff',
          first: 'Rosa',
          last: 'Navarro',
          sex: 'Female',
          birth: '1994-05-23',
          contact: '09191234567',
          email: 'rosa.navarro@tcgc.edu.ph',
          address: 'Brgy. Maya, Tarlac City',
          dept: 'Library',
          pos: 'Librarian'),
      p(
          id: 'S003',
          category: 'Staff',
          first: 'Ana',
          middle: 'P',
          last: 'Mendoza',
          sex: 'Female',
          birth: '1991-10-12',
          contact: '09201234577',
          email: 'ana.mendoza@tcgc.edu.ph',
          address: 'Brgy. Tinib, Tarlac City',
          dept: 'Clinic',
          pos: 'Clinic Staff'),
    ]);

    final active = ReferenceCatalog.activePeriod;
    for (final profile in seed) {
      profile.academicYear = active?.acadYear ?? '';
      profile.semester = active?.semester ?? kDefaultSemester;
    }
    return seed;
  }
}
