// ─────────────────────────────────────────────────────────────────────────────
//  reference_data_service.dart
//  The school's reference lists, read from and written back to Supabase.
//
//  TABLES (exactly the ones the schema defines — nothing else is created here)
//    public.academic_periods       academic_period_id · acad_year · semester ·
//                                   status · created_at
//    public.institutes              institute_id · code · name · created_at
//    public.program                 program_id · institute_id · code · name ·
//                                   created_at
//    public.departments_offices     department_office_id · name · created_at
//    public.positions               position_id · name · created_at
//
//  WHY THIS FILE IS THE ONLY PLACE THAT KNOWS THE ABOVE
//  Every dropdown in the app — School Year & Semester, Institute, Program,
//  Department / Office, Position — has to offer exactly what the database holds,
//  or a record can be saved against an institute, a program or a post that does
//  not exist. Having one loader means an "+" button anywhere adds a row for
//  everybody, and the next screen that opens already lists it.
//
//  WHY THE OFFLINE SEED STILL EXISTS
//  [ReferenceCatalog] starts from the values this school used before the tables
//  did, so a dropdown is never empty while the first read is still in flight and
//  the page still renders when the network is down. The moment [load] succeeds
//  the database is authoritative and the seed is gone — nothing merges them, so
//  a value deleted in the database cannot come back from the seed.
//
//  DUPLICATES
//  Every table here carries a case-insensitive unique index, so the database
//  refuses a second ICS, a second "Registrar Staff" or a second 2025-2026 ·
//  Summer. The add methods still look first and return the row that already
//  exists, because "that is already on file" is a better answer than a 409, and
//  because the lookup is what lets the caller select the existing row instead of
//  failing.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:clinicmanagementsystem/services/data_tracker.dart';
import 'package:clinicmanagementsystem/services/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

// ── ROW MODELS ───────────────────────────────────────────────────────────────

/// One `(acad_year, semester)` pair the school runs, plus whether it is the term
/// being run right now.
class AcademicPeriodOption {
  final String id; // academic_period_id — 'AP-001'
  final String acadYear; // '2025-2026'
  final String semester; // '1st Semester' | '2nd Semester' | 'Summer'
  final String status; // 'Active' | 'Inactive'

  const AcademicPeriodOption({
    required this.id,
    required this.acadYear,
    required this.semester,
    required this.status,
  });

  bool get isActive => status == 'Active';

  /// "2025-2026 · 2nd Semester" — how a term is written everywhere in the app.
  String get label => '$acadYear · $semester';

  factory AcademicPeriodOption.fromSupabase(Map<String, dynamic> m) =>
      AcademicPeriodOption(
        id: (m['academic_period_id'] as String? ?? '').trim(),
        acadYear: (m['acad_year'] as String? ?? '').trim(),
        semester: (m['semester'] as String? ?? '').trim(),
        status: (m['status'] as String? ?? 'Inactive').trim(),
      );

  @override
  String toString() => label;
}

/// An institute. [code] is what every screen shows ('ICS'); [name] is the full
/// title, shown as the dropdown's subtitle and in the detail view.
class InstituteOption {
  final String id; // institute_id — 'INS-001'
  final String code;
  final String name;

  const InstituteOption({
    required this.id,
    required this.code,
    required this.name,
  });

  factory InstituteOption.fromSupabase(Map<String, dynamic> m) =>
      InstituteOption(
        id: (m['institute_id'] as String? ?? '').trim(),
        code: (m['code'] as String? ?? '').trim(),
        name: (m['name'] as String? ?? '').trim(),
      );
}

/// A program. Always owned by exactly one institute — the database enforces it
/// with a composite foreign key, so a program can never point at an institute
/// the row around it does not.
class ProgramOption {
  final String id; // program_id — 'PROG-001'
  final String instituteId; // institute_id
  final String code;
  final String name;

  const ProgramOption({
    required this.id,
    required this.instituteId,
    required this.code,
    required this.name,
  });

  factory ProgramOption.fromSupabase(Map<String, dynamic> m) => ProgramOption(
        id: (m['program_id'] as String? ?? '').trim(),
        instituteId: (m['institute_id'] as String? ?? '').trim(),
        code: (m['code'] as String? ?? '').trim(),
        name: (m['name'] as String? ?? '').trim(),
      );
}

/// A department / office or a position — both tables are just an id and a name,
/// so one shape reads both.
class NamedOption {
  final String id;
  final String name;

  const NamedOption({required this.id, required this.name});

  factory NamedOption.fromSupabase(Map<String, dynamic> m, String idColumn) =>
      NamedOption(
        id: (m[idColumn] as String? ?? '').trim(),
        name: (m['name'] as String? ?? '').trim(),
      );

  @override
  String toString() => name;
}

// ── THE IN-MEMORY CATALOG ────────────────────────────────────────────────────

/// What the dropdowns read. Replaced wholesale by [load] rather than merged, so
/// a value removed in the database stops being offered immediately.
class ReferenceCatalog {
  ReferenceCatalog._();

  static List<AcademicPeriodOption> _periods = _seedPeriods();
  static List<InstituteOption> _institutes = _seedInstitutes();
  static List<ProgramOption> _programs = _seedPrograms();
  static List<NamedOption> _departments = _seedDepartments();
  static List<NamedOption> _positions = _seedPositions();

  /// True once a read has replaced the seed with the database's contents.
  static bool _loaded = false;
  static bool get isLoaded => _loaded;

  // ── ACADEMIC PERIODS ─────────────────────────────────────────────────────

  static List<AcademicPeriodOption> get periods =>
      List<AcademicPeriodOption>.unmodifiable(_periods);

  /// School order: newest year first, then 1st → 2nd → Summer inside it.
  ///
  /// Sorted here rather than in SQL because Postgres sorts the semester labels
  /// alphabetically, which puts 'Summer' before '2nd Semester' before
  /// '1st Semester'. Newest-year-first is what a filter dropdown wants.
  static List<AcademicPeriodOption> get periodsNewestFirst {
    final list = List<AcademicPeriodOption>.of(_periods)
      ..sort((a, b) {
        final y = b.acadYear.compareTo(a.acadYear);
        if (y != 0) return y;
        return _semesterRank(a.semester).compareTo(_semesterRank(b.semester));
      });
    return List<AcademicPeriodOption>.unmodifiable(list);
  }

