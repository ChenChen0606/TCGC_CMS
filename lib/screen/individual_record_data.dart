// ─────────────────────────────────────────────────────────────────────────────
//  individual_record_data.dart
//  The `IndividualRecord` model plus the import-dialog row/result models.
//
//  Split out of individual_record_screen.dart so the Supabase layer
//  (services/individual_record_service.dart) can import the model without
//  pulling in a 3 000-line widget file — the same reason patient_data.dart is
//  its own file.
//
//  PERSISTENCE — TWO TABLES, ONE PERSON
//  A person is not a row. They are a row:
//
//    public.individual_records            one row per human being, forever.
//      person_id (pk AND the printed number), person_type, fn, mn, ln, suffix,
//      sex, date_of_birth, contact_number, email, address, userid,
//      created_by, created_at.
//      Nothing here changes when they shift year, graduate or change post,
//      because none of that is about who they are.
//
//    public.individual_academic_records   one row per person *per academic
//      period*.
//      academic_record_id, person_id, academic_period_id, institute_id,
//      program_id, year_level, department_office_id, position_id, status
//      ('Active' | 'Inactive' | 'Archived'), userid, created_by, created_at.
//
//  So the model is one object with two halves, stitched back together on read
//  and split in two on write - [fromSupabase] takes the joined row,
//  [personPayload] and [academicPayload] are what the two INSERTs receive.
//
//  THE NAMES ABOVE ARE THE LIVE ONES
//  There is no `id`, no `record_no`, no `category`, no `first_name` and no
//  `status` on `individual_records`. Writing and reading those longer spellings
//  is what made every roster read fail with
//  "column individual_records_1.id does not exist".
//
//  `person_type` HOLDS EXACTLY 'Student' / 'Faculty' / 'Staff'
//  `chk_person_type` is
//    CHECK (person_type = ANY (ARRAY['Student','Faculty','Staff']))
//  — capitalised and case-sensitive — so those three spellings are the only
//  values the column can ever hold, and anything else is rejected by the
//  database rather than merely failing to match. [canonicalCategory] (read side)
//  and [personTypeForStorage] (write and filter side) are the only two places
//  that translate, and every call site goes through them.
//
//  Lower-casing the value broke this screen twice over, which is why it is worth
//  stating the constraint rather than the habit: every roster query filtered on
//  `person_type = 'faculty'`, a value no row could hold, so the Faculty and
//  Staff tabs stayed empty while the records sat in the database; and every
//  INSERT sent `faculty`, which `chk_person_type` refused, so no category could
//  be saved at all. The CHECK constraint is the authority — do not "normalise"
//  this column again.
//
//  THREE THINGS THE SCHEMA HAS NO COLUMN FOR
//    * person-level status - so "archived" is defined entirely by the
//      enrolments' own status, which is what
//      IndividualRecordService.archivePerson writes,
//    * status_reason / status_changed_by / status_changed_at - so a removal has
//      no recorded reason and the UI does not offer to collect one,
//    * updated_at / updated_by - so created_at is the only timestamp there is.
//      `created_by` IS written, from the signed-in account, on insert.
// ─────────────────────────────────────────────────────────────────────────────

// Prefixed: this file defines `IndividualRecord.isCurrentTerm`, so the shared
// `isCurrentTerm` function of the same name needs a prefix to be callable here.
import '../core/patient_directory.dart' as terms;

// ── STATUSES ──────────────────────────────────────────────────────────────────

/// The statuses of `individual_records.status` — the person themselves.
///
/// 'Active' is on the roster. 'Archived' is set by `archive_person` and is
/// deliberate: an administrator has decided this person should leave the
/// everyday roster but the history stays readable. There is no 'Inactive' on
/// this table because a person who is merely off the roster for a term has not
/// changed — they still have a row, just an Inactive academic one.
const String kPersonStatusActive = 'Active';
const String kPersonStatusArchived = 'Archived';

/// The statuses of `individual_academic_records.status` — the person's record
/// for one academic period.
///
/// 'Active' is the only one that appears in the roster or in the Clinic Visit
/// lookup. 'Inactive' is a superseded enrolment that is kept for history.
/// 'Archived' is set when the person itself is archived, so a term cannot stay
/// Active after the person has been filed away.
const String kRecordStatusActive = 'Active';
const String kRecordStatusInactive = 'Inactive';
const String kRecordStatusArchived = 'Archived';

