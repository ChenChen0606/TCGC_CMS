// ignore_for_file: avoid_print

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf/pdf.dart';
import 'app_colors.dart';
import 'document_template.dart';
import '../core/patient_directory.dart';
import '../core/visit_details.dart';
import '../services/archive_service.dart';
import '../services/data_tracker.dart';
import '../services/visit_service.dart';
import '../services/procedure_service.dart';
import '../services/individual_record_service.dart';
import '../services/visit_details_service.dart';
import 'individual_record_data.dart';
import 'visit_review_card.dart';
import 'clinic_visit_screen.dart';

/// Returns only the medical records that belong to [institute].
///
/// Each record identifies its patient's program in the "dept" field.
/// Matching is normalized (trimmed + lower-cased) so "IBFS", "ibfs" and
/// "IBFS " are all equivalent, and a record with a missing or empty
/// program is safely skipped instead of crashing.
///
/// * `null` or an empty/blank [institute] → every record (ALL PROGRAMS).
/// * otherwise → only records whose "dept" matches [institute].
List<Map<String, String>> filterRecordsByInstitute(
    List<Map<String, String>> records, String? institute) {
  if (institute == null) return List<Map<String, String>>.from(records);
  final String want = institute.trim().toLowerCase();
  if (want.isEmpty) return List<Map<String, String>>.from(records);
  return records.where((record) {
    final String dept = (record["dept"] ?? "").trim().toLowerCase();
    return dept.isNotEmpty && dept == want;
  }).toList();
}

/// A row's state, as the label and colour the Status column prints it in.
class _VisitState {
  const _VisitState(this.label, this.color);

  final String label;
  final Color color;
}

/// One worked example: the visitor exactly as the table sees them, plus the
/// services ticked and what was entered on each.
///
/// Plain data on purpose. The answers are keyed by the field keys the service's
/// own form uses, so they are read back through `serviceSummary` — the reader a
/// real record goes through — rather than being laid out by hand. An example
/// with its own printing would look right and prove nothing.
class _SampleRecord {
  _SampleRecord({
    required this.record,
    required this.services,
    required this.answers,
    this.prescriptions = const {},
    this.systolic,
    this.diastolic,
    this.heartRate,
  });

  /// The row as the table draws it. Carries a blank `visitId` — a worked
  /// example is not on the database and must not pretend to be.
  final Map<String, String> record;

  /// The services ticked, in the order they were worked in.
  final List<String> services;

  /// What was entered on each service, keyed by that service's own field keys.
  final Map<String, Map<String, dynamic>> answers;

  /// Prescriptions, per service. Kept apart from [answers] because a dose is a
  /// list of rows rather than a value, and writing one into a jsonb blob as if
  /// it were a box is the shape that loses a medicine.
  final Map<String, List<Map<String, dynamic>>> prescriptions;

  final int? systolic;
  final int? diastolic;
  final int? heartRate;
}

class RecordsBooklet extends StatefulWidget {
  // True while the Records Booklet tab is the active dashboard page. The
  // dashboard keeps every page alive in an IndexedStack, so initState runs
  // only once at app launch — without this, newly saved consultations would
  // not appear here until the app was relaunched.
  final bool isActive;

  const RecordsBooklet({super.key, this.isActive = false});

  @override
  State<RecordsBooklet> createState() => RecordsBookletState();
}

class RecordsBookletState extends State<RecordsBooklet> {
  // ── DESIGN TOKENS — matched to the Reports & Patients pages ───────────
  static const Color kPrimary = AppColors.primary;
  static const Color kPrimaryDk = AppColors.primaryDark;
  static const Color kBg = AppColors.bg;
  static const Color kCard = AppColors.surface;
  static const Color kBorder = AppColors.border;
  static const Color kTextMain = AppColors.textMain;
  static const Color kTextDark = AppColors.textDark;
  static const Color kTextSub = AppColors.textSub;
  static const Color kDanger = AppColors.danger;
  static const Color kSuccess = AppColors.success;
  static const Color kWarning = AppColors.warning;

  // Same category accent colors used on the Patients page, so a category
  // reads the same way across the whole app.
  static const Color kStudentColor = AppColors.student;
  static const Color kFacultyColor = AppColors.faculty;
  static const Color kStaffColor = AppColors.staff;

  // Simulated signed-in user — stamped onto records on update, and shown
  // in the audit trail (mirrors `_preparedBy` on the Reports page).
  static const String _currentUser = "Anna Gonzaga";

  // "Today" | "All" | "Custom" (single date) | "Range" (date range)
  String selectedFilter = "Today";
  DateTime selectedDate = DateTime.now();
  DateTimeRange? selectedRange;
  String searchQuery = "";

  // Records compare their "date" (yyyy-MM-dd) against this. Previously a
  // hard-coded simulation date, which is why "Today" never matched visits
  // actually saved on the real clock. Now resolves to the current date.
  static String get _todayStamp =>
      DateFormat("yyyy-MM-dd").format(DateTime.now());

  // The 6 programs offered when printing a Records Booklet. Matching is
  // done against each record's "dept" field.
  static const List<String> _institutes = [
    'IBFS',
    'ICJE',
    'ITE',
    'IHS',
    'ICS',
    'IAS'
  ];

  // The clinic visits to display, loaded from the Supabase `visits` table
  // in `_reloadRecords()`. Each entry carries the audit trail createdBy/At
  // (stamped at intake) and updatedBy/At (set on edit), plus a `visitId`
  // used for DB-backed edits and deletes.
  final List<Map<String, String>> _allRecords = [];

  // All procedures in the system, loaded alongside the visits so each
  // record can be joined to its procedures by `visit_id`. This is what
  // makes a consultation and its procedures show up as one connected
  // history instead of two isolated lists.
  final List<ProcedureRecord> _procedures = [];

  // Every saved visit read back into the shape step 4 renders it in, keyed by
  // visit id.
  //
  // The table needs two things off it on EVERY row — which services were done
  // and what state the visit is in — and the row detail needs the whole of every
  // service behind the row that is clicked. Reading that per row would turn one
  // page into fifty reads, so it is read once for the page and held here. Same
  // object the Clinic Visit wizard holds while it is writing a visit, which is
  // what makes the two screens say the same thing about the same record.
  final Map<String, VisitDetailsController> _savedVisits = {};

  // The worked examples, keyed by the record's id. See [_sampleRecords].
  final Map<String, VisitDetailsController> _sampleVisits = {};

  // Why the last read of `visits` failed, or null when it did not.
  //
  // Held rather than swallowed, because "could not read" and "nothing saved"
  // look identical on this page otherwise — both render five invented visitors
  // — and the second reading is the one that sends somebody hunting for records
  // that were never lost. A read that fails has to say so on the page.
  String? _loadError;

  /// The roster as full records, keyed by the person's printed number.
  ///
  /// The booklet row itself holds only snapshots; the detail view asks for more
  /// — personal and academic information — so the same read that enriches the
  /// table also keeps the full `IndividualRecord` around for the dialog. Read
  /// once per reload, best-effort, and empty for a visit whose person cannot be
  /// matched or for the worked examples.
  final Map<String, IndividualRecord> _rosterById = {};

  /// The worked examples as controllers, built once and shared by the page and
  /// by the tests.
  ///
  /// Exposed because the examples are the only record data this page can be
  /// judged against before there are any real consultations, and "the examples
  /// are complete, cover three categories and carry several services" is a claim
  /// that stops being true the moment someone edits one of them without noticing.
  @visibleForTesting
  static Map<String, VisitDetailsController> buildSampleVisits() =>
      {for (final s in _sampleRecords) s.record["id"] ?? "": _controllerFor(s)};

  VoidCallback? _dataListener;

  @override
  void initState() {
    super.initState();
    _sampleVisits.addAll(buildSampleVisits());
    _reloadRecords();
    _dataListener = () => _reloadRecords();
    DataTracker.listen(_dataListener!);
  }

  @override
  void dispose() {
    if (_dataListener != null) DataTracker.unlisten(_dataListener!);
    super.dispose();
  }