  static int _semesterRank(String s) => switch (s) {
        '1st Semester' => 1,
        '2nd Semester' => 2,
        'Summer' => 3,
        _ => 4,
      };

  /// The term being run. `academic_periods` allows exactly one Active row, so
  /// this is a lookup rather than a preference.
  static AcademicPeriodOption? get activePeriod {
    for (final p in _periods) {
      if (p.isActive) return p;
    }
    return null;
  }

  /// The term a new record is filed under: the Active one, or — before the
  /// school has marked one Active — the newest term on file.
  static AcademicPeriodOption? get currentPeriod {
    final active = activePeriod;
    if (active != null) return active;
    return periodsNewestFirst.isEmpty ? null : periodsNewestFirst.first;
  }

  static String? periodIdFor(String acadYear, String semester) {
    for (final p in _periods) {
      if (p.acadYear == acadYear && p.semester == semester) return p.id;
    }
    return null;
  }

  static AcademicPeriodOption? periodById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final p in _periods) {
      if (p.id == id) return p;
    }
    return null;
  }

  // ── INSTITUTES & PROGRAMS ────────────────────────────────────────────────

  static List<InstituteOption> get institutes =>
      List<InstituteOption>.unmodifiable(_institutes);

  static List<ProgramOption> get programs =>
      List<ProgramOption>.unmodifiable(_programs);

  /// Institute codes, alphabetically — the Student and Faculty "Institute" list.
  static List<String> get instituteCodes {
    final list = _institutes.map((e) => e.code).toList()..sort();
    return List<String>.unmodifiable(list);
  }

  static InstituteOption? instituteById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final e in _institutes) {
      if (e.id == id) return e;
    }
    return null;
  }

  static InstituteOption? instituteByCode(String? code) {
    if (code == null || code.isEmpty) return null;
    final q = code.trim().toLowerCase();
    for (final e in _institutes) {
      if (e.code.toLowerCase() == q) return e;
    }
    return null;
  }

  static String instituteCodeOf(String? id) =>
      instituteById(id)?.code ?? (id == null || id.isEmpty ? '' : id);

  static String instituteNameOf(String? id) => instituteById(id)?.name ?? '';

  /// Programs of [instituteId], by code, alphabetically.
  static List<String> programsOf(String? instituteId) {
    if (instituteId == null || instituteId.isEmpty) return const <String>[];
    final list = _programs
        .where((p) => p.instituteId == instituteId)
        .map((p) => p.code)
        .toList()
      ..sort();
    return List<String>.unmodifiable(list);
  }

  /// The institute that offers [programCode], or null when none does.
  static String? instituteIdOfProgram(String? programCode) {
    if (programCode == null || programCode.isEmpty) return null;
    final q = programCode.trim().toLowerCase();
    for (final p in _programs) {
      if (p.code.toLowerCase() == q) return p.instituteId;
    }
    return null;
  }

  static ProgramOption? programById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final p in _programs) {
      if (p.id == id) return p;
    }
    return null;
  }

  static ProgramOption? programByCode(String? code) {
    if (code == null || code.isEmpty) return null;
    final q = code.trim().toLowerCase();
    for (final p in _programs) {
      if (p.code.toLowerCase() == q) return p;
    }
    return null;
  }

  static String programCodeOf(String? id) =>
      programById(id)?.code ?? (id == null || id.isEmpty ? '' : id);

  static String programNameOf(String? id) => programById(id)?.name ?? '';

  /// True when [instituteId] really offers [programCode] — the check the form
  /// uses before it lets a Save through.
  static bool instituteOffersProgram(String? instituteId, String? programId) {
    if (instituteId == null || programId == null) return false;
    for (final p in _programs) {
      if (p.id == programId && p.instituteId == instituteId) return true;
    }
    return false;
  }

  /// The `program_id` for [programCode] within [instituteId], or null when the
  /// institute does not offer it.
  ///
  /// Scoped to the institute deliberately. Program codes are meant to be unique
  /// school-wide, but a code that *is* offered by two institutes must not resolve
  /// to whichever happens to sort first — the form pairs the program dropdown
  /// with an institute dropdown, and the answer has to follow the pairing the
  /// clerk actually picked.
  static String? programIdFor(String? instituteId, String? programCode) {
    if (programCode == null || programCode.isEmpty) return null;
    final q = programCode.trim().toLowerCase();
    for (final p in _programs) {
      if (p.code.toLowerCase() != q) continue;
      if (instituteId == null || instituteId.isEmpty) return p.id;
      if (p.instituteId == instituteId) return p.id;
    }
    return null;
  }

  // ── DEPARTMENTS & POSITIONS ──────────────────────────────────────────────

  static List<NamedOption> get departments =>
      List<NamedOption>.unmodifiable(_departments);

  static List<NamedOption> get positions =>
      List<NamedOption>.unmodifiable(_positions);

  static List<String> get departmentNames {
    final list = _departments.map((e) => e.name).toList()..sort();
    return List<String>.unmodifiable(list);
  }

  static List<String> get positionNames {
    final list = _positions.map((e) => e.name).toList()..sort();
    return List<String>.unmodifiable(list);
  }

  static NamedOption? departmentById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final e in _departments) {
      if (e.id == id) return e;
    }
    return null;
  }

  static NamedOption? positionById(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final e in _positions) {
      if (e.id == id) return e;
    }
    return null;
  }

  static String departmentNameOf(String? id) => departmentById(id)?.name ?? '';

  static String positionNameOf(String? id) => positionById(id)?.name ?? '';

  static String? departmentIdByName(String? name) =>
      _idByName(_departments, name);

  static String? positionIdByName(String? name) => _idByName(_positions, name);

  static String? _idByName(List<NamedOption> list, String? name) {
    if (name == null || name.isEmpty) return null;
    final q = name.trim().toLowerCase();
    for (final e in list) {
      if (e.name.toLowerCase() == q) return e.id;
    }
    return null;
  }

  // ── LOAD ──────────────────────────────────────────────────────────────────

  /// Reads all five tables and replaces the catalog.
  ///
  /// The five reads run together: they are independent and small, and a term
  /// picker that fills in before the program list does is the flickering this
  /// avoids. A failure leaves whatever was already in the catalog — the seed on a
  /// cold start, the last good read afterwards — and is re-thrown so the caller
  /// can put a "could not load" message on screen instead of pretending the
  /// lists are empty.
  static Future<void> load({bool force = false}) async {
    if (_loaded && !force) return;

    // NO SESSION, NO READ.
    //
    // All five tables are behind Row Level Security, and RLS hides them the
    // quiet way: `HTTP 200` with an empty body. A read taken while signed out
    // therefore *succeeds*, and there is nothing in the response that separates
    // "the anon key cannot see this table" from "this school has never run a
    // term". Trusting it would replace the seed with nothing and latch
    // `_loaded = true` on that nothing, and every later call short-circuits on
    // the latch for the rest of the session.
    //
    // The shape of that failure is why it reads as "my data disappeared":
    //   · the school year / semester dropdowns are empty,
    //   · so `currentPeriod` is null,
    //   · so `kCurrentAcademicPeriodId` is null,
    //   · so `IndividualRecordService.fetchAll` returns no rows rather than
    //     guessing a term — and the roster table is empty as well,
    //   · and nothing anywhere throws.
    //
    // This is not a web-only symptom, but web hits it every single run:
    // `flutter run -d chrome` starts a fresh browser profile, so there is no
    // persisted session to warm-start from, whereas a desktop or mobile run
    // usually still holds one from the previous launch and quietly reads
    // authenticated.
    //
    // So: signed out, the catalog is left exactly as it is and the seed keeps
    // every dropdown usable. [loadAfterSignIn] is what reads it properly.
    if (!hasSignedInUser) return;

    final results = await Future.wait([
      supabaseClient.from('academic_periods').select(),
      supabaseClient.from('institutes').select(),
      supabaseClient.from('program').select(),
      supabaseClient.from('departments_offices').select(),
      supabaseClient.from('positions').select(),
    ]);

    _periods = (results[0] as List)
        .map((r) => AcademicPeriodOption.fromSupabase(
            Map<String, dynamic>.from(r as Map)))
        .where((p) => p.id.isNotEmpty)
        .toList();
    _institutes = (results[1] as List)
        .map((r) =>
            InstituteOption.fromSupabase(Map<String, dynamic>.from(r as Map)))
        .where((e) => e.id.isNotEmpty)
        .toList();
    _programs = (results[2] as List)
        .map((r) =>
            ProgramOption.fromSupabase(Map<String, dynamic>.from(r as Map)))
        .where((e) => e.id.isNotEmpty)
        .toList();
    _departments = (results[3] as List)
        .map((r) => NamedOption.fromSupabase(
            Map<String, dynamic>.from(r as Map), 'department_office_id'))
        .where((e) => e.id.isNotEmpty && e.name.isNotEmpty)
        .toList();
    _positions = (results[4] as List)
        .map((r) => NamedOption.fromSupabase(
            Map<String, dynamic>.from(r as Map), 'position_id'))
        .where((e) => e.id.isNotEmpty && e.name.isNotEmpty)
        .toList();

    _loaded = true;
  }

  /// Loads, swallowing a failure. For call sites that only want the lists to
  /// fill in eventually (a screen's first build, a background refresh) and have
  /// nothing useful to say when the network is down.
  static Future<void> loadQuietly() async {
    try {
      await load();
    } catch (_) {
      // The seed keeps every dropdown usable; there is nothing to report.
    }
  }

  /// Fills the catalog in as soon as there is a session to read it with.
  ///
  /// The other half of [load]'s session guard: [load] now refuses to read while
  /// signed out, so something has to come back afterwards and read. Loads only
  /// when the catalog is still the seed — a warm start has already read it, and
  /// a token refresh does not change what is in `academic_periods`, so there is
  /// no second round trip in either case — then tells every listener, so a
  /// dropdown that was showing the seed repaints instead of staying on it.
  ///
  /// Safe to call from anywhere and as often as you like: a no-op while signed
  /// out, a no-op once loaded, and a failure is swallowed rather than thrown so
  /// that a caller holding up a screen transition cannot be derailed by it. The
  /// seed keeps the dropdowns usable and the next screen that needs the catalog
  /// tries again.
  ///
  /// Awaitable on purpose: the sign-in screen awaits this before it hands over
  /// to the dashboard, so the first screen to build already has the real term in
  /// [currentPeriod] rather than painting an empty roster and repainting after.
  static Future<void> loadAfterSignIn() async {
    if (_loaded || !hasSignedInUser) return;
    try {
      await load(force: true);
    } catch (_) {
      return;
    }
    // Deliberately no `DataTracker.bump()`: the catalog going from seed to
    // database does not mean any *record* changed, and `IndividualRecordScreen`
    // already re-reads the roster from `_catalogListener` when the current term
    // moved. Bumping here would only add a second identical roster query on the
    // way into the dashboard.
    _notify();
  }

  /// Re-reads and tells every listener, so an open form's dropdowns re-list what
  /// was just added.
  static Future<void> reload() async {
    await load(force: true);
    _notify();
    DataTracker.bump();
  }

  /// Re-reads `academic_periods` on its own and replaces the term list.
  ///
  /// WHY THIS IS SEPARATE FROM [reload]
  /// The term being run is a fact the database owns — its `status` column. The
  /// catalogue is otherwise read once per session, so a term switched anywhere
  /// this client did not see (another device, the SQL editor) leaves
  /// [activePeriod] stale. Every answer built on it then drifts the same way:
  /// [IndividualRecordService.statusForTerm] files a new enrolment Inactive, and
  /// the roster query filters on the old `academic_period_id`, so the record is in
  /// the database and nowhere on the screen. Re-reading just this small table
  /// before a write or a roster load makes those two answers current without the
  /// cost — or the re-render storm — of reloading every reference table.
  ///
  /// Deliberately does NOT notify listeners. The callers that need the refreshed
  /// value (the write about to choose a status, the roster read about to run) use
  /// it directly, and notifying here would let a listener that re-reads the roster
  /// call back into this method.
  static Future<void> refreshPeriods() async {
    if (!hasSignedInUser) return;
    final rows = await supabaseClient.from('academic_periods').select();
    _periods = (rows as List)
        .map((r) => AcademicPeriodOption.fromSupabase(
            Map<String, dynamic>.from(r as Map)))
        .where((p) => p.id.isNotEmpty)
        .toList();
  }

  // ── CHANGE NOTIFICATION ───────────────────────────────────────────────────

  static final List<void Function()> _listeners = [];

  static void subscribe(void Function() listener) {
    if (!_listeners.contains(listener)) _listeners.add(listener);
  }

  static void unsubscribe(void Function() listener) =>
      _listeners.remove(listener);

  static void _notify() {
    for (final l in List<void Function()>.of(_listeners)) {
      l();
    }
  }

  // ── OFFLINE SEED ──────────────────────────────────────────────────────────
  //
  // The lists this school ran before the tables existed. Only ever seen before
  // the first successful read or when the database cannot be reached; the ids
  // are placeholders that are replaced wholesale by [load], never merged.

  static List<AcademicPeriodOption> _seedPeriods() => [
        const AcademicPeriodOption(
            id: '',
            acadYear: '2024-2025',
            semester: '1st Semester',
            status: 'Inactive'),
        const AcademicPeriodOption(
            id: '',
            acadYear: '2024-2025',
            semester: '2nd Semester',
            status: 'Inactive'),
        const AcademicPeriodOption(
            id: '',
            acadYear: '2024-2025',
            semester: 'Summer',
            status: 'Inactive'),
        const AcademicPeriodOption(
            id: '',
            acadYear: '2025-2026',
            semester: '1st Semester',
            status: 'Inactive'),
        const AcademicPeriodOption(
            id: '',
            acadYear: '2025-2026',
            semester: '2nd Semester',
            status: 'Active'),
      ];

  // The seed ids are placeholders that only have to be CONSISTENT WITH EACH
  // OTHER: programsOf matches on them, so an institute and its programs share
  // a seed id for the dropdown to narrow correctly before the first read. They
  // are all replaced wholesale by [load], and never merged, so a placeholder id
  // can never end up written to the database.
  static List<InstituteOption> _seedInstitutes() => const [
        InstituteOption(
            id: _seedIbs, code: 'IBFS', name: 'Business and Finance'),
        InstituteOption(
            id: _seedIcje, code: 'ICJE', name: 'Criminal Justice Education'),
        InstituteOption(
            id: _seedIcs, code: 'ICS', name: 'Institute of Computer Science'),
        InstituteOption(id: _seedIhs, code: 'IHS', name: 'Health Sciences'),
        InstituteOption(id: _seedIas, code: 'IAS', name: 'Arts and Sciences'),
        InstituteOption(id: _seedIte, code: 'ITE', name: 'Teacher Education'),
      ];

  static const String _seedIbs = 'seed:IBFS';
  static const String _seedIcje = 'seed:ICJE';
  static const String _seedIcs = 'seed:ICS';
  static const String _seedIhs = 'seed:IHS';
  static const String _seedIas = 'seed:IAS';
  static const String _seedIte = 'seed:ITE';

  static List<ProgramOption> _seedPrograms() => const [
        ProgramOption(
            id: 'seed:P1',
            instituteId: _seedIbs,
            code: 'BSBA-HRM',
            name: 'BSBA in Human Resource Management'),
        ProgramOption(
            id: 'seed:P2',
            instituteId: _seedIbs,
            code: 'BSBA-MM',
            name: 'BSBA in Marketing Management'),
        ProgramOption(
            id: 'seed:P3',
            instituteId: _seedIbs,
            code: 'BSOA',
            name: 'BSBA in Office Administration'),
        ProgramOption(
            id: 'seed:P4',
            instituteId: _seedIcje,
            code: 'BSCRIM',
            name: 'BS in Criminology'),
        ProgramOption(
            id: 'seed:P5',
            instituteId: _seedIcje,
            code: 'BSISM',
            name: 'BS in Information Systems Management'),
        ProgramOption(
            id: 'seed:P6',
            instituteId: _seedIcs,
            code: 'BSCS',
            name: 'BS in Computer Science'),
        ProgramOption(
            id: 'seed:P7',
            instituteId: _seedIhs,
            code: 'GEN. MIDWIFERY',
            name: 'General Midwifery'),
        ProgramOption(
            id: 'seed:P8',
            instituteId: _seedIas,
            code: 'AB POLSCI',
            name: 'AB Political Science'),
        ProgramOption(
            id: 'seed:P9',
            instituteId: _seedIas,
            code: 'AB ENGLISH',
            name: 'AB English'),
        ProgramOption(
            id: 'seed:P10',
            instituteId: _seedIas,
            code: 'AB COMM',
            name: 'AB Communication'),
        ProgramOption(
            id: 'seed:P11',
            instituteId: _seedIte,
            code: 'BSED-MATH',
            name: 'BSED in Mathematics'),
        ProgramOption(
            id: 'seed:P12',
            instituteId: _seedIte,
            code: 'BSED-ENGLISH',
            name: 'BSED in English'),
        ProgramOption(
            id: 'seed:P13',
            instituteId: _seedIte,
            code: 'BSED-SOCSTUD',
            name: 'BSED in Social Studies'),
        ProgramOption(
            id: 'seed:P14',
            instituteId: _seedIte,
            code: 'BSED-FILIPINO',
            name: 'BSED in Filipino'),
        ProgramOption(
            id: 'seed:P15',
            instituteId: _seedIte,
            code: 'BEED',
            name: 'Bachelor of Elementary Education'),
      ];

  static List<NamedOption> _seedDepartments() => [
        'Office of the President',
        'Human Resource Office',
        'Registrar\'s Office',
        'Accounting Office',
        'Finance Office',
        'Student Affairs Office',
        'Clinic',
        'Library',
        'Information Technology Office',
        'Guidance Office',
        'Maintenance Office',
        'Security Office',
        'Admissions Office',
      ].map((n) => NamedOption(id: 'seed:' + n, name: n)).toList();

  static List<NamedOption> _seedPositions() => [
        'Administrative Staff',
        'HR Staff',
        'Registrar Staff',
        'Accounting Staff',
        'Finance Staff',
        'Student Affairs Staff',
        'Clinic Staff',
        'Librarian',
        'IT Staff',
        'Guidance Staff',
        'Maintenance Staff',
        'Security Personnel',
        'Admissions Staff',
        'Instructor',
      ].map((n) => NamedOption(id: 'seed:' + n, name: n)).toList();
}