/// The values offered in the form's "Status" dropdown.
const List<String> kRecordStatuses = [
  kRecordStatusActive,
  kRecordStatusInactive,
];

/// True while [status] keeps the person on the roster.
///
/// The check is by membership in [kRecordStatuses] rather than `== 'Active'` so
/// a lowercase value from a hand-edited import cannot quietly look Active.
bool isActiveStatus(String status) => status == kRecordStatusActive;

// ── CATEGORY SPELLING ─────────────────────────────────────────────────────────

/// The three categories, spelled the way the whole app spells them.
///
/// Every tab, dropdown, count and `==` comparison in the app uses these exact
/// strings, so a row is only ever found by the category it was stored under if
/// both sides agree on the spelling.
const List<String> kPersonCategories = ['Student', 'Faculty', 'Staff'];

/// Maps whatever `individual_records.person_type` actually holds onto one of
/// [kPersonCategories].
///
/// WHY THIS EXISTS — the bug it fixes
/// `person_type` is a `text` column with a CHECK constraint that allows exactly
/// three values: `'Student'`, `'Faculty'`, `'Staff'`. The app filters the roster
/// with an exact equality on the category the reader picked, so the two sides
/// have to agree on spelling or the tab is empty while the rows are in the
/// database. Doing that comparison by hand in every filter is how the tab and
/// the counts drifted apart from the table underneath.
///
/// Matching is by normalised form rather than by `toLowerCase()` equality so a
/// `Student`, `student` or `STUDENT` read out of the database all land on the
/// same label whichever way round they were stored. This is the READ side only
/// and is deliberately forgiving: the value came from a column that cannot hold
/// anything else, so being lenient costs nothing and survives a row written by
/// hand.
///
/// An unrecognised value is passed through trimmed rather than forced into
/// 'Student': inventing a category would file somebody under the wrong tab, and a
/// visibly-wrong value that a human can correct is better than a plausible one.
String canonicalCategory(Object? value) {
  final raw = value?.toString().trim() ?? '';
  if (raw.isEmpty) return kPersonCategories.first;
  final q = raw.toLowerCase();
  for (final c in kPersonCategories) {
    if (c.toLowerCase() == q) return c;
  }
  return raw;
}

/// The spelling written to — and filtered on — `individual_records.person_type`.
///
/// The exact spelling `chk_person_type` enforces: `Student` / `Faculty` /
/// `Staff`. It has to match that list character for character, and it has to be
/// the *capitalised* form, because
///
///   CHECK (person_type = ANY (ARRAY['Student','Faculty','Staff']))
///
/// is a case-sensitive comparison. Lower-casing here — which this function used
/// to do — is not a harmless style choice, it is a value the database refuses:
/// every roster filter built from it matched no row at all (empty Faculty and
/// Staff tabs, and a duplicate-number check that believed a taken number was
/// free) and every INSERT raised `chk_person_type`, so nothing could be saved
/// for any category.
///
/// It deliberately does NOT upper-case, title-case or otherwise "tidy" the
/// value: the CHECK constraint is the authority on the spelling, and the live
/// rows already hold it.
String personTypeForStorage(String category) => canonicalCategory(category);

class IndividualRecord {
  // ── IDENTITY — `individual_records` ────────────────────────────────────────
  String? uuid; // `individual_records.id` — null until the row is persisted
  String id; // person_id: student number, or F/S + six digits → record_no
  String category; // 'Student' | 'Faculty' | 'Staff'

  // Personal
  String firstName;
  String middleName;
  String lastName;
  String suffix; // Jr. / III / …
  String sex;
  DateTime? birthDate;
  String contact;
  String email;
  String address;

  /// 'Active' | 'Archived' — the person themselves.
  String personStatus;

  // ── ACADEMIC / EMPLOYMENT — `individual_academic_records` ──────────────────
  //
  // The row is optional: a person can exist before they are enrolled or
  // appointed to anything, which is why `academicPeriodId` may be null.

  /// `individual_academic_records.id` — null until that row is persisted.
  /// Distinct from [uuid], which identifies the *person*.
  String? academicRecordId;

