// ─────────────────────────────────────────────────────────────────────────────
//  archive_service.dart
//  Supabase-backed Archive module.
//
//  Three different retirement mechanisms, one per kind of thing archived:
//    * people are NOT archived by a column. `individual_records` has no status
//      column, so [fetchArchivedPatients] derives it: a person is archived when
//      they still have an Archived enrolment and no Active one. Archiving is done
//      by IndividualRecordService.archivePerson, which sets
//      `individual_academic_records.status = 'Archived'` on every row of theirs.
//      This is deliberate and person-wide, and it is NOT the same as an Inactive
//      enrolment, which is what rolling the term forward does to everybody; those
//      rows are history, not archive.
//    * medicines carry `is_archived` only — same soft-delete shape: set it true
//      to archive, false to restore. There is no archived_reason / archived_by /
//      archived_at on the table and the app does not write or read any.
//    * visits have neither column: they are snapshotted into archive_log and then
//      hard-deleted, so archive_log is the only copy and is the reason a failed
//      log write is fatal to archiveVisit.
//
//  RLS notes: `archive_log` is member-wide (migration
//  `20260919020000_archive_log_members.sql`), so any active clinic member can
//  archive, browse, and restore logged records. archive_log writes are wrapped in
//  try/catch so a soft-delete always succeeds even if the log write is blocked,
//  while archiveVisit throws on a failed log write so a visit is never
//  hard-deleted without a recoverable trace.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:intl/intl.dart';
// Prefixed: [ArchivedPatient] declares its own `isCurrentTerm` getter, so the
// shared function of the same name has to be called through a prefix.
import 'package:clinicmanagementsystem/core/patient_directory.dart' as terms;
import 'package:clinicmanagementsystem/core/patient_directory.dart'
    show academicTermLabel;
import 'package:clinicmanagementsystem/services/data_tracker.dart';
// `person_type` is written capitalised (`chk_person_type` allows only
// 'Student' / 'Faculty' / 'Staff'), so both sides go through
// [canonicalCategory] before being compared — the database value and the
// category the reader picked have to be spelled the same way.
import 'package:clinicmanagementsystem/screen/individual_record_data.dart'
    show canonicalCategory;
import 'package:clinicmanagementsystem/services/individual_record_service.dart';
import 'package:clinicmanagementsystem/services/reference_data_service.dart';
import 'package:clinicmanagementsystem/services/supabase_config.dart';
import 'package:clinicmanagementsystem/services/visit_service.dart';

/// An archived person (Archive → People tab).
///
/// "Archived" is not a column. It is the absence of any Active enrolment:
/// [fetchArchivedPatients] finds people whose enrolments are all Archived.
/// `individual_records` has no status column to read, so that is the whole
/// definition, and
/// [IndividualRecordService.archivePerson] is the only thing that sets it.
/// It is deliberate and person-wide — which is what makes it the right thing
/// for this page.
///
/// It is deliberately NOT the same as an Inactive enrolment. A superseded
/// enrolment (`individual_academic_records.status = 'Inactive'`) is what rolling
/// the term forward does to *everybody*, so listing those here would bury the two
/// or three people an administrator actually filed away under hundreds of rows
/// that only look archived. Those rows stay where they belong: readable in the
/// Individual Record history for that person.
///
/// [academicYear] / [semester] are the term the person was last filed under, kept
/// so the page can say where somebody was and so the term filter has something to
/// narrow on. They are context, not a gate: an archived person is restorable
/// whatever term they were last in, because [ArchiveService.restorePatient]
/// brings back the person and their enrolments together.
class ArchivedPatient {
  final String id; // record_no
  final String name;
  final String department; // institute (student, faculty) / office (staff)
  final String position; // year level (student) / position (faculty, staff)
  final String category;
  final String archivedDate; // when the person was filed away
  final String reason;
  final String archivedBy;
  final String uuid; // individual_records.id, used by restore

  /// '2025-2026' / '2nd Semester' — the term this person was last filed under.
  final String academicYear;
  final String semester;

  const ArchivedPatient({
    required this.id,
    required this.name,
    required this.department,
    required this.position,
    required this.category,
    required this.archivedDate,
    required this.reason,
    required this.archivedBy,
    required this.uuid,
    this.academicYear = '',
    this.semester = '',
  });

  /// "2024-2025 · 1st Semester" — how the archive groups and filters rows.
  String get termLabel => academicTermLabel(academicYear, semester);

