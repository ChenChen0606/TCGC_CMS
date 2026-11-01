import 'dart:math';

import 'package:clinicmanagementsystem/features/patients/models/individual_record_data.dart';
import 'package:clinicmanagementsystem/features/account/services/account_service.dart';
import 'package:clinicmanagementsystem/core/services/data_tracker.dart';
import 'package:clinicmanagementsystem/core/services/reference_data_service.dart';
import 'package:clinicmanagementsystem/core/config/supabase_config.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

class IndividualRecordSaveIncomplete implements Exception {
  IndividualRecordSaveIncomplete(this.record, this.message);

  final IndividualRecord record;

  final String message;

  @override
  String toString() => message;
}

class IndividualRecordService {
  IndividualRecordService._();

  static const String _people = 'individual_records';

  static const String _enrolments = 'individual_academic_records';

  static dynamic _byPair(
    dynamic query,
    String personUuid,
    String academicPeriodId,
  ) =>
      query
          .eq('person_id', personUuid)
          .eq('academic_period_id', academicPeriodId);

  static const String _rosterSelect = '''
$_enrolmentSelect,
    person:individual_records!left(
      person_id, person_type, fn, mn, ln, suffix, sex, date_of_birth,
      contact_number, email, address, created_at, created_by
    )''';

  static const String _enrolmentSelect = '''
    academic_record_id,
    academic_period_id,
    status,
    institute_id,
    program_id,
    year_level,
    department_office_id,
    position_id,
    period:academic_periods!left(academic_period_id, acad_year, semester),
    institute:institutes!left(institute_id, code),
    program_ref:program!left(program_id, code, name),
    department_ref:departments_offices!left(department_office_id, name),
    position_ref:positions!left(position_id, name)''';

  static const String _personSelect = '''
    person_id,
    person_type,
    fn,
    mn,
    ln,
    suffix,
    sex,
    date_of_birth,
    contact_number,
    email,
    address,
    created_at,
    created_by''';

  static Future<List<IndividualRecord>> fetchAll({
    String? category,
    String? search,
    bool includeInactive = false,
    String? academicPeriodId,
  }) async {
    final cat = category?.trim() ?? '';
    final needle = (search ?? '').trim();

    final periodId = academicPeriodId?.trim() ?? '';
    var effectivePeriod = periodId;
    if (!includeInactive && effectivePeriod.isEmpty) {
      effectivePeriod = ReferenceCatalog.activePeriod?.id ?? '';
      if (effectivePeriod.isEmpty) {
        return const [];
      }
    }

    var q = supabaseClient.from(_enrolments).select(_rosterSelect);

    if (!includeInactive) q = q.eq('status', kRecordStatusActive);

    if (effectivePeriod.isNotEmpty) {
      q = q.eq('academic_period_id', effectivePeriod);
    }

    if (cat.isNotEmpty) {
      q = q.eq('person.person_type', personTypeForStorage(cat));
    }

    if (needle.isNotEmpty) {
      final safe = _filterSafe(needle);
      if (safe.isNotEmpty) {
        final like = '%$safe%';

        final matching = await supabaseClient
            .from(_people)
            .select('person_id')
            .or([
              'person_id.ilike.$like',
              'fn.ilike.$like',
              'mn.ilike.$like',
              'ln.ilike.$like',
              'contact_number.ilike.$like',
              'email.ilike.$like',
              'address.ilike.$like',
            ].join(','))
            .limit(_maxSearchMatches);

        final ids = [
          for (final row in matching) '${row['person_id']}',
        ];
        if (ids.isEmpty) return const [];

        q = q.or([
          'year_level.ilike.$like',
          'person_id.in.(${ids.map(_inFilterSafe).join(',')})',
        ].join(','));
      }
    }

    final rows = await q;
    return _dedupe(rows
        .map<IndividualRecord>(
            (r) => IndividualRecord.fromSupabase(Map<String, dynamic>.from(r)))
        .toList());
  }

  static Future<List<IndividualRecord>> fetchAllOnePerPerson() async {
    final all = await fetchAll(includeInactive: true);
    final best = <String, IndividualRecord>{};
    for (final r in all) {
      final prev = best[r.id];
      if (prev == null || _preferEnrolment(r, prev)) {
        best[r.id] = r;
      }
    }
    return best.values.toList();
  }

