import 'package:clinicmanagementsystem/core/services/data_tracker.dart';
import 'package:clinicmanagementsystem/core/config/supabase_config.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

class AcademicPeriodOption {
  final String id;
  final String acadYear;
  final String semester;
  final String status;

  const AcademicPeriodOption({
    required this.id,
    required this.acadYear,
    required this.semester,
    required this.status,
  });

  bool get isActive => status == 'Active';

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

class InstituteOption {
  final String id;
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

class ProgramOption {
  final String id;
  final String instituteId;
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

class ReferenceCatalog {
  ReferenceCatalog._();

  static List<AcademicPeriodOption> _periods = [];
  static List<InstituteOption> _institutes = [];
  static List<ProgramOption> _programs = [];
  static List<NamedOption> _departments = [];
  static List<NamedOption> _positions = [];

  static bool _loaded = false;
  static bool get isLoaded => _loaded;

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

  static AcademicPeriodOption? get activePeriod {
    for (final p in _periods) {
      if (p.isActive) return p;
    }
    return null;
  }

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

  static List<InstituteOption> get institutes =>
      List<InstituteOption>.unmodifiable(_institutes);

  static List<ProgramOption> get programs =>
      List<ProgramOption>.unmodifiable(_programs);

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

  static List<String> programsOf(String? instituteId) {
    if (instituteId == null || instituteId.isEmpty) return const <String>[];
    final list = _programs
        .where((p) => p.instituteId == instituteId)
        .map((p) => p.code)
        .toList()
      ..sort();
    return List<String>.unmodifiable(list);
  }

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

  static Future<void> load({bool force = false}) async {
    if (_loaded && !force) return;

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

  static Future<void> loadQuietly() async {
    final wasLoaded = _loaded;
    try {
      await load();
    } catch (_) {}
    if (!wasLoaded && _loaded) _notify();
  }

  static Future<void> loadAfterSignIn() async {
    if (_loaded || !hasSignedInUser) return;
    try {
      await load(force: true);
    } catch (_) {
      return;
    }

    _notify();
  }

  static Future<void> reload() async {
    await load(force: true);
    _notify();
    DataTracker.bump();
  }

  static Future<void> refreshPeriods() async {
    if (!hasSignedInUser) return;
    final rows = await supabaseClient.from('academic_periods').select();
    _periods = (rows as List)
        .map((r) => AcademicPeriodOption.fromSupabase(
            Map<String, dynamic>.from(r as Map)))
        .where((p) => p.id.isNotEmpty)
        .toList();
  }

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
}

class ReferenceException implements Exception {
  final String message;
  const ReferenceException(this.message);
  @override
  String toString() => message;
}

class ReferenceDataService {
  ReferenceDataService._();

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

    final previousActive = ReferenceCatalog.activePeriod;

    AcademicPeriodOption period;
    try {
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

    ReferenceException? carryFailure;

    if (makeCurrent &&
        !carryOverRoster &&
        previousActive != null &&
        previousActive.id != period.id) {
      try {
        await _copyRoster(previousActive.id, period.id,
            categories: const {'Faculty', 'Staff'});
      } catch (e) {
        carryFailure = ReferenceException(_explain(
            e, 'Could not carry Faculty and Staff into the new term.'));
      }
      try {
        await _retirePeriod(previousActive.id);
      } catch (e) {
        carryFailure ??= ReferenceException(
            _explain(e, 'Could not close the previous term.'));
      }
    }

    if (carryOverRoster) {
      final from = previousActive;
      if (from == null) {
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

        if (!makeCurrent) {
          try {
            await _retirePeriod(from.id);
          } catch (e) {
            carryFailure ??= ReferenceException(
                _explain(e, 'Could not close the previous term.'));
          }
        } else {
          try {
            await _retirePeriod(from.id);
          } catch (e) {
            carryFailure ??= ReferenceException(
                _explain(e, 'Could not close the previous term.'));
          }
        }
      }
    }

    await ReferenceCatalog.reload();

    if (carryFailure != null) throw carryFailure;

    return (
      period: ReferenceCatalog.periodById(period.id) ?? period,
      carried: carried,
    );
  }

