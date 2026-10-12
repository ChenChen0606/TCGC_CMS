//  individual_record_service.dart
//  Supabase-backed CRUD for the Individual Record roster.
//
//  TWO TABLES, ONE PERSON
//    public.individual_records            the person, once and for good.
//      person_id (pk AND the printed number), person_type, fn, mn, ln, suffix,
//      sex, date_of_birth, contact_number, email, address, userid, created_by,
//      created_at.
//    public.individual_academic_records   their school / work record for one
//                                         academic period.
//
//  THE COLUMN NAMES IN THIS FILE ARE THE LIVE ONES
//  There is no `id`, no `record_no`, no `category`, no `first_name` and no
//  `status` on `individual_records`; the table is keyed and named as above.
//  Earlier revisions of this file wrote and read the longer spellings and every
//  roster read failed with
//    column individual_records_1.id does not exist
//  — the code was written against a schema that was never applied. Do not
//  "tidy" these names back into the long form.
//
//  READS START FROM THE ENROLMENT, NOT THE PERSON
//  Everything the roster shows is "who is on the roster this term", and the
//  answer to that lives on the academic row. So [fetchAll] queries
//  `individual_academic_records` and embeds the person and the four reference
//  tables — which means the period filter, the status filter and the category
//  filter are all plain filters on the table being queried, and an Inactive or
//  Archived enrolment cannot leak into the list no matter what the client does.
//
//  THERE IS NO PERSON-LEVEL STATUS
//  `individual_records` carries no Active/Archived column, so "on the roster" and
//  "archived" are both facts about the enrolment rows. That is why the roster
//  filter no longer mentions `person.status`, and why [archivePerson] works by
//  archiving every enrolment the person has rather than by flipping one column
//  and relying on a database function to cascade.
//
//  `person_type` HOLDS 'Student' / 'Faculty' / 'Staff' — capitalised
//  `chk_person_type` is
//    CHECK (person_type = ANY (ARRAY['Student','Faculty','Staff']))
//  so those are the only values the column can hold, and the comparison is
//  case-sensitive. Every `person_type` filter in this file therefore goes
//  through [personTypeForStorage], and every read through [canonicalCategory]
//  in the model. Filtering on `person_type = 'faculty'` matched nothing, which
//  is why the Faculty and Staff tabs stayed empty while the records sat in the
//  database; inserting `faculty` was refused by the same constraint, which is
//  why no category could be saved. Do not normalise the spelling of this
//  column — the CHECK constraint is the authority and it is already honoured.
//
//  `created_by` / `userid` ARE WRITTEN, NOT TRIGGERED
//  There is no `individual_records_touch_audit` trigger in this project, and a
//  comment in the roster screen used to say otherwise. Both tables carry the
//  column, both are FKs to `useraccount.user_id`, and both are filled here from
//  [AccountService.currentUserId] on insert so the database can answer "who filed
//  this" without the UI.
//
//  An UPDATE NEVER REWRITES AN EXISTING STAMP. It does backfill a row whose stamp
//  is blank, and that is the only way one can exist — both columns are nullable
//  and this file has always written them itself, so rows written before the
//  stamp existed are the ones still blank. A row nobody can be named for is
//  indistinguishable from a row no clerk ever filed, which is the whole reason the
//  column is there. Blank is filled in once; anything already stamped is left
//  alone, so "who created this person" never becomes "who last touched this
//  person".
//
//  A TRUE `NOT NULL` WOULD BE BETTER, and is not done here because altering the
//  table is not this file's to do. Until it is, this is the enforcement: a write
//  with nobody to name is refused on insert (see [_stamped]) and repaired on
//  update.
//
//  WHY ARCHIVE INSTEAD OF DELETE
//  A person leaves the roster by graduating, resigning or transferring, but the
//  visits and history attached to them must survive. Archiving hides them from
//  the everyday roster and keeps every row, its audit trail and every foreign key
//  pointing at it. Nothing is ever hard-deleted from this screen.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:math';

import 'package:clinicmanagementsystem/screen/individual_record_data.dart';
import 'package:clinicmanagementsystem/services/account_service.dart';
import 'package:clinicmanagementsystem/services/data_tracker.dart';
import 'package:clinicmanagementsystem/services/reference_data_service.dart';
import 'package:clinicmanagementsystem/services/supabase_config.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show PostgrestException;

/// Thrown when the PERSON half of a write committed and the ENROLMENT half did
/// not.
///
/// A person is two rows: `individual_records`, and one row in
/// `individual_academic_records` for the term. They are written as two separate
/// statements because the person has to exist before the enrolment can point at
/// it — and between those two statements the person row is already committed.
/// Anything that goes wrong afterwards (a refused enrolment, a term closed since
/// the screen read it, a connection that drops on the second call) therefore
/// leaves a save that IS on file being reported as one that failed.
///
/// That misreport is the bug this type exists to end. PostgREST offers no
/// transaction, so the two statements cannot be made atomic; the honest thing is
/// to carry what DID land out of the failure rather than throw it away. Discarding
/// it is what left a clerk staring at a form saying "could not save" over a record
/// the database already had, with the list behind it stale and no confirmation —
/// and a retry of that same form then hit the unique constraints and turned one
/// failed save into two.
///
/// [record] is the row as the database now holds it, so the caller can refresh the
/// list, close the form and confirm from it. [message] explains the half that did
/// not land, in the same words every other write failure uses.
class IndividualRecordSaveIncomplete implements Exception {
  IndividualRecordSaveIncomplete(this.record, this.message);

  /// The person row, plus whatever the database could be read back as. Real, and
  /// safe to put in the list.
  final IndividualRecord record;

  /// Why the enrolment half did not land.
  final String message;

  @override
  String toString() => message;
}

class IndividualRecordService {
  IndividualRecordService._();

  /// The permanent person.
  static const String _people = 'individual_records';

  /// The period-specific enrolment / appointment.
  static const String _enrolments = 'individual_academic_records';