  /// Whether the last term this person was filed under is the term being run.
  ///
  /// Display only, unlike the old version of this getter: it used to decide
  /// whether the Restore button was offered, because restoring meant putting one
  /// row back on one term's roster. Restoring now goes through `restore_person`
  /// and brings the person and their enrolments back in one transaction, so there
  /// is no term it could be wrong about.
  bool get isCurrentTerm => terms.isCurrentTerm(academicYear, semester);
}

/// Archived medicine row (Trash → Medicines tab).
class ArchivedMedicine {
  final int id;
  final String name;
  final int lastStock;

  const ArchivedMedicine({
    required this.id,
    required this.name,
    required this.lastStock,
  });
}

/// Archived visit record (Trash → Medical Records tab), read from archive_log.
class ArchivedRecord {
  final int logId;
  final String patient;
  final String type;
  final String complaint;
  final String medicine;
  final int qty;
  final String visitDate;
  final String status;
  final String category;
  final Map<String, dynamic> snapshot;

  const ArchivedRecord({
    required this.logId,
    required this.patient,
    required this.type,
    required this.complaint,
    required this.medicine,
    required this.qty,
    required this.visitDate,
    required this.status,
    required this.category,
    this.snapshot = const {},
  });
}

class ArchiveService {
  ArchiveService._();

  /// Just enough of an enrolment for the archive: which term, what affiliation,
  /// and why it stopped being Active. No person embed — the person is the row
  /// this is being read for, and embedding it again would duplicate the whole
  /// identity block once per enrolment.
  /// `individual_academic_records` has one `status` column and no
  /// status_reason / status_changed_by / status_changed_at columns, so there is
  /// nothing to read for a reason or for who archived. [IndividualRecordService
  /// .archivePerson] archives by setting `status = 'Archived'` on the enrolments.
  static const String _lastEnrolmentSelect = '''
    person_id,
    academic_period_id,
    status,
    institute_id,
    program_id,
    year_level,
    department_office_id,
    position_id,
    created_at''';

  static String _ts(DateTime? t) {
    if (t == null) return '—';
    return DateFormat('yyyy-MM-dd').format(t.toLocal());
  }

  static String _who(String? id, Map<String, String> userNames) {
    if (id == null || id.isEmpty || id == '—') return '—';
    final n = userNames[id];
    return (n == null || n.isEmpty) ? id.substring(0, 8) : n;
  }