// ── WRITES ───────────────────────────────────────────────────────────────────

/// Everything that creates a row in one of the five reference tables.
///
/// Each method returns the row that is on file afterwards, which is the row the
/// caller should select. When the value was already there, that is the existing
/// row: saving 2025-2026 · Summer twice must not fail and must not create a
/// second term.
/// A duplicate, or a value the database will not accept.
///
/// Top level rather than nested in [ReferenceDataService]: this SDK rejects a
/// class declared inside another class, and every screen that calls these writes
/// needs to catch it anyway, so a nested name would only have been in the way.
///
/// [message] is written for the person at the keyboard and is safe to show as-is.
class ReferenceException implements Exception {
  final String message;
  const ReferenceException(this.message);
  @override
  String toString() => message;
}

class ReferenceDataService {
  ReferenceDataService._();

  // ── ACADEMIC PERIOD ──────────────────────────────────────────────────────

  /// Registers a school year + semester.
  ///
  /// Goes through the `add_academic_period` RPC, which validates that the end
  /// year is the start year plus one ('2025' / '2026') and does
  /// `ON CONFLICT (acad_year, semester) DO NOTHING` before re-reading the row —
  /// so a term added twice comes back as the same `AP-` id rather than as an
  /// error.
  ///
  /// Set [makeCurrent] to make it the term being run. The previous Active term
  /// is flipped to Inactive *and* its enrolments are retired, so the roster and
  /// the Clinic Visit lookup — both of which read Active enrolments of the
  /// current term — show the new term only. Set [carryOverRoster] to copy
  /// everybody from the term being run into the new one as Active instead of
  /// leaving them behind.
  ///
  /// [carryOverRoster] is what makes a new term usable in one action instead of
  /// re-typing the whole roster: every Active record of the outgoing term gets
  /// an Active copy under the incoming period, so nobody appears twice and
  /// nobody disappears. Returns the number of rows copied.
  static Future<({AcademicPeriodOption period, int carried})>
      addAcademicPeriod({
    required int yearStart,
    required int yearEnd,
    required String semester,
    bool makeCurrent = false,
    bool carryOverRoster = false,
  }) async {
    if (yearEnd != yearStart + 1) {
      throw const ReferenceException(
          'The end year must be the start year plus one (example: 2025-2026).');
    }
    if (!const ['1st Semester', '2nd Semester', 'Summer'].contains(semester)) {
      throw const ReferenceException(
          'Pick 1st Semester, 2nd Semester or Summer.');
    }

    // The term being run *before* this call, so the roster is copied from the
    // right place even though the catalog is reloaded afterwards.
    final previousActive = ReferenceCatalog.activePeriod;

    AcademicPeriodOption period;
    try {
      // Direct INSERT rather than the `add_academic_period` RPC, which is not
      // present in this project. `academic_period_id` is left out so the
      // database supplies it, exactly as `addInstitute` already does for
      // `institute_id` — that path is known to work in this schema.
      //
      // A term is always created Inactive. Whether it is the term being run is a
      // separate decision, made below by `makeCurrent`, so a term can be
      // pre-registered without ever having been the current one.
      final row = await supabaseClient
          .from('academic_periods')
          .insert({
            'acad_year': '$yearStart-$yearEnd',
            'semester': semester,
            'status': 'Inactive',
          })
          .select()
          .single();
      period = AcademicPeriodOption.fromSupabase(
          Map<String, dynamic>.from(row as Map));
    } catch (e) {
      if (e is PostgrestException && e.code == '23505') {
        throw const ReferenceException(
            'That school year and semester already exists.');
      }
      throw ReferenceException(_explain(e, 'Could not save the school year.'));
    }
    if (period.id.isEmpty) {
      throw const ReferenceException(
          'That school year and semester already exists.');
    }

    if (makeCurrent) {
      try {
        await _setActivePeriodRow(period.id);
      } catch (e) {
        throw ReferenceException(
            _explain(e, 'Could not make that the current term.'));
      }
    }

    var carried = 0;
    // Set instead of thrown, so a carry that cannot run cannot skip the reload
    // below. The period row is written before any of this, and the dropdown the
    // clerk is looking at is fed from the catalog — so "carry failed" must not
    // leave the catalog showing the list from before they pressed Save.
    ReferenceException? carryFailure;

    // Switching the term also retires the outgoing term's enrolments, exactly as
    // [setActivePeriod] does. `_setActivePeriodRow` only moves the
    // `academic_periods` flag; without this the previous term's `Active`
    // enrolments stayed Active — hidden while the roster filters on the new term,
    // but still returned by anything that looks at the old term (the Archive
    // counts Active enrolments).
    //
    // The carry-over branch below handles this itself and must run *after* its
    // copy reads the outgoing term's Active rows, so this only covers the
    // no-carry path. `previousActive` was captured before the flip.
    if (makeCurrent &&
        !carryOverRoster &&
        previousActive != null &&
        previousActive.id != period.id) {
      try {
        await _retirePeriod(previousActive.id);
      } catch (e) {
        carryFailure = ReferenceException(
            _explain(e, 'Could not close the previous term.'));
      }
    }

    if (carryOverRoster) {
      final from = previousActive;
      if (from == null) {
        // A school that has never run a term has no roster to carry forward, and
        // that is not a failure — it is the normal first-run case. Refusing here
        // meant the very first period a school ever created could only be made
        // by unticking a box, and the error text ("There is no current term to
        // copy the roster from") read as though the save had failed even though
        // the row was already written.
        carried = 0;
      } else if (from.id == period.id) {
        throw const ReferenceException(
            'That term already holds the roster — nothing to copy.');
      } else {
        try {
          carried = await _copyRoster(from.id, period.id);
        } catch (e) {
          carryFailure = ReferenceException(
              _explain(e, 'Could not copy the roster into the new term.'));
        }
        // The outgoing term is history now, whatever `makeCurrent` said: leaving
        // it Active is what puts one person on the roster twice.
        if (!makeCurrent) {
          try {
            await _retirePeriod(from.id);
          } catch (e) {
            carryFailure ??= ReferenceException(
                _explain(e, 'Could not close the previous term.'));
          }
        } else {
          // `carryOverRoster` already wrote fresh Active rows for the new term, so
          // the outgoing term's enrolments are superseded and must not stay Active.
          // Leaving them Active is not visible today — the roster filters on the
          // current term — but it is a loaded gun: mark that old term current
          // again, by accident or to look at last year, and everyone who has since
          // left is back on the roster as though nothing happened.
          //
          // This runs after `_copyRoster` rather than inside `_setActivePeriodRow`,
          // which is the whole ordering constraint: the copy reads the outgoing
          // term's *Active* enrolments, so retiring first would copy nothing and
          // the new term would open empty.
          try {
            await _retirePeriod(from.id);
          } catch (e) {
            carryFailure ??= ReferenceException(
                _explain(e, 'Could not close the previous term.'));
          }
        }
      }
    }

    // Reload before anything is returned *or* thrown. The new period is already
    // in the database at this point, so the catalog has to catch up with it
    // either way — otherwise the term dropdown keeps offering the list from
    // before the save and the user is told to add a term they already added.
    await ReferenceCatalog.reload();

    if (carryFailure != null) throw carryFailure;

    return (
      period: ReferenceCatalog.periodById(period.id) ?? period,
      carried: carried,
    );
  }