  /// `academic_period_id` — which term this enrolment belongs to.
  String? academicPeriodId;

  /// Denormalised from the joined `academic_periods` so the table can print
  /// "2025-2026 · 2nd Semester" without a second lookup. Never written by the
  /// client: [academicPayload] sends the period *id*, and Postgres joins.
  String academicYear;
  String semester;

  // Student AND Faculty carry an institute. Staff do not — they are filed under
  // an office instead, and the CHECK constraints enforce that split.
  String? instituteId;
  String institute; // code, for display

  String? programId; // Student only
  String program; // Student only, for display

  /// Free text, constrained by `chk_year_level` to 1st to 5th Year. Not a
  /// foreign key: the year levels are a fixed scale in the CHECK constraint
  /// rather than a lookup table, so there is no id to carry.
  String yearLevel; // Student only

  String? departmentOfficeId; // Staff only
  String department; // Staff only, for display

  String? positionId; // Faculty and Staff
  String position; // Faculty and Staff

  /// 'Active' | 'Inactive' | 'Archived' — this enrolment's status, and the only
  /// status column in this schema.
  ///
  /// There is no status_reason / status_changed_at / status_changed_by on either
  /// table, so there is nothing else to record about a change and no audit of who
  /// made it beyond created_by.
  String status;

  // Audit. `created_by` is the `useraccount.user_id` of the account that filed
  // this person, stamped from the signed-in session on INSERT and never rewritten
  // afterwards. `userid` is the same thing in the older spelling; the client does
  // not read it, it just keeps the two columns on a table that carries both.
  DateTime? createdAt;
  String? createdBy; // useraccount.user_id (uuid)

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

  /// True while the person is part of the roster.
  ///
  /// Both halves have to agree. An Active enrolment under a person who has been
  /// archived is not a person on the roster — that combination is exactly what
  /// `archive_person` prevents from happening, and this is the belt to its
  /// braces.
  bool get isActive =>
      isActiveStatus(status) && personStatus == kPersonStatusActive;

  /// True once this person has been filed away by an administrator. Archived
  /// rows are hidden from the roster and shown in the Archive, never deleted.
  bool get isArchived =>
      personStatus == kPersonStatusArchived || status == kRecordStatusArchived;

  String get fullName {
    final parts = [firstName, middleName, lastName, suffix]
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    return parts.isEmpty ? '—' : parts.join(' ');
  }

  /// What the table shows in the PROGRAM column: a student's degree program, a
  /// faculty member's institute, a staff member's office.
  String get programLabel {
    if (isStudent) {
      return program.isEmpty ? '—' : program;
    }
    if (category == 'Faculty') return institute.isEmpty ? '—' : institute;
    return department.isEmpty ? '—' : department;
  }

  String get dbKey => '$personKey|$academicPeriodId';

  /// Just the person, without the term. This is what identifies a human being —
  /// used when asking "does this person already have a record for this term?"
  /// and "which earlier terms must be retired when the new roster arrives?".
  String get personKey => '$category|$id';

  /// True while this enrolment is filed under the term the clinic is running
  /// now.
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

  /// Human-readable list of the fields that differ between this record and
  /// [other]. Academic year / semester are intentionally excluded: the import
  /// applies them to the whole batch, so they never count as "a change".
  /// Status is excluded for the same reason — it is not part of the roster
  /// file, it is set on the record itself.
  List<String> diffLabels(IndividualRecord other) {
    final out = <String>[];
    void cmp(String label, Object? a, Object? b) {
      if ('$a' != '$b') out.add(label);
    }

    cmp('First name', firstName, other.firstName);
    cmp('Middle name', middleName, other.middleName);
    cmp('Last name', lastName, other.lastName);
    cmp('Suffix', suffix, other.suffix);
    cmp('Sex', sex, other.sex);
    cmp('Birth date', birthDate?.toIso8601String(),
        other.birthDate?.toIso8601String());
    cmp('Contact', contact, other.contact);
    cmp('Email', email, other.email);
    cmp('Address', address, other.address);
    cmp('Institute', institute, other.institute);
    cmp('Program', program, other.program);
    cmp('Year level', yearLevel, other.yearLevel);
    cmp('Department/Office', department, other.department);
    cmp('Position', position, other.position);
    return out;
  }