  static bool _preferEnrolment(IndividualRecord next, IndividualRecord prev) {
    final nr = _enrolmentRank(next);
    final pr = _enrolmentRank(prev);
    if (nr != pr) return nr > pr;

    final year = next.academicYear.compareTo(prev.academicYear);
    if (year != 0) return year > 0;
    final sem =
        _semesterRank(next.semester).compareTo(_semesterRank(prev.semester));
    if (sem != 0) return sem > 0;

    final nextAt = next.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    final prevAt = prev.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
    return nextAt.isAfter(prevAt);
  }

  static int _enrolmentRank(IndividualRecord r) {
    if (r.status != kRecordStatusActive) return 0;
    final activeId = ReferenceCatalog.activePeriod?.id ?? '';
    if (activeId.isNotEmpty && r.academicPeriodId == activeId) return 2;
    return 1;
  }

  static Future<IndividualRecord?> fetchLatest(
    String category,
    String recordNo,
  ) async {
    final key = recordNo.trim();
    if (key.isEmpty) return null;

    final rows = await supabaseClient
        .from(_people)
        .select('$_personSelect, academic:$_enrolments($_enrolmentSelect)')
        .eq('person_type', personTypeForStorage(category))
        .eq('person_id', key)
        .limit(1);

    if (rows.isEmpty) return null;
    return IndividualRecord.fromSupabase(
        _withNewestEnrolment(Map<String, dynamic>.from(rows.first)));
  }

  static Future<IndividualRecord?> fetchEnrolment(
    String? personUuid,
    String? academicPeriodId,
  ) async {
    if (personUuid == null || personUuid.isEmpty) return null;
    if (academicPeriodId == null || academicPeriodId.isEmpty) return null;

    final rows = await supabaseClient
        .from(_enrolments)
        .select(_rosterSelect)
        .eq('person_id', personUuid)
        .eq('academic_period_id', academicPeriodId)
        .limit(1);
    if (rows.isEmpty) return null;
    return IndividualRecord.fromSupabase(Map<String, dynamic>.from(rows.first));
  }

  static Future<IndividualRecord?> fetchByUuid(String personUuid) async {
    final rows = await supabaseClient
        .from(_people)
        .select('$_personSelect, academic:$_enrolments($_enrolmentSelect)')
        .eq('person_id', personUuid)
        .limit(1);
    if (rows.isEmpty) return null;
    return IndividualRecord.fromSupabase(
        _withNewestEnrolment(Map<String, dynamic>.from(rows.first)));
  }

  static Map<String, dynamic> _withNewestEnrolment(
      Map<String, dynamic> person) {
    final enrolments = person['academic'] as List<dynamic>? ?? const [];
    final merged = Map<String, dynamic>.from(person)..remove('academic');
    if (enrolments.isEmpty) return merged;

    final sorted = enrolments
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList()
      ..sort((a, b) {
        final ay = '${(a['period'] as Map?)?['acad_year'] ?? ''}';
        final by = '${(b['period'] as Map?)?['acad_year'] ?? ''}';
        final year = by.compareTo(ay);
        if (year != 0) return year;
        return _semesterRank('${(b['period'] as Map?)?['semester'] ?? ''}')
            .compareTo(
                _semesterRank('${(a['period'] as Map?)?['semester'] ?? ''}'));
      });

    merged['academic'] = sorted.first;
    return merged;
  }

  static Future<bool> idExists(
    String category,
    String recordNo, {
    String? ignoringUuid,
  }) async {
    final key = recordNo.trim();
    if (key.isEmpty) return false;
    var q = supabaseClient
        .from(_people)
        .select('person_id')
        .eq('person_type', personTypeForStorage(category))
        .eq('person_id', key);
    if (ignoringUuid != null && ignoringUuid.isNotEmpty) {
      q = q.neq('person_id', ignoringUuid);
    }
    final rows = await q.limit(1);
    return rows.isNotEmpty;
  }