  /// Flips [periodId] to be the term being run and closes the term it replaced.
  ///
  /// The previous Active term goes Inactive, and so do its enrolments. The second
  /// part used to be missing: only `academic_periods.status` moved, leaving every
  /// enrolment of the outgoing term Active. That is invisible while the roster
  /// filters on the current term, and wrong the moment anything looks at the old
  /// one — the Archive counts Active enrolments, so a term that had closed kept
  /// reporting its whole roster as present.
  ///
  /// Only the outgoing term is touched. The term being switched to is left alone,
  /// so somebody who left mid-term stays Inactive — that is a fact about them,
  /// not about the term, and the roster has to keep making it.
  static Future<void> setActivePeriod(String periodId) async {
    // Read before the flip, because afterwards there is no Active row to ask.
    final outgoing = await supabaseClient
        .from('academic_periods')
        .select('academic_period_id')
        .eq('status', 'Active')
        .neq('academic_period_id', periodId);
    final outgoingId = outgoing.isEmpty
        ? ''
        : '${(outgoing.first as Map)['academic_period_id'] ?? ''}';

    try {
      await _setActivePeriodRow(periodId);
    } catch (e) {
      throw ReferenceException(
          _explain(e, 'Could not change the current term.'));
    }
    if (outgoingId.isNotEmpty) {
      try {
        await _retirePeriod(outgoingId);
      } catch (e) {
        throw ReferenceException(_explain(
            e,
            'Changed the current term, but could not close the one '
            'it replaced.'));
      }
    }
    await ReferenceCatalog.reload();
  }