  /// WHY EVERY ENROLMENT WRITE ADDRESSES `(person_id, academic_period_id)`
  /// and not the enrolment's own primary key.
  ///
  /// That pair is unique — the schema carries a partial unique index on exactly
  /// those two columns for Active rows, and a person can only be enrolled once
  /// in a term, which is the rule the whole roster turns on. Addressing a row by
  /// a unique pair instead of by a surrogate id means the code does not have to
  /// know what the enrolment table's key column is called, and it cannot address
  /// the wrong row if a legacy row happens to carry a different key shape.
  /// `academicRecordId` is still read, for display and for matching an import
  /// row to what is stored.
  static dynamic _byPair(
    dynamic query,
    String personUuid,
    String academicPeriodId,
  ) =>
      query
          .eq('person_id', personUuid)
          .eq('academic_period_id', academicPeriodId);

  /// The select every roster read uses: the enrolment's own columns, the person
  /// it belongs to, and the reference rows it points at.
  ///
  /// Every reference embed is `!left` and never `!inner` on purpose. An inner
  /// join would quietly drop a student whose program row was deleted out from
  /// under them — the roster would silently shrink and the person would look
  /// like they had left. The FKs stop the row from being saved in that state;
  /// `!left` just means a legacy row still displays, with the program blank,
  /// rather than vanishing.
  ///
  /// The person columns are the live table's, not a schema this file invented:
  /// `person_id` is the primary key and doubles as the printed number, and the
  /// name is `fn` / `mn` / `ln`.
  static const String _rosterSelect = '''
$_enrolmentSelect,
    person:individual_records!left(
      person_id, person_type, fn, mn, ln, suffix, sex, date_of_birth,
      contact_number, email, address, created_at, created_by
    )''';

  /// The enrolment's own columns plus the reference labels it points at, with no
  /// person embed.
  ///
  /// Split out from [_rosterSelect] because that one embeds the person, and a
  /// query rooted on `individual_records` would then embed the person inside their
  /// own enrolments — the same identity block repeated once per term, nested
  /// under a query that already has it at the top. [_personSelect] is there
  /// already; repeating it costs payload and makes the stitched row ambiguous
  /// about which copy of `status` is the person's.
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

  /// The person row on its own, with their most recent enrolments attached —
  /// the shape the Archive and the person-detail sheet want.
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

  // ── READS ─────────────────────────────────────────────────────────────────

