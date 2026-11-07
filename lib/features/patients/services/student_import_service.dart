import 'dart:convert';
import 'dart:typed_data';

import 'package:clinicmanagementsystem/features/patients/models/individual_record_data.dart';
import 'package:clinicmanagementsystem/features/account/services/account_service.dart';
import 'package:clinicmanagementsystem/core/services/data_tracker.dart';
import 'package:clinicmanagementsystem/features/patients/services/individual_record_service.dart';
import 'package:clinicmanagementsystem/core/services/reference_data_service.dart';
import 'package:clinicmanagementsystem/core/config/supabase_config.dart';
import 'package:excel_plus/excel_plus.dart' as xl;
import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

const String kImportExists = 'Already exists';
const String kImportInvalid = 'Invalid';

class ImportFileException implements Exception {
  const ImportFileException(this.message);
  final String message;
  @override
  String toString() => message;
}

class StudentImportRow {
  StudentImportRow({
    required this.rowNumber,
    required this.record,
    required this.status,
    required this.note,
    this.personChanges = const <String, dynamic>{},
  });

  final int rowNumber;
  final IndividualRecord record;
  final String status;
  final String note;

  final Map<String, dynamic> personChanges;

  bool get willSave =>
      status == kImportNew ||
      status == kImportUpdated ||
      status == kImportUnchanged;
}

class StudentImportPlan {
  StudentImportPlan({
    required this.fileName,
    required this.rows,
    required this.academicPeriodId,
    required this.termLabel,
  });

  final String fileName;
  final List<StudentImportRow> rows;
  final String academicPeriodId;
  final String termLabel;

  int _count(String s) => rows.where((r) => r.status == s).length;

  int get total => rows.length;
  int get added => _count(kImportNew);
  int get updated => _count(kImportUpdated);
  int get unchanged => _count(kImportUnchanged);
  int get exists => _count(kImportExists);
  int get invalid => _count(kImportInvalid);
  int get saveCount => added + updated + unchanged;
}

class ImportFailure {
  const ImportFailure(this.row, this.reason);
  final StudentImportRow row;
  final String reason;
}

class StudentImportReport {
  StudentImportReport({
    required this.termLabel,
    required this.saved,
    required this.alreadyExisting,
    required this.invalid,
    required this.failed,
    required this.retired,
  });

  final String termLabel;

  final List<StudentImportRow> saved;

  final List<StudentImportRow> alreadyExisting;

  final List<StudentImportRow> invalid;

  final List<ImportFailure> failed;

  final int retired;

  int _count(String s) => saved.where((r) => r.status == s).length;
  int get added => _count(kImportNew);
  int get updated => _count(kImportUpdated);
  int get unchanged => _count(kImportUnchanged);
}

class _RawRow {
  _RawRow(this.rowNumber, this.values);
  final int rowNumber;
  final Map<String, String> values;
}

class _Draft {
  _Draft(this.rowNumber, this.record, this.problems, this.notes);
  final int rowNumber;
  final IndividualRecord record;
  final List<String> problems;
  final List<String> notes;
}

class StudentImportService {
  StudentImportService._();

  static const String _people = 'individual_records';
  static const String _enrolments = 'individual_academic_records';
  static const int _chunk = 150;

  static const Map<String, List<String>> _aliases = {
    'id': [
      'studentid',
      'studentno',
      'studentnumber',
      'idnumber',
      'idno',
      'id',
      'schoolid',
      'personid',
    ],
    'first': ['firstname', 'fname', 'givenname', 'first', 'fn'],
    'middle': ['middlename', 'mname', 'middleinitial', 'middle', 'mi', 'mn'],
    'last': ['lastname', 'lname', 'surname', 'familyname', 'last', 'ln'],
    'suffix': ['suffix', 'extension', 'nameextension'],
    'sex': ['sex', 'gender'],
    'birth': ['birthdate', 'dateofbirth', 'birthday', 'dob', 'bdate'],
    'contact': [
      'contact',
      'contactnumber',
      'contactno',
      'mobile',
      'mobilenumber',
      'mobileno',
      'phone',
      'phonenumber',
      'cellphone',
    ],
    'email': ['email', 'emailaddress'],
    'address': ['address', 'homeaddress'],
    'institute': ['institute', 'institutecode', 'college'],
    'program': ['program', 'programcode', 'course', 'degree', 'degreeprogram'],
    'year': ['yearlevel', 'yearlvl', 'year', 'yr', 'level'],
  };