  /// Copy the incoming values onto this (already stored) record. `uuid`,
  /// status and the whole audit block are left alone: they are not part of an
  /// enrolment file and are owned by the database.
  ///
  /// The term is not copied either, and that is deliberate. Which term an
  /// enrolment belongs to is half of its identity — `dbKey` and the database
  /// both key on it — so moving a record from one term to another is not an
  /// edit, it is two writes: insert a row under the new term and deactivate the
  /// old one. `IndividualRecordService.retireEarlierPeriods` plus `create` do
  /// that, and letting a file edit the term here would either silently re-file
  /// someone's history or trip the unique index on a row nobody intended to
  /// touch.
  ///
  /// The reference ids are copied but only when the incoming row carries one, so
  /// an import that was written against a spreadsheet with program *names* still
  /// updates the personal details of a row whose ids it cannot resolve.
  void applyFrom(IndividualRecord incoming) {
    firstName = incoming.firstName;
    middleName = incoming.middleName;
    lastName = incoming.lastName;
    suffix = incoming.suffix;
    sex = incoming.sex;
    birthDate = incoming.birthDate;
    contact = incoming.contact;
    email = incoming.email;
    address = incoming.address;
    institute = incoming.institute;
    program = incoming.program;
    yearLevel = incoming.yearLevel;
    department = incoming.department;
    position = incoming.position;
    if (incoming.instituteId != null) instituteId = incoming.instituteId;
    if (incoming.programId != null) programId = incoming.programId;
    if (incoming.departmentOfficeId != null) {
      departmentOfficeId = incoming.departmentOfficeId;
    }
    if (incoming.positionId != null) positionId = incoming.positionId;
  }

  // ── SERIALIZATION ────────────────────────────────────────────────────────