  /// Makes exactly one term Active.
  ///
  /// Two UPDATEs rather than the `set_active_period` RPC, which is not present in
  /// this project. The first clears the flag everywhere and the second sets it
  /// on one row, so the "at most one Active term" rule cannot be violated by a
  /// concurrent tap no matter what order the two statements land in: the table
  /// ends with one Active row or, if the second statement fails, none — and
  /// "no current term" is a state the roster already handles by showing nothing.
  static Future<void> _setActivePeriodRow(String periodId) async {
    await supabaseClient
        .from('academic_periods')
        .update({'status': 'Inactive'}).eq('status', 'Active');
    await supabaseClient
        .from('academic_periods')
        .update({'status': 'Active'}).eq('academic_period_id', periodId);
  }

  /// Copies every Active enrolment of [fromPeriodId] to [toPeriodId].
  ///
  /// The replacement for the `roll_forward_period` RPC, which is not present in
  /// this project. Read-then-insert rather than `INSERT ... SELECT`, because
  /// PostgREST cannot express it and because reading first is what lets the
  /// category-specific columns be carried across verbatim — a student keeps the
  /// same program and year level in the new term, which is the whole point of
  /// rolling forward.
  ///
  /// `academic_record_id` is not carried: the new term's rows are new rows with
  /// their own ids, and re-using the old one would collide on the primary key.
  static Future<int> _copyRoster(
    String fromPeriodId,
    String toPeriodId,
  ) async {
    final source =
        await supabaseClient.from('individual_academic_records').select('''
          person_id,
          institute_id,
          program_id,
          year_level,
          department_office_id,
          position_id
        ''').eq('academic_period_id', fromPeriodId).eq('status', 'Active');

    if (source.isEmpty) return 0;

    final payloads = [
      for (final row in source)
        {
          ...Map<String, dynamic>.from(row as Map),
          'academic_period_id': toPeriodId,
          'status': 'Active',
        }..remove('academic_record_id'),
    ];

    await supabaseClient.from('individual_academic_records').insert(payloads);
    DataTracker.bump();
    return payloads.length;
  }

