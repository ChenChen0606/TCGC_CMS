// ─────────────────────────────────────────────────────────────────────────────
//  patient_directory.dart
//  The ONE shared list of people the clinic knows about, plus the institute /
//  program / position catalog those people are filed under.
//
//  WHY THIS FILE EXISTS
//  Individual Record used to keep a private, on-device copy of the people,
//  which meant an ID could be perfectly real on one screen and unknown on
//  another. Both screens now read and write THIS list, so:
//    · an ID typed in Clinic Visit resolves to the very same record Individual
//      Record shows, and
//    · a record added / edited / deleted on either screen shows up on the other
//      one immediately, with no network involved.
//
//  WHERE THE DATA LIVES NOW
//  The list is durable: `public.individual_records` is the permanent record of a
//  person and `public.individual_academic_records` is their school / work record
//  for one academic period. `IndividualRecordService`
//  (lib/services/individual_record_service.dart) is the only thing that writes
//  them. The screens fetch the roster and hand it to [PatientDirectory.hydrate],
//  so this file stays an in-memory projection — and the hard-coded
//  [PatientDirectory._seedProfiles] list is only ever seen when the database
//  cannot be reached (no network, or before the first load finishes).
//
//  THE REFERENCE LISTS ARE DATABASE TABLES NOW TOO
//  The school year / semester list, the institutes and their programs, the
//  departments / offices and the positions are all rows — `academic_periods`,
//  `institutes`, `program`, `departments_offices`, `positions`. They are read
//  through `ReferenceCatalog` (lib/services/reference_data_service.dart) and the
//  "+" buttons on the Individual Record page write straight back to them, so
//  every dropdown in the app offers exactly what the database holds.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math';

import 'package:clinicmanagementsystem/services/reference_data_service.dart';

// ── SEMESTER / SEX / YEAR LEVEL ──────────────────────────────────────────────
// Fixed lists, but the values come from CHECK constraints in the schema rather
// than from taste: `chk_semester` allows exactly these three semesters,
// `chk_sex` exactly these two, `chk_year_level` 1st to 5th Year. Offering a
// value the database will reject only moves the failure from a dropdown to an
// error message.
const List<String> kSemesters = ['1st Semester', '2nd Semester', 'Summer'];
const String kDefaultSemester = '1st Semester';
const List<String> kSexes = ['Male', 'Female'];
const List<String> kYearLevels = [
  '1st Year',
  '2nd Year',
  '3rd Year',
  '4th Year',
];

// ── ACADEMIC YEAR / SEMESTER CATALOG ──────────────────────────────────────────
// Read from `public.academic_periods`, never hard-coded. A term the school has
// not run is not offered, and a term that has run does not disappear — which is
// the whole reason the Year & Semester dropdown used to fall out of step with the
// records filed under it.

/// Every school year on file, newest first — the Archive's year filter.
List<String> get kAcademicYears {
  final seen = <String>{};
  for (final p in ReferenceCatalog.periodsNewestFirst) {
    seen.add(p.acadYear);
  }
  return List<String>.unmodifiable(seen);
}

/// Every (year, semester) pair on file, newest school year first.
///
/// Summer follows the second semester inside its own school year — that is the
/// order the school works in, and it is why [ReferenceCatalog.periodsNewestFirst]
/// ranks the semesters explicitly rather than letting Postgres sort the labels.
List<({String year, String semester})> get kAcademicTerms => [
      for (final p in ReferenceCatalog.periodsNewestFirst)
        (year: p.acadYear, semester: p.semester),
    ];

/// The term currently being run. `academic_periods` allows exactly one Active
/// row, so this is read, never chosen. Falls back to the newest term on file
/// while the catalog is still loading, and to the empty string if the school has
/// not created a single term yet — which is the state the Individual Record page
/// tells the user to fix rather than papering over.
String get kCurrentAcademicYear =>
    ReferenceCatalog.currentPeriod?.acadYear ?? '';
String get kCurrentSemester =>
    ReferenceCatalog.currentPeriod?.semester ?? kDefaultSemester;

/// The `academic_period_id` new records are filed under.
String? get kCurrentAcademicPeriodId => ReferenceCatalog.currentPeriod?.id;

/// "2025-2026 · 2nd Semester" — how a term is written in the filter dropdown and
/// in the table's TYPE-adjacent subtitle.
String academicTermLabel(String year, String semester) => '$year · $semester';

/// True while [year]/[semester] is the term the clinic is running now.
///
/// The single definition of "current", used by the form, the import and the
/// status column. It follows `academic_periods.status`, so whoever marks a term
/// Active there decides what "current" means everywhere.
bool isCurrentTerm(String year, String semester) {
  final active = ReferenceCatalog.activePeriod;
  if (active == null) {
    return year == kCurrentAcademicYear && semester == kCurrentSemester;
  }
  return year == active.acadYear && semester == active.semester;
}