  /// Loads archived individual records (`status = 'Inactive'`), newest term first.
  ///
  /// Read from `public.individual_records`, which is where the roster actually
  /// lives. This used to read `public.patients` on `is_archived = true`, a table
  /// the app no longer has — every read raised `PGRST205 Could not find the table
  /// 'public.patients'`, which is the whole reason the Archive's People tab came up
  /// empty while the roster had plenty to show.
  ///
  /// [year] and [semester] narrow on the term the person was *last filed under*,
  /// so they filter after the two tables have been stitched rather than being
  /// pushed into a query — they are not columns on either table. Pass null for
  /// either to leave that filter out.
  static Future<List<ArchivedPatient>> fetchArchivedPatients({
    String? year,
    String? semester,
    String? category,
  }) async {
    Map<String, String> userNames = const {};
    try {
      userNames = await _fetchUserNames();
    } catch (_) {}

// ARCHIVED MEANS "NO ACTIVE ENROLMENT", NOT A COLUMN ON THE PERSON
    //
    // `individual_records` has no status column, so the archived people are found
    // the only way the schema allows: by asking the enrolment table which people
    // still have an Active row. PostgREST cannot express
    // `not exists (an Active enrolment)`, so this is two reads and a set
    // subtraction: everyone with an Archived row, minus everyone with an Active
    // one. Both halves are required. Taking only the Archived ids would list a
    // person who was archived last term and re-enrolled this term — their old row
    // is Archived, but they are plainly on today's roster.
    final archivedIds = await supabaseClient
        .from('individual_academic_records')
        .select('person_id')
        .eq('status', 'Archived');

    final activeIds = await supabaseClient
        .from('individual_academic_records')
        .select('person_id')
        .eq('status', 'Active');

    final stillActive = <String>{
      for (final r in activeIds) '${r['person_id']}',
    };

    final ids = <String>{
      for (final r in archivedIds) '${r['person_id']}',
    }..removeWhere(stillActive.contains);

    if (ids.isEmpty) return const [];

    // Still two reads, stitched here rather than joined in PostgREST: "the most
    // recent enrolment of these people" is an ordering *inside* an embed, which is
    // not something a PostgREST select can express. The person list is small by
    // construction - only archived people, never the roster - so fetching their
    // enrolments separately costs one extra round trip and no memory.
    final people = await supabaseClient
        .from('individual_records')
        .select()
        .inFilter('person_id', ids.toList());

    if (people.isEmpty) return const [];

    final enrolments = await supabaseClient
        .from('individual_academic_records')
        .select(
            '$_lastEnrolmentSelect, academic_period:academic_periods(acad_year, semester)')
        .inFilter('person_id', people.map((p) => p['person_id']).toList())
        .order('created_at', ascending: false);

    // Newest enrolment per person. The rows arrive newest first, so the first time
    // a person is seen is the one to keep.
    final latestByPerson = <String, Map<String, dynamic>>{};
    for (final row in enrolments) {
      final m = Map<String, dynamic>.from(row);
      final personId = '${m['person_id'] ?? ''}';
      if (personId.isEmpty || latestByPerson.containsKey(personId)) continue;
      latestByPerson[personId] = m;
    }

    final ay = year?.trim() ?? '';
    final sem = semester?.trim() ?? '';
    final cat = category?.trim() ?? '';

    final out = <ArchivedPatient>[];
    for (final row in people) {
      final m = Map<String, dynamic>.from(row);
      // Canonicalised because the column holds `faculty` / `staff` and [cat] and
      // every comparison below speak the app's `Faculty` / `Staff`. Comparing the
      // raw value filtered every non-student out of the Archive.
      final category = canonicalCategory(m['person_type']);
      if (cat.isNotEmpty && category != canonicalCategory(cat)) continue;

      // `person_id` is the primary key AND the printed number, so one value is
      // both the row's identity and what the Archive lists under.
      final uuid = m['person_id'] as String? ?? '';
      final academic = latestByPerson[uuid] ?? const <String, dynamic>{};
      final period = academic['academic_period'] as Map<String, dynamic>?;
      final academicYear = (period?['acad_year'] as String?) ?? '';
      final term = (period?['semester'] as String?) ?? '';
      if (ay.isNotEmpty && academicYear != ay) continue;
      if (sem.isNotEmpty && term != sem) continue;

      final isStudent = category == 'Student';
      final first = (m['fn'] as String? ?? '').trim();
      final middle = (m['mn'] as String? ?? '').trim();
      final last = (m['ln'] as String? ?? '').trim();
      final name = [first, middle, last].where((e) => e.isNotEmpty).join(' ');

      out.add(ArchivedPatient(
        id: uuid,
        // A person with no name at all still has to read as something in a list of
        // people; their number identifies them, and a blank cell identifies nobody.
        name: name.isEmpty ? 'Unnamed record' : name,
        // The affiliation comes from the enrolment, and the labels come from the
        // catalog because the columns hold ids. Faculty read their institute,
        // staff their office — which is the same split the roster form enforces.
        department: isStudent
            ? ReferenceCatalog.instituteNameOf(
                academic['institute_id'] as String?)
            : ReferenceCatalog.departmentNameOf(
                academic['department_office_id'] as String?),
        position: isStudent
            ? ((academic['year_level'] as String?) ?? '')
            : ReferenceCatalog.positionNameOf(
                academic['position_id'] as String?),
        category: category,
        // Neither table has updated_at, so the person's created_at is the only
        // stamp available. It says when the record was filed, not when it was
        // archived — which is why the label in the Archive does not claim
        // otherwise.
        archivedDate: _ts(_parseTs(m['created_at'])),
        // There is no reason column and no updated_by column on either table, so
        // neither is invented here. Saying "-" is honest; a plausible-looking
        // reason nobody recorded is not.
        reason: _lastReason(academic),
        archivedBy: _who(m['created_by'] as String?, userNames),
        uuid: uuid,
        academicYear: academicYear,
        semester: term,
      ));
    }

    // Newest term first, then surname, so the people filed away most recently are
    // at the top. Sorted here because the term is denormalised through the
    // enrolment and is not a column the query could have ordered on.
    out.sort((a, b) {
      final byYear = b.academicYear.compareTo(a.academicYear);
      if (byYear != 0) return byYear;
      final byTerm = b.semester.compareTo(a.semester);
      if (byTerm != 0) return byTerm;
      return a.name.compareTo(b.name);
    });
    return out;
  }