  static Future<void> _setActivePeriodRow(String periodId) async {
    await supabaseClient
        .from('academic_periods')
        .update({'status': 'Inactive'}).eq('status', 'Active');
    await supabaseClient
        .from('academic_periods')
        .update({'status': 'Active'}).eq('academic_period_id', periodId);
  }

  static Future<int> _copyRoster(
    String fromPeriodId,
    String toPeriodId, {
    Set<String>? categories,
  }) async {
    final source =
        await supabaseClient.from('individual_academic_records').select('''
          person_id,
          institute_id,
          program_id,
          year_level,
          department_office_id,
          position_id,
          person:individual_records!inner(person_type)
        ''').eq('academic_period_id', fromPeriodId).eq('status', 'Active');

    final wanted = <Map<String, dynamic>>[];
    for (final row in source) {
      final m = Map<String, dynamic>.from(row as Map);
      final person = m.remove('person');
      final type = person is Map ? '${person['person_type'] ?? ''}' : '';
      if (categories != null && !categories.contains(type)) continue;
      wanted.add(m);
    }
    if (wanted.isEmpty) return 0;

    final existing = await supabaseClient
        .from('individual_academic_records')
        .select('person_id')
        .eq('academic_period_id', toPeriodId);
    final already = {for (final r in existing) '${(r as Map)['person_id']}'};

    final payloads = [
      for (final row in wanted)
        if (!already.contains('${row['person_id']}'))
          {
            ...row,
            'academic_period_id': toPeriodId,
            'status': 'Active',
          }..remove('academic_record_id'),
    ];
    if (payloads.isEmpty) return 0;

    await supabaseClient.from('individual_academic_records').insert(payloads);
    DataTracker.bump();
    return payloads.length;
  }

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

    if (existing != null) {
      if (iname.isNotEmpty && !_sameCaseFold(existing.name, iname)) {
        throw ReferenceException(
            'Institute "$ic" is already on file as "${existing.name}". '
            'Pick that entry from the list or use its saved name.');
      }
    } else {
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
      final inst = ReferenceCatalog.instituteById(existingInstituteId);
      final dup = ReferenceCatalog.programsOf(existingInstituteId)
          .where((c) => c.toLowerCase() == pc.toLowerCase());
      if (dup.isNotEmpty) {
        throw ReferenceException(
            'Institute ${inst?.code ?? existingInstituteId} already offers "$pc".');
      }

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

  static Future<int> _retirePeriod(String periodId) async {
    if (periodId.trim().isEmpty) return 0;
    final studentIds = await _activePersonIds(periodId, 'Student');
    if (studentIds.isEmpty) return 0;

    var retired = 0;
    for (var i = 0; i < studentIds.length; i += _idChunk) {
      final end =
          (i + _idChunk < studentIds.length) ? i + _idChunk : studentIds.length;
      final rows = await supabaseClient
          .from('individual_academic_records')
          .update({'status': 'Inactive'})
          .eq('academic_period_id', periodId)
          .eq('status', 'Active')
          .inFilter('person_id', studentIds.sublist(i, end))
          .select('person_id');
      retired += rows.length;
    }
    if (retired > 0) DataTracker.bump();
    return retired;
  }

  static Future<List<String>> _activePersonIds(
    String periodId,
    String category,
  ) async {
    final rows = await supabaseClient
        .from('individual_academic_records')
        .select('person_id, person:individual_records!inner(person_type)')
        .eq('academic_period_id', periodId)
        .eq('status', 'Active')
        .eq('person.person_type', category);
    return [for (final r in rows) '${(r as Map)['person_id']}'];
  }

  static const int _idChunk = 150;

  static Future<InstituteOption?> _findInstituteByCode(String code) async {
    final cached = ReferenceCatalog.instituteByCode(code);
    if (cached != null && cached.id.isNotEmpty) return cached;

    final rows = await supabaseClient
        .from('institutes')
        .select()
        .ilike('code', code)
        .limit(1);
    if (rows.isEmpty) return null;
    return InstituteOption.fromSupabase(Map<String, dynamic>.from(rows.first));
  }

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

  static bool _sameCaseFold(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();

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