  /// Builds a record from a joined row.
  ///
  /// Two shapes are accepted, because two different queries produce them and
  /// both have to build the same object:
  ///
  ///   * an **enrolment row** — `individual_academic_records` as the primary
  ///     table with `individual_records` embedded as `person` and the reference
  ///     tables embedded alongside. The academic columns are the row's own, at
  ///     the top level. This is what [IndividualRecordService.fetchAll] returns
  ///     and is the preferred shape, because filtering on a period or a status is
  ///     then a filter on the table being queried.
  ///
  ///   * a **person row** with the academic row embedded as `academic` — useful
  ///     when the question is about a person rather than about one of their
  ///     enrolments, such as the Archive.
  ///
  /// The academic half is optional in both. When it is absent the record still
  /// carries the person: [status] falls back to the person's own status so the
  /// row is never blank, and [academicYear] / [semester] stay empty because there
  /// is no period to name.
  factory IndividualRecord.fromSupabase(Map<String, dynamic> m) {
    final embeddedPerson = m['person'];
    final person = embeddedPerson is Map<String, dynamic> ? embeddedPerson : m;
    // If the person was embedded, the rest of the row IS the academic half.
    // Otherwise look for a nested academic row, and fall back to the row itself
    // for the audit columns.
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
      // `individual_records.person_id` IS the primary key and it IS the number
      // printed on the card — there is no separate uuid and no separate
      // record_no column. So the one value answers both [uuid] and [id]: the
      // same string addresses the row and identifies the person. Keeping both
      // fields (rather than collapsing them) means every call site that already
      // thinks in terms of "the uuid" keeps working.
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
      // There is no status column on `individual_records`, so there is nothing to
      // read. Archived is therefore derived from the enrolment: a person counts
      // as archived only when their row for this term is Archived. Roster
      // membership is decided entirely by `individual_academic_records.status`,
      // which is what the period-filtered queries already filter on.
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

  /// Payload for the `individual_records` INSERT/UPDATE — the identity half.
  ///
  /// Column names follow the live table exactly: the person number lives in
  /// `person_id` (the primary key), the category in `person_type`, and the name
  /// in the abbreviated `fn` / `mn` / `ln` this schema uses.
  ///
  /// `person_id` goes out on an INSERT and is deliberately left OUT of an
  /// UPDATE — it is the key the update is addressed by, and re-sending it would
  /// try to move the row rather than change it.
  ///
  /// `person_type` goes out through [personTypeForStorage], so the app writes the
  /// lower-case spelling the existing rows already carry. Writing `Faculty` here
  /// while the column holds `faculty` would produce a fourth category that no tab
  /// matches and no count sees.
  ///
  /// `created_by` / `userid` name the account that filed the record and go out on
  /// an INSERT only. They are the same column in two spellings on this table, both
  /// FKs to `useraccount.user_id`, and they are what makes "who saved this" answerable
  /// in the database instead of only on screen. An UPDATE leaves them alone — the
  /// question "who created this person" must not change because somebody corrected
  /// a typo in their address.
  ///
  /// `email` and `sex` go out as NULL when they are blank, and that is a
  /// correctness requirement rather than tidiness. Two partial unique indexes and
  /// one CHECK constraint are waiting on these two columns:
  ///
  ///   uq_individual_email   UNIQUE (lower(trim(email))) WHERE email IS NOT NULL
  ///   chk_sex               CHECK (sex IS NULL OR sex = ANY ('Male','Female'))
  ///
  /// An empty string is *not* null, so sending `email: ''` stored a real value
  /// that every later record with a blank address duplicated — and the save that
  /// broke was the *second* one, on an unrelated person, which is not a bug
  /// anybody could connect back to an empty field. Same for `sex`: `''` is
  /// neither NULL nor 'Male'/'Female', so it was refused outright. Writing NULL
  /// means "not on file", which is what a blank box actually means, and both
  /// constraints then behave as written.
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

  /// Payload for the `individual_academic_records` INSERT/UPDATE — the
  /// enrolment half.
  ///
  /// The category-specific columns go out as NULL when they do not apply, so
  /// `individual_academic_records_category_fields` passes. The ids are required
  /// rather than the names: the columns are foreign keys, and a name that does
  /// not exist is a rejected insert while a name that exists twice is not
  /// something this client can decide — the unique indexes already refuse it.
  ///
  /// The audit columns mean the same thing here as on the person row — the account
  /// that filed this enrolment — and are left out of an UPDATE for the same reason.
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

  /// Everything the two writes need, keyed by the person id — for the batch
  /// upsert, where a file can add people and update existing ones in one call.
  Map<String, dynamic> toSupabase() => {
        'person': personPayload(),
        'academic': academicPayload(),
      };

  static String? _nullIfEmpty(String? v) {
    if (v == null) return null;
    final t = v.trim();
    return t.isEmpty ? null : t;
  }

  /// `date` columns want 'yyyy-MM-dd' (or nothing at all). A birth date is a
  /// plain calendar day, so the local time is the whole value — no timezone
  /// conversion, which would be free to shift the day across midnight.
  static String? _dateString(DateTime? d) =>
      d == null ? null : _dateStringOf(d);

  static String _dateStringOf(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  /// PostgREST hands back timestamptz as an ISO-8601 UTC string and `date` as
  /// 'yyyy-MM-dd'; both parse with [DateTime.tryParse]. A `date` is parsed as
  /// UTC midnight, so it is read back as a local calendar day to keep the day
  /// the form displays identical to the day that is stored.
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

// ── IMPORT RESULT MODELS ─────────────────────────────────────────────────────

const String kImportNew = 'New';
const String kImportUpdated = 'Updated';
const String kImportUnchanged = 'Unchanged';

class ImportRow {
  final IndividualRecord record;
  final String status; // kImportNew / kImportUpdated / kImportUnchanged
  final String note;
  const ImportRow(this.record, this.status, this.note);
}

/// Labels [staged] rows as new, updated or unchanged, against what is already
/// stored.
///
/// Matching is on the (person, period) key ([IndividualRecord.dbKey]), not on
/// category + person number. Those are different questions: category + number
/// answers "is this person known?", which for anybody who has ever been on the
/// roster is always yes — so a returning student's row for a brand new period
/// was reported as "unchanged" and skipped, and the import then inserted nothing
/// for the period it was filed under. [IndividualRecord.dbKey] asks the question
/// that matters: "is this person already enrolled in THIS period?".
///
/// A row with no same-period match is New even when the person exists in another
/// period, and says so in the note, because that row is what causes the earlier
/// periods to be retired.
///
/// Pure, and takes the roster as an argument, so it can be tested without a
/// database.
List<ImportRow> stageImportRows({
  required List<IndividualRecord> staged,
  required List<IndividualRecord> existing,
  required Set<String> categories,
}) {
  final byPeriod = <String, IndividualRecord>{
    for (final r in existing)
      if (r.academicPeriodId != null) r.dbKey: r,
  };
  final people = {for (final r in existing) r.personKey};

  return [
    for (final incoming in staged)
      if (categories.contains(incoming.category))
        () {
          final match = byPeriod[incoming.dbKey];
          if (match == null) {
            return ImportRow(
              incoming,
              kImportNew,
              people.contains(incoming.personKey)
                  ? 'First enrolment for this period — earlier periods will be retired'
                  : 'No existing record with this ID',
            );
          }
          final diff = match.diffLabels(incoming);
          return diff.isEmpty
              ? ImportRow(incoming, kImportUnchanged,
                  'Identical to the existing record')
              : ImportRow(
                  incoming,
                  kImportUpdated,
                  '${diff.length} change${diff.length == 1 ? '' : 's'}: ${diff.join(', ')}',
                );
        }(),
  ];
}

/// The rows the roster table shows: [rows] narrowed to [category] and to
/// [query], sorted by last name then first name.
///
/// Lives here rather than in the screen so it can be tested without a database,
/// for the same reason [stageImportRows] does. It is also the single definition
/// of "what the table is showing", because the alternative — filtering the table
/// here and counting the chips somewhere else — is how the two drifted apart and
/// the header's total started reporting whatever tab was open.
///
/// An empty [query] matches everything, so the plain roster never has to ask.
/// Matching is case-insensitive and covers the fields a clerk would type: the
/// person number, the name, and the affiliation (program, institute, department,
/// position) plus contact details.
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
          // "Dela Cruz, Juan" as well as "Juan Dela Cruz". Two people in a
          // clinic are routinely written down both ways, and the box is where
          // the reader finds out which spelling the school actually uses.
          _reversedName(r).contains(q) ||
          r.program.toLowerCase().contains(q) ||
          r.institute.toLowerCase().contains(q) ||
          r.department.toLowerCase().contains(q) ||
          // Students are filed by year level ("3rd Year") and never carry a
          // position, so without this the tab would be the only way to find
          // them. The database `or` filter already matched year_level; this is
          // the client-side half of that same search and it has to agree,
          // otherwise typing a year finds rows in the query and then throws
          // them away here.
          r.yearLevel.toLowerCase().contains(q) ||
          r.position.toLowerCase().contains(q) ||
          r.contact.toLowerCase().contains(q) ||
          r.address.toLowerCase().contains(q) ||
          r.email.toLowerCase().contains(q))
      .toList()
    ..sort((a, b) {
      final cmp = a.lastName.toLowerCase().compareTo(b.lastName.toLowerCase());
      return cmp != 0
          ? cmp
          : a.firstName.toLowerCase().compareTo(b.firstName.toLowerCase());
    });
}

/// "last, first middle" for [r], lower-cased — the second order a name is
/// written in. Empty when the person has no last name, so a query can never be
/// satisfied by a bare ", ".
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

/// How many of [rows] are in [category].
///
/// Takes the whole roster and never the open tab or the search box. A count that
/// moves when the reader clicks a tab or types in the search field is not a
/// count of the clinic — it is a count of what happened to be on screen, and it
/// is the reason "All" used to read 15 on the Faculty tab and 40 on the Student
/// tab for the same data.
int countInCategory(List<IndividualRecord> rows, String category) =>
    rows.where((r) => r.category == category).length;

class ImportResult {
  final String fileName;
  final List<ImportRow> rows;

  /// The period the whole batch is filed under — one period for the entire file,
  /// the one picked in the import dialog.
  ///
  /// Carried on the result rather than passed separately to the apply step,
  /// because the retire-earlier-periods call needs the same period the rows were
  /// written with. Reading it from anywhere else is how a batch ends up inserting
  /// on one period and retiring another.
  final String academicPeriodId;

  const ImportResult(this.fileName, this.rows, this.academicPeriodId);

  int get total => rows.length;
  int get added => rows.where((r) => r.status == kImportNew).length;
  int get updated => rows.where((r) => r.status == kImportUpdated).length;
  int get unchanged => rows.where((r) => r.status == kImportUnchanged).length;
}