  static Future<String?> identityClash(
    String category, {
    required String firstName,
    required String middleName,
    required String lastName,
    required String suffix,
    DateTime? birthDate,
    String? ignoringUuid,
  }) async {
    final fn = firstName.trim();
    final ln = lastName.trim();
    if (fn.isEmpty || ln.isEmpty) return null;
    final mn = middleName.trim();
    final sx = suffix.trim();
    final wantedDob = birthDate == null ? null : _dateStamp(birthDate);

    var q = supabaseClient
        .from(_people)
        .select('person_id,fn,mn,ln,suffix,date_of_birth')
        .eq('person_type', personTypeForStorage(category));
    if (ignoringUuid != null && ignoringUuid.isNotEmpty) {
      q = q.neq('person_id', ignoringUuid);
    }
    final rows = await q;
    for (final r in rows) {
      final m = Map<String, dynamic>.from(r);
      if (!_nameEquals(m['fn'], fn)) continue;
      if (!_nameEquals(m['mn'], mn)) continue;
      if (!_nameEquals(m['ln'], ln)) continue;
      if (!_nameEquals(m['suffix'], sx)) continue;
      final storedDob = '${m['date_of_birth'] ?? ''}';
      if (wantedDob != null && storedDob.isNotEmpty && storedDob != wantedDob) {
        continue;
      }
      return '${m['person_id']}';
    }
    return null;
  }

  static bool _nameEquals(Object? stored, String value) {
    if (stored == null) return value.isEmpty;
    return '$stored'.trim().toLowerCase() == value.toLowerCase();
  }