  @override
  void didUpdateWidget(RecordsBooklet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _reloadRecords();
    }
  }

  Future<void> _reloadRecords() async {
    // Set while the examples are standing in, so the table can say so rather
    // than letting five invented visitors pass as real consultations.
    bool usingSamples = false;

    try {
      final rosterFuture = _loadRosterFacts();
      final records = await VisitService.fetchAllBookletRecords();
      final roster = await rosterFuture;
      if (!mounted) return;
      for (final r in records) {
        _enrichFromRoster(r, roster);
      }
      setState(() {
        _allRecords
          ..clear()
          ..addAll(records);
        _loadError = null;
      });
    } catch (e) {
      // Keep whatever is already displayed (offline / RLS-denied read), but say
      // why. A page that quietly shows worked examples while the real read is
      // broken is a page that looks correct and is lying about the clinic's
      // records.
      if (mounted) setState(() => _loadError = _describeReadFailure(e));
    }

    // Nothing saved yet, and nothing that could be read: show the worked examples
    // so the page can be read,
    // judged and fixed before there is a real consultation behind it. They are
    // never written anywhere, and they stand down the moment the first real
    // visit exists — so this cannot become a second, silent source of records.
    if (_allRecords.isEmpty && _sampleRecords.isNotEmpty) {
      usingSamples = true;
      if (mounted) {
        setState(() {
          _allRecords
            ..clear()
            ..addAll([for (final s in _sampleRecords) s.record]);
        });
      }
    }

    // The services behind every row on the page, in one read each.
    final ids = [
      for (final r in _allRecords) (r["visitId"] ?? "").trim(),
    ].where((id) => id.isNotEmpty).toList();
    if (ids.isNotEmpty && !usingSamples) {
      try {
        final saved = await VisitDetailsService.readVisits(ids);
        if (!mounted) return;
        setState(() {
          _savedVisits
            ..clear()
            ..addAll(saved);
        });
      } catch (_) {
        // The table falls back to `visits.complaint` for its service column, so a
        // failed read costs the detail view its answers and not the page its rows.
      }
    }

    // Procedures are best-effort too — they feed the "LINKED PROCEDURES"
    // section inside the record detail dialog.
    try {
      final procedures = await ProcedureService.fetchAll();
      if (!mounted) return;
      setState(() {
        _procedures
          ..clear()
          ..addAll(procedures);
      });
    } catch (_) {
      // Keep whatever is already displayed.
    }
  }

  /// The current roster as the few facts a booklet row needs, keyed by the
  /// person's printed number.
  ///
  /// `clinic_visits` does not snapshot the visitor — it only keeps `person_id` —
  /// so a booklet row must be joined back to `individual_records` for the name,
  /// category, institute and term. Best-effort: if the roster cannot be read
  /// (offline, RLS, no active term) the visits keep whatever snapshots they have.
  Future<Map<String, Map<String, String>>> _loadRosterFacts() async {
    try {
      final roster = await IndividualRecordService.fetchAll(
        includeInactive: false,
      );
      _rosterById
        ..clear()
        ..addEntries(roster.map((r) => MapEntry(r.id, r)));
      return {
        for (final r in roster)
          r.id: {
            "name": r.fullName,
            "type": r.category,
            "institute": r.institute,
            "program": r.program,
            "department": r.department,
            "position": r.position,
            "yearLevel": r.yearLevel,
            "academicYear": r.academicYear,
            "semester": r.semester,
          },
      };
    } catch (_) {
      return const {};
    }
  }

  /// Fills the blanks a booklet row cannot snapshot for itself.
  ///
  /// Only rows whose `personId` matches the roster are touched. Everything here
  /// overrides the row's own snapshot fields, because the roster is newer truth
  /// than the snapshot and the whole point is to fix rows whose snapshots were
  /// never written.
  void _enrichFromRoster(
    Map<String, String> r,
    Map<String, Map<String, String>> roster,
  ) {
    final personId = (r["personId"] ?? "").trim();
    final facts = roster[personId];
    if (facts == null || personId.isEmpty) return;

    String pick(String primary, String fallback) =>
        primary.trim().isEmpty ? fallback : primary;

    r["name"] = facts["name"] ?? r["name"] ?? '';
    // person_id *is* the printed number, so for a real person this is the id.
    r["id"] = personId;
    r["type"] = facts["type"] ?? r["type"] ?? '';

    final category = r["type"] ?? '';
    if (category == 'Staff') {
      r["department"] = facts["department"] ?? '';
      r["position"] = facts["position"] ?? '';
      // `dept` stays a place where a person belongs for the print filter; the
      // desk keeps its own spelling in `department`.
      r["dept"] = pick(facts["department"] ?? '', r["dept"] ?? '');
      r["year"] = pick(facts["position"] ?? '', r["year"] ?? '');
    } else if (category == 'Faculty') {
      r["institute"] = facts["institute"] ?? '';
      r["position"] = facts["position"] ?? '';
      r["dept"] = pick(facts["institute"] ?? '', r["dept"] ?? '');
      r["year"] = pick(facts["position"] ?? '', r["year"] ?? '');
    } else {
      // Student carries institute + program + year level.
      r["institute"] = facts["institute"] ?? '';
      r["program"] = facts["program"] ?? '';
      r["year"] = pick(facts["yearLevel"] ?? '', r["year"] ?? '');
      r["dept"] = pick(facts["institute"] ?? '', r["dept"] ?? '');
    }

    r["academicYear"] = facts["academicYear"] ?? r["academicYear"] ?? '';
    r["semester"] = facts["semester"] ?? r["semester"] ?? '';
  }

  /// The one line a reader gets when `visits` could not be read.
  ///
  /// Names the table and the code, because the difference between "you have no
  /// visits" and "the app is not allowed to read them" decides whether somebody
  /// starts typing records or goes looking at a policy. PostgREST's message is
  /// already written for a human; it just needs the sentence around it.
  String _describeReadFailure(Object e) {
    final raw = e.toString();
    final m = RegExp(r"Could not find the table '([^']+)'").firstMatch(raw);
    if (m != null) {
      return "The clinic visits could not be read: the database has no table "
          "called '${m.group(1)}'. Nothing is lost — the page is showing worked "
          "examples until that is fixed.";
    }
    if (raw.contains('JWT') || raw.contains('JWT') || raw.contains('401')) {
      return 'The clinic visits could not be read: this session is not signed '
          'in, or has expired. Sign in again and the records return.';
    }
    if (raw.contains('42501') || raw.contains('permission denied')) {
      return 'The clinic visits could not be read: this account is not allowed '
          'to read the visits table.';
    }
    return 'The clinic visits could not be read, so this page is showing worked '
        'examples instead of the clinic\'s records.';
  }

  // ── FILTER ────────────────────────────────────────────────────────────

  // The records that actually go into the printed booklet. ONLY the chosen
  // program decides the content — ALL PROGRAMS (null) returns every
  // record. The on-screen date/search controls belong to the interactive
  // table and are intentionally NOT applied to the print, so "ALL
  // PROGRAMS" really means all records, regardless of what the user was
  // browsing on screen.
  List<Map<String, String>> _getPrintRecords({String? institute}) {
    return filterRecordsByInstitute(_allRecords, institute);
  }

  List<Map<String, String>> _getFilteredRecords(
      {String? typeFilter, String? institute}) {
    var filtered = List<Map<String, String>>.from(_allRecords);

    if (institute != null) {
      filtered = filterRecordsByInstitute(filtered, institute);
    }
    if (typeFilter != null) {
      filtered = filtered.where((e) => e["type"] == typeFilter).toList();
    }
    if (searchQuery.isNotEmpty) {
      filtered = filtered
          .where((e) => e.values.join(" ").toLowerCase().contains(searchQuery))
          .toList();
    }
    if (selectedFilter == "Today") {
      filtered = filtered.where((e) => e["date"] == _todayStamp).toList();
    } else if (selectedFilter == "Custom") {
      final String picked = DateFormat("yyyy-MM-dd").format(selectedDate);
      filtered = filtered.where((e) => e["date"] == picked).toList();
    } else if (selectedFilter == "Range" && selectedRange != null) {
      final start = DateTime(selectedRange!.start.year,
          selectedRange!.start.month, selectedRange!.start.day);
      final end = DateTime(selectedRange!.end.year, selectedRange!.end.month,
          selectedRange!.end.day);
      filtered = filtered.where((e) {
        final d = DateTime.tryParse(e["date"]!);
        if (d == null) return false;
        final dOnly = DateTime(d.year, d.month, d.day);
        return !dOnly.isBefore(start) && !dOnly.isAfter(end);
      }).toList();
    }
    return filtered;
  }

  Map<String, int> _getVisitSummary({String? institute}) {
    final all = _getFilteredRecords(institute: institute);
    return {
      "all": all.length,
      "student": all.where((e) => e["type"] == "Student").length,
      "faculty": all.where((e) => e["type"] == "Faculty").length,
      "staff": all.where((e) => e["type"] == "Staff").length,
    };
  }

  // ── DATE / RANGE PICKERS ─────────────────────────────────────────────

  Future<void> _pickDate() async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(2025),
      lastDate: DateTime(2027),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: const ColorScheme.light(
            primary: kPrimary,
            onPrimary: Colors.white,
            onSurface: kTextMain,
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        selectedDate = picked;
        selectedFilter = "Custom";
      });
    }
  }

  // Compact (non-fullscreen) range picker — same pattern as the Reports page.
  Future<void> _pickRange() async {
    final range = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
      initialDateRange: selectedRange,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme:
                Theme.of(context).colorScheme.copyWith(primary: kPrimary),
          ),
          child: Dialog(
            insetPadding:
                const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
              child: child,
            ),
          ),
        );
      },
    );
    if (range != null) {
      setState(() {
        selectedRange = range;
        selectedFilter = "Range";
      });
    }
  }

  // ── A ROW'S SERVICES AND STATE ─────────────────────────────────────────

  /// Everything recorded on one visit, read back into the shape step 4 prints.
  ///
  /// A real row resolves to the controller [VisitDetailsService.readVisits]
  /// built from the database, keyed by the visit id the table already carries. A
  /// worked example resolves to one built here from [_sampleRecords]. Both are
  /// the same object, so nothing downstream has to know which it is looking at —
  /// which is the point: an example that is rendered by a different code path
  /// from a real record proves nothing about how a real record looks.
  VisitDetailsController? _visitFor(Map<String, String> record) {
    final id = (record["visitId"] ?? "").trim();
    if (id.isNotEmpty) {
      final saved = _savedVisits[id];
      if (saved != null) return saved;
    }
    return _sampleVisits[record["id"] ?? ""];
  }

  /// The services on a visit, in the order they were worked in.
  ///
  /// Falls back to `visits.complaint` — which holds the catalog labels the nurse
  /// ticked on step 2, joined — when the service rows have not been read. So the
  /// column names the services on every row even while the detail read is still
  /// in flight or has failed, which is the one thing a table must never do.
  List<String> _serviceNames(Map<String, String> record) {
    final visit = _visitFor(record);
    if (visit != null && visit.drafts.isNotEmpty) {
      return [for (final d in visit.drafts) d.label];
    }
    return (record["complaint"] ?? "")
        .split(',')
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
  }

  /// The visit's own state, read off the services behind it.
  ///
  /// It is deliberately not a stored column of its own. A visit is only as
  /// finished as its least-finished service, so the honest answer is the worst
  /// state behind the row — and that is what a nurse scanning the list is
  /// actually asking.
  _VisitState _stateFor(Map<String, String> record) {
    final drafts = _visitFor(record)?.drafts ?? <ServiceDraft>[];
    if (drafts.isEmpty) return const _VisitState('Not Recorded', kTextSub);
    final done =
        drafts.where((d) => d.status == ServiceDraftStatus.completed).length;
    final started =
        drafts.where((d) => d.status == ServiceDraftStatus.inProgress).length;
    if (done == drafts.length) {
      return const _VisitState('Completed', kSuccess);
    }
    if (done > 0) return const _VisitState('Partly Complete', kWarning);
    if (started > 0) return const _VisitState('In Progress', kWarning);
    return const _VisitState('Not Started', kTextSub);
  }

  /// True while the rows on screen are the worked examples rather than saved
  /// consultations. The page says so, and the edit and delete actions on a row
  /// are not offered, because there is nothing behind them to write to.
  bool _isSample(Map<String, String> record) =>
      _sampleVisits.containsKey(record["id"] ?? "");

  // ── THE WORKED EXAMPLES ────────────────────────────────────────────────
  //
  // Five of them, written out in full — a single-service visit, a visit with
  // several, a finished one, a half-finished one, and all three categories —
  // because a table and a record detail designed against an empty database is a
  // table designed against nothing. These are here to be looked at and argued
  // with.
  //
  // They are not written to the database. They are never edited or deleted, and
  // they are gone the moment the first real consultation is saved, so they can
  // never become a second and quieter source of records.
  static String _dayFromToday(int days) => DateFormat("yyyy-MM-dd")
      .format(DateTime.now().subtract(Duration(days: days)));

  static final List<_SampleRecord> _sampleRecords = [
    _SampleRecord(
      record: {
        "name": "Maria Santos",
        "id": "2024-0182",
        "type": "Student",
        "dept": "IBFS",
        "year": "BS Psychology - 3rd Year",
        "institute": "IBFS",
        "program": "BS Psychology",
        "position": "",
        "academicYear": "2025-2026",
        "semester": "2nd Semester",
        "contact": "0917 555 0142",
        "complaint": "BP Tracking, Medical Consultation",
        "medicine": "Paracetamol 500mg",
        "qty": "10",
        "date": _todayStamp,
        "time": "08:14 AM",
        "timeOut": "08:31 AM",
        "visitId": "",
        "createdBy": _currentUser,
        "createdAt": "08:14 AM",
        "updatedBy": _currentUser,
        "updatedAt": "08:31 AM",
      },
      systolic: 118,
      diastolic: 76,
      heartRate: 72,
      services: [
        'bp_tracking',
        'medicine_consultation',
      ],
      answers: {
        'bp_tracking': {
          'systolic': '118',
          'diastolic': '76',
          'pulse_bpm': '72',
          'position': 'Sitting',
          'arm_used': 'Right',
          'notes': 'Seated, right arm, after five minutes rest.',
        },
        'medicine_consultation': {
          'chief_complaint':
              'Headache and dizziness for 2 days, worse in the mornings.',
          'symptoms': ['Headache', 'Dizziness'],
          'duration_onset': 'Started 2 days ago',
          'history': ['Headache'],
          'history_details': 'No known allergies. Took paracetamol twice '
              'yesterday with some relief.',
          'physical_exam':
              'Alert and oriented. No neck stiffness. Speech clear. '
                  'No visual disturbance reported on exam.',
          'clinical_impression': 'Tension-type headache, likely dehydration.',
          'treatment': ['Advice / Health Education', 'Medication'],
          'medication_service_needed': ['No'],
          'medication_summary': 'Paracetamol 500mg, twice daily as needed',
          'follow_up_needed': ['Yes'],
          'follow_up_instructions':
              'Return if the headache lasts past a week, or if vision changes.',
          'attending': 'Nurse',
          'referral_needed': ['No'],
          'notes': 'Advised on hydration and sleep schedule. BP within normal '
              'limits.',
        },
      },
    ),
    _SampleRecord(
      record: {
        "name": "Rafael Lim",
        "id": "2019-0447",
        "type": "Faculty",
        "dept": "ICJE",
        "year": "Associate Professor - Civil Engineering",
        "institute": "ICJE",
        "program": "",
        "position": "Associate Professor",
        "academicYear": "",
        "semester": "",
        "contact": "0918 555 0290",
        "complaint": "Wound Dressing",
        "medicine": "Povidone-Iodine",
        "qty": "1",
        "date": _todayStamp,
        "time": "09:02 AM",
        "timeOut": "09:24 AM",
        "visitId": "",
        "createdBy": _currentUser,
        "createdAt": "09:02 AM",
        "updatedBy": _currentUser,
        "updatedAt": "09:24 AM",
      },
      services: ['wound_dressing'],
      answers: {
        'wound_dressing': {
          'wound_location': 'Left forearm',
          'wound_type': 'Laceration',
          'wound_condition': 'Healing',
          'wound_length_cm': '3',
          'wound_width_cm': '1.5',
          'cleaning_performed': ['Normal Saline', 'Povidone-Iodine'],
          'medication_applied': ['Povidone-Iodine 10%'],
          'dressing_applied': ['Sterile Gauze', 'Bandage / Roller'],
          'assessment': [
            'Wound edges clean',
            'No signs of infection',
            'Bleeding controlled',
          ],
          'next_dressing_date': _dayFromToday(2),
          'notes': 'Day 3 dressing. Sutures intact, no dehiscence.',
        },
      },
    ),
    _SampleRecord(
      record: {
        "name": "Divine Oduya",
        "id": "S-0913",
        "type": "Staff",
        "dept": "ITE",
        "year": "Laboratory Technician II",
        "institute": "",
        "program": "",
        "department": "Laboratory",
        "position": "Laboratory Technician II",
        "academicYear": "",
        "semester": "",
        "contact": "0920 555 0177",
        "complaint": "Medical Consultation",
        "medicine": "-",
        "qty": "-",
        "date": _todayStamp,
        "time": "10:40 AM",
        "timeOut": "-",
        "visitId": "",
        "createdBy": "Jonah Reyes",
        "createdAt": "10:40 AM",
        "updatedBy": "Jonah Reyes",
        "updatedAt": "10:52 AM",
      },
      systolic: 148,
      diastolic: 96,
      heartRate: 88,
      services: ['medicine_consultation'],
      answers: {
        // Left deliberately part-finished: a consultation that was opened and
        // walked away from is exactly the row the Status column exists for, and
        // an example set where everything is ticked to the last box cannot show
        // that the column works.
        'medicine_consultation': {
          'chief_complaint':
              'Persistent chest heaviness after shift, 5 days now.',
          'symptoms': ['Chest', 'Other'],
          'symptom_other': 'Chest heaviness',
          'duration_onset': 'About a week, gets worse toward the end of shift',
          'history': ['Other'],
          'history_other': 'Hypertension, on medication since 2023',
          'physical_exam':
              'Alert, no distress. Heart sounds regular, no murmur.',
        },
      },
    ),
    _SampleRecord(
      record: {
        "name": "Kayla Bautista",
        "id": "2023-1104",
        "type": "Student",
        "dept": "ICS",
        "year": "BS Computer Science - 4th Year",
        "institute": "ICS",
        "program": "BS Computer Science",
        "position": "",
        "academicYear": "2025-2026",
        "semester": "2nd Semester",
        "contact": "0917 555 0338",
        "complaint": "BP Tracking, Medication, Health Counselling",
        "medicine": "Amlodipine 5mg",
        "qty": "30",
        "date": _todayStamp,
        "time": "01:15 PM",
        "timeOut": "01:58 PM",
        "visitId": "",
        "createdBy": _currentUser,
        "createdAt": "01:15 PM",
        "updatedBy": _currentUser,
        "updatedAt": "01:58 PM",
      },
      systolic: 138,
      diastolic: 88,
      heartRate: 80,
      services: ['bp_tracking', 'medication', 'health_counselling'],
      prescriptions: {
        'medication': [
          {
            'medicine_id': 14,
            'name': 'Amlodipine 5mg',
            'unit': 'tablet',
            'stock_at_pick': 120,
            'quantity': 30,
            'dose': '5mg',
            'frequency': 'once daily',
            'action': 'Given',
            'notes': 'Take in the morning, with or without food.',
          },
        ],
      },
      answers: {
        'medication': {
          'reason': 'Raised her own blood pressure at intake - 138/88.',
          'medication_action': ['Dispensed / Given to Individual'],
          'response': ['Not Observed'],
          'additional_service_needed': ['Yes'],
          'referral_service': 'Health Counselling',
          'referral_reason':
              'Needs the routine and diet changes to go with it.',
          'notes': 'One month supply, with the counselling session booked for '
              'the same visit.',
        },
        'bp_tracking': {
          'systolic': '138',
          'diastolic': '88',
          'pulse_bpm': '80',
          'position': 'Sitting',
          'arm_used': 'Left',
          'resp_rate': '16',
          'action_taken': ['Rechecked after rest', 'Advised on salt intake'],
          'notes':
              'Second reading after 10 minutes, consistent with the first.',
        },
        'health_counselling': {
          'counsellor': 'Jonah Reyes',
          'topic': ['Nutrition / Diet', 'Physical Activity / Exercise'],
          'reason': 'Raised her own blood pressure at intake and is starting '
              'medication today; wants to know what to change in her routine.',
          'provided': [
            'Health Education',
            'Lifestyle / Behavior Advice',
          ],
          'follow_up_needed': ['Yes'],
          'follow_up_reason': 'To review the home readings in two weeks.',
          'follow_up_date': _dayFromToday(14),
          'additional_service_needed': ['No'],
          'notes': 'Discussed sodium intake and a 3x weekly routine.',
        },
      },
    ),
    _SampleRecord(
      record: {
        "name": "Nino Valdez",
        "id": "F-2208",
        "type": "Faculty",
        "dept": "IHS",
        "year": "Instructor - Health Sciences",
        "institute": "IHS",
        "program": "",
        "position": "Instructor",
        "academicYear": "",
        "semester": "",
        "contact": "0919 555 0461",
        "complaint": "Medical Clearance",
        "medicine": "-",
        "qty": "-",
        "date": _todayStamp,
        "time": "03:30 PM",
        "timeOut": "03:41 PM",
        "visitId": "",
        "createdBy": "Jonah Reyes",
        "createdAt": "03:30 PM",
        "updatedBy": "Jonah Reyes",
        "updatedAt": "03:41 PM",
      },
      services: ['medical_clearance'],
      answers: {
        'medical_clearance': {
          'purpose': 'Sports / Intramurals',
          'status': 'Cleared',
          'recommendations': 'Hydrate during events. Stretch before warm-up. '
              'Stop and report any chest pain or dizziness.',
          'validity_date': _dayFromToday(180),
          'notes': 'Cleared for intramurals, one term.',
        },
      },
    ),
  ];

  /// Turns a worked example into the same controller a real visit is read back
  /// into, so the detail view downstream has one path and not two.
  static VisitDetailsController _controllerFor(_SampleRecord s) {
    final c = VisitDetailsController(serviceIds: s.services);
    c.vitals
      ..systolic = s.systolic
      ..diastolic = s.diastolic
      ..heartRate = s.heartRate;
    for (final d in c.drafts) {
      final answers = s.answers[d.serviceId];
      if (answers == null && s.prescriptions[d.serviceId] == null) continue;
      if (answers != null) {
        // Straight into `data`, the same way `_seeded` writes a prefilled box:
        // the nurse did not type any of this in front of the widget, so it must
        // not make the service look half-entered on the way in.
        d.data.addAll(answers);
      }
      for (final m
          in s.prescriptions[d.serviceId] ?? const <Map<String, dynamic>>[]) {
        d.medicines.add(MedicineDose.fromJson(m));
      }
      d.refreshStatus();
    }
    return c;
  }

  // ── FORMATTING HELPERS ───────────────────────────────────────────────

  String _fmtDisplayDate(String yyyyMmDd) {
    // A visit with no `visit_date` is real — the column is nullable — so this
    // prints an em dash rather than leaving the cell empty. A blank cell reads as
    // "the app failed to load this"; a dash reads as "this was never recorded".
    if (yyyyMmDd.trim().isEmpty) return '—';
    try {
      final d = DateFormat("yyyy-MM-dd").parse(yyyyMmDd);
      return DateFormat("MMM d, yyyy").format(d);
    } catch (_) {
      return yyyyMmDd;
    }
  }

  String _fmtShort(DateTime d) => DateFormat("MMM d, yyyy").format(d);