/// The term's (year, semester) pair for a record, falling back to the current
/// term when the record carries neither — a row saved before terms were tracked
/// belongs to the term the clinic is on now, not to a year that does not exist.
({String year, String semester}) termOf(String year, String semester) {
  if (year.trim().isEmpty) {
    return (year: kCurrentAcademicYear, semester: kCurrentSemester);
  }
  return (year: year.trim(), semester: semester.trim());
}

// ── CATALOG HELPERS ──────────────────────────────────────────────────────────
// Thin wrappers over [ReferenceCatalog] so the call sites keep reading as one
// question ("what can this dropdown offer?") and the ids behind the labels stay
// in one place.

/// Institute code → the program codes it offers. Derived from `program`.
Map<String, List<String>> get kProgramCatalog {
  final map = <String, List<String>>{};
  for (final e in ReferenceCatalog.institutes) {
    map[e.code] = ReferenceCatalog.programsOf(e.id);
  }
  return Map<String, List<String>>.unmodifiable(map);
}

/// Every institute code, alphabetically — the Student and Faculty "Institute"
/// list.
List<String> get kInstitutes => ReferenceCatalog.instituteCodes;

/// Programs offered by [instituteCode], or an empty list when it is unknown.
List<String> programsOf(String? instituteCode) {
  final inst = ReferenceCatalog.instituteByCode(instituteCode) ??
      ReferenceCatalog.instituteById(instituteCode);
  return ReferenceCatalog.programsOf(inst?.id);
}

/// The institute code that offers [programCode], or null when no institute does.
String? instituteOfProgram(String? programCode) {
  final id = ReferenceCatalog.instituteIdOfProgram(programCode);
  return id == null ? null : ReferenceCatalog.instituteCodeOf(id);
}

/// The offices a staff member can be assigned to.
///
/// Faculty no longer pick one: they are filed under an *institute* plus a
/// position, while staff are filed under a department / office plus a position.
/// The helper keeps its name because it is asked the same question either way.
List<String> departmentOptionsFor(String? category) =>
    ReferenceCatalog.departmentNames;

/// Posts anyone can hold. The database keeps one `positions` table for faculty
/// and staff, so both see the same list rather than two lists that could drift.
List<String> positionOptionsFor(String? category) =>
    ReferenceCatalog.positionNames;

/// Teaching / academic leadership posts a faculty member can hold.
List<String> get kFacultyPositions => ReferenceCatalog.positionNames;

/// Administrative / support posts a staff member can hold.
List<String> get kStaffPositions => ReferenceCatalog.positionNames;

/// Offices a staff member can be assigned to.
List<String> get kStaffDepartments => ReferenceCatalog.departmentNames;

/// True when [program] is an offering [institute] actually has.
bool isKnownProgram(String? institute, String? program) =>
    program != null &&
    program.isNotEmpty &&
    programsOf(institute).contains(program);

/// True when [value] is a year level the school uses.
bool isKnownYearLevel(String? value) =>
    value != null && kYearLevels.contains(value);

/// True when [value] is a post on file.
bool isKnownPosition(String? category, String? value) =>
    value != null && positionOptionsFor(category).contains(value);

/// One person's clinic record — the same information Individual Record keeps,
/// in a shape both screens can use.
class ClinicProfile {
  /// `individual_records.id`. Carried through so a write from any consumer can
  /// target the right row; null only for a profile that has never been saved.
  String? uuid;

  String id; // Student ID / Faculty ID / Staff ID
  String category; // 'Student' | 'Faculty' | 'Staff'

  // Personal
  String firstName;
  String middleName;
  String lastName;
  String suffix; // Jr. / III / …
  String sex;
  String birthDate; // yyyy-MM-dd, '' when unknown
  String contact;
  String email;
  String address;

  // Academic / employment
  String academicYear;
  String semester;
  String institute; // Student and Faculty
  String program; // Student only
  String yearLevel; // Student only
  String department; // Staff only
  String position; // Faculty and Staff

  // Clinic-side extras the visit form can show
  String emergencyName;
  String emergencyContact;

  // 'Active' on the roster, 'Inactive' when the person has left.
  String status;

  // Audit
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

  /// "C" out of "Cresa" — what the visit form's M.I. box shows.
  String get middleInitial {
    final m = middleName.trim();
    return m.isEmpty ? '' : '${m[0]}.';
  }

  String get displayId => id;

  /// What the PROGRAM column shows: a student's degree program, a faculty or
  /// staff member's post. Used by both screens so a person is described the
  /// same way everywhere.
  String get programLabel => isStudent
      ? (program.isEmpty ? '-' : program)
      : (position.isEmpty ? '-' : position);