  static String _dateStamp(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  static Future<bool> enrolmentExists(
    String personUuid,
    String academicPeriodId,
  ) async {
    if (personUuid.isEmpty || academicPeriodId.isEmpty) return false;
    final rows = await _byPair(
            supabaseClient.from(_enrolments).select('person_id'),
            personUuid,
            academicPeriodId)
        .limit(1);
    return rows.isNotEmpty;
  }

  static final Random _random = Random.secure();

  static const int _maxIdAttempts = 40;

  static String idLetterFor(String category) => category == 'Staff' ? 'S' : 'F';

  static Future<String> nextIdFor(String category) async {
    final letter = idLetterFor(category);

    try {
      final data = await supabaseClient.rpc(
        'generate_person_id',
        params: {'p_category': category, 'p_letter': letter},
      );
      final id = data is List
          ? (data.isEmpty ? '' : '${data.first}')
          : '${data ?? ''}';
      if (id.isNotEmpty && id != 'null') return id;
    } catch (_) {}

    for (var attempt = 0; attempt < _maxIdAttempts; attempt++) {
      final digits =
          List<String>.generate(6, (_) => '${_random.nextInt(10)}').join();
      final candidate = '$letter$digits';
      if (!await idExists(category, candidate)) return candidate;
    }
    throw StateError(
      'Could not find a free $category number after $_maxIdAttempts tries. '
      'Enter one manually.',
    );
  }

  static String describeWriteFailure(
    Object error, {
    required String category,
    required String recordNo,
  }) {
    if (error is IndividualRecordSaveIncomplete) return error.message;
    if (error is! PostgrestException) return '$error';
    final code = error.code ?? '';
    final message = error.message;
    final details = error.details is String ? error.details! as String : '';
    final who = '${category.toLowerCase()} number $recordNo';

    String because(String text) =>
        details.isEmpty ? text : '$text\n\n($details)';

    if (code == '23505' || code == '23514') {
      if (message.contains('uq_individual_email')) {
        return because(
            'That email address is already on file for someone else.\n'
            'Leave the email blank if this person has none — a blank box is '
            'saved as "no address", not as an empty address.');
      }
      if (message.contains('uq_individual_identity')) {
        return because(
            'Someone with the same first, middle, last name, suffix and birth '
            'date is already on file. Check whether this is the same person '
            'before filing a second record.');
      }
      if (message.contains('individual_records_pkey')) {
        return because(
            '$who is already on file. A number identifies one person for good — '
            'it does not restart each term.');
      }
      if (message.contains('uq_person_period')) {
        return because(
            '$who is already enrolled in this term. Edit that record instead of '
            'adding them again.');
      }
      if (message.contains('chk_person_type')) {
        return because(
            'The category "$category" is not one the database accepts. It must '
            'be exactly Student, Faculty or Staff.');
      }
      if (message.contains('chk_person_id_prefix')) {
        final letter = idLetterFor(category);
        return because('A $category number has to start with "$letter". '
            'Use the number this form generated, or type one that does.');
      }
      if (message.contains('chk_sex')) {
        return because('Sex has to be Male or Female, or left blank.');
      }
      if (message.contains('chk_year_level')) {
        return because(
            'Year level has to be between 1st Year and 4th Year, or left blank.');
      }
    }
    if (code == '23503') {
      if (message.contains('fk_program_in_institute')) {
        return because(
            'That program is not offered by the institute selected. Pick a '
            'program belonging to it.');
      }
      return because(
          'One of the institute, program, office, position or term selected no '
          'longer exists. Close the form, reload the page and try again.');
    }
    if (code == '42501') {
      return 'You are signed in, but this account is not allowed to write to '
          'the roster. Ask an administrator.';
    }

    final server = [
      if (message.trim().isNotEmpty) message.trim(),
      if (details.trim().isNotEmpty) details.trim(),
    ].join(' — ');
    final tail = server.isEmpty
        ? ''
        : '\n\nThe database said: $server'
            '${code.trim().isEmpty ? '' : ' (code $code)'}';
    return 'Could not save $who.$tail';
  }

  static String _periodLabel(String periodId) =>
      ReferenceCatalog.periodById(periodId)?.label ?? 'enrolment';

  static Future<IndividualRecord> create(IndividualRecord r) async {
    final periodId = (r.academicPeriodId ?? '').trim();
    if (periodId.isEmpty) {
      throw StateError(
          'Cannot save ${r.category} ${r.id}: no academic period, so the record '
          'would be written with no enrolment and would not appear in the '
          'roster, the visitor list or the archive.');
    }
    await _syncPeriods();
    r.status = statusForTerm(periodId);

    String personUuid = r.id;

    final personExists = await idExists(r.category, r.id);
    if (personExists) {
      try {
        final stamped = _stamped(r);
        await supabaseClient
            .from(_people)
            .update(stamped.personPayload(includeAudit: false))
            .eq('person_id', r.id);
      } catch (e) {
        debugPrint('create: failed to update existing person ${r.id}: $e');
      }
    } else {
      personUuid = await _insertPerson(_stamped(r));
    }

    try {
      final existingEnrol = await fetchEnrolment(personUuid, periodId);
      if (existingEnrol != null) {
        await supabaseClient
            .from(_enrolments)
            .update({
              ...r.academicPayload(includeAudit: false),
              'status': r.status,
            })
            .eq('person_id', personUuid)
            .eq('academic_period_id', periodId);
      } else {
        await _insertEnrolment(personUuid, r);
      }
    } catch (e) {
      debugPrint(
          'IndividualRecordService: create of ${r.id} enrollment issue for '
          '$personUuid period $periodId — $e');
      throw IndividualRecordSaveIncomplete(
        await _readBack(personUuid, r, what: 'create of ${r.id}'),
        'Could not save ${r.category} ${r.id}.\n\n'
        'The person was saved/updated, but the '
        '${_periodLabel(periodId)} could not be saved.\n\n'
        '${describeWriteFailure(e, category: r.category, recordNo: r.id)}',
      );
    }
    DataTracker.bump();
    return _readBack(personUuid, r, what: '${r.category} ${r.id}');
  }

  static Future<IndividualRecord> _readBack(
    String uuid,
    IndividualRecord written, {
    String what = 'record',
  }) async {
    try {
      final saved = await fetchByUuid(uuid);
      if (saved != null) return saved;
      debugPrint('IndividualRecordService: $what $uuid was written but read '
          'back as missing.');
    } catch (e) {
      debugPrint('IndividualRecordService: $what $uuid was written but could '
          'not be read back — $e');
    }
    return written..uuid = uuid;
  }

  static String _currentAccount() => AccountService.currentUserId.trim();

  static bool _blank(Object? value) => (value ?? '').toString().trim().isEmpty;

  static IndividualRecord _stamped(IndividualRecord r) {
    if ((r.createdBy ?? '').trim().isNotEmpty) return r;
    final uid = _currentAccount();
    if (uid.isEmpty) {
      throw StateError(
        'Cannot save ${r.category} ${r.id}: no signed-in account, so there is '
        'nobody to record as the person who filed it.\n'
        'Sign in again and save once more — nothing was written.',
      );
    }
    r.createdBy = uid;
    return r;
  }

  static Future<String> _insertPerson(IndividualRecord r) async {
    await supabaseClient.from(_people).insert(r.personPayload());
    return r.id;
  }

  static Future<void> _insertEnrolment(
    String personUuid,
    IndividualRecord r,
  ) async {
    if (r.academicPeriodId == null || r.academicPeriodId!.isEmpty) return;
    await supabaseClient.from(_enrolments).insert({
      ..._stamped(r).academicPayload(),
      'person_id': personUuid,
    });
  }

  static Future<void> _fileEnrolment(
    String personUuid,
    IndividualRecord r,
    String wantedStatus,
  ) async {
    final periodId = (r.academicPeriodId ?? '').trim();
    if (periodId.isEmpty) return;

    final payload = {
      ...r.academicPayload(includeAudit: false),
      'status': wantedStatus,
    };

    final existing = await _byPair(
            supabaseClient.from(_enrolments).select('status'),
            personUuid,
            periodId)
        .limit(1);

    if (existing.isEmpty) {
      await supabaseClient.from(_enrolments).insert({
        ..._stamped(r).academicPayload(),
        'person_id': personUuid,
        'status': wantedStatus,
      });
      return;
    }

    await _byPair(
        supabaseClient.from(_enrolments).update(payload), personUuid, periodId);
  }

  static Future<IndividualRecord> update(
    IndividualRecord r, {
    String? previousPeriodId,
  }) async {
    final uuid = r.uuid;
    if (uuid == null) {
      throw StateError('Cannot update an individual record without a uuid.');
    }

    final touched = await supabaseClient
        .from(_people)
        .update(r.personPayload(includeAudit: false))
        .eq('person_id', uuid)
        .select('person_id')
        .then((rows) => rows.cast<Map<String, dynamic>>());

    if (touched.isEmpty) {
      debugPrint(
          'IndividualRecordService: update of ${r.id} ($uuid) matched no '
          'person row. Either it is gone, or RLS hides it from this account.');
      throw StateError(
        'Could not save ${r.category} ${r.id}: this session cannot see that '
        'record, so nothing was changed.\n\n'
        'It may have been archived or removed from another session. Close the '
        'form, reload the roster, and reopen the person. If the record is still '
        'listed after reloading, ask an administrator — your account may not be '
        'permitted to edit it.',
      );
    }

    final account = _currentAccount();
    if (account.isNotEmpty) {
      final missingAudit = await supabaseClient
          .from(_people)
          .select('created_by')
          .eq('person_id', uuid)
          .limit(1);
      if (missingAudit.isNotEmpty && _blank(missingAudit.first['created_by'])) {
        await supabaseClient.from(_people).update(
            {'created_by': account, 'userid': account}).eq('person_id', uuid);
      }
    }

    final periodId = (r.academicPeriodId ?? '').trim();

    await _syncPeriods();

    final wantedStatus = r.status == kRecordStatusArchived
        ? kRecordStatusInactive
        : (previousPeriodId != null && previousPeriodId.trim() != periodId)
            ? statusForTerm(periodId)
            : (r.status.isEmpty ? statusForTerm(periodId) : r.status);

    if (periodId.isNotEmpty) {
      try {
        await _fileEnrolment(uuid, r, wantedStatus);
      } catch (e) {
        debugPrint(
            'IndividualRecordService: update of ${r.id} saved the person '
            '$uuid but its $periodId enrolment was refused — $e');
        throw IndividualRecordSaveIncomplete(
          await _readBack(uuid, r, what: 'update of ${r.id}'),
          'Could not save ${r.category} ${r.id}.\n\n'
          'The details were saved, but the '
          '${_periodLabel(periodId)} was not, so this record may not show '
          'on the roster.\n\n'
          '${describeWriteFailure(e, category: r.category, recordNo: r.id)}',
        );
      }
    }

    DataTracker.bump();
    return _readBack(uuid, r, what: 'update of ${r.id}');
  }

  static Future<void> archivePerson(
    String personUuid, {
    String? reason,
  }) async {
    await supabaseClient
        .from(_enrolments)
        .update({'status': kRecordStatusArchived})
        .eq('person_id', personUuid)
        .neq('status', kRecordStatusArchived);
    DataTracker.bump();
  }

  static Future<void> restorePerson(String personUuid) async {
    await supabaseClient
        .from(_enrolments)
        .update({'status': kRecordStatusActive})
        .eq('person_id', personUuid)
        .eq('status', kRecordStatusArchived);
    DataTracker.bump();
  }

  static Future<Map<String, String>> fetchUserNames() async {
    try {
      final rows = await supabaseClient
          .from('useraccount')
          .select('user_id, username, fn, ln');
      return {
        for (final r in rows)
          if (r['user_id'] != null) r['user_id'] as String: _nameOf(r),
      };
    } catch (_) {
      return const {};
    }
  }

  static String _nameOf(Map<String, dynamic> row) {
    final name = [
      (row['fn'] as String? ?? '').trim(),
      (row['ln'] as String? ?? '').trim(),
    ].where((s) => s.isNotEmpty).join(' ');
    return name.isNotEmpty ? name : (row['username'] as String? ?? '').trim();
  }

  static List<IndividualRecord> _dedupe(List<IndividualRecord> input) {
    final byKey = <String, IndividualRecord>{};
    for (final r in input) {
      final key = r.academicRecordId ?? r.dbKey;
      final prev = byKey[key];
      if (prev == null) {
        byKey[key] = r;
        continue;
      }
      final prevAt = prev.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final nextAt = r.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      byKey[key] = nextAt.isAfter(prevAt) ? r : prev;
    }
    return byKey.values.toList();
  }

  static String statusForTerm(String? academicPeriodId) {
    final id = (academicPeriodId ?? '').trim();
    if (id.isEmpty) return kRecordStatusInactive;
    try {
      ReferenceCatalog.refreshPeriods();
    } catch (_) {}
    final current = ReferenceCatalog.currentPeriod?.id ?? '';
    final active = ReferenceCatalog.activePeriod?.id ?? '';
    if (active.isNotEmpty && id == active) return kRecordStatusActive;
    if (current.isNotEmpty && id == current) return kRecordStatusActive;

    return kRecordStatusInactive;
  }

  static Future<void> _syncPeriods() async {
    try {
      await ReferenceCatalog.refreshPeriods();
    } catch (e) {
      debugPrint('IndividualRecordService: could not re-read the academic '
          'periods — $e');
    }
  }

  static Future<int> retireEarlierPeriods(
    List<({String category, String recordNo})> people, {
    required String academicPeriodId,
  }) async {
    if (academicPeriodId.trim().isEmpty) return 0;

    final ids = <String>{};
    for (final p in people) {
      final no = p.recordNo.trim();
      final cat = p.category.trim();
      if (no.isEmpty || cat.isEmpty) continue;

      if (canonicalCategory(cat) != 'Student') continue;
      final rows = await supabaseClient
          .from(_people)
          .select('person_id')
          .eq('person_type', personTypeForStorage(cat))
          .eq('person_id', no)
          .limit(1);
      for (final r in rows) {
        ids.add('${r['person_id']}');
      }
    }
    if (ids.isEmpty) return 0;

    final written = await supabaseClient
        .from(_enrolments)
        .update({'status': kRecordStatusInactive})
        .inFilter('person_id', ids.toList())
        .neq('academic_period_id', academicPeriodId)
        .eq('status', kRecordStatusActive)
        .select('academic_record_id');
    if (written.isEmpty) return 0;
    DataTracker.bump();
    return written.length;
  }

  static int _semesterRank(String semester) {
    final s = semester.trim().toLowerCase();
    if (s.startsWith('1')) return 0;
    if (s.startsWith('2')) return 1;
    if (s.startsWith('summer')) return 2;
    return 3;
  }

  static String _filterSafe(String v) =>
      v.replaceAll(RegExp(r'[,()*:\\"\s]'), ' ').trim();

  static const int _maxSearchMatches = 300;

  static String _inFilterSafe(String v) =>
      v.replaceAll(RegExp(r'''[,()"'\\]'''), '').replaceAll(' ', '').trim();
}