  // ── INSTITUTE / PROGRAM ───────────────────────────────────────────────────

  /// Saves an institute and its first program from four typed values, writing
  /// only the tables that actually need a row.
  ///
  /// This is what the Add Institute / Program dialog calls, and it is one method
  /// rather than two because the dialog has one button: whether that button writes
  /// one row or two is the service's problem, not the clerk's. The form used to ask
  /// which of the three writes they wanted before they had typed anything, which
  /// meant picking a mode and then possibly not needing it.
  ///
  /// The institute code is the decision, and it is made from what is already on
  /// file rather than from a dropdown:
  ///
  ///   * **code not on file** → INSERT the institute, then the program if one was
  ///     typed. That is a new college and its first offering.
  ///   * **code already on file** → reuse it and insert only the program. Typing
  ///     a code that already exists is how a school ends up with two institutes
  ///     called the same thing, and the name typed here is only used when the
  ///     institute has to be created.
  ///
  /// [programCode] is optional on purpose: an institute is legal before it offers
  /// anything, and forcing a program here is how a placeholder "TBA" ends up on
  /// the roster forever. Leaving both program boxes empty registers the institute
  /// alone.
  ///
  /// Returns the `(instituteCode, programCode)` pair the caller's form stores, with
  /// an empty `programCode` for an institute added on its own, plus [created] —
  /// false when both codes were already on file and nothing was written, so the
  /// caller can say "already on file" rather than claiming a save that did not
  /// happen.
  static Future<({String instituteCode, String programCode, bool created})>
      saveInstituteAndProgram({
    required String instituteCode,
    required String instituteName,
    String programCode = '',
    String programName = '',
  }) async {
    final ic = instituteCode.trim();
    final iname = instituteName.trim();
    final pc = programCode.trim();
    final pn = programName.trim();

    if (ic.isEmpty) throw const ReferenceException('Enter the institute code.');
    if (pc.isNotEmpty && pn.isEmpty) {
      throw const ReferenceException(
          'Enter the program name too — or clear the program code to register '
          'the institute on its own.');
    }

    final existing = await _findInstituteByCode(ic);

    // The code is the identity, so an existing code is reused and never written
    // twice. The NAME is checked on the same pass: the promise behind "already
    // on file" is that both code and name stay unique no matter how the user
    // caps them. A code that exists but was given a different name is rejected —
    // silently reusing it would bury the typed name — and a name that belongs to
    // a different code is rejected too, so one school cannot exist under two
    // codes.
    if (existing != null) {
      if (iname.isNotEmpty && !_sameCaseFold(existing.name, iname)) {
        throw ReferenceException(
            'Institute "$ic" is already on file as "${existing.name}". '
            'Pick that entry from the list or use its saved name.');
      }
    } else {
      // The name is only required when the institute has to be created. Asking for
      // it unconditionally made re-saving a known code fail on a box the clerk had
      // no reason to fill in, since the name is already on file.
      if (iname.isEmpty) {
        throw const ReferenceException('Enter the institute name.');
      }
      final named = await _findInstituteByName(iname);
      if (named != null) {
        throw ReferenceException(
            'An institute named "$iname" is already on file as '
            '"${named.code}". Use "${named.code}" rather than inventing '
            '"$ic" for the same school.');
      }
    }

    String instituteId;
    var created = false;
    if (existing != null) {
      instituteId = existing.id;
    } else {
      instituteId = await _insertInstitute(ic, iname);
      created = true;
    }

    if (pc.isEmpty) {
      // An institute on its own. The catalog still has to learn about it, because
      // every dropdown on every screen is built from the catalog.
      if (created) await ReferenceCatalog.reload();
      return (instituteCode: ic, programCode: '', created: created);
    }

    final program = await addProgram(
      existingInstituteId: instituteId,
      instituteCode: ic,
      instituteName: iname,
      programCode: pc,
      programName: pn,
    );
    return (instituteCode: ic, programCode: program.code, created: true);
  }