  static const List<String> _required = [
    'id',
    'first',
    'last',
    'sex',
    'program',
    'year',
  ];

  static const Map<String, String> _fieldLabels = {
    'id': 'Student ID',
    'first': 'First Name',
    'last': 'Last Name',
    'sex': 'Sex',
    'program': 'Program',
    'year': 'Year Level',
  };

  static const Map<String, String> _columnLabels = {
    'fn': 'First name',
    'mn': 'Middle name',
    'ln': 'Last name',
    'suffix': 'Suffix',
    'sex': 'Sex',
    'date_of_birth': 'Birth date',
    'contact_number': 'Contact',
    'email': 'Email',
    'address': 'Address',
  };

  static String _key(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static List<List<String>> readTable(Uint8List bytes, String fileName) {
    final lower = fileName.toLowerCase();

    // Real Excel files start with "PK" (.xlsx) or D0 CF (.xls).
    final isExcelBinary = bytes.length > 1 &&
        ((bytes[0] == 0x50 && bytes[1] == 0x4B) ||
            (bytes[0] == 0xD0 && bytes[1] == 0xCF));

    if (lower.endsWith('.csv') || lower.endsWith('.txt')) {
      return _readCsv(bytes);
    }
    if (lower.endsWith('.xlsx') || lower.endsWith('.xls')) {
      // Some ".xls" files from schools are really text/CSV in disguise.
      return isExcelBinary ? _readXlsx(bytes) : _readCsv(bytes);
    }
    return isExcelBinary ? _readXlsx(bytes) : _readCsv(bytes);
  }

  static List<List<String>> _readXlsx(Uint8List bytes) {
    try {
      final book = xl.Excel.decodeBytes(bytes);
      for (final name in book.tables.keys) {
        final sheet = book.tables[name];
        if (sheet == null) continue;
        final rows = <List<String>>[
          for (final r in sheet.rows) [for (final c in r) _cellText(c)],
        ];
        if (rows.any((r) => r.any((c) => c.isNotEmpty))) return rows;
      }
      return const [];
    } catch (e) {
      throw ImportFileException(
          'Could not read that Excel file ($e). If the file opens fine in '
          'Excel, save it as CSV and import the CSV instead.');
    }
  }

  static String _cellText(xl.Data? d) {
    final dynamic v = d?.value;
    if (v == null) return '';
    if (v is xl.IntCellValue) return '${v.value}';
    if (v is xl.DoubleCellValue) {
      final n = v.value;
      return n == n.truncateToDouble() ? '${n.toInt()}' : '$n';
    }
    if (v is xl.DateCellValue) return _iso(v.year, v.month, v.day);
    if (v is xl.DateTimeCellValue) return _iso(v.year, v.month, v.day);
    if (v is xl.TextCellValue) {
      final dynamic t = v.value;
      final text = _spanText(t).trim();
      return text.isNotEmpty ? text : '$v'.trim();
    }
    return '$v'.trim();
  }

  static String _spanText(dynamic t) {
    if (t == null) return '';
    if (t is String) return t;
    final buf = StringBuffer();
    try {
      final dynamic own = t.text;
      if (own is String) buf.write(own);
    } catch (_) {}
    try {
      final dynamic kids = t.children;
      if (kids is Iterable) {
        for (final k in kids) {
          buf.write(_spanText(k));
        }
      }
    } catch (_) {}
    return buf.toString();
  }

  static List<List<String>> _readCsv(Uint8List bytes) {
    var text = utf8.decode(bytes, allowMalformed: true);
    if (text.startsWith('\uFEFF')) text = text.substring(1);

    final firstLine = text.split('\n').first;
    var delim = ',';
    if (firstLine.split(';').length > firstLine.split(',').length) {
      delim = ';';
    } else if (!firstLine.contains(',') && firstLine.contains('\t')) {
      delim = '\t';
    }

    final rows = <List<String>>[];
    var row = <String>[];
    final cell = StringBuffer();
    var quoted = false;
    for (var i = 0; i < text.length; i++) {
      final ch = text[i];
      if (quoted) {
        if (ch == '"') {
          if (i + 1 < text.length && text[i + 1] == '"') {
            cell.write('"');
            i++;
          } else {
            quoted = false;
          }
        } else {
          cell.write(ch);
        }
      } else if (ch == '"') {
        quoted = true;
      } else if (ch == delim) {
        row.add(cell.toString());
        cell.clear();
      } else if (ch == '\n' || ch == '\r') {
        if (ch == '\r' && i + 1 < text.length && text[i + 1] == '\n') i++;
        row.add(cell.toString());
        cell.clear();
        rows.add(row);
        row = <String>[];
      } else {
        cell.write(ch);
      }
    }
    if (cell.isNotEmpty || row.isNotEmpty) {
      row.add(cell.toString());
      rows.add(row);
    }
    return [
      for (final r in rows) [for (final c in r) c.trim()],
    ];
  }

  static Map<String, int> _mapHeader(List<String> row) {
    final out = <String, int>{};
    for (var c = 0; c < row.length; c++) {
      final k = _key(row[c]);
      if (k.isEmpty) continue;

      final tries = <String>[
        k,
        if (k.startsWith('stud') && k.length > 4) k.substring(4),
        if (k.startsWith('enr') && k.length > 3) k.substring(3),
      ];
      var matched = false;
      for (final t in tries) {
        for (final e in _aliases.entries) {
          if (e.value.contains(t)) {
            out.putIfAbsent(e.key, () => c);
            matched = true;
            break;
          }
        }
        if (matched) break;
      }
    }
    return out;
  }

  static List<_RawRow> _extract(List<List<String>> table) {
    var headerAt = -1;
    var cols = <String, int>{};
    for (var i = 0; i < table.length && i < 10; i++) {
      final m = _mapHeader(table[i]);
      if (m.length >= 3) {
        headerAt = i;
        cols = m;
        break;
      }
    }
    if (headerAt < 0) {
      throw const ImportFileException(
          'Could not find the column headings. The first row should name the '
          'columns: Student ID, First Name, Last Name, Sex, Program, Year Level.');
    }
    final missing = [
      for (final f in _required)
        if (!cols.containsKey(f)) _fieldLabels[f]!,
    ];
    if (missing.isNotEmpty) {
      throw ImportFileException(
          'The file is missing required column(s): ${missing.join(', ')}.');
    }

    final out = <_RawRow>[];
    for (var i = headerAt + 1; i < table.length; i++) {
      final row = table[i];
      final values = <String, String>{
        for (final e in cols.entries)
          e.key: e.value < row.length ? row[e.value].trim() : '',
      };
      if (values.values.every((v) => v.isEmpty)) continue;
      out.add(_RawRow(i + 1, values));
    }
    return out;
  }

  static String _norm(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static String? _normYear(String raw) {
    final t = raw.toLowerCase().trim();
    if (t.isEmpty) return null;
    const words = {
      'first': 1,
      'second': 2,
      'third': 3,
      'fourth': 4,
      'fifth': 5
    };
    int? n;
    for (final e in words.entries) {
      if (t.contains(e.key)) n = e.value;
    }
    n ??= int.tryParse(RegExp(r'\d+').firstMatch(t)?.group(0) ?? '');
    if (n == null || n < 1 || n > 5) return null;
    const suffix = {1: 'st', 2: 'nd', 3: 'rd', 4: 'th', 5: 'th'};
    return '$n${suffix[n]} Year';
  }

  static String _cleanContact(String s) {
    var d = s.replaceAll(RegExp(r'\D'), '');
    if (d.startsWith('63') && d.length == 12) d = '0${d.substring(2)}';

    if (d.length == 10 && d.startsWith('9')) d = '0$d';
    return d.length > 11 ? d.substring(0, 11) : d;
  }

  static DateTime? _parseDate(String s) {
    final t = s.trim();
    if (t.isEmpty) return null;
    DateTime? ok(int y, int m, int d) {
      final dt = DateTime(y, m, d);
      if (dt.year != y || dt.month != m || dt.day != d) return null;
      if (y < 1900 || dt.isAfter(DateTime.now())) return null;
      return dt;
    }

    final iso = RegExp(r'^(\d{4})-(\d{1,2})-(\d{1,2})').firstMatch(t);
    if (iso != null) {
      return ok(int.parse(iso.group(1)!), int.parse(iso.group(2)!),
          int.parse(iso.group(3)!));
    }
    for (final f in const [
      'M/d/yyyy',
      'M/d/yy',
      'MMM d, yyyy',
      'MMMM d, yyyy',
      'd-MMM-yyyy',
      'd MMM yyyy',
    ]) {
      try {
        final p = DateFormat(f).parseStrict(t);
        final r = ok(p.year, p.month, p.day);
        if (r != null) return r;
      } catch (_) {}
    }
    return null;
  }

  static String _iso(int y, int m, int d) => '${y.toString().padLeft(4, '0')}-'
      '${m.toString().padLeft(2, '0')}-'
      '${d.toString().padLeft(2, '0')}';

  static _Draft _draft(
    _RawRow raw,
    AcademicPeriodOption period,
    String status,
  ) {
    final v = raw.values;
    final problems = <String>[];
    final notes = <String>[];

    var id = (v['id'] ?? '').replaceAll(RegExp(r'\s'), '');
    if (RegExp(r'^\d+\.0+$').hasMatch(id)) id = id.split('.').first;
    if (id.isEmpty) {
      problems.add('Student ID is missing');
    } else if (!RegExp(r'^\d{6}$').hasMatch(id)) {
      problems.add('Student ID must be exactly 6 digits');
    }

    final first = (v['first'] ?? '').trim();
    final last = (v['last'] ?? '').trim();
    if (first.isEmpty) problems.add('First name is missing');
    if (last.isEmpty) problems.add('Last name is missing');

    final sexRaw = (v['sex'] ?? '').trim().toLowerCase();
    var sex = '';
    if (sexRaw.isEmpty) {
      problems.add('Sex is missing');
    } else if (sexRaw == 'm' || sexRaw == 'male') {
      sex = 'Male';
    } else if (sexRaw == 'f' || sexRaw == 'female') {
      sex = 'Female';
    } else {
      problems.add('Sex must be Male or Female');
    }

    final yearRaw = (v['year'] ?? '').trim();
    String year = '';
    if (yearRaw.isEmpty) {
      problems.add('Year level is missing');
    } else {
      final y = _normYear(yearRaw);
      if (y == null) {
        problems.add('Year level "$yearRaw" is not recognised');
      } else {
        year = y;
      }
    }

    String? instituteId;
    String instituteCode = '';
    String? programId;
    String programCode = '';
    final progText = (v['program'] ?? '').trim();
    final instText = (v['institute'] ?? '').trim();
    if (progText.isEmpty) {
      problems.add('Program is missing');
    } else {
      InstituteOption? inst;
      if (instText.isNotEmpty) {
        final q = _norm(instText);
        for (final i in ReferenceCatalog.institutes) {
          if (_norm(i.code) == q || _norm(i.name) == q) {
            inst = i;
            break;
          }
        }
      }
      final q = _norm(progText);
      final matches = [
        for (final p in ReferenceCatalog.programs)
          if (_norm(p.code) == q || _norm(p.name) == q) p,
      ];
      if (matches.isEmpty) {
        problems.add('Program "$progText" is not in the program list');
      } else if (inst != null) {
        final inInst = matches.where((p) => p.instituteId == inst!.id).toList();
        if (inInst.isEmpty) {
          final owner =
              ReferenceCatalog.instituteCodeOf(matches.first.instituteId);
          problems.add(
              'Program ${matches.first.code} belongs to $owner, not ${inst.code}');
        } else {
          programId = inInst.first.id;
          programCode = inInst.first.code;
          instituteId = inst.id;
          instituteCode = inst.code;
        }
      } else {
        if (matches.length > 1) {
          problems.add('Program "$progText" is offered by more than one '
              'institute — add an Institute column');
        } else {
          programId = matches.first.id;
          programCode = matches.first.code;
          instituteId = matches.first.instituteId;
          instituteCode = ReferenceCatalog.instituteCodeOf(instituteId);
          if (instText.isNotEmpty) {
            notes.add('Institute "$instText" not found, used $instituteCode '
                'from the program');
          }
        }
      }
    }

    final birth = _parseDate(v['birth'] ?? '');
    final contact = _cleanContact(v['contact'] ?? '');
    var email = (v['email'] ?? '').trim();
    if (email.isNotEmpty &&
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      notes.add('Email ignored (not a valid address)');
      email = '';
    }

    final record = IndividualRecord(
      id: id,
      category: 'Student',
      firstName: first,
      middleName: (v['middle'] ?? '').trim(),
      lastName: last,
      suffix: (v['suffix'] ?? '').trim(),
      sex: sex,
      birthDate: birth,
      contact: contact,
      email: email,
      address: (v['address'] ?? '').trim(),
      academicPeriodId: period.id,
      academicYear: period.acadYear,
      semester: period.semester,
      instituteId: instituteId,
      institute: instituteCode,
      programId: programId,
      program: programCode,
      yearLevel: year,
      status: status,
    );
    return _Draft(raw.rowNumber, record, problems, notes);
  }

  static Future<StudentImportPlan> analyze({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final raws = _extract(readTable(bytes, fileName));
    if (raws.isEmpty) {
      throw const ImportFileException(
          'The file has column headings but no student rows.');
    }

    try {
      await ReferenceCatalog.load(force: true);
    } catch (_) {}
    if (!ReferenceCatalog.isLoaded) {
      throw const ImportFileException(
          'The school lists (programs, institutes, terms) could not be loaded. '
          'Check the connection, sign in again and retry.');
    }
    final period = ReferenceCatalog.activePeriod;
    if (period == null || period.id.isEmpty) {
      throw const ImportFileException(
          'There is no current school year & semester. Add one first.');
    }

    final status = IndividualRecordService.statusForTerm(period.id);
    final drafts = [for (final r in raws) _draft(r, period, status)];

    final firstRow = <String, int>{};
    for (final d in drafts) {
      if (d.problems.isNotEmpty) continue;
      final prev = firstRow[d.record.id];
      if (prev != null) {
        d.problems.add('Duplicate of row $prev in this file');
      } else {
        firstRow[d.record.id] = d.rowNumber;
      }
    }
    final ids = firstRow.keys.toList();

    final people = <String, Map<String, dynamic>>{};
    for (final chunk in _chunks(ids)) {
      final rows = await supabaseClient
          .from(_people)
          .select('person_id, person_type, fn, mn, ln, suffix, sex, '
              'date_of_birth, contact_number, email, address')
          .inFilter('person_id', chunk);
      for (final r in rows) {
        final m = Map<String, dynamic>.from(r);
        people['${m['person_id']}'] = m;
      }
    }
    final enrolled = await _enrolledIds(period.id, ids);

    final out = <StudentImportRow>[];
    for (final d in drafts) {
      final rec = d.record;
      StudentImportRow row(String s, String note,
              [Map<String, dynamic> changes = const <String, dynamic>{}]) =>
          StudentImportRow(
            rowNumber: d.rowNumber,
            record: rec,
            status: s,
            note: note,
            personChanges: changes,
          );
      final extra = d.notes.isEmpty ? '' : ' · ${d.notes.join('; ')}';

      if (d.problems.isNotEmpty) {
        out.add(row(kImportInvalid, d.problems.join('; ')));
        continue;
      }
      if (enrolled.contains(rec.id)) {
        out.add(row(
            kImportExists, 'Already has a record in ${period.label}$extra'));
        continue;
      }
      final p = people[rec.id];
      if (p == null) {
        out.add(row(kImportNew, 'New student$extra'));
        continue;
      }
      final type = '${p['person_type'] ?? ''}';
      if (type.isNotEmpty && type.toLowerCase() != 'student') {
        out.add(row(kImportInvalid, 'This ID already belongs to a $type'));
        continue;
      }
      final changes = _changes(rec, p);
      if (changes.isEmpty) {
        out.add(row(kImportUnchanged,
            'Personal info is the same · term record will be added$extra'));
      } else {
        final labels = [for (final c in changes.keys) _columnLabels[c] ?? c];
        out.add(row(
            kImportUpdated, 'Changed: ${labels.join(', ')}$extra', changes));
      }
    }

    return StudentImportPlan(
      fileName: fileName,
      rows: out,
      academicPeriodId: period.id,
      termLabel: period.label,
    );
  }

  static Map<String, dynamic> _changes(
    IndividualRecord r,
    Map<String, dynamic> p,
  ) {
    final out = <String, dynamic>{};
    void text(String col, String incoming) {
      final inc = incoming.trim();
      if (inc.isEmpty) return;
      final stored = '${p[col] ?? ''}'.trim();
      if (stored.toLowerCase() != inc.toLowerCase()) out[col] = inc;
    }

    text('fn', r.firstName);
    text('mn', r.middleName);
    text('ln', r.lastName);
    text('suffix', r.suffix);
    text('sex', r.sex);
    text('contact_number', r.contact);
    text('email', r.email);
    text('address', r.address);
    final b = r.birthDate;
    if (b != null) {
      final iso = _iso(b.year, b.month, b.day);
      if ('${p['date_of_birth'] ?? ''}' != iso) out['date_of_birth'] = iso;
    }
    return out;
  }

  static Future<StudentImportReport> save(StudentImportPlan plan) async {
    final account = AccountService.currentUserId.trim();
    if (account.isEmpty) {
      throw const ImportFileException(
          'There is no signed-in account to record as the person who imported '
          'these students. Sign in again — nothing was written.');
    }

    try {
      await ReferenceCatalog.refreshPeriods();
    } catch (_) {}
    if (ReferenceCatalog.activePeriod?.id != plan.academicPeriodId) {
      throw const ImportFileException(
          'The current school year & semester changed after this file was '
          'analyzed. Close this window and import again — nothing was written.');
    }

    final candidates = [
      for (final r in plan.rows)
        if (r.willSave) r,
    ];

    final raced = await _enrolledIds(
        plan.academicPeriodId, [for (final r in candidates) r.record.id]);
    final alreadyExisting = <StudentImportRow>[
      for (final r in plan.rows)
        if (r.status == kImportExists ||
            (r.willSave && raced.contains(r.record.id)))
          r,
    ];
    final toSave = [
      for (final r in candidates)
        if (!raced.contains(r.record.id)) r,
    ];

    for (final r in toSave) {
      r.record.createdBy = account;
    }

    final failed = <ImportFailure>[];
    final ready = <StudentImportRow>[];

    final newRows = [
      for (final r in toSave)
        if (r.status == kImportNew) r,
    ];
    final newErrors = await _insertMany(
        _people, [for (final r in newRows) r.record.personPayload()]);
    for (var i = 0; i < newRows.length; i++) {
      final err = newErrors[i];
      if (err != null) {
        failed.add(ImportFailure(newRows[i], _short(err, newRows[i])));
      } else {
        ready.add(newRows[i]);
      }
    }

    for (final r in toSave.where((r) => r.status == kImportUpdated)) {
      try {
        final touched = await supabaseClient
            .from(_people)
            .update(r.personChanges)
            .eq('person_id', r.record.id)
            .select('person_id');
        if (touched.isEmpty) {
          failed.add(ImportFailure(
              r,
              'Could not update the personal info — this account cannot see '
              'that person record.'));
        } else {
          ready.add(r);
        }
      } catch (e) {
        failed.add(ImportFailure(r, _short(e, r)));
      }
    }

    ready.addAll(toSave.where((r) => r.status == kImportUnchanged));

    final acErrors = await _insertMany(_enrolments, [
      for (final r in ready)
        {...r.record.academicPayload(), 'person_id': r.record.id},
    ]);
    final saved = <StudentImportRow>[];
    for (var i = 0; i < ready.length; i++) {
      final r = ready[i];
      final err = acErrors[i];
      if (err == null) {
        saved.add(r);
        continue;
      }
      var tail = '';
      if (r.status == kImportNew) {
        try {
          await supabaseClient
              .from(_people)
              .delete()
              .eq('person_id', r.record.id);
          tail = ' The new person record was removed again.';
        } catch (_) {
          tail = ' The person record was kept.';
        }
      } else if (r.status == kImportUpdated) {
        tail = ' The personal info was updated, but the term record was not.';
      }
      failed.add(ImportFailure(r, '${_short(err, r)}$tail'));
    }

    final retired = await _retireEarlier([
      for (final r in saved)
        if (r.status != kImportNew) r.record.id,
    ], plan.academicPeriodId);

    if (saved.isNotEmpty) DataTracker.bump();

    return StudentImportReport(
      termLabel: plan.termLabel,
      saved: saved,
      alreadyExisting: alreadyExisting,
      invalid: [
        for (final r in plan.rows)
          if (r.status == kImportInvalid) r,
      ],
      failed: failed,
      retired: retired,
    );
  }

  static Iterable<List<String>> _chunks(List<String> ids) sync* {
    for (var i = 0; i < ids.length; i += _chunk) {
      final end = i + _chunk < ids.length ? i + _chunk : ids.length;
      yield ids.sublist(i, end);
    }
  }

  static Future<Set<String>> _enrolledIds(
    String periodId,
    List<String> ids,
  ) async {
    final out = <String>{};
    for (final chunk in _chunks(ids)) {
      final rows = await supabaseClient
          .from(_enrolments)
          .select('person_id')
          .eq('academic_period_id', periodId)
          .inFilter('person_id', chunk);
      for (final r in rows) {
        out.add('${r['person_id']}');
      }
    }
    return out;
  }

  static Future<Map<int, Object>> _insertMany(
    String table,
    List<Map<String, dynamic>> rows,
  ) async {
    final failed = <int, Object>{};
    if (rows.isEmpty) return failed;
    try {
      await supabaseClient.from(table).insert(rows);
      return failed;
    } catch (_) {}
    for (var i = 0; i < rows.length; i++) {
      try {
        await supabaseClient.from(table).insert(rows[i]);
      } catch (e) {
        failed[i] = e;
      }
    }
    return failed;
  }

  static Future<int> _retireEarlier(List<String> ids, String periodId) async {
    var n = 0;
    for (final chunk in _chunks(ids)) {
      try {
        final rows = await supabaseClient
            .from(_enrolments)
            .update({'status': kRecordStatusInactive})
            .inFilter('person_id', chunk)
            .neq('academic_period_id', periodId)
            .eq('status', kRecordStatusActive)
            .select('academic_record_id');
        n += rows.length;
      } catch (e) {
        debugPrint('StudentImportService: could not retire earlier terms — $e');
      }
    }
    return n;
  }

  static String _short(Object e, StudentImportRow r) {
    final text = IndividualRecordService.describeWriteFailure(
      e,
      category: 'Student',
      recordNo: r.record.id,
    );
    return text.replaceAll(RegExp(r'\s+'), ' ').trim();
  }
}