  /// Second line of context in a search result: institute + program + year for
  /// a student, institute + post for faculty, office + post for staff.
  ///
  /// Faculty are filed under an institute rather than an office, so the same
  /// join serves all three: the fields a category does not use are blank and
  /// drop out on their own.
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

  /// Everything a search should be able to match on: ID, any part of the name,
  /// the institute, the program, the department, the post and the contact.
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

/// The shared, on-device registry. Screens hold a listener so a change made in
/// one place refreshes the other without a reload.
class PatientDirectory {
  PatientDirectory._();

  static final PatientDirectory instance = PatientDirectory._();

  static final Random _random = Random();

  final List<ClinicProfile> _all = _seedProfiles();
  final List<void Function()> _listeners = [];

  /// Live view of the registry. Treat as read-only from screens.
  List<ClinicProfile> get all => List<ClinicProfile>.unmodifiable(_all);

  int get length => _all.length;

  // ── SEARCH ────────────────────────────────────────────────────────────────

  /// Case-insensitive match on ID, any name part, institute, program,
  /// department, post or contact. An exact ID match always sorts first so
  /// typing the full ID never lands on the wrong person.
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

  /// The record for [id], or null. The one place an ID typed by a user is
  /// turned into a person.
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

  // ── HYDRATION ───────────────────────────────────────────────────────────

  /// Replaces the whole registry with [profiles] and notifies listeners.
  ///
  /// This is the seam the database sits behind: the screen fetches the roster
  /// from `public.individual_records` and hands it here, so every consumer
  /// (this page and anything else that searches people) keeps reading one list.
  /// A person missing from [profiles] is simply no longer in the registry.
  void hydrate(List<ClinicProfile> profiles) {
    _all
      ..clear()
      ..addAll(profiles);
    _notify();
  }

  /// The stored record for [id], or null, counted across every category.
  /// Lookups deliberately ignore [status]: an inactive person must still
  /// resolve (and refuse a duplicate person number), they are just not listed.
  bool holds(String id) => byId(id) != null;

  // ── WRITES ────────────────────────────────────────────────────────────────

  /// Adds [profile], or replaces the record that already owns its ID.
  /// Returns the stored record.
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

  /// Applies [mutate] to the stored record with [id], if there is one.
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

  /// A free Faculty / Staff number for a new record: the category letter and six
  /// digits — `F` for faculty, `S` for staff — taken from the people already in
  /// memory.
  ///
  /// This mirrors `generate_person_id` in the database, which is what actually
  /// issues numbers. It exists only for the case the database cannot answer (no
  /// network, table not reachable) so the form still offers something usable
  /// rather than sitting empty; the offline value is deliberately not memorable,
  /// exactly like the real one, and is checked against this list so two people
  /// added while offline cannot end up with the same number.
  ///
  /// [academicYear] is not used any more and is kept only so the one call site
  /// that passes it keeps compiling.
  String nextIdFor(String category, [String academicYear = '']) {
    final letter = category == 'Staff' ? 'S' : 'F';
    final taken = _all.map((p) => p.id.toLowerCase()).toSet();
    final random = _random;
    for (var attempt = 0; attempt < 50; attempt++) {
      final candidate = '$letter${(random.nextInt(900000) + 100000)}';
      if (!taken.contains(candidate.toLowerCase())) return candidate;
    }
    // 50 collisions on a 900 000-value space means the registry is full of this
    // exact number; fall back to a counter so a number is still produced.
    var n = 100000;
    while (taken.contains('$letter$n')) {
      n++;
    }
    return '$letter$n';
  }

  // ── CHANGE NOTIFICATION ───────────────────────────────────────────────────

  void subscribe(void Function() listener) {
    if (!_listeners.contains(listener)) _listeners.add(listener);
  }

  void unsubscribe(void Function() listener) => _listeners.remove(listener);

  void _notify() {
    // Copy first: a listener that unsubscribes while being notified would
    // otherwise mutate the list being iterated.
    for (final l in List<void Function()>.of(_listeners)) {
      l();
    }
  }

  // ── SEED (trial data) ─────────────────────────────────────────────────────
  //
  // Thirteen people across all three categories, with every field already
  // filled in, so the search box can be tried with a real ID and the whole
  // form fills itself. These are the exact same IDs Individual Record shows.
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
      // ── Students ──────────────────────────────────────────────────────
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

      // ── Faculty ───────────────────────────────────────────────────────
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

      // ── Staff ─────────────────────────────────────────────────────────
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

    // The seed predates academic periods, so it carries no term of its own. It
    // stands in for the roster under the term the clinic is on now — which is
    // the same rule the form uses for a record that names no period.
    final active = ReferenceCatalog.activePeriod;
    for (final profile in seed) {
      profile.academicYear = active?.acadYear ?? '';
      profile.semester = active?.semester ?? kDefaultSemester;
    }
    return seed;
  }
}