  /// Inserts one `institutes` row and returns its `institute_id`.
  ///
  /// Split out of [addInstitute] and [saveInstituteAndProgram] so both write the
  /// institute the same way and neither has to re-implement the error wrapping.
  static Future<String> _insertInstitute(String code, String name) async {
    try {
      final row = await supabaseClient
          .from('institutes')
          .insert({'code': code, 'name': name})
          .select('institute_id')
          .single();
      return '${(row as Map)['institute_id']}';
    } catch (e) {
      throw ReferenceException(_explain(e, 'Could not save the institute.'));
    }
  }

  /// Adds an institute on its own.
  ///
  /// Legal on its own — an institute can exist before it offers anything, and
  /// forcing a program here is how a school ends up with a placeholder "TBA"
  /// program. Returns the institute on file, existing or new.
  static Future<InstituteOption> addInstitute({
    required String code,
    required String name,
  }) async {
    final c = code.trim();
    final n = name.trim();
    if (c.isEmpty) throw const ReferenceException('Enter the institute code.');
    if (n.isEmpty) throw const ReferenceException('Enter the institute name.');

    final existing = await _findInstituteByCode(c);
    if (existing != null) {
      throw ReferenceException(
          'Institute "$c" is already on file as "${existing.name}".');
    }
    final named = await _findInstituteByName(n);
    if (named != null) {
      throw ReferenceException(
          'An institute named "$n" is already on file as "${named.code}". '
          'Use "${named.code}" instead of "$c".');
    }

    try {
      final row = await supabaseClient
          .from('institutes')
          .insert({'code': c, 'name': n})
          .select()
          .single();
      await ReferenceCatalog.reload();
      return InstituteOption.fromSupabase(Map<String, dynamic>.from(row));
    } catch (e) {
      throw ReferenceException(_explain(e, 'Could not save the institute.'));
    }
  }

  /// Adds a program, creating its institute when the institute is new.
  ///
  /// Reached through [saveInstituteAndProgram] for the Add Institute / Program
  /// dialog. [existingInstituteId] is the switch that decides the write: given, the
  /// program is bolted onto an institute the school already has; omitted, the
  /// institute named by [instituteCode] is inserted first and the program goes on
  /// it — two statements, because there is no `add_program_with_institute` RPC in
  /// this project.
  ///
  /// Throws [ReferenceException] when the institute code is already on file and no
  /// id was supplied: the caller then knows to use the existing institute rather
  /// than to invent a second one whose name may not match. [saveInstituteAndProgram]
  /// looks the code up first, so that case never reaches here from the dialog.
  static Future<ProgramOption> addProgram({
    required String instituteCode,
    required String instituteName,
    required String programCode,
    required String programName,
    String? existingInstituteId,
  }) async {
    final pc = programCode.trim();
    final pn = programName.trim();
    if (pc.isEmpty) throw const ReferenceException('Enter the program code.');
    if (pn.isEmpty) throw const ReferenceException('Enter the program name.');

    if (existingInstituteId != null && existingInstituteId.isNotEmpty) {
      // Bolting a program onto an institute the school already has.
      final inst = ReferenceCatalog.instituteById(existingInstituteId);
      final dup = ReferenceCatalog.programsOf(existingInstituteId)
          .where((c) => c.toLowerCase() == pc.toLowerCase());
      if (dup.isNotEmpty) {
        throw ReferenceException(
            'Institute ${inst?.code ?? existingInstituteId} already offers "$pc".');
      }
      // The code and the name are both checked, case-insensitively, so a program
      // retyped under a differently-spelled code or name is caught before it is
      // written a second time.
      final named = ReferenceCatalog.programs
          .where((p) =>
              p.instituteId == existingInstituteId && _sameCaseFold(p.name, pn))
          .toList();
      if (named.isNotEmpty) {
        throw ReferenceException(
            'Institute ${inst?.code ?? existingInstituteId} already has a '
            'program named "$pn".');
      }
      try {
        final row = await supabaseClient
            .from('program')
            .insert({
              'institute_id': existingInstituteId,
              'code': pc,
              'name': pn,
            })
            .select()
            .single();
        await ReferenceCatalog.reload();
        return ProgramOption.fromSupabase(Map<String, dynamic>.from(row));
      } catch (e) {
        throw ReferenceException(_explain(e, 'Could not save the program.'));
      }
    }

    final ic = instituteCode.trim();
    final iname = instituteName.trim();
    if (ic.isEmpty) {
      throw const ReferenceException('Enter the institute code.');
    }
    if (iname.isEmpty) {
      throw const ReferenceException('Enter the institute name.');
    }
    final clash = await _findInstituteByCode(ic);
    if (clash != null) {
      throw ReferenceException(
          'Institute "$ic" is already on file as "${clash.name}" — pick it '
          'from the list instead of creating it again.');
    }

    // Two INSERTs rather than the `add_program_with_institute` RPC, which is not
    // present in this project. The clash check above has already established the
    // institute is not on file, and `institute_id` is left to the database — the
    // same thing [addInstitute] does and the same thing that is known to work
    // here.
    //
    // If the program INSERT fails after the institute INSERT has landed, the
    // institute is left on file with no program. That is recoverable and
    // reported rather than hidden: the error text names what to clean up.
    String instituteId;
    try {
      final instRow = await supabaseClient
          .from('institutes')
          .insert({'code': ic, 'name': iname})
          .select('institute_id')
          .single();
      instituteId = '${(instRow as Map)['institute_id']}';
    } catch (e) {
      throw ReferenceException(_explain(e, 'Could not save the institute.'));
    }

    try {
      final row = await supabaseClient
          .from('program')
          .insert({
            'institute_id': instituteId,
            'code': pc,
            'name': pn,
          })
          .select()
          .single();
      await ReferenceCatalog.reload();
      return ProgramOption.fromSupabase(Map<String, dynamic>.from(row));
    } catch (e) {
      throw ReferenceException(
        '${_explain(e, 'Could not save the program.')} '
        'The institute "$ic" may have been saved without its program.',
      );
    }
  }