  /// Reads the roster from the database, optionally narrowed by [category],
  /// [search], [includeInactive] and [academicPeriodId].
  ///
  /// The narrowing happens in Postgres rather than in Dart so the table can only
  /// ever display rows the database considers a match — picking the Student tab
  /// cannot surface a faculty member even if the client-side filter were
  /// bypassed.
  ///
  /// By default only **Active enrolments under the Active academic period** come
  /// back, which is the rule the rest of the app relies on: the roster and the
  /// Clinic Visit lookup both show the people who are here now. Pass
  /// [academicPeriodId] to look at one specific period (the term filter), or
  /// [includeInactive] to bring the superseded and archived enrolments back for
  /// the history view.
  ///
  /// [academicPeriodId] narrows to one term. Leave it null for the term being
  /// run — which is what "the roster" means — or pass null together with
  /// [includeInactive] for every term at once, which is the history view.
  ///
  /// [search] is matched case-insensitively across the fields a clinic user
  /// would actually type: the record number, the person's name (including the
  /// "Last, First" order), the affiliation (institute / program / year level for
  /// students, institute / position for faculty, office / position for staff),
  /// plus contact, email and address. An empty or whitespace-only term is
  /// ignored.
  static Future<List<IndividualRecord>> fetchAll({
    String? category,
    String? search,
    bool includeInactive = false,
    String? academicPeriodId,
  }) async {
    final cat = category?.trim() ?? '';
    final needle = (search ?? '').trim();

    // Resolved here rather than left to the caller, because "the roster" has to
    // mean one thing everywhere. A caller that forgets to pass a period used to
    // get every Active enrolment in the database with no period filter at all,
    // and `_dedupe` then picked one row per person — so a student enrolled in
    // two terms appeared once and the school looked right, while a person who
    // had *already left* still showed up because some other term had them
    // Active. The Clinic Visit picker was doing exactly that on every launch.
    final periodId = academicPeriodId?.trim() ?? '';
    var effectivePeriod = periodId;
    if (!includeInactive && effectivePeriod.isEmpty) {
      effectivePeriod = ReferenceCatalog.activePeriod?.id ?? '';
      if (effectivePeriod.isEmpty) {
        // No current term is defined, so there is no roster. Returning every
        // period would be the one answer that is definitely wrong: it would list
        // the whole school as present. The screens that offer a way to fix this
        // (Add Academic Period) are one tap away.
        return const [];
      }
    }

    var q = supabaseClient.from(_enrolments).select(_rosterSelect);

    // There is no `status` on `individual_records`, so the person's Active /
    // Archived flag cannot be filtered here — roster membership is exactly
    // "has an Active row for this term", which the next line already asks for.
    if (!includeInactive) q = q.eq('status', kRecordStatusActive);

    if (effectivePeriod.isNotEmpty) {
      q = q.eq('academic_period_id', effectivePeriod);
    }

    // `chk_person_type` allows exactly 'Student' / 'Faculty' / 'Staff', capitalised.
    if (cat.isNotEmpty) {
      q = q.eq('person.person_type', personTypeForStorage(cat));
    }

    if (needle.isNotEmpty) {
      // PostgREST's `or=` filter takes one comma-separated string, so the term
      // is stripped of the characters that would otherwise terminate or split
      // the filter. Those are filter-syntax characters, not part of any real
      // ID or name, and a search box must never be able to change the shape of
      // the query behind it.
      final safe = _filterSafe(needle);
      if (safe.isNotEmpty) {
        // `like` with surrounding % wildcards gives "contains". ilike makes it
        // case-insensitive, which is what a person typing an ID expects.
        final like = '%$safe%';

        // TWO QUERIES, ON PURPOSE.
        //
        // PostgREST cannot filter on a column of an embedded resource: an
        // `or=(person.ln.ilike...)` is rejected outright with
        //   PGRST100 failed to parse logic tree
        // so searching by name or number straight off the enrolment query never
        // worked — it threw rather than returning nothing.
        //
        // So the person side of the search is resolved first against
        // `individual_records`, whose columns are all real root columns, and the
        // answer is fed back as an id list. The second query then filters on
        // `person_id`, which IS a column of the table being queried.
        //
        // Reference-table names (institute, program, office) still cannot be
        // searched here for the same reason. `filterRoster` in the model layer
        // covers those names for typing, and the reference ids are on the row
        // for anything stricter.
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

  /// The person's most recent enrolment, used by the Clinic Visit lookup and
  /// anywhere that asks "is this number taken?" without naming a period.
  ///
  /// Includes inactive enrolments on purpose: a person who was on last term's
  /// roster and is not on this one still holds their number, and reusing it would
  /// split one person's history across two rows that look like two people.
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

  /// The enrolment for one (person, period) pair — the key the database
  /// enforces.
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

  /// Reads a person by uuid, with their enrolments attached. Used by the Archive
  /// and by the detail sheet, where the question is about the person rather than
  /// about one of their enrolments.
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

  /// Picks a person's newest enrolment out of the embedded `academic` list and
  /// stitches it onto their row, so [IndividualRecord.fromSupabase] sees the one
  /// shape it reads.
  ///
  /// PostgREST returns an embedded one-to-many as a JSON ARRAY even when the
  /// person has exactly one enrolment, and `fromSupabase` reads an OBJECT. Handing
  /// it the raw list therefore dropped the entire academic half in silence: no
  /// period, no program, no position, and the default `Active` status. The visible
  /// cost was on the save path — [create] reads the new row back through
  /// [fetchByUuid], got a record whose `academicPeriodId` was null, and the roster
  /// then retired that person's enrolments with an empty period, which is every
  /// Active row they have, including the one just written. Every new record landed
  /// Inactive.
  ///
  /// A person with no enrolment keeps their identity and gets no `academic` key;
  /// `fromSupabase` already handles that, so the form still opens to add one.
  static Map<String, dynamic> _withNewestEnrolment(
      Map<String, dynamic> person) {
    final enrolments = person['academic'] as List<dynamic>? ?? const [];
    final merged = Map<String, dynamic>.from(person)..remove('academic');
    if (enrolments.isEmpty) return merged;

    // Newest period first, so the row is the one a reader would call "this person
    // now". A period is ordered by its school year and semester rather than its id
    // because there is no natural order on a uuid; 1st Semester, then 2nd, then
    // Summer is the order the school works in.
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

  /// Every enrolment of one person, newest period first.
  static Future<List<IndividualRecord>> fetchEnrolmentsOf(
      String personUuid) async {
    final rows = await supabaseClient
        .from(_enrolments)
        .select(_rosterSelect)
        .eq('person_id', personUuid);
    final records = rows
        .map<IndividualRecord>(
            (r) => IndividualRecord.fromSupabase(Map<String, dynamic>.from(r)))
        .toList()
      ..sort((a, b) {
        final year = b.academicYear.compareTo(a.academicYear);
        return year != 0
            ? year
            : _semesterRank(b.semester).compareTo(_semesterRank(a.semester));
      });
    return records;
  }

  /// True when [recordNo] is already used by anybody in [category].
  ///
  /// `person_id` is the primary key of `individual_records`, so this is really
  /// just "does this number belong to somebody already" — a number identifies a
  /// *person* for their entire life rather than per term, which is the point of
  /// splitting the tables. A number that exists on an earlier period is still
  /// that person's number, and a new row reusing it is how one person becomes
  /// two.
  ///
  /// [ignoringUuid] excludes the row being edited, so saving a record without
  /// changing its number is not reported as a collision.
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

  /// The uuid of an existing person whose identity matches [firstName] /
  /// [middleName] / [lastName] / [suffix] / [birthDate], or null when nobody
  /// does.
  ///
  /// Students bring their own number, so their duplicate test is [idExists].
  /// Faculty and Staff numbers are six random digits that never collide, so the
  /// test that matters for them is "is this person already here under a
  /// different number" — which is what this answers. Names are compared
  /// ignoring capitalisation, which the database's
  /// `uq_individual_identity` index is case-sensitive about, so this is the
  /// only place the two spellings of one name are caught. The birth date, when
  /// known, is part of the match too, exactly as the index couples it to the
  /// name: two members who merely share a name are not the same person.
  ///
  /// [ignoringUuid] excludes the row being edited, so saving a record without
  /// changing its name is never reported as a collision with itself.
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

  /// Whether a text column from the database is [value] ignoring case and
  /// trim — the comparison used by [identityClash].
  static bool _nameEquals(Object? stored, String value) {
    if (stored == null) return value.isEmpty;
    return '$stored'.trim().toLowerCase() == value.toLowerCase();
  }

  /// [d] as the `yyyy-MM-dd` string the database stores a date as.
  static String _dateStamp(DateTime d) {
    final y = d.year.toString().padLeft(4, '0');
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '$y-$m-$day';
  }

  /// True when [personUuid] already has an enrolment in [academicPeriodId].
  ///
  /// This is the duplicate the roster actually cares about — a person can only
  /// be enrolled once in a term, which a partial unique index enforces — and it
  /// is asked separately from [idExists] because they answer different questions
  /// about different tables.
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

  // ── GENERATED FACULTY / STAFF NUMBERS ───────────────────────────────────
  //
  //  'F' / 'S' plus six random digits — `F482913`, `S107265`.
  //
  //  WHY RANDOM AND NOT A SEQUENCE
  //  The numbers these replace ('F001', '2025-3004') told you the year and the
  //  order of arrival, which is exactly what a person number should not: it
  //  leaked who joined most recently. Six random digits over a 900 000-value
  //  space makes a number unguessable and uninformative while still being short
  //  enough to read over the phone, and the letter in front says at a glance
  //  whose it is.
  //
  /// The sequence lives in the database (`generate_person_id`) rather than in
  /// Dart, because a number handed out on two devices at once must still be
  /// unique and the only thing that can guarantee that is the unique index.

  static final Random _random = Random.secure();

  /// How many candidates [nextIdFor] tries before giving up.
  ///
  /// A collision needs the same letter and the same six digits — about one in
  /// 900 000 — so this bounds the astronomically unlikely rather than encoding a
  /// real strategy. It is here so the loop can never spin forever against a table
  /// that somehow contains every number in the range.
  static const int _maxIdAttempts = 40;

  /// The category letter inside a generated number. Students bring their own
  /// number and are never generated, so [category] is Faculty or Staff.
  static String idLetterFor(String category) => category == 'Staff' ? 'S' : 'F';

  static final RegExp _generatedIdPattern = RegExp(r'^[FS]\d{6}$');

  /// Whether [value] has the generated shape, whatever category it belongs to —
  /// used to recognise rows the form should offer a generated number for.
  static bool looksGenerated(String value) =>
      _generatedIdPattern.hasMatch(value.trim());

  /// Asks the database for the next free Faculty/Staff number.
  ///
  /// Tries `generate_person_id` first, because a database-side sequence is the
  /// only thing that can guarantee two devices never draw the same number. That
  /// function is not present in this Supabase project, so there is a client-side
  /// fallback: draw a random candidate and check it is unused.
  ///
  /// The fallback is safe here specifically because `person_id` is the table's
  /// PRIMARY KEY — a duplicate number cannot be inserted, so the worst outcome of
  /// a race is one of the two saves being rejected with a duplicate-key error the
  /// form already reports, not two people sharing one number.
  ///
  /// [category] must be Faculty or Staff; a Student number is the school's own
  /// and is never generated here.
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
    } catch (_) {
      // No such function in this project — fall through to the local draw.
    }

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

  // ── WRITES ────────────────────────────────────────────────────────────────

  /// Turns a failed INSERT or UPDATE into one sentence the clerk can act on.
  ///
  /// WHY THIS EXISTS
  /// The roster table is protected by two partial unique indexes, three CHECK
  /// constraints and seven foreign keys, and each refusal arrives as a
  /// `PostgrestException` whose `message` names the constraint and whose
  /// `details` quotes the offending key. That is enough for a developer and not
  /// enough for somebody whose job is to file people: `duplicate key value
  /// violates unique constraint "uq_individual_email"` does not say which field
  /// was duplicated, and — because `uq_individual_email` is indexed on
  /// `lower(btrim(email)) WHERE email IS NOT NULL` — the offending value is an
  /// empty string that was never on screen. A blank email box quietly became a
  /// real value, so the *second* record with a blank email box failed on a field
  /// nobody had filled in, on a person who had nothing to do with the first.
  ///
  /// So the constraint named in `message` is the routing key and `details` is
  /// only ever the extra context appended to a sentence that already explains
  /// the problem.
  ///
  /// Anything unrecognised falls through to the original error rather than being
  /// swallowed: a message this function has never seen is still a true one, and
  /// hiding it would trade a clear bug for a vague one.
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

    // Nothing here recognises it, so the server's own words are all there is.
    // They go IN, not just `details`: a `42503` (column not allowed), a
    // `PGRST` shape error or a malformed filter explains itself in `message`
    // and says nothing in `details`, so appending only the latter reported
    // "Could not save" with no reason at all — nothing the clerk could act on
    // and nothing a developer could diagnose without the console. The code is
    // included because it is what turns a complaint into a lookup.
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

  /// The term's label as the clerk typed it on the form, for a message that has to
  /// say which enrolment failed.
  ///
  /// Falls back to 'enrolment' rather than to the raw id or to nothing: an
  /// operator reading a failure needs to know which of a person's terms went wrong,
  /// and the id means nothing to them.
  static String _periodLabel(String periodId) =>
      ReferenceCatalog.periodById(periodId)?.label ?? 'enrolment';

  /// Inserts a person and their enrolment and returns the stitched result.
  ///
  /// Two INSERTs, and deliberately not one transaction from here: the person has
  /// to exist before the enrolment can point at them. The partial unique indexes
  /// are what actually protect the pair; the client is the polite layer that
  /// produces a readable error instead of a constraint violation.
  ///
  /// AN ACADEMIC PERIOD IS REQUIRED, and this used to be the quietest bug in the
  /// app. The enrolment used to be skipped when [IndividualRecord.academicPeriodId]
  /// was blank, on the reasoning that "a person can be filed before they are
  /// enrolled". But *every* consumer — the roster table, the Clinic Visit visitor
  /// picker, the archive — reads `individual_academic_records` and never
  /// `individual_records`. A person written with no enrolment is therefore on file
  /// and visible nowhere, and the save reported success: the clerk checked the
  /// database, saw their new faculty member, and the table stayed empty. Refusing
  /// here rather than skipping means no caller can ever produce that row, and the
  /// message says which term is missing instead of leaving a mystery behind.
  ///
  /// The status is decided here, by [statusForTerm], and whatever the caller put
  /// on the record is overwritten. A person being added has no prior decision to
  /// preserve, so there is nothing to be gained from trusting the caller's guess
  /// and a whole class of bug available from doing it — the row was saved, the
  /// confirmation dialog appeared, and the roster could not show it because the
  /// two disagreed about which term is current.
  ///
  /// A refused enrolment is reported as [IndividualRecordSaveIncomplete] rather
  /// than as a failure, because by then the person IS on file. See that class.
  static Future<IndividualRecord> create(IndividualRecord r) async {
    final periodId = (r.academicPeriodId ?? '').trim();
    if (periodId.isEmpty) {
      throw StateError(
          'Cannot save ${r.category} ${r.id}: no academic period, so the record '
          'would be written with no enrolment and would not appear in the '
          'roster, the visitor list or the archive.');
    }
    // The term the database is running can have changed since this session read
    // the catalogue — another device, or the SQL editor — so ask again before
    // deciding whether this enrolment belongs on the roster. Otherwise a record
    // saved under the freshly-active term is written Inactive and never appears.
    await _syncPeriods();
    r.status = statusForTerm(periodId);

    final personUuid = await _insertPerson(_stamped(r));
    try {
      await _insertEnrolment(personUuid, r);
    } catch (e) {
      // The person row is already committed by the time this runs. Reporting this
      // as "could not save" would be a lie about the database — and the clerk's
      // natural reaction to it, trying again, would then be refused by the primary
      // key on a person who is genuinely already there.
      debugPrint('IndividualRecordService: create of ${r.id} saved the person '
          '$personUuid but its $periodId enrolment was refused — $e');
      throw IndividualRecordSaveIncomplete(
        await _readBack(personUuid, r, what: 'create of ${r.id}'),
        'Could not save ${r.category} ${r.id}.\n\n'
        'The person was saved, but the '
        '${_periodLabel(periodId)} was not, so this record will not appear '
        'on the roster.\n\n'
        '${describeWriteFailure(e, category: r.category, recordNo: r.id)}',
      );
    }
    DataTracker.bump();
    return _readBack(personUuid, r, what: '${r.category} ${r.id}');
  }

  /// Reads [uuid] back out of the database once a write has already committed, and
  /// falls back to [written] — the row exactly as this client sent it — when that
  /// read fails.
  ///
  /// IT DOES NOT THROW, and that is the whole reason it exists. Every write here
  /// is a separate statement that has already committed by the time this runs, so
  /// a failing read-back is not a failed save — it is a save whose confirmation
  /// could not be fetched. Letting the exception escape turned every one of those
  /// into a lie the user could not argue with: the database had the record, and
  /// the form said it could not be saved, stayed open, showed no confirmation and
  /// never re-read the table. The person who filed the row was left believing
  /// nothing happened and filing it again.
  ///
  /// The value this returns is the row as the database now holds it, including
  /// the real `created_at` and audit stamps, which is what makes it worth having.
  /// When the read fails the caller still gets a usable record: [written] with its
  /// uuid filled in, so the detail sheet and the follow-up actions work rather
  /// than throwing "cannot update an unsaved record" on the next tap.
  ///
  /// The reason is printed to the debug console instead of being swallowed, so a
  /// read-back that keeps failing stays diagnosable.
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

  /// Records the signed-in account on [r] as the person who filed it, and returns
  /// [r].
  ///
  /// Done here rather than in the form so no caller can forget it: the service is
  /// the only thing that writes these two tables, and a record with a null
  /// `created_by` is indistinguishable from one nobody created. The value is
  /// stamped onto [r] as well as into the payload, so the row the roster holds in
  /// memory carries the same audit trail as the row in the database and the
  /// detail sheet can name the person straight after saving.
  ///
  /// IT REFUSES WHEN THERE IS NO ACCOUNT TO NAME, and that refusal is the point.
  /// This used to give up quietly when the session was missing — an expired
  /// refresh token, or a write attempted before sign-in finished — and wrote
  /// `created_by = NULL`, which is exactly the row this method exists to prevent:
  /// nobody could ever say who filed it, and the database cannot tell it apart
  /// from a row written by a script. Both columns are nullable in the schema, so
  /// the mistake was silent and permanent. Failing here is loud, happens BEFORE
  /// the first statement, and leaves nothing half-written.
  ///
  /// The id is `auth.currentUser.id`, which is the same value as
  /// `useraccount.user_id` — the column both tables point at — so the write
  /// cannot be rejected by `created_by_fkey` for naming the wrong kind of id.
  ///
  /// Never called on the update path — see [update].
  /// The signed-in account's id, or `''` when there is no session.
  ///
  /// [_stamped] refuses to continue on an empty value, because a new row with a
  /// null `created_by` is the mistake worth refusing over. The backfill in
  /// [update] reads the same thing and does the opposite: there an empty value
  /// means there is nobody to name, so it leaves the row alone rather than failing
  /// an otherwise-correct edit.
  static String _currentAccount() => AccountService.currentUserId.trim();

  /// Whether a value coming back from PostgREST is absent — NULL, or a string of
  /// nothing but spaces.
  ///
  /// An empty string is NOT null, which is the whole reason this exists: a blank
  /// email box used to be written as a real value, and the *second* person with a
  /// blank box failed on a field nobody had filled in.
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

  /// Inserts the person half only — for somebody who is on file but not yet
  /// enrolled in anything this term.
  static Future<String> createPersonOnly(IndividualRecord r) async {
    final personUuid = await _insertPerson(_stamped(r));
    DataTracker.bump();
    return personUuid;
  }

  static Future<String> _insertPerson(IndividualRecord r) async {
    // `person_id` is the primary key AND the printed number, so it is written by
    // the client rather than defaulted by the database — there is no uuid to fall
    // back on. Read it straight back out of the payload, which removes a round
    // trip that `.select('id')` used to make against a column that does not
    // exist.
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

  /// Files [r] under `(personUuid, periodId)`, updating the enrolment when there
  /// already is one and inserting it when there is not.
  ///
  /// WHY THIS IS NOT AN `UPDATE`-THEN-INSERT, WHICH IS WHAT IT REPLACED
  /// The obvious spelling asks the UPDATE what it touched — `.select()` on an
  /// UPDATE returns the rows it matched — and INSERTs when the answer is empty.
  /// That treats an empty return as proof the row was absent, and an empty return
  /// is not proof of that: an UPDATE that matched a row can still come back empty
  /// if the caller is not allowed to read it back, and then the INSERT collides
  /// with `uq_person_period` and fails a save that actually worked. The duplicate
  /// INDEX that protects the roster was being turned into a user-facing error by
  /// the client code, on writes that were already correct.
  ///
  /// So the row's existence is decided by reading that term's row first, and only
  /// the statement that can succeed is issued.
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

    // Archived is a person-level decision made by an administrator and is not
    // reachable from here, so this UPDATE cannot be refused by `chk_status` for a
    // value the form could not have chosen. It is still sent through the same
    // `_byPair` address as everything else so it cannot land on the wrong term's
    // row if the record carries several enrolments.
    await _byPair(
        supabaseClient.from(_enrolments).update(payload), personUuid, periodId);
  }

  /// Updates the form-owned fields of an existing person and enrolment.
  ///
  /// `individual_records.status` is not in the payload — see [archivePerson].
  /// The enrolment's own status is, because Active/Inactive is a roster decision
  /// this screen makes all the time; Archived is not accepted there and is
  /// rejected by the CHECK constraint if a caller tries.
  ///
  /// `created_by` / `userid` are left out of both payloads. They are stamped once,
  /// on insert, so "who created this person" keeps naming the clerk who added
  /// them rather than whoever last corrected a typo. The one exception is a row
  /// whose stamp is still blank — see the backfill below.
  ///
  /// A refused enrolment is reported as [IndividualRecordSaveIncomplete] rather
  /// than as a failure, because by then the person row IS on file. See that class.
  ///
  /// [previousPeriodId] is the term the enrolment is filed under *today*, as the
  /// caller last read it. It is what makes moving somebody between terms work at
  /// all, and it is not derivable here: [IndividualRecord.academicPeriodId] has
  /// already been overwritten with the term being written, so without it the
  /// update below filters on a pair the database has never seen.
  static Future<IndividualRecord> update(
    IndividualRecord r, {
    String? previousPeriodId,
  }) async {
    final uuid = r.uuid;
    if (uuid == null) {
      throw StateError('Cannot update an individual record without a uuid.');
    }

    // `.select()` is not decoration here. It is the only way the client learns
    // whether the statement matched a row, and this file has been wrong twice by
    // assuming it did: an UPDATE that matches nothing and an UPDATE that matches
    // one are indistinguishable without it. `person_id` is the primary key, so an
    // empty result can only mean the row is gone — deleted elsewhere, or a
    // filtered-out record — and reporting success there is a lie the roster would
    // then contradict the moment it was re-read.
    final touched = await supabaseClient
        .from(_people)
        .update(r.personPayload(includeAudit: false))
        .eq('person_id', uuid)
        .select('person_id')
        .then((rows) => rows.cast<Map<String, dynamic>>());

    if (touched.isEmpty) {
      // Worth distinguishing from a refused write before anyone is told anything:
      // this row is simply not visible to the UPDATE, which under RLS can also
      // mean the account is not allowed to see it. Those need different answers —
      // one says "reopen the person", the other says "ask an administrator" — and
      // the code cannot tell them apart, so the status is recorded here.
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

    // The one case where the audit stamp IS written by an update: a row whose
    // `created_by` is still blank. Those are the rows written before the stamp
    // existed, or by a session that had none, and leaving them blank is the exact
    // hole the column exists to close — the database cannot tell such a row from
    // one no clerk ever filed. A stamp that is already there is never rewritten:
    // "who created this person" must keep naming whoever added them, not whoever
    // last corrected a typo.
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

    // Same reason as [create]: the active term may have moved since this session
    // read the catalogue, and this edit derives the enrolment status from it.
    await _syncPeriods();

    // Archived is a person-level decision made by an administrator, so an edit
    // never puts somebody back on the roster and never leaves them in the
    // Archive either — they settle as Inactive, which is where somebody who was
    // removed and then had a typo corrected belongs.
    final wantedStatus = r.status == kRecordStatusArchived
        ? kRecordStatusInactive
        // Filing somebody under a DIFFERENT term is a new enrolment, so its
        // status is derived from that term rather than carried over. Carrying it
        // over is what made a record moved into the current term invisible: the
        // clerk changed the year, the row was written Inactive because that is
        // what the old term's history had been set to, and the roster — which
        // lists Active enrolments of the current term — showed nothing.
        : (previousPeriodId != null && previousPeriodId.trim() != periodId)
            ? statusForTerm(periodId)
            // Same term: whatever the row already says stands. A person who
            // resigned mid-term is Inactive while the term is still current, and
            // correcting their address must not enrol them again. An empty string
            // means the caller has no opinion — the import path sends one — and
            // the term decides.
            : (r.status.isEmpty ? statusForTerm(periodId) : r.status);

    if (periodId.isNotEmpty) {
      try {
        await _fileEnrolment(uuid, r, wantedStatus);
      } catch (e) {
        // The person row is written and correct by the time this is reachable.
        // Saying "could not save" is what produced the original complaint: the
        // database held the edit, the form said it failed, the table behind it
        // never refreshed, and the clerk filed it all over again. So the person
        // half is handed back as the success it is, and the enrolment half is
        // named as the part that did not land.
        //
        // Printed for the same reason [describeWriteFailure] keeps the server's own
        // words: a half-completed write is the one failure the clerk cannot act on
        // from the dialog alone, so the console has to say which statement refused
        // and what it said.
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

  /// Flips an *enrolment* between 'Active' and 'Inactive'.
  ///
  /// This is what the screen's Delete button calls for somebody leaving the
  /// current roster: the person stays in `individual_records` and keeps every
  /// enrolment, but this term's row goes Inactive and off the list. Nothing is
  /// hard-deleted, so the history behind the person survives.
  ///
  /// Archiving the *person* — taking them out of the roster entirely, every term
  /// at once — is [archivePerson].
  ///
  /// `individual_academic_records` carries a single `status` column and no
  /// reason / who / when columns, so [reason] cannot be stored. It is accepted
  /// so callers do not have to change, and it is included in the error text when
  /// the caller asked for a status the table will not hold.
  static Future<IndividualRecord> setStatus(
    IndividualRecord r,
    String status, {
    String? reason,
  }) async {
    final uuid = r.uuid;
    if (uuid == null) {
      throw StateError('Cannot change the status of an unsaved record.');
    }
    if (status == kRecordStatusArchived && (reason ?? '').trim().isNotEmpty) {
      // Accepted for the caller's benefit, but the table has nowhere to put it.
      // Dropping it silently would be worse than saying so, so it is reported in
      // the debug console rather than pretended to be saved.
      debugPrint(
        'IndividualRecordService: this table has no reason column, so "$reason" '
        'was not stored.',
      );
    }

    // A person with no enrolment row in the requested period still needs
    // retiring, otherwise `setStatus` reports success and changes nothing. The
    // period is required for that, and there is only one sensible target: the
    // period the record is currently filed under.
    final periodId = r.academicPeriodId;
    if ((periodId ?? '').isEmpty) {
      // No period at all to act on: there is no enrolment to retire, so say so
      // rather than reporting a write that never happened.
      DataTracker.bump();
      return r;
    }

    final existing = await fetchEnrolment(uuid, periodId);
    if (existing == null) {
      // No row for this period — insert one already carrying the new status, so
      // the record's affiliation is on file rather than silently dropped.
      await _insertEnrolment(uuid, r..status = status);
    }
    await _byPair(supabaseClient.from(_enrolments).update({'status': status}),
        uuid, periodId!);

    DataTracker.bump();
    return _readBack(uuid, r, what: 'status change to $status');
  }

  /// Convenience for the delete button: retires this term's enrolment, marking
  /// it 'Inactive'.
  static Future<IndividualRecord> deactivate(
    IndividualRecord r, {
    String? reason,
  }) =>
      setStatus(r, kRecordStatusInactive, reason: reason);

  /// Puts a retired enrolment back on the roster. Clearing the reason and the
  /// who/when keeps the row from still looking like a pending removal.
  static Future<IndividualRecord> reactivate(IndividualRecord r) =>
      setStatus(r, kRecordStatusActive);

  /// Takes a person out of the roster entirely, for every period at once.
  ///
  /// There is no `status` column on `individual_records` in this schema, so
  /// archiving is defined entirely on the enrolments: every term this person was
  /// filed under becomes 'Archived', which is what removes them from every
  /// roster and from the Clinic Visit lookup. `archive_person` did this in one
  /// transaction when it existed; it is not present in this project, so this is
  /// one UPDATE filtered on `person_id` — still a single statement, so there is
  /// no window in which some terms are archived and others are not.
  ///
  /// The person row itself is left completely alone. Every enrolment, its audit
  /// trail, and every foreign key pointing at the person survive.
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

  /// The other half of [archivePerson]: brings the person back by putting every
  /// enrolment that was archived straight back to Active.
  static Future<void> restorePerson(String personUuid) async {
    await supabaseClient
        .from(_enrolments)
        .update({'status': kRecordStatusActive})
        .eq('person_id', personUuid)
        .eq('status', kRecordStatusArchived);
    DataTracker.bump();
  }

  /// Bulk create used by the roster import: one INSERT per table for the whole
  /// batch, so a 500-row file is two round trips rather than a thousand.
  ///
  /// People first, because the enrolments need their ids. The two lists are
  /// matched back on `(person_type, person_id)` — the key the insert was made
  /// against — and not by position.
  ///
  /// Position would be simpler and is wrong: `INSERT ... RETURNING` gives no
  /// ordering guarantee, so on a large batch Postgres is free to return the rows
  /// in whatever order the plan produced. Walking both lists by index would then
  /// file somebody's year level against somebody else's person row, which raises
  /// nothing, passes every CHECK constraint, and is not visible until a term is
  /// rolled forward. The unique key cannot drift.
  static Future<List<IndividualRecord>> createAll(
    List<IndividualRecord> records,
  ) async {
    if (records.isEmpty) return const [];

    // An import derives every row's status from the term it is filed under, and
    // the active term may have moved since this session read the catalogue.
    await _syncPeriods();

    // Stamped here as well as on the single-record path: an imported roster is
    // filed by the same signed-in clerk as one typed in by hand, and both must
    // leave the same audit trail behind.
    for (final r in records) {
      _stamped(r);
    }

    // `person_id` is the primary key and is supplied by the client, so the
    // read-back is only needed to confirm which rows landed. Selecting
    // `person_type` as well is what makes the match unambiguous.
    final personRows = await supabaseClient
        .from(_people)
        .insert(records.map((r) => r.personPayload()).toList())
        .select('person_id, person_type');
    DataTracker.bump();

    final idsByKey = <String, String>{};
    for (final row in personRows) {
      final key = _personKey(
          '${row['person_type'] ?? ''}', '${row['person_id'] ?? ''}');
      idsByKey[key] = '${row['person_id']}';
    }

    final payloads = <Map<String, dynamic>>[];
    final enrolled = <IndividualRecord>[];
    for (final record in records) {
      final personUuid = idsByKey[_personKey(record.category, record.id)];
      if (personUuid == null) {
        // The insert reported success but did not return a row for this person.
        // Carrying on would enrol nobody and still report the import as done, so
        // say which record is missing rather than quietly dropping it.
        throw StateError(
            'Saved ${record.category} ${record.id} but the database did not '
            'return them. Nothing was enrolled for this row.');
      }
      record.uuid = personUuid;
      // Same rule as the single-record path, applied before the payload is built:
      // a row imported against a term that is not the current one is history, and
      // the model defaults `status` to Active, so without this every row of a
      // back-dated import would land Active and be listed on a roster it does not
      // belong to.
      record.status = statusForTerm(record.academicPeriodId);
      if ((record.academicPeriodId ?? '').isEmpty) continue;
      payloads.add({
        ...record.academicPayload(),
        'person_id': personUuid,
      });
      enrolled.add(record);
    }
    if (payloads.isNotEmpty) {
      await supabaseClient.from(_enrolments).insert(payloads);
      DataTracker.bump();
    }

    return enrolled;
  }

  /// The identity key of a person row, as the insert and the read-back both spell
  /// it. One function so the two can never disagree about what a person is.
  ///
  /// Both sides are canonicalised because one comes from the database and one
  /// from the form: `person_type` is written capitalised by
  /// [personTypeForStorage], and a read-back of a row written by hand could
  /// carry different casing, so an exact comparison would report every imported
  /// row as missing from its own insert.
  static String _personKey(String category, String recordNo) =>
      '${canonicalCategory(category)}|${recordNo.trim()}';

  /// Maps useraccount.user_id -> "First Last" so the audit trail shows a name
  /// instead of a uuid, using the table's fn / ln columns and falling back to
  /// the username. Returns an empty map when the table is unreadable, which the
  /// UI degrades on gracefully.
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

  /// Keeps the newest enrolment per (person, period) so a duplicate that slipped
  /// in before the unique index existed never shows up as two people in the
  /// table. Ordered by creation, so the last one wins.
  ///
  /// The period is part of the key on purpose: the same person legitimately holds
  /// a row per period, and collapsing on the person alone would erase the
  /// enrolment history the Year & Semester filter exists to show.
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

  // ── PERIOD WORKFLOW ──────────────────────────────────────────────────────

  /// The status an enrolment filed under [academicPeriodId] should carry.
  ///
  /// ONE RULE, ONE PLACE — an enrolment is Active if and only if it is filed
  /// under the term the school is currently running. Everything else is history
  /// and is Inactive. This is the answer to "if the year I filed it under is
  /// still the current year, it should be Active; if that year is no longer
  /// current, it should be Inactive", and it is deliberately a function of the
  /// term rather than a value the form guesses at.
  ///
  /// WHY IT LIVES HERE AND NOT IN THE FORM
  /// The form used to decide this from its own copy of the term, and the two
  /// copies are not the same thing: the form asked `_selectedPeriodId`, which
  /// falls back to the Active period when the typed year is not on file, and
  /// compared that against the catalog's Active id. Any disagreement — an
  /// unloaded catalog, a term renamed, a year typed by hand — produced a save
  /// that reported success and a row the roster could not see, because
  /// `fetchAll` only ever lists Active enrolments. Deriving it from
  /// [ReferenceCatalog.activePeriod] at the moment of the write means the
  /// question is asked once, of the database, and the answer is the same one the
  /// roster will use.
  ///
  /// WHY THE COLUMN IS NOT SIMPLY DELETED, given that this decides it
  /// `academic_periods.status` and `individual_academic_records.status` are
  /// different facts. "This is the current term" is a fact about the school;
  /// "this person is still here" is a fact about a person in that term. Somebody
  /// who resigns mid-term has to leave the roster while the term carries on being
  /// current, and the only place that decision can live is this column — it is
  /// what `deactivate` writes. It also carries a third value, `Archived`, which
  /// describes a person removed by an administrator and which no term ever has.
  /// Deriving the column from the term on every save is right; erasing it and
  /// reading the term instead would throw away the mid-term departures and the
  /// archive with them.
  ///
  /// A term that is not on file at all yields Inactive: an enrolment pointing at
  /// a period nobody registered is not something to put on the roster.
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
    // Some other term: history. It stays on file but off the roster, which is the
    // whole point of the third value this column carries. Returning Active here
    // put every back-dated year on the current roster.
    return kRecordStatusInactive;
  }

  /// Re-reads the term list from `academic_periods`, swallowing a failure.
  ///
  /// Every write that has to decide whether an enrolment is on the roster calls
  /// this first, so the decision is made against the term the database is running
  /// *now* rather than the one this session read when it started. A failure is
  /// deliberately not fatal: refusing a save because one extra read of a small
  /// table could not be made would trade a stale answer for no answer, and the
  /// catalogue already in memory is only ever out of date, never wrong in kind.
  static Future<void> _syncPeriods() async {
    try {
      await ReferenceCatalog.refreshPeriods();
    } catch (e) {
      debugPrint('IndividualRecordService: could not re-read the academic '
          'periods — $e');
    }
  }

  /// Retires the earlier enrolments of every person in [people] when
  /// [academicPeriodId] becomes their current term, so a new period's roster does
  /// not leave two Active rows for one human being.
  ///
  /// The rules:
  ///   * enrolments in [academicPeriodId] are left alone — that IS the person
  ///     being saved, and deactivating them would make the save look like it
  ///     failed,
  ///   * every other period for those same people flips to Inactive.
  ///
  /// ONE UPDATE for the whole batch. A 500-row roster is a single statement
  /// rather than 500 round trips, and the filter is built in SQL rather than by
  /// reading the person's rows first, so nothing races between the read and the
  /// write.
  ///
  /// This is what the "roll the roster forward" switch in the Add Academic Period
  /// dialog calls, but through [ReferenceDataService.setActivePeriod] rather
  /// than directly, so the UI has one path for "make this term the current one".
  static Future<int> retireEarlierPeriods(
    List<({String category, String recordNo})> people, {
    required String academicPeriodId,
  }) async {
    // A blank period would make the `neq` below match EVERY other period, so the
    // statement would retire every Active enrolment the person has — including the
    // one that was just saved. "Earlier than nothing" is not a term, so there is
    // nothing to retire. This is also the guard that turned a lost read-back
    // `academicPeriodId` into a silent mass-deactivation before [fetchByUuid]
    // stopped dropping the academic half.
    if (academicPeriodId.trim().isEmpty) return 0;

    // Distinct, so a person listed twice in one file is not matched twice — and
    // so one malformed key cannot make the whole `or=` string invalid, which
    // would fail the statement and take the whole import with it.
    final ids = <String>{};
    for (final p in people) {
      final no = p.recordNo.trim();
      final cat = p.category.trim();
      if (no.isEmpty || cat.isEmpty) continue;
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

  /// 1st Semester, then 2nd, then Summer — the order the school works in.
  /// Postgres sorts the labels alphabetically, which puts "1st Semester" and
  /// "2nd Semester" in the right order by luck and "Summer" last by luck too,
  /// but only for these three strings; ranking it here means a term list is in
  /// school order no matter what the labels are.
  static int _semesterRank(String semester) {
    final s = semester.trim().toLowerCase();
    if (s.startsWith('1')) return 0;
    if (s.startsWith('2')) return 1;
    if (s.startsWith('summer')) return 2;
    return 3;
  }

  /// Removes the characters that would terminate or split a PostgREST `or=`
  /// filter. Those are filter-syntax characters, not part of any real record
  /// number, and a person number must never be able to change the shape of the
  /// query behind it.
  static String _filterSafe(String v) =>
      v.replaceAll(RegExp(r'[,()*:\\"\s]'), ' ').trim();

  /// How many people a single search term may match before the id list stops
  /// growing.
  ///
  /// A one-character search matches everybody, and the id list goes straight into
  /// an `in.(...)` filter. Without a cap, typing one letter into the search box
  /// would build a URL holding every person in the school — long enough to be
  /// rejected outright, and pointless anyway because the table only shows the
  /// current term. A roster search is for finding one person, not for listing
  /// them all.
  static const int _maxSearchMatches = 300;

  /// Makes a value safe to sit inside an `in.(...)` list.
  ///
  /// Ids come from the database rather than from the search box, so this is
  /// belt-and-braces: a value carrying a comma, a quote or a bracket would
  /// restructure the filter around it instead of being compared to a column.
  static String _inFilterSafe(String v) =>
      v.replaceAll(RegExp(r'''[,()"'\\]'''), '').replaceAll(' ', '').trim();
}