// ── ROW DETAIL ────────────────────────────────────────────────────────
  //
  // Everything about one visit, printed the way step 4 of the Clinic Visit
  // wizard printed it on the way in: the visitor, the services, one card per
  // service with everything that was entered on it, and the record itself.
  //
  // The rows come from `serviceSummary` and the frame from `VisitReviewCard`,
  // both shared with the wizard. This is the whole point of the layout: a record
  // read back three weeks later is the record somebody confirmed three weeks
  // ago, and the one place allowed to disagree about it is the place a clinic
  // looks when something has gone wrong.
  //
  // What used to be here was a flat list of six fields — complaint, medicine,
  // quantity — which could only ever say what the `visits` row happened to hold
  // and threw away every answer given on any of the forms.
  //
  // A row opens into a compact summary that floats over the table — the same
  // "container" the Individual Records roster opens its rows into — so looking
  // at one visit never leaves the page. The header, the cards and the actions
  // are the same widgets the page used to show; only the carrier (a dialog
  // instead of a route) changed.
  void _showDetailDialog(Map<String, String> record) {
    final visit = _visitFor(record);
    final services = _serviceNames(record);
    final state = _stateFor(record);
    final sample = _isSample(record);
    final procedures = _linkedProcedures(record["visitId"] ?? "");
    final person =
        _rosterById[(record["personId"] ?? record["id"] ?? '').trim()];
    final category = (person?.category ?? record["type"] ?? '').trim();

    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        backgroundColor: kCard,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 660, maxHeight: 720),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _detailHeader(record, person, category, state),
                const SizedBox(height: 18),
                const Divider(color: kBorder, height: 1),
                const SizedBox(height: 6),
                Flexible(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: _detailBody(
                      record: record,
                      person: person,
                      category: category,
                      visit: visit,
                      services: services,
                      sample: sample,
                      procedures: procedures,
                    ),
                  ),
                ),
                if (!sample) ...[
                  const SizedBox(height: 8),
                  const Divider(color: kBorder, height: 1),
                  const SizedBox(height: 14),
                  // A worked example has no row behind it in the database, so
                  // it gets no buttons that would edit or delete nothing.
                  _detailFooter(record),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _detailFooter(Map<String, String> record) {
    return Row(children: [
      Expanded(
        child: OutlinedButton.icon(
          onPressed: () {
            Navigator.pop(context);
            _showDeleteConfirmDialog(record);
          },
          icon: const Icon(Icons.delete_outline_rounded,
              size: 16, color: kDanger),
          label: const Text("Delete", style: TextStyle(color: kDanger)),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: kBorder),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(vertical: 13),
          ),
        ),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: OutlinedButton.icon(
          onPressed: () {
            Navigator.pop(context);
            _openVisitEditor(record);
          },
          icon: const Icon(Icons.edit_outlined, size: 16, color: kPrimary),
          label: const Text("Edit Record", style: TextStyle(color: kPrimary)),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: kBorder),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(vertical: 13),
          ),
        ),
      ),
    ]);
  }

  /// The record opened up in the same order the Individual Records roster uses:
  /// who the person is, their academic or employment information, the services
  /// they were seen for — each with its own answers — and the record's own date,
  /// time and recorder.
  Widget _detailBody({
    required Map<String, String> record,
    required IndividualRecord? person,
    required String category,
    required VisitDetailsController? visit,
    required List<String> services,
    required bool sample,
    required List<ProcedureRecord> procedures,
  }) {
    final isStudent = category == 'Student';
    final isFaculty = category == 'Faculty';

    // A real visit is joined to its person, so the whole personal record prints.
    // A worked example names nobody in the registry, so it falls back to the
    // little the row itself carries.
    final personalRows = person != null
        ? <Widget>[
            _infoRow('First Name', person.firstName),
            _infoRow('Middle Name', person.middleName),
            _infoRow('Last Name', person.lastName),
            _infoRow('Suffix', person.suffix),
            _infoRow('Sex', person.sex),
            _infoRow(
                'Birth Date',
                person.birthDate == null
                    ? ''
                    : DateFormat('MMMM d, yyyy').format(person.birthDate!)),
            _infoRow('Contact', person.contact),
            _infoRow('Email', person.email),
            _infoRow('Address', person.address),
          ]
        : <Widget>[
            _infoRow('Name', record["name"] ?? ''),
            _infoRow('Record No', record["id"] ?? ''),
            _infoRow('Role', category),
            if ((record["contact"] ?? '').trim().isNotEmpty)
              _infoRow('Contact', record["contact"]!),
          ];

    // Academic / employment, read the way the roster reads it: a student has a
    // programme and a year level, a teacher an institute and a post, a staff
    // member an office and a post.
    final academicRows = <Widget>[
      _infoRow(
          'School Year', person?.academicYear ?? record["academicYear"] ?? ''),
      _infoRow('Semester', person?.semester ?? record["semester"] ?? ''),
      if (isStudent) ...[
        _infoRow('Institute', person?.institute ?? record["institute"] ?? ''),
        _infoRow('Program', person?.program ?? record["program"] ?? ''),
        _infoRow('Year Level', person?.yearLevel ?? record["year"] ?? ''),
      ] else if (isFaculty) ...[
        _infoRow('Institute', person?.institute ?? record["institute"] ?? ''),
        _infoRow('Position',
            person?.position ?? record["position"] ?? record["year"] ?? ''),
      ] else ...[
        _infoRow('Department / Office',
            person?.department ?? record["department"] ?? record["dept"] ?? ''),
        _infoRow('Position',
            person?.position ?? record["position"] ?? record["year"] ?? ''),
      ],
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _infoSection(
            'Personal Information', Icons.person_outline, personalRows),
        _infoSection(
          isStudent
              ? 'Academic Information'
              : (isFaculty ? 'Teaching Assignment' : 'Employment Information'),
          isStudent ? Icons.school_outlined : Icons.work_outline,
          academicRows,
        ),
        _sectionHeader('Services & Records', Icons.fact_check_outlined),
        const SizedBox(height: 4),
        // The count and the names, because a visit can carry one service or six
        // and "BP Tracking, Medical Consultation" as a single line says neither
        // which nor how many.
        if (visit == null)
          _emptyServicesNote(services)
        else
          for (final draft in visit.drafts) ...[
            VisitReviewCard(
              title: draft.label,
              lines: visitReviewAnswerLines(draft, visit.vitals),
              trailing: _draftStatePill(draft),
            ),
            const SizedBox(height: 10),
          ],
        if (procedures.isNotEmpty) ...[
          _sectionHeader('Linked Procedures', Icons.link_rounded),
          const SizedBox(height: 10),
          ...procedures.map(_procedureTile),
        ],
        if (sample) ...[
          const SizedBox(height: 14),
          _noteBanner(
            kWarning,
            Icons.science_outlined,
            'This is one of the page\'s worked examples, not a saved '
            'consultation. It is shown while the clinic has no records of its '
            'own, cannot be edited or deleted, and disappears as soon as the '
            'first real visit is saved.',
          ),
        ],
        _infoSection('Record Information', Icons.history_rounded, [
          _infoRow('Date', _fmtDisplayDate(record["date"] ?? '')),
          _infoRow('Time in', record["time"] ?? ''),
          // "-" and not a dash the reader has to interpret: a visit still open
          // has no out-time, and that is a fact about the visit rather than a
          // missing value.
          _infoRow('Time out', record["timeOut"] ?? '-'),
          _infoRow('Recorded by', record["createdBy"] ?? '-'),
          if ((record["complaint"] ?? '').trim().isNotEmpty)
            _infoRow('Complaint', record["complaint"]!),
        ]),
      ],
    );
  }

  /// The detail dialog's header — same palette as the Individual Records
  /// roster: a category-coloured glyph, the name, and a row of pills.
  Widget _detailHeader(
    Map<String, String> record,
    IndividualRecord? person,
    String category,
    _VisitState state,
  ) {
    final color = _categoryColor(category);
    final isStudent = category == 'Student';
    final ay = (person?.academicYear ?? record["academicYear"] ?? '').trim();
    final sem = (person?.semester ?? record["semester"] ?? '').trim();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            isStudent
                ? Icons.person_outline_rounded
                : Icons.work_outline_rounded,
            color: Colors.white,
            size: 22,
          ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(record["name"] ?? '',
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: kTextMain),
                  overflow: TextOverflow.ellipsis),
              const SizedBox(height: 5),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(category.isEmpty ? 'Unassigned' : category,
                        style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: color)),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF1F5F9),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(record["id"] ?? '',
                        style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: kTextSub)),
                  ),
                  if (ay.isNotEmpty || sem.isNotEmpty)
                    Text('AY $ay · $sem',
                        style:
                            const TextStyle(fontSize: 12.5, color: kTextSub)),
                  _statusPill(state),
                ],
              ),
            ],
          ),
        ),
        IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.close_rounded, color: kTextSub),
          iconSize: 20,
        ),
      ],
    );
  }

  Color _categoryColor(String category) => category == 'Student'
      ? kStudentColor
      : category == 'Faculty'
          ? kFacultyColor
          : kStaffColor;

  Widget _sectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Row(children: [
        Icon(icon, size: 16, color: kPrimary),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: kTextMain,
                letterSpacing: 0.3)),
        const SizedBox(width: 12),
        const Expanded(child: Divider(color: kBorder, height: 1)),
      ]),
    );
  }

  /// A titled block of `label / value` rows, laid out in one column on a narrow
  /// dialog and two when it is wide enough — the roster's section shape.
  Widget _infoSection(String title, IconData icon, List<Widget> rows) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _sectionHeader(title, icon),
      const SizedBox(height: 12),
      LayoutBuilder(builder: (context, c) {
        final twoCol = c.maxWidth > 460;
        final pairs = <Widget>[];
        for (var i = 0; i < rows.length; i += (twoCol ? 2 : 1)) {
          final end = (i + (twoCol ? 2 : 1)).clamp(0, rows.length);
          pairs.add(Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: rows[i]),
              if (twoCol && end - i == 2) ...[
                const SizedBox(width: 16),
                Expanded(child: rows[i + 1]),
              ],
            ]),
          ));
        }
        return Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: pairs);
      }),
    ]);
  }

  Widget _infoRow(String label, String value) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: const TextStyle(
              fontSize: 11.5, color: kTextSub, fontWeight: FontWeight.w600)),
      const SizedBox(height: 2),
      Text(value.trim().isEmpty ? '—' : value,
          style: const TextStyle(
              fontSize: 14.5, color: kTextMain, fontWeight: FontWeight.w600)),
    ]);
  }

  /// A visit whose service rows could not be read.
  ///
  /// Said out loud rather than replaced by an empty card: a reader who cannot
  /// tell "nothing was recorded" from "we could not load it" will take the first
  /// to be the truth.
  Widget _emptyServicesNote(List<String> services) {
    return _noteBanner(
      kWarning,
      Icons.cloud_off_outlined,
      services.isEmpty
          ? 'No services were recorded on this visit.'
          : 'The ${services.length} service'
              '${services.length == 1 ? '' : 's'} on this visit could not have '
              'their answers loaded. They are stored on the server and come back '
              'on the next read.',
    );
  }

  /// The state of one service, small enough to sit in a card's title row.
  Widget _draftStatePill(ServiceDraft draft) {
    final Color color = draft.isComplete
        ? kSuccess
        : draft.status == ServiceDraftStatus.notStarted
            ? kTextSub
            : kWarning;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        draft.status.label,
        style:
            TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: color),
      ),
    );
  }

  /// A line of explanation, in the colour of what kind of thing it is.
  ///
  /// Used here for the two things the record detail has to be honest about: a
  /// visit whose answers could not be loaded, and a row that is one of the
  /// worked examples rather than a real consultation. Both are better said in
  /// words than shown as an empty card.
  Widget _noteBanner(Color color, IconData icon, String message) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                  fontSize: 12.5,
                  height: 1.35,
                  color: color,
                  fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  // ── EDIT → CLINIC VISIT WIZARD ────────────────────────────────────────

  /// Opens the visit in the Clinic Visit wizard, in edit mode.
  ///
  /// The old quick dialog edited complaint / medicine / qty — three fields the
  /// `clinic_visits` row barely holds and none of the service forms, which is
  /// where every real answer lives. The wizard already knows how to record a
  /// visit, so correcting one goes through the same screens: seeded with the
  /// visitor, the services and the answers as they are on file, saving back to
  /// the same visit id. The page reloads on return, so the table and the detail
  /// view show the corrected record rather than the copy this was opened from.
  Future<void> _openVisitEditor(Map<String, String> record) async {
    final visitId = (record["visitId"] ?? '').trim();
    if (visitId.isEmpty) return;

    final person =
        _rosterById[(record["personId"] ?? record["id"] ?? '').trim()];
    if (person == null) {
      // Without the roster record the wizard has no visitor to seed and would
      // open against nobody. Say so rather than filing an edit nobody asked for.
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'This visitor is not on the current roster, so the visit cannot be edited here.'),
        backgroundColor: kWarning,
        behavior: SnackBarBehavior.floating,
      ));
      return;
    }

    final visit = _visitFor(record);
    final drafts = visit?.drafts ?? const <ServiceDraft>[];

    await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ClinicVisitScreen(
          userName: _currentUser,
          editVisitId: visitId,
          editVisitor: person,
          editServiceIds: [for (final d in drafts) d.serviceId],
          editServiceData: {
            for (final d in drafts) d.serviceId: d.toJson(),
          },
          editVitals: visit?.vitals,
          editMedicines: visit?.draftFor('medication')?.medicines,
          editCheckedInAt: _checkedInFromRecord(record),
          editReasonForVisit: record["complaint"],
        ),
      ),
    );
    if (!mounted) return;
    await _reloadRecords();
  }

  /// The visit's check-in as a `DateTime`, from the booklet row's date and time.
  ///
  /// Best-effort: the row's time is display text ("10:30 AM"), and an edit that
  /// cannot parse it still opens — the check-in is then taken from the clock,
  /// the same thing a fresh visit does.
  DateTime? _checkedInFromRecord(Map<String, String> record) {
    final date = (record["date"] ?? '').trim();
    if (date.isEmpty) return null;
    final time = (record["time"] ?? '').trim();
    final stamp = '$date ${time.isEmpty || time == '-' ? '12:00 AM' : time}';
    return DateFormat('yyyy-MM-dd hh:mm a').tryParse(stamp) ??
        DateTime.tryParse(date);
  }

  // ── DELETE CONFIRMATION ───────────────────────────────────────────────

  void _showDeleteConfirmDialog(Map<String, String> e) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        backgroundColor: Colors.white,
        child: SizedBox(
          width: 300,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: kDanger.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.delete_outline_rounded,
                    color: kDanger, size: 22),
              ),
              const SizedBox(height: 12),
              const Text("Delete Record",
                  style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      color: kTextMain)),
              const SizedBox(height: 6),
              const Text("Are you sure you want to delete this record?",
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12, color: kTextSub, height: 1.5)),
              const SizedBox(height: 20),
              Row(children: [
                Expanded(
                    child: OutlinedButton(
                  onPressed: () => Navigator.pop(context),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: kBorder),
                    foregroundColor: kTextSub,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: const Text("Cancel", style: TextStyle(fontSize: 12)),
                )),
                const SizedBox(width: 10),
                Expanded(
                    child: ElevatedButton(
                  onPressed: () async {
                    final String visitId = e["visitId"] ?? "";
                    if (visitId.isNotEmpty) {
                      try {
                        await ArchiveService.archiveVisitById(
                            int.parse(visitId));
                        await _reloadRecords();
                        if (!mounted) return;
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          backgroundColor: kDanger,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10)),
                          content: const Row(children: [
                            Icon(Icons.check_circle_outline,
                                color: Colors.white, size: 18),
                            SizedBox(width: 10),
                            Text("Record moved to Trash.",
                                style: TextStyle(color: Colors.white)),
                          ]),
                          duration: const Duration(seconds: 2),
                        ));
                      } catch (err) {
                        if (!mounted) return;
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                          content: Text('Could not archive record: $err'),
                          backgroundColor: kDanger,
                          behavior: SnackBarBehavior.floating,
                        ));
                      }
                    } else {
                      setState(() => _allRecords.remove(e));
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                        backgroundColor: kDanger,
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        content: const Row(children: [
                          Icon(Icons.check_circle_outline,
                              color: Colors.white, size: 18),
                          SizedBox(width: 10),
                          Text("Record deleted.",
                              style: TextStyle(color: Colors.white)),
                        ]),
                        duration: const Duration(seconds: 2),
                      ));
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kDanger,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  child: const Text("Delete",
                      style:
                          TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                )),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  // ── PROGRAM PICKER ───────────────────────────────────────────────────
  // Lets the user choose which program to print before generating the
  // Records Booklet. "All Programs" keeps the previous behavior.

  // Lets the user pick program + paper size + orientation, then opens the
  // print preview. Returns (institute?, PdfPageFormat) or null if cancelled.
  Future<void> _showInstitutePicker() async {
    // Ordered exactly as the client requested: IBFS, ICJE, ITE, IHS, ICS, IAS, ALL PROGRAMS.
    final List<String> choices = [..._institutes, "ALL PROGRAMS"];

    String selected = "ALL PROGRAMS";
    String paperKey = "A4";
    bool landscape = true;

    final ({String? institute, PdfPageFormat format})? result =
        await showDialog<({String? institute, PdfPageFormat format})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          return Dialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            backgroundColor: Colors.white,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 380, maxWidth: 380),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(children: [
                      Icon(Icons.print_outlined, color: kPrimary, size: 20),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text("Print Records Booklet",
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                                color: kTextMain)),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    const Text(
                        "Select a program to include in the printed records.",
                        style: TextStyle(fontSize: 12, color: kTextSub)),
                    const SizedBox(height: 16),
                    Flexible(
                      child: SingleChildScrollView(
                        child: Column(
                          children: [
                            ...choices.map((label) {
                              final bool isSelected = selected == label;
                              return Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: SizedBox(
                                  width: double.infinity,
                                  child: InkWell(
                                    onTap: () =>
                                        setDialogState(() => selected = label),
                                    borderRadius: BorderRadius.circular(12),
                                    child: AnimatedContainer(
                                      duration:
                                          const Duration(milliseconds: 150),
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 14, vertical: 12),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? kPrimary.withValues(alpha: 0.08)
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color:
                                              isSelected ? kPrimary : kBorder,
                                          width: isSelected ? 1.5 : 1,
                                        ),
                                      ),
                                      child: Row(children: [
                                        Icon(
                                          label == "ALL INSTITUTES"
                                              ? Icons.layers_outlined
                                              : Icons.school_outlined,
                                          size: 17,
                                          color:
                                              isSelected ? kPrimary : kTextSub,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(label,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: isSelected
                                                    ? FontWeight.w700
                                                    : FontWeight.w500,
                                                color: isSelected
                                                    ? kPrimary
                                                    : kTextMain,
                                              )),
                                        ),
                                        Icon(
                                          isSelected
                                              ? Icons.radio_button_checked
                                              : Icons.radio_button_off,
                                          size: 18,
                                          color:
                                              isSelected ? kPrimary : kBorder,
                                        ),
                                      ]),
                                    ),
                                  ),
                                ),
                              );
                            }),
                            const SizedBox(height: 14),
                            PaperFormatPicker(
                              paperKey: paperKey,
                              landscape: landscape,
                              onPaper: (key) =>
                                  setDialogState(() => paperKey = key),
                              onOrientation: (value) =>
                                  setDialogState(() => landscape = value),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Navigator.pop(ctx),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: kBorder),
                            foregroundColor: kTextSub,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text("Cancel"),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () => Navigator.pop(
                            ctx,
                            (
                              institute:
                                  selected == "ALL PROGRAMS" ? null : selected,
                              format:
                                  PaperFormat.formatFor(paperKey, landscape),
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kPrimary,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          child: const Text("Review & Print",
                              style: TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 12)),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );

    if (result == null) return; // Cancelled — do not open print preview.
    await _showPrintPreview(
        institute: result.institute, initialFormat: result.format);
  }

  // ── PRINT PREVIEW ───────────────────────────────────────────────────
  // Full-screen in-app preview that renders the REAL PDF for the chosen
  // program + paper size. Its toolbar lets the user switch between
  // A4 / Letter / Legal and orientation, then print through the OS dialog
  // (the same `Printing.layoutPdf` used before the preview step existed).

  Future<void> _showPrintPreview(
      {String? institute, required PdfPageFormat initialFormat}) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog.fullscreen(
        child: Scaffold(
          backgroundColor: kBg,
          appBar: AppBar(
            backgroundColor: Colors.white,
            foregroundColor: kTextMain,
            elevation: 0.5,
            titleSpacing: 20,
            title: Text('Print Preview — ${institute ?? 'All Programs'}',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            leading: IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Close preview',
              onPressed: () => Navigator.pop(ctx),
            ),
          ),
          body: PdfPreview(
            pdfFileName: 'TCGC_Medical_Records_Booklet.pdf',
            initialPageFormat: initialFormat,
            pageFormats: const <String, PdfPageFormat>{
              'A4': PdfPageFormat.a4,
              'Letter': PdfPageFormat.letter,
              'Legal': PdfPageFormat.legal,
            },
            canChangePageFormat: true,
            canChangeOrientation: true,
            canDebug: false,
            allowSharing: false,
            build: (format) async =>
                (await _buildDocument(institute: institute, pageFormat: format))
                    .save(),
          ),
        ),
      ),
    );
  }

  // ── PDF BUILDER (Today / single date / date range / all — whatever is
  //    currently selected/filtered on screen) ─────────────────────────
  // The page size comes from the caller (A4/Letter/Legal × orientation),
  // so the margins and table automatically adapt to each format.

  Future<pw.Document> _buildDocument(
      {String? institute, required PdfPageFormat pageFormat}) async {
    final doc = pw.Document();
    // The booklet is driven purely by the selected program: the chosen
    // records (or ALL of them) appear regardless of the on-screen date or
    // search filters.
    final records = _getPrintRecords(institute: institute);
    final Map<String, int> summary = {
      "all": records.length,
      "student": records.where((e) => e["type"] == "Student").length,
      "faculty": records.where((e) => e["type"] == "Faculty").length,
      "staff": records.where((e) => e["type"] == "Staff").length,
    };
    final headers = [
      "ID",
      "Name",
      "Type",
      "Dept",
      "Year/Pos",
      "Complaint",
      "Medicine",
      "Qty",
      "Date",
      "Time"
    ];
    final tableData = records
        .map((e) => [
              e["id"]!,
              e["name"]!,
              e["type"]!,
              e["dept"]!,
              e["year"]!,
              e["complaint"]!,
              e["medicine"]!,
              e["qty"]!,
              e["date"]!,
              e["time"]!
            ])
        .toList();

    // Program chosen for this print, e.g. "ICS" or "All Programs".
    final instituteLabel = institute ?? 'All Programs';

    // Coverage span of this booklet. Program filtering is date-agnostic,
    // so the label always reads "All Records".
    final coverageLabel = "All Records ($instituteLabel)";

    // Official school/clinic logos on the header (best-effort — if a logo
    // asset is missing the header simply shows the school name only).
    final pw.Widget tcgcLogo = await _loadLogo('asset/tcgc.png');
    final pw.Widget clinicLogo = await _loadLogo('asset/cliniclogo.png');

    final bool isLandscape = pageFormat.width > pageFormat.height;
    // Portrait gets wider side margins so the long table stays legible.
    final pw.EdgeInsets margin = isLandscape
        ? const pw.EdgeInsets.fromLTRB(26, 30, 26, 30)
        : const pw.EdgeInsets.fromLTRB(34, 38, 34, 36);

    doc.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        margin: margin,
        header: (pw.Context context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: [
                tcgcLogo,
                pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.center,
                    children: [
                      pw.Text('TANGUB CITY GLOBAL COLLEGE',
                          style: pw.TextStyle(
                              fontSize: isLandscape ? 13 : 12,
                              fontWeight: pw.FontWeight.bold,
                              letterSpacing: 0.6)),
                      pw.SizedBox(height: 2),
                      pw.Text('School Clinic System',
                          style: const pw.TextStyle(
                              fontSize: 10, color: PdfColors.grey700)),
                    ]),
                clinicLogo,
              ],
            ),
            pw.SizedBox(height: 10),
            pw.Divider(color: PdfColors.teal, thickness: 1.2),
            pw.SizedBox(height: 8),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text('MEDICAL RECORDS BOOKLET',
                    style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColors.teal800)),
                pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.end,
                    children: [
                      pw.Text('Program: $instituteLabel',
                          style: const pw.TextStyle(
                              fontSize: 8.5, color: PdfColors.grey700)),
                      pw.Text('Coverage: $coverageLabel',
                          style: const pw.TextStyle(
                              fontSize: 8.5, color: PdfColors.grey700)),
                      pw.Text(
                          'Total: ${summary['all']}  |  Students: ${summary['student']}  |  Faculty: ${summary['faculty']}  |  Staff: ${summary['staff']}',
                          style: const pw.TextStyle(
                              fontSize: 8.5, color: PdfColors.grey600)),
                    ]),
              ],
            ),
            pw.SizedBox(height: 8),
          ],
        ),
        footer: (pw.Context context) => pw.Column(children: [
          pw.Divider(color: PdfColors.grey300),
          pw.SizedBox(height: 4),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('Tangub City Global College • School Clinic System',
                  style: const pw.TextStyle(
                      fontSize: 7.5, color: PdfColors.grey500)),
              pw.Text(
                  'Generated: ${DateFormat('MMM d, yyyy hh:mm a').format(DateTime.now())}  ·  Page ${context.pageNumber} of ${context.pagesCount}',
                  style: const pw.TextStyle(
                      fontSize: 7.5, color: PdfColors.grey500)),
            ],
          ),
        ]),
        build: (pw.Context context) => [
          pw.Table(
            border: pw.TableBorder.all(color: PdfColors.grey300, width: 0.5),
            columnWidths: {
              0: const pw.FlexColumnWidth(1.2),
              1: const pw.FlexColumnWidth(2.0),
              2: const pw.FlexColumnWidth(1.0),
              3: const pw.FlexColumnWidth(1.0),
              4: const pw.FlexColumnWidth(1.2),
              5: const pw.FlexColumnWidth(2.0),
              6: const pw.FlexColumnWidth(1.5),
              7: const pw.FlexColumnWidth(0.5),
              8: const pw.FlexColumnWidth(1.2),
              9: const pw.FlexColumnWidth(1.1)
            },
            children: [
              pw.TableRow(
                decoration: const pw.BoxDecoration(color: PdfColors.teal),
                children: headers
                    .map((h) => pw.Padding(
                          padding: const pw.EdgeInsets.symmetric(
                              horizontal: 5, vertical: 7),
                          child: pw.Text(h,
                              style: pw.TextStyle(
                                  fontSize: 8.5,
                                  fontWeight: pw.FontWeight.bold,
                                  color: PdfColors.white),
                              textAlign: pw.TextAlign.center),
                        ))
                    .toList(),
              ),
              ...tableData.asMap().entries.map((entry) {
                final isEven = entry.key % 2 == 0;
                return pw.TableRow(
                  decoration: pw.BoxDecoration(
                      color: isEven ? PdfColors.white : PdfColors.teal50),
                  children: entry.value
                      .map((cell) => pw.Padding(
                            padding: const pw.EdgeInsets.symmetric(
                                horizontal: 5, vertical: 6),
                            child: pw.Text(cell,
                                style: const pw.TextStyle(fontSize: 8),
                                textAlign: pw.TextAlign.center),
                          ))
                      .toList(),
                );
              }),
            ],
          ),
          // Signature lines — only facts that already exist in the system
          // (the signed-in user's name + role) are printed here.
          if (records.isNotEmpty) ...[
            pw.SizedBox(height: 18),
            _signatureSection(),
          ],
        ],
      ),
    );

    return doc;
  }

  // Loads a bundled logo as a fixed-size pdf widget. A missing file falls
  // back to an invisible placeholder so the header row stays balanced.
  Future<pw.Widget> _loadLogo(String assetPath) async {
    try {
      final bytes = (await rootBundle.load(assetPath)).buffer.asUint8List();
      return pw.Image(pw.MemoryImage(bytes),
          width: 42, height: 42, fit: pw.BoxFit.contain);
    } catch (_) {
      return pw.SizedBox(width: 42, height: 42);
    }
  }

  // Prepared-by / Noted-by signature block at the end of the booklet.
  pw.Widget _signatureSection() {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.start, children: [
          pw.Text('Prepared by:',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 26),
          pw.Container(width: 180, height: 0.6, color: PdfColors.black),
          pw.SizedBox(height: 5),
          pw.Text(_currentUser,
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          pw.Text('Clinic Head',
              style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
        ]),
        pw.Column(crossAxisAlignment: pw.CrossAxisAlignment.end, children: [
          pw.Text('Noted by:',
              style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold)),
          pw.SizedBox(height: 26),
          pw.Container(width: 180, height: 0.6, color: PdfColors.black),
          pw.SizedBox(height: 5),
          pw.SizedBox(height: 11),
          pw.Text('(Signature)',
              style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600)),
        ]),
      ],
    );
  }

  // ── BUILD ─────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final summary = _getVisitSummary();

    // Single DefaultTabController shared by the tab bar AND the
    // TabBarView below, so tapping All / Student / Faculty / Staff
    // actually switches (and filters) the table. (The previous version
    // had two separate controllers — one wrapping the tab bar, another
    // wrapping the TabBarView — so taps on the bar never reached the view.)
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        backgroundColor: kBg,
        floatingActionButton: FloatingActionButton(
          onPressed: _showInstitutePicker,
          backgroundColor: kPrimary,
          child: const Icon(Icons.print_outlined, color: Colors.white),
        ),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeaderRow(summary),
                const SizedBox(height: 20),
                _buildSearchAndFilters(),
                const SizedBox(height: 16),
                _buildTabsBar(),
                const SizedBox(height: 14),
                Expanded(
                  child: TabBarView(
                    children: [
                      _buildTable(null),
                      _buildTable("Student"),
                      _buildTable("Faculty"),
                      _buildTable("Staff"),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── HEADER: title on the left, compact counts pinned to the right ─────
  // Was previously a row of large stat cards; now uses the same small
  // pill-chip style as the Patients page so it doesn't dominate the header.

  Widget _buildHeaderRow(Map<String, int> summary) {
    return LayoutBuilder(builder: (context, constraints) {
      final bool isNarrow = constraints.maxWidth < 700;

      final titleBlock = Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                  colors: [kPrimary, kPrimaryDk],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.menu_book_rounded,
                color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text("Medical Records",
                  style: TextStyle(
                      color: kTextDark,
                      fontWeight: FontWeight.w800,
                      fontSize: 22)),
              Text("Manage student, faculty & staff visit records",
                  style: TextStyle(color: kTextSub, fontSize: 13)),
            ],
          ),
          const SizedBox(width: 6),
        ],
      );

      final chips = _buildCategorySummary(summary);

      if (isNarrow) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [titleBlock, const SizedBox(height: 12), chips],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          titleBlock,
          const Spacer(),
          chips,
        ],
      );
    });
  }

  Widget _buildCategorySummary(Map<String, int> summary) {
    return Wrap(
      alignment: WrapAlignment.end,
      spacing: 8,
      runSpacing: 8,
      children: [
        _summaryChip('All', summary['all']!, kPrimary, Icons.groups_rounded),
        _summaryChip('Students', summary['student']!, kStudentColor,
            Icons.school_outlined),
        _summaryChip('Faculty', summary['faculty']!, kFacultyColor,
            Icons.co_present_outlined),
        _summaryChip(
            'Staff', summary['staff']!, kStaffColor, Icons.badge_outlined),
      ],
    );
  }

  // Compact — icon, count, label all on one line. Same size as the chips
  // on the Patients page, deliberately smaller than the old stat cards.
  Widget _summaryChip(String label, int count, Color color, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 6),
        Text('$count',
            style: TextStyle(
                fontSize: 15, fontWeight: FontWeight.w800, color: color)),
        const SizedBox(width: 4),
        Text(label,
            style: TextStyle(
                fontSize: 13, color: color, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  // ── CUSTOM TAB BAR ────────────────────────────────────────────────────

  Widget _buildTabsBar() {
    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2F6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: TabBar(
        indicator: BoxDecoration(
          color: kPrimary,
          borderRadius: BorderRadius.circular(10),
          boxShadow: [
            BoxShadow(
                color: kPrimary.withValues(alpha: 0.3),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        dividerColor: Colors.transparent,
        labelColor: Colors.white,
        unselectedLabelColor: kTextSub,
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
        unselectedLabelStyle:
            const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        tabs: const [
          Tab(text: "ALL"),
          Tab(text: "STUDENTS"),
          Tab(text: "FACULTY"),
          Tab(text: "STAFF"),
        ],
      ),
    );
  }

  // ── SEARCH + FILTERS ──────────────────────────────────────────────────

  Widget _buildSearchAndFilters() {
    return LayoutBuilder(builder: (context, constraints) {
      bool isMobile = constraints.maxWidth < 760;
      return isMobile
          ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              _searchField(),
              const SizedBox(height: 10),
              _filterRow(wrap: true),
            ])
          : Row(children: [
              Expanded(child: _searchField()),
              const SizedBox(width: 14),
              _filterRow(wrap: false),
            ]);
    });
  }

  Widget _searchField() {
    return TextField(
      onChanged: (v) => setState(() => searchQuery = v.toLowerCase()),
      style: const TextStyle(fontSize: 13, color: kTextMain),
      decoration: InputDecoration(
        hintText: "Search by name, ID, complaint...",
        hintStyle: const TextStyle(color: kTextSub, fontSize: 13),
        prefixIcon: const Icon(Icons.search_rounded, color: kTextSub, size: 20),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(vertical: 13, horizontal: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kBorder)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kBorder)),
        focusedBorder: const OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
            borderSide: BorderSide(color: kPrimary, width: 1.5)),
      ),
    );
  }

  Widget _filterRow({required bool wrap}) {
    final dateLabel = selectedFilter == "Custom"
        ? DateFormat("MMM d, yyyy").format(selectedDate)
        : "Pick Date";
    final rangeLabel = selectedFilter == "Range" && selectedRange != null
        ? "${_fmtShort(selectedRange!.start)} – ${_fmtShort(selectedRange!.end)}"
        : "Pick Range";

    final chips = [
      _filterChip("Today"),
      _filterChip("All"),
      _pickerChip(
        icon: Icons.calendar_today_outlined,
        label: dateLabel,
        active: selectedFilter == "Custom",
        onTap: _pickDate,
      ),
      _pickerChip(
        icon: Icons.date_range_outlined,
        label: rangeLabel,
        active: selectedFilter == "Range",
        onTap: _pickRange,
      ),
    ];

    if (wrap) {
      return Wrap(spacing: 8, runSpacing: 8, children: chips);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < chips.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          chips[i]
        ]
      ],
    );
  }

  Widget _pickerChip(
      {required IconData icon,
      required String label,
      required bool active,
      required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: active
              ? kPrimary.withValues(alpha: 0.08)
              : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(25),
          border: Border.all(
              color: active
                  ? kPrimary.withValues(alpha: 0.4)
                  : Colors.transparent),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: active ? kPrimary : kTextSub),
          const SizedBox(width: 6),
          Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: active ? kPrimary : kTextSub,
                  fontWeight: active ? FontWeight.w600 : FontWeight.normal)),
        ]),
      ),
    );
  }

  Widget _filterChip(String label) {
    final sel = selectedFilter == label;
    return GestureDetector(
      onTap: () => setState(() => selectedFilter = label),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: sel ? kPrimary : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(25),
          boxShadow: sel
              ? [
                  BoxShadow(
                      color: kPrimary.withValues(alpha: 0.3),
                      blurRadius: 8,
                      offset: const Offset(0, 2))
                ]
              : [],
        ),
        child: Center(
          child: Text(label,
              style: TextStyle(
                  fontSize: 12,
                  color: sel ? Colors.white : kTextSub,
                  fontWeight: sel ? FontWeight.w700 : FontWeight.w500)),
        ),
      ),
    );
  }

  // ── PROCEDURES LINK ──────────────────────────────────────────────────
  // A record (visit) is joined to its procedure(s) by `visit_id`. Records
  // saved before procedures were linked simply have none, which is fine —
  // they just render "—" in the table and no section in the detail dialog.

  List<ProcedureRecord> _linkedProcedures(String visitId) {
    if (visitId.isEmpty) return [];
    final int? vid = int.tryParse(visitId);
    if (vid == null) return [];
    return _procedures.where((p) => p.visitId == vid).toList();
  }

  String _fmtPDate(DateTime? d) =>
      d == null ? '—' : DateFormat('MMM d, yyyy').format(d);

  String _fmtFollowUp(String yyyyMmDd) {
    final DateTime? d = DateTime.tryParse(yyyyMmDd);
    return d == null ? yyyyMmDd : DateFormat('MMM d, yyyy').format(d);
  }

  Widget _procedureStatusChip(String status) {
    final (Color bg, Color fg) = switch (status) {
      'Pending' => (kWarning.withValues(alpha: 0.14), kWarning),
      'Cancelled' => (kDanger.withValues(alpha: 0.12), kDanger),
      _ => (kSuccess.withValues(alpha: 0.14), kSuccess),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(status,
          style:
              TextStyle(color: fg, fontSize: 11, fontWeight: FontWeight.bold)),
    );
  }

  Widget _procedureTile(ProcedureRecord p) {
    final supplies = (p.details["suppliesUsed"] as List?)?.cast<Map>();
    final followUp = p.details["followUpOn"]?.toString();
    final referred = p.details["referredTo"]?.toString();
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.medical_services_outlined,
              size: 16, color: kPrimary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(p.procedureName,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: kTextMain)),
          ),
          _procedureStatusChip(p.status),
        ]),
        const SizedBox(height: 6),
        Text(_fmtPDate(p.performedAt),
            style: const TextStyle(fontSize: 12, color: kTextSub)),
        if (supplies != null && supplies.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
                "Supplies: ${supplies.map((s) => "${s["name"]} x${s["qty"]}").join(", ")}",
                style: const TextStyle(fontSize: 12, color: kTextSub)),
          ),
        if (followUp != null && followUp.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text("Follow-up: ${_fmtFollowUp(followUp)}",
                style: const TextStyle(fontSize: 12, color: kTextSub)),
          ),
        if (referred != null && referred.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text("Referred to: $referred",
                style: const TextStyle(fontSize: 12, color: kTextSub)),
          ),
      ]),
    );
  }

  // ── TABLE ─────────────────────────────────────────────────────────────
  // Four columns, each value centred: who came in (name, record number and
  // year/term), the affiliation, the services and when. Tap a row to open the
  // full record — the same "container" style the Individual Records roster
  // uses — including its audit trail. Styled to match the DataTable used on
  // the Patients page (same header/cell type sizes).

  /// The academic term line under a visitor's name: "2025-2026 · 1st
  /// Semester", written the same way the Individual Records roster writes it.
  ///
  /// A visit does not snapshot the term — `clinic_visits` carries the person's
  /// id, not their enrolment — so the term is resolved from the roster first
  /// (surfaced into the row's own keys by `_enrichFromRoster`), then from
  /// PatientDirectory when this page never enriched that row, and the visit's
  /// own `year` snapshot (year level for a student, position for faculty /
  /// staff) stands in when neither can. The worked examples name nobody in the
  /// registry, so they always fall back to their `year` line.
  String _visitorTermLine(Map<String, String> e) {
    final year = (e["academicYear"] ?? '').trim();
    final sem = (e["semester"] ?? '').trim();
    if (year.isNotEmpty || sem.isNotEmpty) {
      return academicTermLabel(year, sem);
    }
    final profile =
        PatientDirectory.instance.byId((e["personId"] ?? e["id"] ?? '').trim());
    if (profile != null &&
        (profile.academicYear.isNotEmpty || profile.semester.isNotEmpty)) {
      return academicTermLabel(profile.academicYear, profile.semester);
    }
    return (e["year"] ?? "").trim();
  }

  /// The column set for one tab. Each category reads columns that actually
  /// apply to it — a student's programme, a teacher's institute and post, a
  /// staff member's office — while the All tab stays wide enough to carry the
  /// category pill.
  List<String> _bookletHeaders(String? type) {
    switch (type) {
      case 'Student':
        return const [
          'VISITOR',
          'INSTITUTE',
          'PROGRAM',
          'SERVICES',
          'DATE & TIME',
        ];
      case 'Faculty':
        return const ['VISITOR', 'INSTITUTE', 'SERVICES', 'DATE & TIME'];
      case 'Staff':
        return const [
          'VISITOR',
          'DEPARTMENT / POSITION',
          'SERVICES',
          'DATE & TIME',
        ];
      default:
        return const ['VISITOR', 'TYPE', 'SERVICES', 'DATE & TIME'];
    }
  }

  /// One affiliation cell: a main line (institute / programme / office) and an
  /// optional sub line (position). Left-aligned to match the visitor column.
  Widget _affiliationCell(String main, [String sub = '']) {
    final m = main.trim();
    final s = sub.trim();
    if (m.isEmpty && s.isEmpty) {
      return Align(
          alignment: Alignment.centerLeft,
          child: const Text('-', style: TextStyle(color: kTextSub)));
    }
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(m.isEmpty ? '-' : m,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: m.isEmpty
                ? const TextStyle(fontSize: 13.5, color: kTextSub)
                : const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: kPrimary)),
        if (s.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(s,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11.5, color: kTextSub)),
        ],
      ],
    );
  }

  Widget _typePill(String t) {
    Color bg, fg;
    switch (t) {
      case "Student":
        bg = const Color(0xFFDBEAFE);
        fg = kStudentColor;
        break;
      case "Faculty":
        bg = const Color(0xFFFEF3C7);
        fg = kFacultyColor;
        break;
      default:
        // Grey for "Staff" and for "Unassigned" alike would be ambiguous, so
        // "Unassigned" gets its own flat grey: it must not wear the staff
        // badge, because the staff badge is a claim about the person that a
        // visit with no category has not made.
        if (t == "Staff") {
          bg = const Color(0xFFEDE9FE);
          fg = kStaffColor;
        } else {
          bg = const Color(0xFFEEF1F5);
          fg = kTextSub;
        }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)),
      child: Text(t,
          style:
              TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.bold)),
    );
  }

  /// The services on one visit, as chips.
  ///
  /// A visit can carry one service or several, so this shows the first two as
  /// chips and marks anything beyond them with an ellipsis rather than spilling
  /// a long list across the cell. Hovering the ellipsis names every unfinished
  /// one, so the count is never silently hidden. What it does not do is put them
  /// in one comma-joined string: "BP Tracking, Medical Consultation" in a table
  /// cell cannot be counted, and a visit that came in for six things looks
  /// identical to one that came in for two.
  Widget _serviceCell(List<String> names) {
    if (names.isEmpty) {
      return const Text('-', style: TextStyle(color: kTextSub));
    }
    const shown = 2;
    final visible = names.take(shown).toList();
    final hidden = names.length - visible.length;
    return Row(
      children: [
        for (final n in visible) ...[
          Flexible(child: _serviceChip(n)),
          const SizedBox(width: 6),
        ],
        if (hidden > 0)
          Tooltip(
            message: names.skip(shown).join(', '),
            triggerMode: TooltipTriggerMode.longPress,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: kTextSub.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '...',
                style: const TextStyle(
                    fontSize: 14, fontWeight: FontWeight.w800, color: kTextSub),
              ),
            ),
          ),
      ],
    );
  }

  Widget _serviceChip(String name) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: kPrimary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: kPrimary.withValues(alpha: 0.18)),
      ),
      child: Text(
        name,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
            fontSize: 12, fontWeight: FontWeight.w600, color: kPrimaryDk),
      ),
    );
  }

  Widget _statusPill(_VisitState s) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
          color: s.color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(6)),
      child: Text(
        s.label,
        style: TextStyle(
            color: s.color, fontSize: 12.5, fontWeight: FontWeight.w800),
      ),
    );
  }

  Widget _buildTable(String? type) {
    final filtered = _getFilteredRecords(typeFilter: type);
    final isAll = type == null;
    final isStudent = type == 'Student';
    final isFaculty = type == 'Faculty';
    final isStaff = !isAll && !isStudent && !isFaculty;

    if (filtered.isEmpty) {
      // An unreadable table and a table with nothing in it are different
      // problems with different fixes, so they are not allowed to share a
      // message. "No records found" while the read is failing is the kind of
      // sentence that sends somebody looking for records that still exist.
      if (_loadError != null) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: kDanger.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kDanger.withValues(alpha: 0.3)),
          ),
          child: Row(children: [
            const Icon(Icons.cloud_off_rounded, color: kDanger, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(_loadError!,
                  style: const TextStyle(
                      color: kDanger, fontSize: 13, height: 1.4)),
            ),
            IconButton(
              onPressed: _reloadRecords,
              icon: const Icon(Icons.refresh_rounded, color: kDanger, size: 20),
              tooltip: 'Try again',
            ),
          ]),
        );
      }
      return Center(
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.search_off_rounded, size: 48, color: AppColors.borderStrong),
        const SizedBox(height: 8),
        const Text("No records found",
            style: TextStyle(color: kTextSub, fontSize: 14)),
      ]));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sits above the table, not on the empty state: a read can fail while
        // there are still rows on screen from an earlier successful read, and
        // the rows then look complete while being stale.
        if (_loadError != null) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: kDanger.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: kDanger.withValues(alpha: 0.28)),
            ),
            child: Row(children: [
              const Icon(Icons.cloud_off_rounded, color: kDanger, size: 17),
              const SizedBox(width: 10),
              Expanded(
                child: Text(_loadError!,
                    style: const TextStyle(
                        color: kDanger, fontSize: 12.5, height: 1.35)),
              ),
              IconButton(
                onPressed: _reloadRecords,
                icon:
                    const Icon(Icons.refresh_rounded, color: kDanger, size: 18),
                visualDensity: VisualDensity.compact,
                tooltip: 'Try again',
              ),
            ]),
          ),
          const SizedBox(height: 10),
        ],
        // The card fills the height the tab gives it, so the table runs all the
        // way down the page and its own scroll carries any rows past the fold.
        // Left as a content-sized box it stopped at the last row and left a
        // large dead gap beneath it.
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kBorder),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withValues(alpha: .04),
                      blurRadius: 10,
                      offset: const Offset(0, 2))
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: LayoutBuilder(builder: (context, constraints) {
                  // Columns are scoped per tab and kept compact — the booklet is
                  // a log, not the roster. Each width is still a floor, because a
                  // name wrapping mid-word or a service chip pushed onto a second
                  // line turns a list of records into a wall. The row scrolls
                  // sideways instead, which is the lesser evil.
                  const visitorWidth = 200.0;
                  const typeWidth = 96.0;
                  const instituteWidth = 150.0;
                  const programWidth = 158.0;
                  const servicesWidth = 170.0;
                  const dateWidth = 140.0;

                  return SingleChildScrollView(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: ConstrainedBox(
                        constraints:
                            BoxConstraints(minWidth: constraints.maxWidth),
                        child: DataTable(
                          headingRowHeight: 52,
                          dataRowMinHeight: 64,
                          dataRowMaxHeight: 76,
                          showCheckboxColumn: false,
                          headingRowColor:
                              WidgetStateProperty.all(const Color(0xFFF8FAFC)),
                          headingTextStyle: const TextStyle(
                              fontWeight: FontWeight.w800,
                              color: kTextSub,
                              fontSize: 12,
                              letterSpacing: 0.9),
                          dataTextStyle:
                              const TextStyle(color: kTextMain, fontSize: 15),
                          columnSpacing: 24,
                          horizontalMargin: 20,
                          dividerThickness: 1,
                          // Only the horizontal rules. `DataTable` draws a top and
                          // bottom line by default, which sat inside the rounded corner
                          // and drew a straight edge across the top of the first row.
                          border: const TableBorder(
                            horizontalInside:
                                BorderSide(color: kBorder, width: 0.8),
                          ),
                          columns: [
                            for (final h in _bookletHeaders(type))
                              DataColumn(label: Center(child: Text(h))),
                          ],
                          rows: filtered.asMap().entries.map((entry) {
                            final e = entry.value;
                            final even = entry.key % 2 == 0;
                            final rowType = ((e["type"] ?? '').trim());
                            final isStudentRow = rowType == 'Student';
                            // Faculty and staff have no term to print; a position
                            // wearing the year/term slot would look like a class
                            // year, so only students get the line.
                            final yearLine =
                                isStudentRow ? _visitorTermLine(e) : '';
                            final cells = <DataCell>[
                              // VISITOR — name and record number for everyone,
                              // plus the academic year · semester for students.
                              // Left-aligned like the roster, not centred.
                              DataCell(SizedBox(
                                width: visitorWidth - 8,
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(e["name"] ?? '',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            fontSize: 15,
                                            color: kTextMain)),
                                    const SizedBox(height: 2),
                                    Text(e["id"] ?? '',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                            fontSize: 11.5,
                                            color: kTextSub,
                                            fontWeight: FontWeight.w500)),
                                    if (yearLine.isNotEmpty) ...[
                                      const SizedBox(height: 2),
                                      Text(yearLine,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                              fontSize: 11.5, color: kTextSub)),
                                    ],
                                  ],
                                ),
                              )),
                            ];
                            if (isAll) {
                              cells.add(DataCell(SizedBox(
                                width: typeWidth - 8,
                                child: Center(child: _typePill(rowType)),
                              )));
                            } else if (isStudent) {
                              cells.add(DataCell(SizedBox(
                                width: instituteWidth - 8,
                                child: _affiliationCell(e["institute"] ?? ''),
                              )));
                              cells.add(DataCell(SizedBox(
                                width: programWidth - 8,
                                child: _affiliationCell(e["program"] ?? ''),
                              )));
                            } else if (isFaculty) {
                              cells.add(DataCell(SizedBox(
                                width: instituteWidth - 8,
                                child: _affiliationCell(
                                  e["institute"] ?? '',
                                  e["position"] ?? '',
                                ),
                              )));
                            } else if (isStaff) {
                              // Staff: the office, then the post within it.
                              cells.add(DataCell(SizedBox(
                                width: instituteWidth - 8,
                                child: _affiliationCell(
                                  e["department"] ?? '',
                                  e["position"] ?? '',
                                ),
                              )));
                            }
                            cells.add(DataCell(SizedBox(
                              width: servicesWidth - 8,
                              child: Align(
                                alignment: Alignment.centerLeft,
                                child: _serviceCell(_serviceNames(e)),
                              ),
                            )));
                            cells.add(DataCell(SizedBox(
                              width: dateWidth - 8,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(_fmtDisplayDate(e["date"] ?? ''),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 13.5,
                                          fontWeight: FontWeight.w600,
                                          color: kTextMain)),
                                  const SizedBox(height: 2),
                                  Text(e["time"] ?? '',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                          fontSize: 11.5, color: kTextSub)),
                                ],
                              ),
                            )));
                            return DataRow(
                              color: WidgetStateProperty.resolveWith((s) {
                                if (s.contains(WidgetState.hovered)) {
                                  return kPrimary.withValues(alpha: 0.04);
                                }
                                return even
                                    ? Colors.white
                                    : const Color(0xFFFAFCFD);
                              }),
                              onSelectChanged: (_) => _showDetailDialog(e),
                              cells: cells,
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