  // ── DEPARTMENT / OFFICE ──────────────────────────────────────────────────

  /// Adds a department or office. Only staff carry one.
  static Future<NamedOption> addDepartment(String name) async {
    final n = name.trim();
    if (n.isEmpty) {
      throw const ReferenceException('Enter the department or office name.');
    }
    final dup = ReferenceCatalog.departmentIdByName(n);
    if (dup != null) {
      throw ReferenceException('"$n" is already on file.');
    }
    try {
      final row = await supabaseClient
          .from('departments_offices')
          .insert({'name': n})
          .select()
          .single();
      await ReferenceCatalog.reload();
      return NamedOption.fromSupabase(
          Map<String, dynamic>.from(row), 'department_office_id');
    } catch (e) {
      throw ReferenceException(
          _explain(e, 'Could not save the department / office.'));
    }
  }

  // ── POSITION ──────────────────────────────────────────────────────────────

  /// Adds a position. Faculty and staff both carry one.
  static Future<NamedOption> addPosition(String name) async {
    final n = name.trim();
    if (n.isEmpty) throw const ReferenceException('Enter the position name.');
    final dup = ReferenceCatalog.positionIdByName(n);
    if (dup != null) {
      throw ReferenceException('"$n" is already on file.');
    }
    try {
      final row = await supabaseClient
          .from('positions')
          .insert({'name': n})
          .select()
          .single();
      await ReferenceCatalog.reload();
      return NamedOption.fromSupabase(
          Map<String, dynamic>.from(row), 'position_id');
    } catch (e) {
      throw ReferenceException(_explain(e, 'Could not save the position.'));
    }
  }

  // ── INTERNALS ─────────────────────────────────────────────────────────────

  /// Marks every Active record of [periodId] Inactive, so the roster shows the
  /// term being run only.
  static Future<int> _retirePeriod(String periodId) async {
    final rows = await supabaseClient
        .from('individual_academic_records')
        .update({'status': 'Inactive'})
        .eq('academic_period_id', periodId)
        .eq('status', 'Active')
        .select('person_id');
    if (rows.isNotEmpty) DataTracker.bump();
    return rows.length;
  }

  static Future<InstituteOption?> _findInstituteByCode(String code) async {
    final cached = ReferenceCatalog.instituteByCode(code);
    if (cached != null && cached.id.isNotEmpty) return cached;
    // `ilike` with no wildcard is Postgres's case-insensitive equality, which is
    // what the uq_institute_code unique index compares.
    final rows = await supabaseClient
        .from('institutes')
        .select()
        .ilike('code', code)
        .limit(1);
    if (rows.isEmpty) return null;
    return InstituteOption.fromSupabase(Map<String, dynamic>.from(rows.first));
  }

  /// An institute whose NAME matches [name], ignoring capitalisation — the other
  /// half of "both code and name must be unique". Found by name so an institute
  /// someone typed again under a different code is caught before a second row for
  /// the same school is written.
  static Future<InstituteOption?> _findInstituteByName(String name) async {
    final cached = ReferenceCatalog.institutes
        .where((e) => _sameCaseFold(e.name, name))
        .toList();
    if (cached.isNotEmpty && cached.first.id.isNotEmpty) return cached.first;
    final rows = await supabaseClient
        .from('institutes')
        .select()
        .ilike('name', name)
        .limit(1);
    if (rows.isEmpty) return null;
    return InstituteOption.fromSupabase(Map<String, dynamic>.from(rows.first));
  }

  /// Whether [a] and [b] are the same text ignoring leading/trailing spaces and
  /// capitalisation — how every name and code duplicate is compared.
  static bool _sameCaseFold(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();

  /// Turns a PostgREST / Postgres error into something a clerk can act on.
  ///
  /// 23505 is `unique_violation` — the duplicate the caller asked about anyway,
  /// so it is reported as "already on file" rather than as a crash. 23514 is a
  /// CHECK constraint (a year that does not parse, a semester spelled
  /// differently) and its message is Postgres's own, which is already written for
  /// a human.
  static String _explain(Object e, String fallback) {
    final text = e.toString();
    if (text.contains('23505')) {
      return 'That is already on file.';
    }
    if (text.contains('23503')) {
      return 'That refers to something that is not on file.';
    }
    if (text.contains('23514')) {
      final m = RegExp(r'detail: (.*?)(?:[)]|\n)').firstMatch(text);
      final detail = m?.group(1)?.trim();
      if (detail != null && detail.isNotEmpty) return detail;
    }
    if (text.contains('PGRST')) return '$fallback ($text)';
    return '$fallback $text';
  }
}