  /// What the archive shows in its Reason column for an archived person.
  ///
  /// There is no answer to read: neither `individual_records` nor
  /// `individual_academic_records` has a `status_reason` column, and neither has
  /// a `status_changed_at`, so the fact of the archiving is all that was ever
  /// recorded. Saying so is honest. A plausible-looking reason nobody entered
  /// would be worse — the Archive is the page people trust to say what happened.
  ///
  /// The row's own status is used when it is available, so a person whose latest
  /// enrolment was Inactive for some other reason reads as that instead of
  /// being asserted as archived.
  static String _lastReason(Map<String, dynamic> academic) {
    final status = (academic['status'] as String?)?.trim();
    if (status != null && status.isNotEmpty) return status;
    return 'Archived';
  }

  /// Loads archived medicines (is_archived=true).
  static Future<List<ArchivedMedicine>> fetchArchivedMedicines() async {
    final rows = await supabaseClient
        .from('medicines')
        .select()
        .eq('is_archived', true)
        .order('name');
    return rows.map((r) {
      final m = Map<String, dynamic>.from(r);
      return ArchivedMedicine(
        id: m['id'] as int? ?? 0,
        name: m['name'] as String? ?? '',
        lastStock: m['stock'] as int? ?? 0,
      );
    }).toList();
  }

  /// Loads archived visit records from archive_log (Head-only under RLS;
  /// staff will simply receive an empty list).
  static Future<List<ArchivedRecord>> fetchArchivedRecords() async {
    try {
      final rows = await supabaseClient
          .from('archive_log')
          .select()
          .eq('entity_type', 'visit')
          .order('archived_at', ascending: false);
      return rows.map((r) {
        final m = Map<String, dynamic>.from(r);
        final snap = (m['snapshot'] as Map?)?.cast<String, dynamic>() ??
            const <String, dynamic>{};
        return ArchivedRecord(
          logId: m['id'] as int? ?? 0,
          patient: snap['patient_name'] as String? ?? '—',
          type: snap['category'] as String? ?? '—',
          complaint: snap['complaint'] as String? ?? '—',
          medicine: snap['medicine_name'] as String? ?? 'None',
          qty: _asInt(snap['qty']),
          visitDate: DateFormat('yyyy-MM-dd').format(
              _parseTs(snap['visit_date']) ??
                  (_parseTs(m['archived_at']) ?? DateTime.now())),
          status: m['status'] as String? ?? 'Archived',
          category: snap['category'] as String? ?? '—',
          snapshot: snap,
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Soft-archives a medicine.
  static Future<void> archiveMedicine(int id, String name, int stock,
      {required String reason}) async {
    await supabaseClient.from('medicines').update({
      'is_archived': true,
    }).eq('id', id);

    try {
      await supabaseClient.from('archive_log').insert({
        'entity_type': 'medicine',
        'entity_id': id.toString(),
        'reason': reason,
        'status': null,
        'snapshot': {'id': id, 'name': name, 'stock': stock},
      });
    } catch (_) {
      // Non-Head member.
    }
  }

  /// Archives a visit by snapshotting it into archive_log, then — only if the
  /// log write succeeded (Head) — hard-deletes the visit row. For a non-Head
  /// member the archive_log insert is blocked by RLS, so we throw: the visit
  /// must NOT disappear without a recoverable trace.
  static Future<void> archiveVisit(Visit v) async {
    if (v.id == null) {
      throw StateError('Cannot archive a visit without a database id.');
    }
    final stringify = DateFormat('yyyy-MM-dd');
    await supabaseClient
        .from('archive_log')
        .insert({
          'entity_type': 'visit',
          'entity_id': v.id.toString(),
          'reason': 'Archived',
          'status': v.category,
          'snapshot': {
            'id': v.id,
            'patient_id': v.patientId,
            'patient_no': v.patientNo,
            'patient_name': v.patientName,
            'category': v.category,
            'department': v.department,
            'year_position': v.yearPosition,
            'complaint': v.complaint,
            if (v.visitDate != null)
              'visit_date': stringify.format(v.visitDate!),
            'visit_time': v.visitTime,
          },
        })
        .select('id')
        .single();
    await VisitService.delete(v.id!);
  }

  /// Convenience overload used by the Records Booklet, which only holds
  /// `Map<String, String>` rows. Loads the row, then archives it.
  static Future<void> archiveVisitById(int id) async {
    final rows = await supabaseClient.from('visits').select().eq('id', id);
    if (rows.isEmpty) {
      throw StateError('Visit $id no longer exists.');
    }
    final v = Visit.fromSupabase(Map<String, dynamic>.from(rows.first));
    await archiveVisit(v);
  }

  /// Puts an archived person back on the roster of the term they belong to.
  ///
  /// Only meaningful for a row on the term being run — one removed from the
  /// current roster by hand. A row from a term that has ended is refused rather
  /// than quietly reactivated: its `status = 'Inactive'` is how the current
  /// roster is defined, so flipping it would put somebody on today's roster on
  /// the strength of last year's enrolment, and would double them up against
  /// their current-term row. The message says what to do instead.
  ///
  /// `status_reason` and the who/when are cleared as well as the flag, so a
  /// restored row does not still read as a pending removal.
  static Future<void> restorePatient(ArchivedPatient p) async {
    if (p.uuid.isEmpty) return;
    // `restore_person`, not an UPDATE. The person and their enrolments are one
    // decision: flipping `individual_records.status` back to Active on its own
    // would leave Archived enrolments behind it, which is an Active person with no
    // row on any term — invisible on the roster and unexplainable. The RPC does it
    // in one transaction and stamps the audit trail from the session.
    await IndividualRecordService.restorePerson(p.uuid);
    // The roster is a live screen that stays mounted in the dashboard's
    // IndexedStack. Without this it would keep showing the person as archived
    // until the user navigated away and back, which reads as the restore having
    // silently failed.
    DataTracker.bump();
    try {
      await supabaseClient
          .from('archive_log')
          .delete()
          .eq('entity_type', 'patient')
          .eq('entity_id', p.uuid);
    } catch (_) {}
  }

  /// Restores a medicine.
  static Future<void> restoreMedicine(ArchivedMedicine m) async {
    await supabaseClient.from('medicines').update({
      'is_archived': false,
    }).eq('id', m.id);
    try {
      await supabaseClient
          .from('archive_log')
          .delete()
          .eq('entity_type', 'medicine')
          .eq('entity_id', m.id.toString());
    } catch (_) {}
  }

  /// Restores an archived visit record by re-inserting it from its archive_log
  /// snapshot, then removing the log entry. Head-only (both table and RLS).
  static Future<Visit> restoreRecord(ArchivedRecord r) async {
    final snap = r.snapshot;
    final v = await VisitService.create(
      patientId: snap['patient_id']?.toString() ?? '',
      patientNo: snap['patient_no']?.toString() ?? '—',
      patientName: snap['patient_name']?.toString() ?? '—',
      category: snap['category']?.toString() ?? 'Student',
      department: snap['department']?.toString() ?? '',
      yearPosition: snap['year_position']?.toString() ?? '',
      complaint: snap['complaint']?.toString() ?? '',
      visitDate: _parseTs(snap['visit_date']) ?? DateTime.now(),
      visitTime: snap['visit_time']?.toString() ?? '',
    );
    await supabaseClient.from('archive_log').delete().eq('id', r.logId);
    return v;
  }

  /// useraccount.user_id -> "First Last" for the archived-record footer, using
  /// the table's fn / ln columns and falling back to the username.
  static Future<Map<String, String>> _fetchUserNames() async {
    final rows = await supabaseClient
        .from('useraccount')
        .select('user_id, username, fn, ln');
    return {
      for (final r in rows)
        if (r['user_id'] != null) r['user_id'] as String: _nameOf(r),
    };
  }

  static String _nameOf(Map<String, dynamic> row) {
    final name = [
      (row['fn'] as String? ?? '').trim(),
      (row['ln'] as String? ?? '').trim(),
    ].where((s) => s.isNotEmpty).join(' ');
    return name.isNotEmpty ? name : (row['username'] as String? ?? '').trim();
  }

  static DateTime? _parseTs(Object? v) {
    if (v is DateTime) return v;
    if (v is String) return DateTime.tryParse(v);
    return null;
  }

  static int _asInt(Object? v) {
    if (v == null) return 0;
    if (v is int) return v;
    if (v is num) return v.toInt();
    return int.tryParse(v.toString()) ?? 0;
  }
}
