import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'app_colors.dart';
import 'individual_record_data.dart';
import '../core/patient_directory.dart';
import '../services/data_tracker.dart';
import '../services/individual_record_service.dart';
import '../services/reference_data_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  individual_record_screen.dart
//  The per-person student / faculty / staff roster, backed by
//  `public.individual_records` through `IndividualRecordService`.
//
//  The rows shown here are still a projection of `PatientDirectory`
//  (`lib/core/patient_directory.dart`) so a record added on one screen is
//  immediately findable on another — but the directory is no longer the source
//  of truth. `_loadRecords()` fills it from the database, and every write goes
//  to the database first and only then back into the directory.
//
//  WHAT THE DATABASE OWNS
//    * The audit trail (Created / Created By / Updated / Updated By) comes
//      from the `individual_records_touch_audit` trigger, so it names the real
//      signed-in account and uses the server clock. This screen no longer
//      writes the strings "Manual entry" / "Batch import".
//    * `status` ('Active' / 'Inactive') is persisted and is only ever changed by
//      the row's Delete / Restore action — there is no Status box on the form.
//      Deleting is a soft delete that flips the status instead of dropping the
//      row — see `_confirmDelete`.
// ─────────────────────────────────────────────────────────────────────────────

// ── INSTITUTE → PROGRAM CATALOG ──────────────────────────────────────────────
// kProgramCatalog, kFacultyPositions, kStaffPositions, kStaffDepartments,
// kYearLevels, kSemesters and kSexes now live in
// `lib/core/patient_directory.dart` so this page and Clinic Visit can never
// drift apart on what programs / posts / offices exist. The helpers there
// (kInstitutes, programsOf, instituteOfProgram, departmentOptionsFor,
// positionOptionsFor) are the shared way to ask for a valid list.

/// Sentinel value for the "add a new institute / program" dropdown item.
const String _kAddProgram = '__add_program__';

/// Sentinel values for the "add a new department / office" and "add a new
/// position" dropdown items. Like [_kAddProgram], each is a value no real name
/// can be, so choosing it is recognised rather than stored.
const String _kAddDepartment = '__add_department__';
const String _kAddPosition = '__add_position__';

/// Sentinel for the "+ New institute" entry in the Add Institute / Program
/// dialog's institute dropdown — reveals the code and name boxes for an
/// institute that is not on file yet.
const String _kNewInstitute = '__new_institute__';

// ── MODEL ────────────────────────────────────────────────────────────────────
// The `IndividualRecord` model and the import row/result models now live in
// `individual_record_data.dart` so `IndividualRecordService` can import them
// without pulling in this file. Re-exported here because every call site below
// already refers to them by this screen's imports.

// ── SCREEN ───────────────────────────────────────────────────────────────────

class IndividualRecordScreen extends StatefulWidget {
  const IndividualRecordScreen({super.key});

  @override
  State<IndividualRecordScreen> createState() => _IndividualRecordScreenState();
}

class _IndividualRecordScreenState extends State<IndividualRecordScreen>
    with TickerProviderStateMixin {
  // ── DESIGN TOKENS ──────────────────────────────────────────────────────
  static const Color kPrimary = AppColors.primary;
  static const Color kPrimaryDk = AppColors.primaryDark;
  static const Color kCard = AppColors.surface;
  static const Color kBorder = AppColors.border;
  static const Color kTextMain = AppColors.textMain;
  static const Color kTextSub = AppColors.textSub;
  static const Color kDanger = AppColors.danger;

  static const Color kStudentColor = AppColors.student;
  static const Color kFacultyColor = AppColors.faculty;
  static const Color kStaffColor = AppColors.staff;
  static const Color kSuccess = AppColors.success;
  static const Color kBg = AppColors.bg;

  // ── VIEW STATE ─────────────────────────────────────────────────────────
  String filter = 'Student';
  final TextEditingController search = TextEditingController();
  late AnimationController _fadeCtrl;
  late Animation<double> _fadeAnim;

  /// Set while the first (or a refresh) query is in flight, and to the message
  /// when it fails. The table shows a spinner or the error instead of rows, so
  /// a network problem never reads as "this school has no students".
  bool _loading = true;
  String? _loadError;

  /// profiles.id -> full name, so the audit trail in the detail dialog shows
  /// "Dr. Santos" instead of a truncated uuid.
  Map<String, String> _userNames = const {};

  /// The roster shows the term being run, and only that.
  ///
  /// Active-only, which now means "the current term only": a record on an ended
  /// term is retired to Inactive when the next term is imported, and Inactive
  /// records live in the Archive. Listing them here as well put one person in the
  /// roster two or three times — once per term — with nothing on screen to say
  /// which row was current.
  ///
  /// The Archive is where a removed person is looked up now, and it is also
  /// where their Restore button lives.
  static const bool includeInactive = false;

  /// Set while a create / update / status change is being written, so the
  /// dialog's Save button can disable itself instead of double-submitting.
  bool _saving = false;

  /// Re-reads the roster when another tab (or the import) changed the data.
  VoidCallback? _dataListener;

  IndividualRecord? _editing;
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  /// Which step of the Add/Edit dialog is currently showing (0-based). The
  /// dialog stays open and swaps its body, so filling a record never leaves
  /// the list behind it.
  int _formStep = 0;
  static const int _formStepCount = 3;

  /// Setter of the open Add/Edit dialog. It lives on its own route, so a
  /// change made inside it (picking an institute re-lists the programs, for
  /// instance) has to rebuild the dialog rather than the page behind it.
  StateSetter? _dlgSet;

  /// True while the generated number is being fetched from the database, so the
  /// ID field can show a placeholder instead of a stale in-memory guess.
  bool _fetchingId = false;

  /// Counts ID fetches so a late reply can be recognised and dropped.
  ///
  /// Needed because the box is read-only for Faculty/Staff and so the app owns
  /// its content — which means nothing downstream stops a reply from landing in
  /// the wrong form. Pick Faculty, switch to Staff while the request is in
  /// flight, and the Faculty reply arrives into a Staff form with no category
  /// of its own to be rejected on: it would be saved as a Staff row wearing an
  /// F number, and nothing would object, because the uniqueness constraint is
  /// per category. Comparing tokens drops it instead.
  int _idRequest = 0;

  // ── FORM STATE ─────────────────────────────────────────────────────────
  final TextEditingController _cId = TextEditingController();
  final TextEditingController _cFirst = TextEditingController();
  final TextEditingController _cMiddle = TextEditingController();
  final TextEditingController _cLast = TextEditingController();
  final TextEditingController _cSuffix = TextEditingController();
  final TextEditingController _cBirth = TextEditingController();
  final TextEditingController _cContact = TextEditingController();
  final TextEditingController _cEmail = TextEditingController();
  final TextEditingController _cAddress = TextEditingController();
  final TextEditingController _cYearStart = TextEditingController();
  final TextEditingController _cYearEnd = TextEditingController();

  String? _fCategory;
  String? _fSex;
  String? _fSemester;
  String? _fInstitute;
  String? _fProgram;
  String? _fYearLevel;
  String? _fDepartment;
  String? _fPosition;

  /// The `academic_period_id` the record will be filed under.
  ///
  /// Held directly rather than re-derived from the two year boxes at save time.
  /// The dropdown hands over a single label ("2023-2024 · 1st Semester"), and
  /// splitting it back into columns was one bad edit away from writing a year no
  /// period matches — which is exactly the "no academic period" refusal
  /// `IndividualRecordService.create` raises: the person is never written and the
  /// clerk sees only a failure. Setting this from the same label the dropdown
  /// shows keeps the id and the visible term from ever disagreeing.
  String? _fPeriodId;

  // Status is not a form field: _saveFormAsync derives it from the term the
  // record is filed under (current term Active, earlier term Inactive, and an
  // Inactive row stays Inactive when edited). A dropdown here would offer to
  // contradict that and be silently overridden on save.

  /// The birth date is held as a real DateTime; `_cBirth` is only the
  /// "MMM d, yyyy" label shown in the field (DateTime.tryParse can't read that
  /// format back, so the value must not be round-tripped through the text).
  DateTime? _fBirthDate;

  /// Institute code → the programs it offers, read live from [ReferenceCatalog].
  ///
  /// This used to be a mutable copy taken once when the screen was built. That
  /// is why an institute or program added through the dropdown was written to
  /// the database and then not offered by the very dropdown that added it: the
  /// copy never learned about it. Reading the catalog on each build keeps the
  /// form in step with what was just saved.
  Map<String, List<String>> get _catalog => kProgramCatalog;

  // ── SHARED DIRECTORY (see lib/core/patient_directory.dart) ──────────────
  // `public.individual_records` is the source of truth; PatientDirectory is the
  // in-memory projection of it that every screen shares. _loadRecords() fetches
  // the roster and hands it to the directory, each write goes to the database
  // first and is only then pushed into the directory, and a change made
  // elsewhere shows up here on the next DataTracker bump.
  //
  // [_records] holds the WHOLE active roster, every category — not just the tab
  // on screen. It used to hold the selected category only, which meant switching
  // Student -> Faculty had to be a fresh query: the rows for the other category
  // were not in the page, so there was nothing to show until the database
  // answered. A tab click on a clinic wifi connection is a visible wait, and it
  // read as the page loading. With the whole roster already in hand the category
  // and the search box are local filters over [_filtered], so both are instant
  // and cannot disagree with the counts above them.
  final List<IndividualRecord> _records = [];

  /// True only for the duration of [_loadRecords]'s own hydrate call, so the
  /// notification that hydrate raises does not immediately re-query the view
  /// with the values the query has not changed.
  bool _suppressDirectoryRefresh = false;

  /// Reads the active roster from the database, publishes it to the shared
  /// directory, and fills [_records]. Called on mount and whenever
  /// [DataTracker] signals a write from anywhere in the app. A failure leaves the
  /// previous rows on screen and surfaces [_loadError] rather than silently
  /// emptying the table.
  ///
  /// [silent] keeps the current rows on screen while re-querying. Writes made
  /// by this screen bump [DataTracker], which lands back here — without this the
  /// table would blank to a spinner every time the user saved a record.
  ///
  /// This is the only read the page makes: no category, no search term, so the
  /// shared directory ends up holding everybody and the table has all three
  /// categories to filter locally. That matters because the directory backs the
  /// per-category counts in the header, the next-number suggestion on the form,
  /// and the duplicate-number check.
  Future<void> _loadRecords({bool silent = false}) async {
    if (mounted && !silent) {
      setState(() {
        _loading = true;
        _loadError = null;
      });
    }
    try {
      // The roster is "the current term's people", and which term that is is the
      // database's to say. Re-read it on an explicit load so a term switched
      // anywhere else stops filtering this table on a term that is no longer
      // current. Silent refreshes skip it: the write that triggered them already
      // re-read the periods on its way through, so the value is fresh.
      if (!silent) {
        try {
          await ReferenceCatalog.refreshPeriods();
        } catch (_) {
          // Keep the term already in memory; the roster read below still runs.
        }
      }
      final results = await Future.wait([
        IndividualRecordService.fetchAll(includeInactive: includeInactive),
        IndividualRecordService.fetchUserNames(),
      ]);
      final list = results[0] as List<IndividualRecord>;
      final names = results[1] as Map<String, String>;
      if (!mounted) return;
      _userNames = names;
      _suppressDirectoryRefresh = true;
      PatientDirectory.instance.hydrate(list.map(_profileFromRecord).toList());
      _suppressDirectoryRefresh = false;
      setState(() {
        _records
          ..clear()
          ..addAll(list);
        _loading = false;
        _loadError = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadError = '$e';
      });
    }
  }

  /// Search box handler.
  ///
  /// Filters in memory. There is no debounce and no query: the roster is one
  /// term of a school clinic and is already loaded for the header counts, so a
  /// keystroke is a `setState` over a list rather than a round trip — which is
  /// what "typing a 6-digit ID shows nothing for half a second, then something"
  /// was.
  void _onSearchChanged(String _) {
    setState(() {});
  }

  /// A write landed in the shared directory, so the table's rows are stale.
  ///
  /// Re-reads the roster rather than copying the directory in: the directory is
  /// a projection of people, not of records, and it carries no term or status, so
  /// a row for an ended term could reach the table from there.
  ///
  /// Skipped while [_loadRecords] is running, because that call hydrates the
  /// directory itself and would otherwise fire a second identical query.
  void _directoryListener() {
    if (!mounted || _suppressDirectoryRefresh) return;
    _loadRecords(silent: true);
  }

  /// Writes this page's record into the shared directory, carrying over the
  /// clinic-side extras (emergency contact) the directory also holds.
  void _pushToDirectory(IndividualRecord r) {
    PatientDirectory.instance.upsert(_profileFromRecord(r));
  }

  ClinicProfile _profileFromRecord(IndividualRecord r) {
    final existing = PatientDirectory.instance.byId(r.id);
    return ClinicProfile(
      uuid: r.uuid,
      id: r.id,
      category: r.category,
      firstName: r.firstName,
      middleName: r.middleName,
      lastName: r.lastName,
      suffix: r.suffix,
      sex: r.sex,
      birthDate: r.birthDate == null
          ? ''
          : DateFormat('yyyy-MM-dd').format(r.birthDate!),
      contact: r.contact,
      email: r.email,
      address: r.address,
      academicYear: r.academicYear,
      semester: r.semester,
      institute: r.institute,
      program: r.program,
      yearLevel: r.yearLevel,
      department: r.department,
      position: r.position,
      emergencyName: existing?.emergencyName ?? '',
      emergencyContact: existing?.emergencyContact ?? '',
      status: r.status,
      createdAt: r.createdAt,
      createdBy: r.createdBy,
      updatedAt: null,
      updatedBy: null,
    );
  }

  // ── LIFECYCLE ──────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    PatientDirectory.instance.subscribe(_directoryListener);
    _fadeCtrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 300));
    _fadeAnim = CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeIn);
    _fadeCtrl.forward();
    final ay = _splitAcademicYear(_defaultAcademicYear);
    _cYearStart.text = ay.$1;
    _cYearEnd.text = ay.$2;
    // Two reads on mount used to happen here: the whole roster for the shared
    // directory, and a second category-scoped query for the table. There is one
    // now. The table deliberately does not start from the directory's
    // hard-coded fallback list — showing three invented people for a frame before
    // the real roster arrives reads as data, so the page shows its loading state
    // instead.
    _loadRecords();
    // A write anywhere re-reads the roster, silently, since the rows on screen
    // stay valid while it does.
    _dataListener = () => _loadRecords(silent: true);
    DataTracker.listen(_dataListener!);
  }

  @override
  void dispose() {
    if (_dataListener != null) DataTracker.unlisten(_dataListener!);
    PatientDirectory.instance.unsubscribe(_directoryListener);
    _fadeCtrl.dispose();
    search.dispose();
    _cId.dispose();
    _cFirst.dispose();
    _cMiddle.dispose();
    _cLast.dispose();
    _cSuffix.dispose();
    _cBirth.dispose();
    _cContact.dispose();
    _cEmail.dispose();
    _cAddress.dispose();
    _cYearStart.dispose();
    _cYearEnd.dispose();
    super.dispose();
  }

  // ── ACADEMIC YEAR HELPERS ──────────────────────────────────────────────
  // The school year is treated as starting in June, so anything from June
  // onwards already belongs to the year that began this calendar year.

  /// The term a new record is filed under: the one the clinic is running.
  ///
  /// Was computed from the clock — "the school year that began in June" — which
  /// meant a new record's term silently changed on 1 June without anybody
  /// deciding it, and could disagree with the terms already in the table. The
  /// clinic runs one term at a time and that term is written down in
  /// [kCurrentAcademicYear] / [kCurrentSemester]; this reads it.
  static String get _defaultAcademicYear => kCurrentAcademicYear;

  static String get _defaultSemester => kCurrentSemester;

  /// '2026-2027' → ('2026', '2027'), falling back to the current default so a
  /// record with a hand-typed / legacy year still opens on a usable pair.
  static (String, String) _splitAcademicYear(String ay) {
    final parts = ay.split('-');
    if (parts.length == 2 &&
        int.tryParse(parts[0]) != null &&
        int.tryParse(parts[1]) != null) {
      return (parts[0], parts[1]);
    }
    final def = _defaultAcademicYear.split('-');
    return (def[0], def[1]);
  }

  /// What the two "School Year" boxes add up to.
  String get _composedAcademicYear =>
      '${_cYearStart.text.trim()}-${_cYearEnd.text.trim()}';

  // ── FILTERING ──────────────────────────────────────────────────────────

  String get _idLabel => filter == 'Student'
      ? 'Student ID'
      : filter == 'Faculty'
          ? 'Faculty ID'
          : 'Staff ID';

  /// The rows the table shows: the active roster narrowed to the open category
  /// and to whatever is in the search box.
  ///
  /// Both filters are local, and deliberately so. [_records] already holds the
  /// whole active roster, so the alternative was a round trip per tab click and
  /// per keystroke — which is the loading the page used to do. The counting and
  /// the filtering are the same two functions the tests exercise, so the numbers
  /// above the table cannot describe a different set of people than the rows
  /// below them.
  List<IndividualRecord> get _filtered =>
      filterRoster(rows: _records, category: filter, query: search.text);

  /// Headline counts for the Student / Faculty / Staff chips.
  ///
  /// Counted from [_records] — the whole active roster — rather than from
  /// [_filtered], which holds only what the open tab and search box matched.
  /// That was the wrong count: "All" read [_records].length while the table held
  /// one category, so the total fell every time a tab was clicked and again
  /// every time anything was typed.
  int _countFor(String category) => countInCategory(_records, category);

  /// Everybody on the active roster, all three categories.
  int get _totalCount => _records.length;

  // ── PROGRAM <-> INSTITUTE ──────────────────────────────────────────────
  // Program dropdown values are '$institute|$program' so one dropdown can
  // show every program of every institute while still storing both parts.

  String _programValue(String institute, String program) =>
      '$institute|$program';

  (String, String)? _parseProgramValue(String? value) {
    if (value == null || value.isEmpty || value == _kAddProgram) return null;
    final i = value.indexOf('|');
    if (i < 0) return null;
    return (value.substring(0, i), value.substring(i + 1));
  }

  /// Programs of the institute currently picked — nothing else. An institute
  /// with a single offering (ICS, IHS) therefore only ever lists that one.
  List<String> get _programOptions {
    final inst = _fInstitute;
    if (inst == null) return const <String>[];
    return List<String>.of(_catalog[inst] ?? const <String>[]);
  }

  /// Faculty belong to an institute, staff to an office, so the two never see
  /// the same list.
  List<String> _departmentOptions(String? category) => category == 'Faculty'
      ? (_catalog.keys.toList()..sort())
      : List<String>.of(kStaffDepartments);

  /// Faculty only see teaching posts, staff only administrative / support ones.
  List<String> _positionOptions(String? category) => category == 'Faculty'
      ? List<String>.of(kFacultyPositions)
      : List<String>.of(kStaffPositions);

  // ── FORM OPEN / CLOSE ──────────────────────────────────────────────────

  /// Opens the small Add/Edit container. The dialog collects one record at a
  /// time, one step at a time — it swaps its own body instead of pushing a
  /// new page, so the record list is never hidden behind it.
  void _openForm({IndividualRecord? edit}) {
    final category = edit?.category ?? filter;
    setState(() {
      _editing = edit;
      _formStep = 0;
      _fCategory = category;
      _fSex = edit?.sex.isNotEmpty == true ? edit!.sex : null;
      // Defaulted to the term being run. Was kSemesters.first, which filed every new
      // record under 1st Semester — a term that is over half the year and that
      // the clinic is not running.
      _fSemester =
          edit?.semester.isNotEmpty == true ? edit!.semester : _defaultSemester;
      _fInstitute =
          (edit?.institute.isNotEmpty ?? false) ? edit!.institute : null;
      _fProgram = (edit?.program.isNotEmpty ?? false)
          ? _programValue(edit!.institute, edit.program)
          : null;
      _fYearLevel =
          (edit?.yearLevel.isNotEmpty ?? false) ? edit!.yearLevel : null;
      // A record kept from before the lists were split can hold a department /
      // position / program the current category no longer offers. Drop those
      // instead of handing the dropdown a value that is not in its items.
      // For a Faculty member the "Department" dropdown IS the institute picker
      // — its options are the institute codes — and the database keeps that
      // value in `institute_id`, so the saved row carries it in `institute`.
      // For a Staff member the same dropdown is the department / office.
      final dept = category == 'Faculty'
          ? ((edit?.institute.isNotEmpty ?? false) ? edit!.institute : null)
          : ((edit?.department.isNotEmpty ?? false) ? edit!.department : null);
      _fDepartment =
          (dept != null && _departmentOptions(category).contains(dept))
              ? dept
              : null;
      final pos = (edit?.position.isNotEmpty ?? false) ? edit!.position : null;
      _fPosition = (pos != null && _positionOptions(category).contains(pos))
          ? pos
          : null;
      if (_fProgram != null &&
          !_programOptions.contains(_parseProgramValue(_fProgram)?.$2)) {
        _fProgram = null;
      }
      _fBirthDate = edit?.birthDate;

      _cId.text = edit?.id ?? '';
      _cFirst.text = edit?.firstName ?? '';
      _cMiddle.text = edit?.middleName ?? '';
      _cLast.text = edit?.lastName ?? '';
      _cSuffix.text = edit?.suffix ?? '';
      _cBirth.text = edit?.birthDate == null
          ? ''
          : DateFormat('MMM d, yyyy').format(edit!.birthDate!);
      _cContact.text = edit?.contact ?? '';
      _cEmail.text = edit?.email ?? '';
      _cAddress.text = edit?.address ?? '';

      // A record filed under a term the school does not run — one hand-typed before
      // the term picker, or a year the calendar has moved past — is pulled onto
      // the current term rather than left as a value the dropdown cannot show.
      // The alternative is a dropdown that renders blank and silently files the
      // save under whatever the picker defaults to.
      final ay = _splitAcademicYear(edit?.academicYear.isNotEmpty == true
          ? edit!.academicYear
          : _defaultAcademicYear);
      _cYearStart.text = ay.$1;
      _cYearEnd.text = ay.$2;
      // Resolved once, here, so the save never has to re-derive it from the year
      // boxes. A record opens on the term it was filed under; a new one opens on
      // the term the clinic is running.
      _fPeriodId = (edit?.academicPeriodId?.isNotEmpty ?? false)
          ? edit!.academicPeriodId
          : ReferenceCatalog.periodIdFor(
              _composedAcademicYear, _fSemester ?? '');
    });

    // Faculty / staff numbers are generated, and the next free one has to come
    // from the database (a row saved on another device would not be in the
    // in-memory list). Fill it in as soon as it arrives.
    if (edit == null && category != 'Student') _fillNextId(category);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDlg) {
          _dlgSet = setDlg;
          return _buildFormDialog(ctx, setDlg);
        },
      ),
    );
  }

  /// Asks the database for the next free number and drops it into the ID box.
  ///
  /// The year in a generated number is the term the person is being filed
  /// under, so this has to follow the term dropdown: a record added for
  /// 2026-2027 is '2026F001', not '2025F001'. It only rewrites the box while
  /// the number is still one the app issued — the moment a clerk types over it,
  /// the field is theirs and changing the term leaves it alone.
  Future<void> _fillNextId(String category) async {
    if (_editing != null) return;
    final token = ++_idRequest;
    setState(() => _fetchingId = true);
    try {
      final next = await IndividualRecordService.nextIdFor(category);
      if (!mounted || _editing != null || token != _idRequest) return;
      setState(() {
        _cId.text = next;
        _fetchingId = false;
      });
      _refreshForm();
    } catch (_) {
      // No network / no table yet: fall back to the in-memory sequence so the
      // form is still usable, exactly as it was before the database existed.
      if (!mounted || _editing != null || token != _idRequest) return;
      setState(() {
        if (_cId.text.trim().isEmpty) {
          _cId.text = PatientDirectory.instance.nextIdFor(category);
        }
        _fetchingId = false;
      });
      _refreshForm();
    }
  }

  /// Repaints the open Add/Edit container in place.
  void _refreshForm() => _dlgSet?.call(() {});

  /// Closes the container and forgets its setter so no late rebuild can reach
  /// a disposed dialog.
  void _closeFormDialog(BuildContext ctx) {
    _dlgSet = null;
    Navigator.pop(ctx);
  }

  /// Validates the step on screen; advances to the next one when it is clean.
  void _formNext(StateSetter setDlg) {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setDlg(() => setState(() => _formStep++));
  }

  // ── SAVE ───────────────────────────────────────────────────────────────

  /// Validates the visible step, then hands off to [_saveFormAsync]. [ctx] is
  /// the Add/Edit dialog's own context, so the dialog can stay open (with a
  /// spinner on its button) until the write actually succeeds.
  void _saveForm(BuildContext ctx) {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_saving) return;
    _saveFormAsync(ctx);
  }

  /// The status to file a save under, resolved from the term on screen.
  ///
  /// [IndividualRecordService.statusForTerm] is the one rule for this — an
  /// enrolment is Active only while it is filed under the term the school is
  /// running — so this turns the year/semester pair into its period id and lets
  /// that rule decide. [ReferenceCatalog.periodIdFor] returns null for a term
  /// the school does not run, which the service reads as Inactive rather than
  /// putting a hand-typed year onto the roster.
  String _effectiveStatusFor(String academicYear, String semester) {
    final periodId =
        _fPeriodId ?? ReferenceCatalog.periodIdFor(academicYear, semester);
    return IndividualRecordService.statusForTerm(periodId);
  }

  /// Writes the form to `public.individual_records`, then reflects the saved
  /// row (server-assigned uuid, real Created By / Created At) back into the
  /// list and the shared directory.
  ///
  /// The audit columns are deliberately absent: the
  /// `individual_records_touch_audit` trigger fills them from the signed-in
  /// session, so the "Created By" a user sees afterwards is their own account
  /// and not a hard-coded string.
  ///
  /// Status is not chosen by hand: a record on the term being run is Active,
  /// because that is the roster the clinic works from. A record filed on an
  /// earlier term is history and is written Inactive — the same thing the
  /// import does, so a record added by hand and one added by CSV end up in the
  /// same state for the same term.
  Future<void> _saveFormAsync(BuildContext dialogCtx) async {
    final isEdit = _editing != null;
    final target = _editing;
    final category = _fCategory!;
    final isStudent = category == 'Student';

    // Build the payload without touching the stored record yet, so a failed
    // write leaves the row on screen exactly as it was.
    final parsedProgram = isStudent ? _parseProgramValue(_fProgram) : null;
    final programCode = parsedProgram?.$2 ?? '';
    // Faculty has no institute field of its own: the dropdown the form labels
    // "Department" is the institute picker (it lists institute codes), so the
    // value it collected is what resolves to `institute_id`. A Faculty enrolment
    // whose institute_id is null is refused by the database trigger
    // "Faculty requires institute and position", which left the person row saved
    // but with no enrolment. Staff has no institute at all.
    //
    // `_fInstitute` holds the institute CODE (the dropdown lists codes), but
    // `programIdFor` scopes a program by its institute ID. Passing the code
    // through matched no program — `p.instituteId` is an id like 'INS-001', never
    // 'ICS' — so `program_id` was written as NULL and the "Student requires
    // institute, program and year level" trigger refused the enrolment. Resolve
    // the id once, here, and use it for both the program lookup and the payload.
    final instituteId = isStudent
        ? ReferenceCatalog.instituteByCode(_fInstitute)?.id
        : (category == 'Faculty'
            ? ReferenceCatalog.instituteByCode(_fDepartment)?.id
            : null);
    final programId = isStudent
        ? ReferenceCatalog.programIdFor(instituteId, programCode)
        : null;
    final deptId = category == 'Staff'
        ? ReferenceCatalog.departmentIdByName(_fDepartment ?? '')
        : null;
    final posId =
        !isStudent ? ReferenceCatalog.positionIdByName(_fPosition ?? '') : null;

    final draft = IndividualRecord(
      uuid: target?.uuid,
      id: isEdit ? target!.id : _cId.text.trim(),
      category: category,
      academicPeriodId: _fPeriodId ??
          ReferenceCatalog.periodIdFor(_composedAcademicYear, _fSemester ?? ''),
      firstName: _cFirst.text.trim(),
      middleName: _cMiddle.text.trim(),
      lastName: _cLast.text.trim(),
      suffix: _cSuffix.text.trim(),
      sex: _fSex ?? '',
      birthDate: _fBirthDate,
      contact: _cContact.text.trim(),
      email: _cEmail.text.trim(),
      address: _cAddress.text.trim(),
      academicYear: _composedAcademicYear,
      semester: _fSemester ?? '',
      instituteId: instituteId,
      // Student and Faculty both display an institute; for a Faculty member the
      // value is the code chosen in the dropdown the form labels "Department".
      institute: isStudent
          ? (_fInstitute ?? '')
          : (category == 'Faculty' ? (_fDepartment ?? '') : ''),
      programId: programId,
      program: isStudent ? programCode : '',
      yearLevel: isStudent ? (_fYearLevel ?? '') : '',
      departmentOfficeId: deptId,
      department: category == 'Staff' ? (_fDepartment ?? '') : '',
      positionId: posId,
      position: isStudent ? '' : (_fPosition ?? ''),
      // An Inactive row the user is editing stays Inactive — re-saving an old
      // term's history must not quietly promote it onto the current roster.
      status: target?.status == kRecordStatusInactive
          ? kRecordStatusInactive
          : _effectiveStatusFor(_composedAcademicYear, _fSemester ?? ''),
    );

    setState(() => _saving = true);
    _refreshForm();

    try {
      // A person number already taken in this category *for the term being
      // saved* fails the unique constraint; check first so the message can be
      // specific.
      //
      // Scoped to the term on purpose. The same person legitimately holds one
      // row per term, so a person-wide check made it impossible to add anyone
      // to next term — the check fired on their 2024-2025 row and refused a
      // 2025-2026 entry that was not a duplicate at all.
      if (!isEdit &&
          await IndividualRecordService.idExists(category, draft.id)) {
        if (mounted) setState(() => _saving = false);
        _showErrorDialog(
            '$_idLabel "${draft.id}" is already used in this category '
            'for ${academicTermLabel(draft.academicYear, draft.semester)}.');
        _refreshForm();
        return;
      }

      // 1) Persist.
      final saved = isEdit
          ? await IndividualRecordService.update(draft,
              previousPeriodId: target?.academicPeriodId)
          : await IndividualRecordService.create(draft);

      // 2) Retire this person's earlier terms. Adding someone for the term being
      //    run is the same statement as "they are not on the earlier terms any
      //    more", and doing only the first half is how one name ends up on the
      //    active roster twice.
      // The period is the one the form filed under, not whatever the read-back
      // happened to carry: this statement retires everything EXCEPT that period,
      // so an off-by-one here deactivates the record that was just saved.
      final retired = isEdit
          ? 0
          : await IndividualRecordService.retireEarlierPeriods(
              [(category: category, recordNo: saved.id)],
              academicPeriodId: draft.academicPeriodId ?? '',
            );

      // 3) Reflect the persisted row (uuid + real audit stamps) in the list
      //    and the shared directory, so the other screens see it too.
      if (isEdit) {
        final i = _records.indexWhere((r) => r.uuid == saved.uuid);
        if (i >= 0) _records[i] = saved;
      } else {
        _records.add(saved);
        // Jump the active tab to match so the new row is immediately visible.
        filter = category;
        search.clear();
      }
      _pushToDirectory(saved);

      // Close the dialog only now that the row is safely in the database. The
      // `_saving` flag is cleared here as well: this is the SUCCESS path, and
      // leaving it set is what left the next Add/Edit dialog opening with its
      // Save button already spinning and disabled.
      _editing = null;
      if (mounted) setState(() => _saving = false);
      if (dialogCtx.mounted) _closeFormDialog(dialogCtx);
      _showResultDialog(
        isEdit ? 'Updated Record' : 'Saved Record',
        detail:
            retired > 0 ? '$retired earlier-term record(s) deactivated' : null,
      );
      // Re-read the roster so the table shows the row the database now holds —
      // the server-assigned uuid and audit stamps, and the term's real status.
      // DataTracker already fires a refresh on the write; this makes the reload
      // immediate and visible even if that signal is missed.
      if (mounted) await _loadRecords(silent: true);
    } catch (e) {
      if (e is IndividualRecordSaveIncomplete) {
        final saved = e.record;
        if (isEdit) {
          final i = _records.indexWhere((r) => r.uuid == saved.uuid);
          if (i >= 0) _records[i] = saved;
        } else {
          _records.add(saved);
          filter = category;
          search.clear();
        }
        _pushToDirectory(saved);
        _editing = null;
        if (mounted) setState(() => _saving = false);
        if (dialogCtx.mounted) _closeFormDialog(dialogCtx);
        _showError('${e.message}');
        return;
      }
      if (mounted) setState(() => _saving = false);
      _showError('Could not save the record: $e');
      _refreshForm();
    }
  }

  /// Confirms a successful write with a centred dialog that closes itself after
  /// five seconds.
  ///
  /// A dialog rather than the floating SnackBar so the confirmation is not missed
  /// behind the roster the clerk looks at next, and an automatic close so it never
  /// has to be dismissed — long enough to read, gone before the next entry. A tap
  /// anywhere closes it sooner. [detail] is a second, quieter line for anything
  /// the headline cannot carry, such as the number of earlier-term enrolments a
  /// save retired.
  void _showResultDialog(
    String message, {
    String? detail,
    bool danger = false,
  }) {
    if (!mounted) return;
    // Deferred to the next frame: every caller reaches this straight after popping
    // the Add/Edit dialog, and pushing a route in the same frame as that pop can
    // reorder the two.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog<void>(
        context: context,
        barrierDismissible: true,
        barrierColor: Colors.black.withValues(alpha: 0.35),
        builder: (_) =>
            _AutoCloseMessage(message: message, detail: detail, danger: danger),
      );
    });
  }

  void _showSuccess(String msg, {bool danger = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: danger ? kDanger : kPrimary,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      content: Row(children: [
        const Icon(Icons.check_circle_outline, color: Colors.white, size: 18),
        const SizedBox(width: 10),
        Expanded(child: Text(msg, style: const TextStyle(color: Colors.white))),
      ]),
      duration: const Duration(seconds: 2),
    ));
  }

  /// A failed write gets the same floating treatment as a successful one, so a
  /// dropped connection is as visible as a saved record.
  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      backgroundColor: kDanger,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      content: Row(children: [
        const Icon(Icons.error_outline, color: Colors.white, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Text(msg,
              style: const TextStyle(color: Colors.white), maxLines: 3),
        ),
      ]),
      duration: const Duration(seconds: 4),
    ));
  }

  void _showErrorDialog(String msg) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('Already Exists',
            style: TextStyle(fontWeight: FontWeight.w700)),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  // ── BUILD ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: _fadeAnim,
      child: Scaffold(
        backgroundColor: kBg,
        // Same "+" affordance the Inventory page uses: Add Record lives at the
        // bottom-right instead of taking a slot in the filter bar.
        floatingActionButton: FloatingActionButton(
          onPressed: _openForm,
          backgroundColor: kPrimary,
          tooltip: 'Add Record',
          child: const Icon(Icons.add, color: Colors.white),
        ),
        body: Padding(
          padding: const EdgeInsets.all(24),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _buildHeaderRow(),
            const SizedBox(height: 20),
            _buildFilterBar(),
            const SizedBox(height: 16),
            _buildTabs(),
            const SizedBox(height: 14),
            // A failed refresh must be visible even when stale rows are still
            // on screen — otherwise the user reads the old list as current.
            if (_loadError != null && !_loading) ...[
              _loadErrorBanner(),
              const SizedBox(height: 14),
            ],
            Expanded(child: _buildTable(_filtered)),
          ]),
        ),
      ),
    );
  }

  /// Slim strip shown above the table when the last query failed but previous
  /// rows are still on screen.
  Widget _loadErrorBanner() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: kDanger.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kDanger.withValues(alpha: 0.28)),
      ),
      child: Row(children: [
        const Icon(Icons.cloud_off_rounded, size: 18, color: kDanger),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            'Could not refresh the record list — showing the last loaded data.',
            style: TextStyle(
                fontSize: 13.5, color: kDanger, fontWeight: FontWeight.w600),
          ),
        ),
        const SizedBox(width: 10),
        TextButton(
          onPressed: _loadRecords,
          style: TextButton.styleFrom(
            foregroundColor: kDanger,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('Retry'),
        ),
      ]),
    );
  }

  // ── HEADER ─────────────────────────────────────────────────────────────

  Widget _buildHeaderRow() {
    return LayoutBuilder(builder: (context, constraints) {
      final bool isNarrow = constraints.maxWidth < 700;

      final titleBlock = Row(
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
            child:
                const Icon(Icons.badge_outlined, color: Colors.white, size: 22),
          ),
          const SizedBox(width: 14),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Individual Record',
                style: TextStyle(
                    fontSize: 23,
                    fontWeight: FontWeight.w800,
                    color: kTextMain)),
            const Text('Manage Student, Faculty, & Staff Records',
                style: TextStyle(fontSize: 15, color: kTextSub)),
          ]),
        ],
      );

      final chips = _buildCategorySummary();

      if (isNarrow) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [titleBlock, const SizedBox(height: 12), chips],
        );
      }
      return Row(children: [titleBlock, const Spacer(), chips]);
    });
  }

  Widget _buildCategorySummary() {
    return Wrap(spacing: 8, runSpacing: 8, children: [
      _summaryChip('All', _totalCount, kPrimary, Icons.groups_rounded),
      _summaryChip('Students', _countFor('Student'), kStudentColor,
          Icons.school_outlined),
      _summaryChip('Faculty', _countFor('Faculty'), kFacultyColor,
          Icons.co_present_outlined),
      _summaryChip(
          'Staff', _countFor('Staff'), kStaffColor, Icons.badge_outlined),
    ]);
  }

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

  // ── FILTER BAR (search + academic year & semester + import) ───────────

  Widget _buildFilterBar() {
    final searchField = TextField(
      controller: search,
      // Debounced into a real database query rather than re-filtering the cached
      // roster, so a search covers everyone on file and not just the rows this
      // page happens to be holding.
      onChanged: _onSearchChanged,

      style: const TextStyle(fontSize: 16, color: kTextMain),
      decoration: InputDecoration(
        hintText: 'Search by ID, name, program, contact...',
        hintStyle: const TextStyle(color: kTextSub, fontSize: 15),
        prefixIcon: const Icon(Icons.search_rounded, color: kTextSub, size: 20),
        filled: true,
        fillColor: kCard,
        contentPadding: const EdgeInsets.symmetric(vertical: 12),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kBorder)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kBorder)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kPrimary, width: 1.5)),
      ),
    );

    // One dropdown carries both: "2025-2026 · 2nd Semester". The five terms come
    // from kAcademicTerms, so the list is the school's calendar rather than a
    // window rolled forward from today's date.
    final importBtn = OutlinedButton.icon(
      onPressed: _openImportDialog,
      icon: const Icon(Icons.upload_file_rounded, size: 17, color: kPrimary),
      label: const Text('Import Record'),
      style: OutlinedButton.styleFrom(
        foregroundColor: kPrimary,
        side: const BorderSide(color: kPrimary, width: 1.2),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
      ),
    );

    return LayoutBuilder(builder: (ctx, con) {
      final w = con.maxWidth;
      if (w < 780) {
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          searchField,
          const SizedBox(height: 10),
          Align(alignment: Alignment.centerLeft, child: importBtn),
        ]);
      }
      // Wide: search on the left, Import Record on the right.
      return Row(children: [
        Expanded(child: searchField),
        const SizedBox(width: 12),
        importBtn,
      ]);
    });
  }

  // ── CATEGORY TABS ──────────────────────────────────────────────────────

  Widget _buildTabs() {
    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF2F6),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: ['Student', 'Faculty', 'Staff'].map((tab) {
          final sel = filter == tab;
          return Expanded(
            child: GestureDetector(
              onTap: () {
                if (filter == tab) return;
                setState(() {
                  filter = tab;
                  // The search text is deliberately NOT cleared: typing a name
                  // once and tapping through Student/Faculty/Staff re-runs the
                  // same search against each tab instead of forcing a retype.
                  // Nothing is re-read from the database here — the rows are
                  // already in [_records] — so this is the whole cost of a tab
                  // click, and the table swaps in the next frame.
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: sel ? kPrimary : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: sel
                      ? [
                          BoxShadow(
                              color: kPrimary.withValues(alpha: 0.3),
                              blurRadius: 8,
                              offset: const Offset(0, 2))
                        ]
                      : [],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      tab == 'Student'
                          ? Icons.school_outlined
                          : tab == 'Faculty'
                              ? Icons.person_outlined
                              : Icons.badge_outlined,
                      size: 15,
                      color: sel ? Colors.white : kTextSub,
                    ),
                    const SizedBox(width: 6),
                    Text(tab,
                        style: TextStyle(
                          color: sel ? Colors.white : kTextSub,
                          fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                          fontSize: 16,
                        )),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  // ── ADD / EDIT CONTAINER (stepped dialog) ──────────────────────────────
  // One record at a time, one step at a time. The container never navigates:
  // it swaps its own body, so the table stays mounted behind it and every
  // record is still added individually.

  static const List<String> _formStepTitles = [
    'Record Type & School Year',
    'Personal Information',
    'Academic / Employment',
  ];

  Widget _buildFormDialog(BuildContext ctx, StateSetter setDlg) {
    final isEdit = _editing != null;
    final isStudent = _fCategory == 'Student';
    final screen = MediaQuery.of(ctx).size.width;
    final w = screen < 620 ? screen * 0.92 : 560.0;

    return Dialog(
      backgroundColor: kCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: w,
        constraints: const BoxConstraints(maxHeight: 660),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _formDialogHeader(ctx, isEdit),
          const Divider(color: kBorder, height: 1),
          _formStepBar(),
          Flexible(
            child: Form(
              key: _formKey,
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 18),
                child: _formStepBody(isStudent),
              ),
            ),
          ),
          const Divider(color: kBorder, height: 1),
          _formDialogFooter(ctx, setDlg, isEdit),
        ]),
      ),
    );
  }

  Widget _formDialogHeader(BuildContext ctx, bool isEdit) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 12, 14),
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: kPrimary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(isEdit ? Icons.edit_outlined : Icons.person_add_outlined,
              color: kPrimary, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
            child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(isEdit ? 'Update Record' : 'Add New Record',
                style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.w700,
                    color: kTextMain)),
            Text('${_fCategory ?? ''} record',
                style: const TextStyle(fontSize: 13.5, color: kTextSub)),
          ],
        )),
        IconButton(
          onPressed: () => _closeFormDialog(ctx),
          icon: const Icon(Icons.close_rounded, color: kTextSub),
          iconSize: 20,
          tooltip: 'Close',
        ),
      ]),
    );
  }

  /// Short progress bars + a caption, so it is obvious the record is being
  /// filled in pieces instead of all at once.
  Widget _formStepBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          for (var i = 0; i < _formStepCount; i++) ...[
            Expanded(
                child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              height: 5,
              decoration: BoxDecoration(
                color: i <= _formStep ? kPrimary : const Color(0xFFEEF2F6),
                borderRadius: BorderRadius.circular(3),
              ),
            )),
            if (i < _formStepCount - 1) const SizedBox(width: 6),
          ],
        ]),
        const SizedBox(height: 10),
        Text(
          'Step ${_formStep + 1} of $_formStepCount · ${_formStepTitles[_formStep]}',
          style: const TextStyle(
              fontSize: 12.5, color: kTextSub, fontWeight: FontWeight.w700),
        ),
      ]),
    );
  }

  /// Only the fields belonging to the current step are mounted, so "Next"
  /// validates the visible ones and nothing else.
  Widget _formStepBody(bool isStudent) {
    switch (_formStep) {
      case 0:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sectionHeader(Icons.badge_outlined, 'Record Details'),
          _fieldGrid([_categoryField(_editing != null), _idField()],
              columns: 2),
          const SizedBox(height: 16),
          _schoolYearFields(),
        ]);
      case 1:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sectionHeader(Icons.person_outline, 'Personal Information'),
          // The address is the longest value typed in this step and would be
          // squeezed into a half-width grid column, so it gets a full-width
          // row of its own underneath the two-column grid.
          _fieldGrid([
            _firstNameField(),
            _middleNameField(),
            _lastNameField(),
            _suffixField(),
            _sexField(),
            _birthField(),
            _contactField(),
            _emailField(),
          ], columns: 2),
          const SizedBox(height: 14),
          _addressField(),
        ]);
      default:
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          _sectionHeader(
            isStudent ? Icons.school_outlined : Icons.work_outline,
            isStudent
                ? 'Academic Information'
                : (_fCategory == 'Faculty'
                    ? 'Teaching Assignment'
                    : 'Employment Information'),
          ),
          _fieldGrid(
            isStudent
                ? [_instituteField(), _programField(), _yearLevelField()]
                : [_departmentField(), _positionField()],
            columns: 2,
          ),
        ]);
    }
  }

  Widget _formDialogFooter(BuildContext ctx, StateSetter setDlg, bool isEdit) {
    final isLast = _formStep == _formStepCount - 1;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 14, 24, 18),
      child: Row(children: [
        const Spacer(),
        if (_formStep > 0) ...[
          OutlinedButton.icon(
            onPressed: () => setDlg(() => setState(() => _formStep--)),
            icon: const Icon(Icons.arrow_back_rounded, size: 16),
            label: const Text('Back'),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: kBorder),
              foregroundColor: kTextSub,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
          ),
          const SizedBox(width: 10),
        ],
        if (!isLast)
          ElevatedButton.icon(
            onPressed: () => _formNext(setDlg),
            icon: const Icon(Icons.arrow_forward_rounded, size: 16),
            label: const Text('Next'),
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
          )
        else
          ElevatedButton.icon(
            // The dialog stays open while the write is in flight and its button
            // shows a spinner, so a double tap cannot insert the same person
            // number twice and the user sees that something is happening.
            onPressed: _saving
                ? null
                : () {
                    if (!(_formKey.currentState?.validate() ?? false)) return;
                    _saveForm(ctx);
                  },
            icon: _saving
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Icon(isEdit ? Icons.save_outlined : Icons.add, size: 16),
            label: Text(_saving
                ? 'Saving…'
                : (isEdit ? 'Update Record' : 'Save Record')),
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: kPrimary.withValues(alpha: 0.6),
              disabledForegroundColor: Colors.white70,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            ),
          ),
      ]),
    );
  }

  Widget _sectionHeader(IconData icon, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(children: [
        Icon(icon, size: 17, color: kPrimary),
        const SizedBox(width: 8),
        Text(title,
            style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: kTextMain,
                letterSpacing: 0.3)),
        const SizedBox(width: 12),
        const Expanded(child: Divider(color: kBorder, height: 1)),
      ]),
    );
  }

  /// Lays fields out in a fixed-column grid that collapses on narrow screens.
  Widget _fieldGrid(List<Widget> fields, {required int columns}) {
    const gap = 12.0;
    return LayoutBuilder(builder: (context, c) {
      final w = (c.maxWidth - gap * (columns - 1)) / columns;
      return Wrap(
        spacing: gap,
        runSpacing: 14,
        children: fields.map((f) => SizedBox(width: w, child: f)).toList(),
      );
    });
  }

  // ── FORM FIELDS ────────────────────────────────────────────────────────

  String? _requiredText(String? v) =>
      (v == null || v.trim().isEmpty) ? 'This field is required' : null;

  Widget _categoryField(bool isEdit) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _dlabel('Record Category'),
      DropdownButtonFormField<String>(
        initialValue: _fCategory,
        isExpanded: true,
        onChanged: isEdit
            ? null
            : (v) {
                if (v == null || v == _fCategory) return;
                _fCategory = v;
                // Category drives which academic/employment fields apply.
                _fInstitute = null;
                _fProgram = null;
                _fYearLevel = null;
                _fDepartment = null;
                _fPosition = null;
                // Faculty/Staff get a generated 2025F001 / 2025S001
                // number, Students bring their own 6-digit one, so the ID has
                // to be REPLACED in both directions. Clearing it on the way back
                // to Student stops the auto-generated number from lingering in
                // the field and being saved as the student's ID.
                if (v == 'Student') {
                  _cId.clear();
                } else {
                  // The next free number comes from the database, so a row
                  // saved on another device cannot be overwritten.
                  _cId.clear();
                  _fillNextId(v);
                }
                _refreshForm();
              },
        decoration: _ideco('Select category',
            prefixIcon: Icons.category_outlined, readOnly: isEdit),
        style: const TextStyle(fontSize: 15, color: kTextMain),
        items: const ['Student', 'Faculty', 'Staff']
            .map((e) => DropdownMenuItem(value: e, child: Text(e)))
            .toList(),
      ),
    ]);
  }

  Widget _idField() {
    final isStudent = _fCategory == 'Student';
    final isEdit = _editing != null;
    final readOnly = !isStudent || isEdit;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _dlabel(isStudent
          ? 'Student ID'
          : (_fCategory == 'Faculty' ? 'Faculty ID' : 'Staff ID')),
      TextFormField(
        controller: _cId,
        readOnly: readOnly,
        keyboardType: isStudent ? TextInputType.number : TextInputType.text,
        inputFormatters: isStudent
            ? [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6)
              ]
            : [],
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: readOnly ? kTextSub : kTextMain,
        ),
        decoration: _ideco('e.g. 2025F001',
            prefixIcon: Icons.badge_outlined,
            readOnly: readOnly,
            suffix: readOnly && !isEdit
                ? (_fetchingId
                    ? const Padding(
                        padding: EdgeInsets.only(right: 12),
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: kPrimary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Text('Auto',
                            style: TextStyle(
                                fontSize: 12,
                                color: kPrimary,
                                fontWeight: FontWeight.w600)),
                      ))
                : null),
        validator: (v) {
          if (v == null || v.trim().isEmpty) return 'ID is required';
          if (isStudent && v.trim().length != 6) {
            return 'Must be exactly 6 digits';
          }
          final dup = _records.any((r) =>
              r.category == _fCategory &&
              r.id == v.trim() &&
              !identical(r, _editing));
          if (dup) {
            return _fCategory == 'Student'
                ? 'This Student ID already exists'
                : 'This ID is already in use';
          }
          return null;
        },
      ),
    ]);
  }

  /// One "School Year & Semester" dropdown, offering the five terms the school
  /// runs.
  ///
  /// This was two free-text year boxes beside a semester dropdown, which let a
  /// clerk file somebody under '2027-2028 · Summer' — a term that has never run,
  /// that nothing in the filter dropdown can select, and that the unique
  /// constraint then counts as a different person. Picking the term removes the
  /// possibility rather than reporting it afterwards.
  Widget _schoolYearFields() {
    final current = _composedAcademicYear;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _dlabel('School Year & Semester'),
      DropdownButtonFormField<String>(
        key: ValueKey('form-term-$_fCategory'),
        initialValue: kAcademicTerms
                .any((t) => t.year == current && t.semester == _fSemester)
            ? academicTermLabel(current, _fSemester ?? '')
            : academicTermLabel(_defaultAcademicYear, _defaultSemester),
        isExpanded: true,
        decoration:
            _ideco('Select term', prefixIcon: Icons.calendar_month_outlined),
        style: const TextStyle(fontSize: 15, color: kTextMain),
        items: [
          for (final t in kAcademicTerms)
            DropdownMenuItem(
              value: academicTermLabel(t.year, t.semester),
              child: Row(children: [
                Flexible(
                  child: Text(
                    academicTermLabel(t.year, t.semester),
                    style: const TextStyle(fontSize: 15),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (isCurrentTerm(t.year, t.semester)) ...[
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: kSuccess.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: const Text("CURRENT",
                        style: TextStyle(
                            fontSize: 9.5,
                            fontWeight: FontWeight.w800,
                            color: kSuccess,
                            letterSpacing: 0.5)),
                  ),
                ],
              ]),
            ),
        ],
        onChanged: (v) {
          if (v == null) return;
          final i = v.indexOf(' · ');
          if (i < 0) return;
          // "2023-2024 · 1st Semester" -> year "2023-2024", semester "1st
          // Semester". The year still has to be split into its two boxes before
          // [_composedAcademicYear] puts it back together; storing the whole
          // label in the end box is what turned the composed year into
          // "2023-2024-1st Semester" and left [_fPeriodId] null.
          final year = v.substring(0, i);
          final semester = v.substring(i + 3);
          final parts = year.split('-');
          setState(() {
            _cYearStart.text = parts.isNotEmpty ? parts.first : '';
            _cYearEnd.text = parts.length > 1 ? parts.last : '';
            _fSemester = semester;
            _fPeriodId = ReferenceCatalog.periodIdFor(year, semester);
          });
          _refreshForm();
          // The year in a generated Faculty/Staff number is the year of the
          // term being filed, so filing somebody under 2026-2027 must produce
          // '2026F001'. Re-issued rather than hand-corrected: the sequence is
          // per cohort year, and editing the digits could land on a number
          // somebody else already holds.
          final category = _fCategory;
          if (category != null && category != 'Student' && _editing == null) {
            _fillNextId(category);
          }
        },
      ),
      if (_composedAcademicYear.isEmpty) ...[
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: kPrimary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: kPrimary.withValues(alpha: 0.18)),
          ),
          child: Row(children: [
            const Icon(Icons.info_outline, size: 14, color: kPrimary),
            const SizedBox(width: 7),
            const Expanded(
              child: Text(
                'Pick the term this record belongs to.',
                style: TextStyle(
                    fontSize: 12, color: kPrimary, fontWeight: FontWeight.w600),
              ),
            ),
          ]),
        ),
      ],
    ]);
  }

  Widget _sexField() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _dlabel('Sex'),
      DropdownButtonFormField<String>(
        initialValue: _fSex,
        isExpanded: true,
        decoration: _ideco('Select sex', prefixIcon: Icons.wc_rounded),
        style: const TextStyle(fontSize: 15, color: kTextMain),
        items: kSexes
            .map((s) => DropdownMenuItem(value: s, child: Text(s)))
            .toList(),
        onChanged: (v) {
          _fSex = v;
          _refreshForm();
        },
        validator: _requiredText,
      ),
    ]);
  }

  Widget _birthField() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _dlabel('Birth Date'),
      TextFormField(
        controller: _cBirth,
        readOnly: true,
        onTap: _pickBirthDate,
        style: const TextStyle(fontSize: 15, color: kTextMain),
        decoration: _ideco('Select date', prefixIcon: Icons.cake_outlined),
      ),
    ]);
  }

  Future<void> _pickBirthDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _fBirthDate ?? DateTime(now.year - 20),
      firstDate: DateTime(now.year - 90),
      lastDate: now,
    );
    if (picked != null) {
      _fBirthDate = picked;
      _cBirth.text = DateFormat('MMM d, yyyy').format(picked);
      _refreshForm();
    }
  }

  Widget _suffixField() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _dlabel('Suffix'),
      TextFormField(
        controller: _cSuffix,
        textCapitalization: TextCapitalization.words,
        style: const TextStyle(fontSize: 15, color: kTextMain),
        decoration:
            _ideco('Jr., III (optional)', prefixIcon: Icons.tag_rounded),
      ),
    ]);
  }

  Widget _firstNameField() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _dlabel('First Name'),
      TextFormField(
        controller: _cFirst,
        textCapitalization: TextCapitalization.words,
        style: const TextStyle(fontSize: 15, color: kTextMain),
        decoration: _ideco('e.g. Maria', prefixIcon: Icons.person_outline),
        validator: _requiredText,
      ),
    ]);
  }

  Widget _middleNameField() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _dlabel('Middle Name'),
      TextFormField(
        controller: _cMiddle,
        textCapitalization: TextCapitalization.words,
        style: const TextStyle(fontSize: 15, color: kTextMain),
        decoration: _ideco('e.g. Santos (optional)'),
      ),
    ]);
  }

  Widget _lastNameField() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _dlabel('Last Name'),
      TextFormField(
        controller: _cLast,
        textCapitalization: TextCapitalization.words,
        style: const TextStyle(fontSize: 15, color: kTextMain),
        decoration: _ideco('e.g. Dela Cruz', prefixIcon: Icons.person_outline),
        validator: _requiredText,
      ),
    ]);
  }

  Widget _contactField() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _dlabel('Contact Number'),
      TextFormField(
        controller: _cContact,
        keyboardType: TextInputType.phone,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(11),
        ],
        style: const TextStyle(fontSize: 15, color: kTextMain),
        decoration:
            _ideco('e.g. 09171234567', prefixIcon: Icons.phone_outlined),
      ),
    ]);
  }

  Widget _emailField() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _dlabel('Email Address'),
      TextFormField(
        controller: _cEmail,
        keyboardType: TextInputType.emailAddress,
        style: const TextStyle(fontSize: 15, color: kTextMain),
        decoration: _ideco('e.g. name@tcgc.edu.pg or name@gmail.com',
            prefixIcon: Icons.email_outlined),
        validator: (v) {
          if (v == null || v.trim().isEmpty) return null;
          return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(v.trim())
              ? null
              : 'Enter a valid email';
        },
      ),
    ]);
  }

  Widget _addressField() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _dlabel('Address'),
      TextFormField(
        controller: _cAddress,
        maxLines: 2,
        minLines: 1,
        textCapitalization: TextCapitalization.words,
        style: const TextStyle(fontSize: 15, color: kTextMain),
        decoration: _ideco('e.g. Brgy. San Rafael, Tarlac City',
            prefixIcon: Icons.location_on_outlined),
      ),
    ]);
  }

  Widget _instituteField() {
    final institutes = _catalog.keys.toList()..sort();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _dlabel('Institute'),
      DropdownButtonFormField<String>(
        key: ValueKey('form-inst-${_catalog.length}-$_fInstitute'),
        initialValue: _fInstitute,
        isExpanded: true,
        decoration: _ideco('Select institute',
            prefixIcon: Icons.account_balance_outlined),
        style: const TextStyle(fontSize: 15, color: kTextMain),
        items: [
          ...institutes.map((e) => DropdownMenuItem(value: e, child: Text(e))),
          const DropdownMenuItem(
            value: _kAddProgram,
            child: Row(children: [
              Icon(Icons.add_circle_outline, size: 17, color: kPrimary),
              SizedBox(width: 8),
              Text('Add institute / program...',
                  style: TextStyle(
                      fontSize: 15,
                      color: kPrimary,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        ],
        onChanged: (v) {
          if (v == _kAddProgram) {
            _openAddProgramDialog();
            return;
          }
          _fInstitute = v;
          _fProgram = null;
          // Institutes with a single offering (ICS, IHS) pre-select it so the
          // user doesn't have to pick the obvious option.
          final progs =
              v == null ? const <String>[] : (_catalog[v] ?? const <String>[]);
          if (progs.length == 1) _fProgram = _programValue(v!, progs.first);
          _refreshForm();
        },
        validator: _requiredText,
      ),
    ]);
  }

  Widget _programField() {
    final readOnly = _fInstitute == null;
    final institute = _fInstitute;
    final programs = _programOptions;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _dlabel('Program'),
      DropdownButtonFormField<String>(
        key: ValueKey('form-prog-$institute-$_fProgram'),
        initialValue: _fProgram,
        isExpanded: true,
        decoration: _ideco(
          readOnly
              ? 'Select an institute first'
              : (programs.length == 1
                  ? 'Only one program offered'
                  : 'Select program'),
          prefixIcon: Icons.menu_book_outlined,
          readOnly: readOnly,
        ),
        style: TextStyle(fontSize: 15, color: readOnly ? kTextSub : kTextMain),
        // Only the programs of the institute already chosen — pick ICS and the
        // list is just BSCS, pick IBFS and only its three programs show up.
        items: [
          ...programs.map((p) => DropdownMenuItem(
                value: _programValue(institute!, p),
                child: Text(p,
                    style: const TextStyle(
                        fontSize: 15, overflow: TextOverflow.ellipsis)),
              )),
          const DropdownMenuItem(
            value: _kAddProgram,
            child: Row(children: [
              Icon(Icons.add_circle_outline, size: 17, color: kPrimary),
              SizedBox(width: 8),
              Text('Add institute / program...',
                  style: TextStyle(
                      fontSize: 15,
                      color: kPrimary,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        ],
        onChanged: (v) {
          if (v == _kAddProgram) {
            _openAddProgramDialog();
          } else if (v != null) {
            _fProgram = v;
            _refreshForm();
          }
        },
        validator: (v) => _fInstitute == null ? null : _requiredText(v),
      ),
    ]);
  }

  /// Opens the single Add Institute / Program form, then selects whatever the
  /// database stored. The dialog writes the row itself (see
  /// [ReferenceDataService.saveInstituteAndProgram]); an institute alone is
  /// legal and its program is optional, but a program always lands on an
  /// institute — new or already on file.
  Future<void> _openAddProgramDialog() async {
    final result = await showDialog<
        ({String instituteCode, String programCode, bool created})?>(
      context: context,
      builder: (ctx) => _AddProgramDialog(
        institutes: (_catalog.keys.toList()..sort()),
        initialInstitute: _fInstitute,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _fInstitute = result.instituteCode;
      // An institute on its own comes back with an empty program code: leave the
      // program box empty rather than fabricate a "$institute|" value no item
      // matches.
      _fProgram = result.programCode.isEmpty
          ? null
          : _programValue(result.instituteCode, result.programCode);
    });
    _refreshForm();
    // Only when something was actually written. Picking an institute already on
    // file and saving changes nothing, so it must not claim a save.
    if (result.created) _showResultDialog('Saved Record');
  }

  Widget _yearLevelField() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _dlabel('Year Level'),
      DropdownButtonFormField<String>(
        initialValue: _fYearLevel,
        isExpanded: true,
        decoration: _ideco('Select year level',
            prefixIcon: Icons.calendar_today_outlined),
        style: const TextStyle(fontSize: 15, color: kTextMain),
        items: kYearLevels
            .map((e) => DropdownMenuItem(value: e, child: Text(e)))
            .toList(),
        onChanged: (v) {
          _fYearLevel = v;
          _refreshForm();
        },
        validator: _requiredText,
      ),
    ]);
  }

  Widget _departmentField() {
    final isFaculty = _fCategory == 'Faculty';
    final options = _departmentOptions(_fCategory);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _dlabel(isFaculty ? 'Institute' : 'Department / Office'),
      DropdownButtonFormField<String>(
        key: ValueKey('form-dept-$_fCategory-$_fDepartment'),
        initialValue: _fDepartment,
        isExpanded: true,
        decoration: _ideco(
          isFaculty ? 'Select institute' : 'Select department / office',
          prefixIcon: Icons.business_outlined,
        ),
        style: const TextStyle(fontSize: 15, color: kTextMain),
        items: [
          ...options.map((e) => DropdownMenuItem(
              value: e, child: Text(e, style: const TextStyle(fontSize: 15)))),
          // Faculty's "Department" is the institute picker, and a new institute
          // is already added through the Program dropdown, so the add item is
          // only offered to staff — whose list really is departments / offices.
          if (!isFaculty)
            const DropdownMenuItem(
              value: _kAddDepartment,
              child: Row(children: [
                Icon(Icons.add_circle_outline, size: 17, color: kPrimary),
                SizedBox(width: 8),
                Text('Add department / office...',
                    style: TextStyle(
                        fontSize: 15,
                        color: kPrimary,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
        ],
        onChanged: (v) {
          if (v == _kAddDepartment) {
            _openAddDepartmentDialog();
            return;
          }
          _fDepartment = v;
          _refreshForm();
        },
        validator: _requiredText,
      ),
    ]);
  }

  Widget _positionField() {
    final isFaculty = _fCategory == 'Faculty';
    final options = _positionOptions(_fCategory);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      _dlabel('Position'),
      DropdownButtonFormField<String>(
        key: ValueKey('form-pos-$_fCategory-$_fPosition'),
        initialValue: _fPosition,
        isExpanded: true,
        decoration: _ideco(
          isFaculty ? 'Select faculty position' : 'Select staff position',
          prefixIcon: Icons.work_outline,
        ),
        style: const TextStyle(fontSize: 15, color: kTextMain),
        items: [
          ...options.map((e) => DropdownMenuItem(
              value: e, child: Text(e, style: const TextStyle(fontSize: 15)))),
          const DropdownMenuItem(
            value: _kAddPosition,
            child: Row(children: [
              Icon(Icons.add_circle_outline, size: 17, color: kPrimary),
              SizedBox(width: 8),
              Text('Add position...',
                  style: TextStyle(
                      fontSize: 15,
                      color: kPrimary,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        ],
        onChanged: (v) {
          if (v == _kAddPosition) {
            _openAddPositionDialog();
            return;
          }
          _fPosition = v;
          _refreshForm();
        },
        validator: _requiredText,
      ),
    ]);
  }

  /// Opens the small add dialog for a department / office, then selects what the
  /// database just stored. [ReferenceDataService.addDepartment] writes the row
  /// and reloads the catalog, so the value is a real `departments_offices` id by
  /// the time the form saves — not a name typed into a dropdown the database has
  /// never heard of.
  Future<void> _openAddDepartmentDialog() async {
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => _AddNamedDialog(
        title: 'Add Department / Office',
        subtitle: 'Added to the list',
        label: 'Department / Office',
        hint: 'e.g. Office of the Registrar',
        icon: Icons.business_outlined,
        onSave: (value) async =>
            (await ReferenceDataService.addDepartment(value)).name,
      ),
    );
    if (name == null || !mounted) return;
    setState(() => _fDepartment = name);
    _refreshForm();
    _showResultDialog('Saved Record');
  }

  /// The position counterpart of [_openAddDepartmentDialog].
  Future<void> _openAddPositionDialog() async {
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => _AddNamedDialog(
        title: 'Add Position',
        subtitle: 'Added to the list',
        label: 'Position',
        hint: 'e.g. Instructor',
        icon: Icons.work_outline,
        onSave: (value) async =>
            (await ReferenceDataService.addPosition(value)).name,
      ),
    );
    if (name == null || !mounted) return;
    setState(() => _fPosition = name);
    _refreshForm();
    _showResultDialog('Saved Record');
  }

  Widget _dlabel(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(label,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: kTextSub)),
      );

  InputDecoration _ideco(String hint,
      {IconData? prefixIcon, bool readOnly = false, Widget? suffix}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: kTextSub, fontSize: 14.5),
      filled: true,
      fillColor: readOnly ? const Color(0xFFF1F5F9) : const Color(0xFFFAFCFE),
      prefixIcon: prefixIcon != null
          ? Icon(prefixIcon, size: 18, color: kTextSub)
          : null,
      suffixIcon: suffix,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kBorder)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kBorder)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kPrimary, width: 1.5)),
      errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kDanger)),
      focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kDanger, width: 1.5)),
    );
  }

  // ── DETAIL VIEW ────────────────────────────────────────────────────────

  void _showDetail(IndividualRecord r) {
    final color = _categoryColor(r.category);
    showDialog(
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
                // Header
                Row(children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                        color: color, borderRadius: BorderRadius.circular(12)),
                    child: Icon(
                      r.isStudent
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
                      Text(r.fullName,
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: kTextMain)),
                      const SizedBox(height: 5),
                      Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 3),
                              decoration: BoxDecoration(
                                  color: color.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6)),
                              child: Text(r.category,
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold,
                                      color: color)),
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 9, vertical: 3),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF1F5F9),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Text(r.id,
                                  style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: kTextSub)),
                            ),
                            if (r.academicYear.isNotEmpty)
                              Text('AY ${r.academicYear} · ${r.semester}',
                                  style: const TextStyle(
                                      fontSize: 12.5, color: kTextSub)),
                          ]),
                    ],
                  )),
                  IconButton(
                      onPressed: () => Navigator.pop(ctx),
                      icon: const Icon(Icons.close_rounded, color: kTextSub),
                      iconSize: 20),
                ]),
                const SizedBox(height: 18),
                const Divider(color: kBorder, height: 1),
                const SizedBox(height: 6),

                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _infoSection(
                              'Personal Information', Icons.person_outline, [
                            _infoRow('First Name', r.firstName),
                            _infoRow('Middle Name', r.middleName),
                            _infoRow('Last Name', r.lastName),
                            _infoRow('Suffix', r.suffix),
                            _infoRow('Sex', r.sex),
                            _infoRow(
                                'Birth Date',
                                r.birthDate == null
                                    ? ''
                                    : DateFormat('MMMM d, yyyy')
                                        .format(r.birthDate!)),
                            _infoRow('Contact', r.contact),
                            _infoRow('Email', r.email),
                            _infoRow('Address', r.address),
                          ]),

                          // Academic / employment fields depend on the category:
                          // a student has a program + year level, a faculty member
                          // a teaching assignment, a staff member an office + post.
                          _infoSection(
                            r.isStudent
                                ? 'Academic Information'
                                : (r.category == 'Faculty'
                                    ? 'Teaching Assignment'
                                    : 'Employment Information'),
                            r.isStudent
                                ? Icons.school_outlined
                                : Icons.work_outline,
                            [
                              _infoRow('School Year', r.academicYear),
                              _infoRow('Semester', r.semester),
                              if (r.isStudent) ...[
                                _infoRow('Institute', r.institute),
                                _infoRow('Program', r.program),
                                _infoRow('Year Level', r.yearLevel),
                              ] else if (r.category == 'Faculty') ...[
                                // A Faculty member has no department / office,
                                // only a teaching institute and a post.
                                _infoRow('Institute', r.institute),
                                _infoRow('Position', r.position),
                              ] else ...[
                                _infoRow('Department / Office', r.department),
                                _infoRow('Position', r.position),
                              ],
                            ],
                          ),

                          // Everything here is read straight from the row: the
                          // timestamps come from the database trigger (server
                          // clock) and the "by" fields are resolved account
                          // uuids, not the hard-coded strings this dialog
                          // used to show.
                          _infoSection(
                              'Record Information', Icons.history_rounded, [
                            _infoRow('Status', r.status),
                            _infoRow(
                                'Created',
                                r.createdAt == null
                                    ? '—'
                                    : DateFormat('MMM d, yyyy, h:mm a')
                                        .format(r.createdAt!)),
                            _infoRow('Created By', _auditWho(r.createdBy)),
                          ]),
                        ]),
                  ),
                ),

                const SizedBox(height: 8),
                const Divider(color: kBorder, height: 1),
                const SizedBox(height: 14),
                Row(children: [
                  Expanded(
                      child: OutlinedButton.icon(
                    onPressed: () {
                      Navigator.pop(ctx);
                      _openForm(edit: r);
                    },
                    icon: const Icon(Icons.edit_outlined,
                        size: 16, color: kPrimary),
                    label: const Text('Edit Record',
                        style: TextStyle(color: kPrimary)),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: kBorder),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 13),
                    ),
                  )),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _infoSection(String title, IconData icon, List<Widget> rows) {
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
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
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, c) {
          final twoCol = c.maxWidth > 460;
          final pairs = <Widget>[];
          for (var i = 0; i < rows.length; i += (twoCol ? 2 : 1)) {
            final end = (i + (twoCol ? 2 : 1)).clamp(0, rows.length);
            pairs.add(Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
      ]),
    );
  }

  Widget _infoRow(String label, String value) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label,
          style: const TextStyle(
              fontSize: 11.5, color: kTextSub, fontWeight: FontWeight.w600)),
      const SizedBox(height: 2),
      Text(value.isEmpty ? '—' : value,
          style: const TextStyle(
              fontSize: 14.5, color: kTextMain, fontWeight: FontWeight.w600)),
    ]);
  }

  /// Turns a `profiles.id` from the audit columns into a name. RLS only lets a
  /// Clinic Head see every profile, so a member sees their own account and
  /// falls back to a short uuid prefix for anyone else rather than showing a
  /// blank.
  String _auditWho(String? id) {
    if (id == null || id.isEmpty) return '—';
    final name = _userNames[id];
    if (name != null && name.isNotEmpty) return name;
    return id.length > 8 ? id.substring(0, 8) : id;
  }

  // ── TABLE ──────────────────────────────────────────────────────────────

  Widget _buildTable(List<IndividualRecord> list) {
    return Container(
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 2))
        ],
      ),
      child: _loading
          ? _loadingState()
          : list.isEmpty
              ? _emptyState()
              : Column(children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: SingleChildScrollView(
                        child: LayoutBuilder(builder: (ctx, con) {
                          return SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: ConstrainedBox(
                              constraints:
                                  BoxConstraints(minWidth: con.maxWidth),
                              child: DataTable(
                                headingRowHeight: 52,
                                dataRowMinHeight: 58,
                                dataRowMaxHeight: 68,
                                showCheckboxColumn: false,
                                headingRowColor: WidgetStateProperty.all(
                                    const Color(0xFFF8FAFC)),
                                headingTextStyle: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: kTextSub,
                                    fontSize: 14,
                                    letterSpacing: 0.5),
                                dataTextStyle: const TextStyle(
                                    color: kTextMain, fontSize: 15),
                                columnSpacing: 24,
                                horizontalMargin: 20,
                                dividerThickness: 1,
                                border: const TableBorder(
                                  horizontalInside:
                                      BorderSide(color: kBorder, width: 0.8),
                                ),
                                columns: [
                                  DataColumn(
                                      label: Text(_idLabel.toUpperCase())),
                                  const DataColumn(label: Text('NAME')),
                                  const DataColumn(label: Text('SEX')),
                                  // A student's column is their degree program; for
                                  // faculty / staff the same slot holds their
                                  // department, so the header follows the tab.
                                  DataColumn(
                                      label: Text(filter == 'Student'
                                          ? 'PROGRAM'
                                          : 'INSTITUTE')),
                                  const DataColumn(label: Text('CONTACT')),
                                  const DataColumn(label: Text('ACTIONS')),
                                ],
                                rows: list.asMap().entries.map((entry) {
                                  final r = entry.value;
                                  final even = entry.key % 2 == 0;
                                  return DataRow(
                                    color: WidgetStateProperty.all(
                                        even ? kCard : const Color(0xFFFAFCFD)),
                                    onSelectChanged: (_) => _showDetail(r),
                                    cells: [
                                      DataCell(Text(
                                        r.id,
                                        style: TextStyle(
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700,
                                            color: _categoryColor(r.category)),
                                      )),
                                      DataCell(Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        mainAxisAlignment:
                                            MainAxisAlignment.center,
                                        children: [
                                          Text(r.fullName,
                                              style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                  fontSize: 15)),
                                          if (r.academicYear.isNotEmpty ||
                                              r.semester.isNotEmpty) ...[
                                            const SizedBox(height: 2),
                                            Text(
                                                academicTermLabel(
                                                    r.academicYear, r.semester),
                                                style: const TextStyle(
                                                    fontSize: 12,
                                                    color: kTextSub)),
                                          ],
                                        ],
                                      )),
                                      DataCell(Text(r.sex.isEmpty ? '—' : r.sex,
                                          style: const TextStyle(
                                              fontSize: 14.5,
                                              color: kTextSub))),
                                      DataCell(Text(
                                        r.programLabel,
                                        style: const TextStyle(
                                            fontSize: 14.5,
                                            fontWeight: FontWeight.w600,
                                            color: kPrimary),
                                      )),
                                      DataCell(Text(
                                          r.contact.isEmpty ? '—' : r.contact,
                                          style: const TextStyle(
                                              fontSize: 14.5,
                                              color: kTextSub))),
                                      DataCell(Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            _actionBtn(
                                              icon: Icons.edit_outlined,
                                              color: kPrimary,
                                              tooltip: 'Edit',
                                              onTap: () => _openForm(edit: r),
                                            ),
                                            const SizedBox(width: 4),
                                            // Delete only. "Delete" is a soft
                                            // delete: the row flips to Inactive and
                                            // leaves this list for the Archive, where
                                            // it can be brought back. Restore used to
                                            // share this button, which meant the
                                            // roster had to list the Inactive rows it
                                            // was meant to be hiding — one person once
                                            // per term.
                                            _actionBtn(
                                              icon: Icons.delete_outline,
                                              color: kDanger,
                                              tooltip: 'Delete',
                                              onTap: () => _confirmDelete(r),
                                            ),
                                          ])),
                                    ],
                                  );
                                }).toList(),
                              ),
                            ),
                          );
                        }),
                      ),
                    ),
                  ),
                  _tableFooter(),
                ]),
    );
  }

  /// The strip under the table is now only a way out of a search that narrowed
  /// the roster, so it disappears entirely when nothing is filtered. The term is
  /// no longer shown as a page caption — it sits under each person's name, where
  /// it belongs to that row.
  Widget _tableFooter() {
    final searching = search.text.trim().isNotEmpty;
    if (!searching) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: kBorder, width: 0.8)),
      ),
      child: Row(children: [
        TextButton(
          onPressed: () => setState(search.clear),
          style: TextButton.styleFrom(
            foregroundColor: kPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: const Text('Clear search'),
        ),
      ]),
    );
  }

  Widget _actionBtn(
      {required IconData icon,
      required Color color,
      required String tooltip,
      required VoidCallback onTap}) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
              color: color.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8)),
          child: Icon(icon, color: color, size: 16),
        ),
      ),
    );
  }

  /// Shown while the roster query is in flight, so the table never flashes
  /// "no students" on the way to a real answer.
  Widget _loadingState() {
    return SizedBox(
      height: 260,
      child: Center(
        child: _loadError == null
            ? const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              )
            : Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.cloud_off_rounded,
                        size: 34, color: kTextSub),
                    const SizedBox(height: 12),
                    const Text('Could not load the record list',
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: kTextMain)),
                    const SizedBox(height: 6),
                    Text(_loadError!,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 13, color: kTextSub, height: 1.4)),
                    const SizedBox(height: 14),
                    OutlinedButton.icon(
                      onPressed: _loadRecords,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('Try again'),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _emptyState() {
    final q = search.text.trim();
    // The search text survives a tab switch, so the message always names the
    // tab that came back empty instead of a bare "No results".
    final msg = q.isEmpty
        ? (_countFor(filter) == 0
            ? 'No $filter records added yet.'
            : 'No $filter records match "$q".')
        : 'No $filter records match "$q".';
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.search_off_rounded,
              size: 48, color: AppColors.borderStrong),
          const SizedBox(height: 12),
          Text(
            msg,
            textAlign: TextAlign.center,
            style: const TextStyle(color: kTextSub, fontSize: 16),
          ),
          // A search that finds nothing while the category plainly has people in
          // it needs a way out, or the empty table is a dead end.
          if (q.isNotEmpty) ...[
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => setState(search.clear),
              icon: const Icon(Icons.close_rounded, size: 18),
              label: const Text('Clear search'),
            ),
          ],
        ]),
      ),
    );
  }

  // ── DELETE ──────────────────────────────────────────────────────────────
  // Deleting is a soft delete: `status` flips to 'Archived' in the database,
  // the row and its audit trail stay, and the person leaves the active roster.
  // Nothing here issues a hard DELETE, so the visits and history that reference
  // this person are never orphaned. The Archive is where a removed person is
  // found and put back.

  /// Confirms the removal, then archives this term's enrolment.
  ///
  /// The person row and its full history survive; only this term's enrolment
  /// flips to 'Archived'. The dialog shows nothing but the question and the two
  /// choices — no name, no reason, no note.
  void _confirmDelete(IndividualRecord r) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: kCard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        content: const SizedBox(
          width: 320,
          child: Text(
            'Are you sure to delete this',
            style: TextStyle(fontSize: 15, color: kTextMain, height: 1.4),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel', style: TextStyle(color: kTextSub)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _setStatus(r, kRecordStatusArchived);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: kDanger,
              foregroundColor: Colors.white,
              elevation: 0,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  /// Writes the status change, then reflects it in the list and the shared
  /// directory so the other screens see it too.
  Future<void> _setStatus(
    IndividualRecord r,
    String status, {
    String? reason,
  }) async {
    try {
      final saved =
          await IndividualRecordService.setStatus(r, status, reason: reason);
      if (!mounted) return;
      // Matched by uuid first, then by dbKey — two rows for one person, one per
      // term, are two different records and only one of them changes.
      final i = _records.indexWhere((x) => x.uuid == saved.uuid);
      final j = i >= 0 ? i : _records.indexWhere((x) => x.dbKey == saved.dbKey);
      if (saved.isActive) {
        if (j >= 0) {
          _records[j] = saved;
        } else {
          _records.add(saved);
        }
      } else if (j >= 0) {
        // Taken out rather than swapped for the Archived row. [_records] holds
        // the ACTIVE roster, and the counts above the table are counted from it
        // — so a deleted person left sitting in the list would keep being counted
        // as one of the clinic's students until the next refresh.
        _records.removeAt(j);
      }
      _pushToDirectory(saved);
      _showResultDialog('Deleted Record');
      // Re-read so the table and the header counts drop the row the moment it
      // leaves the active roster.
      if (mounted) await _loadRecords(silent: true);
    } catch (e) {
      _showError('Could not change the status: $e');
    }
  }

  Color _categoryColor(String cat) => cat == 'Student'
      ? kStudentColor
      : cat == 'Faculty'
          ? kFacultyColor
          : kStaffColor;

  // ── IMPORT ─────────────────────────────────────────────────────────────
  // The file is really opened (so the name and size shown are genuine) but the
  // rows are still staged locally and compared against the current roster to
  // produce the new / updated / unchanged breakdown. _applyImport is where the
  // batch is actually written to `public.individual_records`.

  void _openImportDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _ImportDialog(
        existingCount: _records.length,
        defaultAY: _defaultAcademicYear,
        onAnalyze: _stageRows,
        onApply: _applyImport,
      ),
    );
  }

  /// Stages the rows an "uploaded" file would contain, then classifies each
  /// one against the records already on this page.
  List<ImportRow> _stageRows(String ay, String sem, Set<String> cats) {
    final staged = <IndividualRecord>[];

    // 1) Echoes of existing records — some untouched, some with edits, so the
    //    analysis has all three outcomes to report.
    final pool = _records.where((r) => cats.contains(r.category)).toList();

    for (final r in pool.take(4)) {
      staged.add(r.clone()
        ..academicYear = ay
        ..semester = sem);
    }
    var mutated = 0;
    for (final r in pool.skip(4)) {
      if (mutated >= 3) break;
      final c = r.clone()
        ..academicYear = ay
        ..semester = sem
        // A new phone number and, for students, a re-shifted program/year
        // level — the kind of edit an enrolment file carries.
        ..contact =
            '0917${(1300000 + mutated * 13579).toString().substring(0, 7)}';
      if (c.isStudent) {
        final progs = _catalog[c.institute] ?? const <String>[];
        if (progs.isNotEmpty) c.program = progs.last;
        c.yearLevel = '3rd Year';
      } else {
        // Stay inside the category's own department list so an import never
        // hands a faculty member an office (or the other way round).
        final depts = _departmentOptions(c.category);
        final i = depts.indexOf(c.department);
        c.department =
            depts.isEmpty ? c.department : depts[(i + 1) % depts.length];
      }
      staged.add(c);
      mutated++;
    }

    // 2) Rows the page has never seen — these come in as new.
    staged.addAll(_newImportRows(ay, sem));

    // Classification lives in stageImportRows so it can be tested without a
    // database: the per-term matching is the part that decides whether a
    // returning student is inserted or silently skipped.
    return stageImportRows(
      staged: staged,
      existing: _records,
      categories: cats,
    );
  }

  List<IndividualRecord> _newImportRows(String ay, String sem) {
    return [
      IndividualRecord(
        id: '235001',
        category: 'Student',
        firstName: 'Kevin',
        middleName: 'M',
        lastName: 'Bautista',
        sex: 'Male',
        birthDate: DateTime(2005, 4, 22),
        contact: '09251234567',
        email: 'kevin.bautista@tcgc.edu.ph',
        address: 'Brgy. San Rafael, Tarlac City',
        academicYear: ay,
        semester: sem,
        institute: 'ITE',
        program: 'BSED-FILIPINO',
        yearLevel: '1st Year',
      ),
      IndividualRecord(
        id: '235014',
        category: 'Student',
        firstName: 'Dani',
        lastName: 'Ocampo',
        sex: 'Female',
        birthDate: DateTime(2006, 7, 9),
        contact: '09261234567',
        email: 'dani.ocampo@tcgc.edu.ph',
        address: 'Brgy. Agopa, Tarlac City',
        academicYear: ay,
        semester: sem,
        institute: 'IBFS',
        program: 'BSBA-MM',
        yearLevel: '2nd Year',
      ),
      IndividualRecord(
        id: '235027',
        category: 'Student',
        firstName: 'Ralf',
        middleName: 'T',
        lastName: 'Domingo',
        sex: 'Male',
        birthDate: DateTime(2004, 1, 30),
        contact: '09271234567',
        email: 'ralf.domingo@tcgc.edu.ph',
        address: 'Brgy. Tinib, Tarlac City',
        academicYear: ay,
        semester: sem,
        institute: 'ICJE',
        program: 'BSISM',
        yearLevel: '3rd Year',
      ),
      IndividualRecord(
        id: 'F005',
        category: 'Faculty',
        firstName: 'Cecile',
        middleName: 'A',
        lastName: 'Manalo',
        sex: 'Female',
        birthDate: DateTime(1989, 3, 18),
        contact: '09291234567',
        email: 'cecile.manalo@tcgc.edu.ph',
        address: 'Brgy. San Jose, Tarlac City',
        academicYear: ay,
        semester: sem,
        department: 'IBFS',
        position: 'Instructor',
      ),
      IndividualRecord(
        id: 'S004',
        category: 'Staff',
        firstName: 'Tito',
        lastName: 'Ramos',
        sex: 'Male',
        birthDate: DateTime(1992, 11, 27),
        contact: '09301234567',
        email: 'tito.ramos@tcgc.edu.ph',
        address: 'Brgy. Maya, Tarlac City',
        academicYear: ay,
        semester: sem,
        department: 'Finance',
        position: 'Librarian',
      ),
    ];
  }

  /// Writes the staged import to the database: one bulk INSERT for the brand
  /// new person numbers and one UPDATE per changed record.
  ///
  /// The audit stamps are not fabricated here — the `individual_records_touch_audit`
  /// trigger records the importing account and the server time, so an imported
  /// record is indistinguishable from a hand-typed one except for the reason
  /// the change was made. Unchanged rows are skipped entirely.
  Future<void> _applyImport(ImportResult result) async {
    final fresh = <IndividualRecord>[];
    final changed = <IndividualRecord>[];

    for (final row in result.rows) {
      if (row.status == kImportUnchanged) continue;
      // Same per-term key as the staging pass, for the same reason: a person
      // who is already on last term has no row for this term, so matching them
      // by ID alone would UPDATE last term's row with this term's file and
      // leave the current term empty.
      final match =
          _records.where((r) => r.dbKey == row.record.dbKey).firstOrNull;
      if (match == null) {
        fresh.add(row.record);
      } else {
        // applyFrom leaves the uuid, status and audit block alone, so only the
        // enrolment-file fields are overwritten.
        final draft = match.clone();
        draft.applyFrom(row.record);
        changed.add(draft);
      }
    }

    if (fresh.isEmpty && changed.isEmpty) {
      setState(() {});
      _showSuccess('Nothing to import — every row already matches.');
      return;
    }

    setState(() => _saving = true);
    try {
      final termLabel =
          ReferenceCatalog.periodById(result.academicPeriodId)?.label ?? '';

      final inserted = fresh.isEmpty
          ? const <IndividualRecord>[]
          : await IndividualRecordService.createAll(fresh);
      for (final draft in changed) {
        await IndividualRecordService.update(draft);
      }

      // Retire the same people's earlier terms, now that this term's rows exist.
      //
      // This is the whole point of the per-term key: importing 2025-2026 · 2nd
      // Semester means "these people are on the roster now", and the only way
      // that is true is if their 2024-2025 rows stop being Active at the same
      // time. Left Active, a person appears twice in the default roster — once
      // per term — with nothing on screen to say which one is current.
      //
      // Everyone in the file, including the rows that were unchanged.
      //
      // An unchanged row can still belong to somebody whose earlier term is
      // still Active — the two facts are independent — and the whole point of
      // the import is that afterwards each person is on this term only.
      final touched = <({String category, String recordNo})>{
        for (final r in result.rows)
          (category: r.record.category, recordNo: r.record.id),
      }.toList();
      final retired = await IndividualRecordService.retireEarlierPeriods(
        touched,
        academicPeriodId: result.academicPeriodId,
      );

      // Every service write bumps DataTracker, whose listener re-queries the
      // roster, so the refreshed rows (real uuid, real audit stamps) land on
      // their own. `_saving` only guards against a second submit here.
      if (mounted) setState(() => _saving = false);

      final wrote = inserted.length + changed.length;
      // The retired count is in the message because it is a real change the
      // clinic made, and someone who later asks "why is last term's roster gone
      // from the active list?" should not have to work it out from this dialog.
      _showSuccess('Imported $wrote record(s) for '
          '$termLabel — ${result.added} new, '
          '${result.updated} updated, ${result.unchanged} unchanged skipped.'
          '${retired > 0 ? ' $retired earlier-term record(s) were deactivated.' : ''}');
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      _showError('Could not import the file: $e');
    }
  }
}

// ── ADD INSTITUTE / PROGRAM DIALOG ───────────────────────────────────────────

class _AddProgramDialog extends StatefulWidget {
  final List<String> institutes;
  final String? initialInstitute;

  const _AddProgramDialog({required this.institutes, this.initialInstitute});

  @override
  State<_AddProgramDialog> createState() => _AddProgramDialogState();
}

class _AddProgramDialogState extends State<_AddProgramDialog> {
  static const Color kPrimary = AppColors.primary;
  static const Color kCard = AppColors.surface;
  static const Color kBorder = AppColors.border;
  static const Color kTextMain = AppColors.textMain;
  static const Color kTextSub = AppColors.textSub;
  static const Color kDanger = AppColors.danger;

  /// One form, not a mode picker. The institute dropdown says whether this is an
  /// institute already on file or a new one; picking "New institute" reveals the
  /// code and name boxes. The program is optional throughout.
  bool _newInstitute = false;
  String? _institute;
  final TextEditingController _instCodeCtrl = TextEditingController();
  final TextEditingController _instNameCtrl = TextEditingController();
  final TextEditingController _progCodeCtrl = TextEditingController();
  final TextEditingController _progNameCtrl = TextEditingController();
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _institute = widget.initialInstitute;
    if (widget.institutes.isEmpty && _institute == null) {
      // Nothing on file yet, so there is no existing institute to pick: open on
      // the new-institute path instead of an empty dropdown.
      _newInstitute = true;
    } else {
      _institute ??= widget.institutes.first;
    }
  }

  @override
  void dispose() {
    _instCodeCtrl.dispose();
    _instNameCtrl.dispose();
    _progCodeCtrl.dispose();
    _progNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final ic = _newInstitute
        ? _instCodeCtrl.text.trim().toUpperCase()
        : (_institute ?? '');
    final iname = _newInstitute ? _instNameCtrl.text.trim() : '';
    if (_newInstitute && ic.isEmpty) {
      setState(() => _error = 'Enter the institute code.');
      return;
    }
    if (_newInstitute && iname.isEmpty) {
      setState(() => _error = 'Enter the institute name.');
      return;
    }
    if (!_newInstitute && ic.isEmpty) {
      setState(() => _error = 'Select an institute or add a new one.');
      return;
    }

    // The program is optional, but it is all-or-nothing: a code with no name (or
    // a name with no code) is half a program, and writing it as an institute-only
    // row would silently drop what was typed.
    final pc = _progCodeCtrl.text.trim().toUpperCase();
    final pn = _progNameCtrl.text.trim();
    if (pc.isNotEmpty != pn.isNotEmpty) {
      setState(() => _error = pc.isEmpty
          ? 'Enter the program code too.'
          : 'Enter the program name too.');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // The service decides the writes from the institute code: not on file →
      // insert the institute (and its program, when one was typed); already on
      // file → reuse it and insert only the program. A program can never be
      // written without an institute, new or existing.
      final saved = await ReferenceDataService.saveInstituteAndProgram(
        instituteCode: ic,
        instituteName: iname,
        programCode: pc,
        programName: pn,
      );
      if (!mounted) return;
      Navigator.pop(context, saved);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: kCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
            child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                          color: kPrimary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10)),
                      child: const Icon(Icons.add_business_outlined,
                          color: kPrimary, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Add Institute / Program',
                            style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w700,
                                color: kTextMain)),
                        const Text(
                            'An institute on its own, or one with a program',
                            style: TextStyle(fontSize: 13.5, color: kTextSub)),
                      ],
                    )),
                    IconButton(
                        onPressed:
                            _saving ? null : () => Navigator.pop(context),
                        icon: const Icon(Icons.close_rounded, color: kTextSub),
                        iconSize: 20),
                  ]),
                  const SizedBox(height: 18),
                  const Divider(color: kBorder, height: 1),
                  const SizedBox(height: 16),

                  _labeled('Institute'),
                  DropdownButtonFormField<String>(
                    initialValue: _newInstitute ? _kNewInstitute : _institute,
                    isExpanded: true,
                    decoration: _ideco('Select institute',
                        prefixIcon: Icons.account_balance_outlined),
                    style: const TextStyle(fontSize: 15, color: kTextMain),
                    items: [
                      ...widget.institutes.map(
                          (e) => DropdownMenuItem(value: e, child: Text(e))),
                      const DropdownMenuItem(
                        value: _kNewInstitute,
                        child: Row(children: [
                          Icon(Icons.add_circle_outline,
                              size: 17, color: kPrimary),
                          SizedBox(width: 8),
                          Text('New institute',
                              style: TextStyle(
                                  fontSize: 15,
                                  color: kPrimary,
                                  fontWeight: FontWeight.w600)),
                        ]),
                      ),
                    ],
                    onChanged: (v) => setState(() {
                      if (v == _kNewInstitute) {
                        _newInstitute = true;
                      } else {
                        _newInstitute = false;
                        _institute = v;
                      }
                      _error = null;
                    }),
                  ),

                  // A brand-new institute needs both a code and a name; an
                  // existing one is identified by the code alone.
                  if (_newInstitute) ...[
                    const SizedBox(height: 14),
                    _labeled('Institute Code'),
                    TextField(
                      controller: _instCodeCtrl,
                      textCapitalization: TextCapitalization.characters,
                      style: const TextStyle(fontSize: 15, color: kTextMain),
                      decoration: _ideco('e.g. INTS',
                          prefixIcon: Icons.qr_code_2_outlined),
                    ),
                    const SizedBox(height: 14),
                    _labeled('Institute Name'),
                    TextField(
                      controller: _instNameCtrl,
                      textCapitalization: TextCapitalization.words,
                      style: const TextStyle(fontSize: 15, color: kTextMain),
                      decoration: _ideco('e.g. Institute of Nursing',
                          prefixIcon: Icons.account_balance_outlined),
                    ),
                  ],

                  const SizedBox(height: 20),
                  Row(children: [
                    const Text('Program',
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: kTextSub)),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                          color: kPrimary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6)),
                      child: const Text('Optional',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: kPrimary)),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Row(children: [
                    Expanded(
                      child: TextField(
                        controller: _progCodeCtrl,
                        textCapitalization: TextCapitalization.characters,
                        style: const TextStyle(fontSize: 15, color: kTextMain),
                        decoration: _ideco('Code',
                            prefixIcon: Icons.qr_code_2_outlined),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _progNameCtrl,
                        textCapitalization: TextCapitalization.words,
                        onSubmitted: (_) => _submit(),
                        style: const TextStyle(fontSize: 15, color: kTextMain),
                        decoration: _ideco('Program name',
                            prefixIcon: Icons.menu_book_outlined),
                      ),
                    ),
                  ]),

                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Row(children: [
                      const Icon(Icons.error_outline, size: 15, color: kDanger),
                      const SizedBox(width: 6),
                      Expanded(
                          child: Text(_error!,
                              style: const TextStyle(
                                  fontSize: 13, color: kDanger))),
                    ]),
                  ],

                  const SizedBox(height: 20),
                  Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                    ElevatedButton.icon(
                      onPressed: _saving ? null : _submit,
                      icon: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save_outlined, size: 17),
                      label: Text(_saving ? 'Saving…' : 'Save to database'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kPrimary,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 20, vertical: 12),
                      ),
                    ),
                  ]),
                ]),
          ),
        ),
      ),
    );
  }

  Widget _labeled(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(label,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: kTextSub)),
      );

  InputDecoration _ideco(String hint, {IconData? prefixIcon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: kTextSub, fontSize: 14.5),
      filled: true,
      fillColor: const Color(0xFFFAFCFE),
      prefixIcon: prefixIcon != null
          ? Icon(prefixIcon, size: 18, color: kTextSub)
          : null,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kBorder)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kBorder)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kPrimary, width: 1.5)),
    );
  }
}

/// The Add Department / Office and Add Position dialog.
///
/// One small form: a title, a single name box, and a "Save to database" button.
/// There is no Cancel button beside the submit — the X in the corner does
/// exactly that, and having both made one look broken. [onSave] is where the
/// row is actually written; when it throws (a duplicate, no session, a network
/// failure) the message is shown in place instead of the dialog closing on a
/// write that never happened.
class _AddNamedDialog extends StatefulWidget {
  const _AddNamedDialog({
    required this.title,
    required this.subtitle,
    required this.label,
    required this.hint,
    required this.icon,
    required this.onSave,
  });

  final String title;
  final String subtitle;
  final String label;
  final String hint;
  final IconData icon;
  final Future<String> Function(String name) onSave;

  @override
  State<_AddNamedDialog> createState() => _AddNamedDialogState();
}

class _AddNamedDialogState extends State<_AddNamedDialog> {
  static const Color kPrimary = AppColors.primary;
  static const Color kCard = AppColors.surface;
  static const Color kBorder = AppColors.border;
  static const Color kTextMain = AppColors.textMain;
  static const Color kTextSub = AppColors.textSub;
  static const Color kDanger = AppColors.danger;

  final TextEditingController _ctrl = TextEditingController();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _ctrl.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter the ${widget.label.toLowerCase()}.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final saved = await widget.onSave(name);
      if (!mounted) return;
      Navigator.pop(context, saved);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: kCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 22, 24, 20),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                        color: kPrimary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10)),
                    child: Icon(widget.icon, color: kPrimary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(widget.title,
                          style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w700,
                              color: kTextMain)),
                      Text(widget.subtitle,
                          style:
                              const TextStyle(fontSize: 13.5, color: kTextSub)),
                    ],
                  )),
                  IconButton(
                      onPressed: _saving ? null : () => Navigator.pop(context),
                      icon: const Icon(Icons.close_rounded, color: kTextSub),
                      iconSize: 20),
                ]),
                const SizedBox(height: 18),
                const Divider(color: kBorder, height: 1),
                const SizedBox(height: 16),
                _labeled(widget.label),
                TextField(
                  controller: _ctrl,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  onSubmitted: (_) => _submit(),
                  style: const TextStyle(fontSize: 15, color: kTextMain),
                  decoration: _ideco(widget.hint),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 12),
                  Row(children: [
                    const Icon(Icons.error_outline, size: 15, color: kDanger),
                    const SizedBox(width: 6),
                    Expanded(
                        child: Text(_error!,
                            style:
                                const TextStyle(fontSize: 13, color: kDanger))),
                  ]),
                ],
                const SizedBox(height: 20),
                Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                  ElevatedButton.icon(
                    onPressed: _saving ? null : _submit,
                    icon: _saving
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save_outlined, size: 17),
                    label: Text(_saving ? 'Saving…' : 'Save to database'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kPrimary,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 12),
                    ),
                  ),
                ]),
              ]),
        ),
      ),
    );
  }

  Widget _labeled(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(label,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: kTextSub)),
      );

  InputDecoration _ideco(String hint) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: kTextSub, fontSize: 14.5),
      filled: true,
      fillColor: const Color(0xFFFAFCFE),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kBorder)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kBorder)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kPrimary, width: 1.5)),
    );
  }
}

// ── IMPORT DIALOG ────────────────────────────────────────────────────────────

class _ImportDialog extends StatefulWidget {
  final int existingCount;
  final String defaultAY;
  final List<ImportRow> Function(String ay, String sem, Set<String> cats)
      onAnalyze;
  final void Function(ImportResult result) onApply;

  const _ImportDialog({
    required this.existingCount,
    required this.defaultAY,
    required this.onAnalyze,
    required this.onApply,
  });

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  static const Color kPrimary = AppColors.primary;
  static const Color kCard = AppColors.surface;
  static const Color kBorder = AppColors.border;
  static const Color kTextMain = AppColors.textMain;
  static const Color kTextSub = AppColors.textSub;
  static const Color kDanger = AppColors.danger;

  /// Stage: 0 = configure, 1 = analyzing, 2 = results.
  int _stage = 0;
  double _progress = 0;

  // One term for the whole file, picked from the five the school runs.
  //
  // Was two year boxes and a semester list. That combination lets a file be
  // filed under a term that has never run, which the roster filter then cannot
  // show — the rows land in the database and are unreachable from the UI. Since
  // the whole batch is one term, one dropdown says it once.
  String _term = academicTermLabel(kCurrentAcademicYear, kCurrentSemester);
  final Set<String> _cats = {'Student', 'Faculty', 'Staff'};

  String? _fileName;
  int _fileSize = 0;
  String? _fileError;

  ImportResult? _result;

  /// The picked term, split back into the two columns the table stores.
  ({String year, String semester}) get _termPair {
    for (final t in kAcademicTerms) {
      final label = academicTermLabel(t.year, t.semester);
      if (label == _term) return (year: t.year, semester: t.semester);
    }
    return (year: kCurrentAcademicYear, semester: kCurrentSemester);
  }

  @override
  void initState() {
    super.initState();
    // Opened from the roster, so start on the term the roster is showing; falls
    // back to the term being run when the caller has none to offer.
    for (final t in kAcademicTerms) {
      if (widget.defaultAY == t.year) {
        _term = academicTermLabel(t.year, t.semester);
        return;
      }
    }
  }

  void _toggleCat(String cat, bool on) {
    setState(() => on ? _cats.add(cat) : _cats.remove(cat));
  }

  Future<void> _chooseFile() async {
    setState(() => _fileError = null);
    try {
      const typeGroup = XTypeGroup(
        label: 'Spreadsheet',
        extensions: ['xlsx', 'xls', 'csv'],
        uniformTypeIdentifiers: [
          'org.openxmlformats.spreadsheetml.sheet',
          'com.microsoft.excel',
          'public.comma-separated-values-text',
          'public.text',
        ],
      );
      final file = await openFile(acceptedTypeGroups: [typeGroup]);
      if (file == null) return;
      // Read the bytes so the size shown is the real one (and so a truncated
      // upload is caught before the analysis runs).
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) {
        setState(() {
          _fileName = file.name;
          _fileSize = 0;
          _fileError = 'That file is empty.';
        });
        return;
      }
      setState(() {
        _fileName = file.name;
        _fileSize = bytes.length;
        _result = null;
        _stage = 0;
      });
    } catch (e) {
      setState(() => _fileError = 'Could not open the file: $e');
    }
  }

  Future<void> _analyze() async {
    if (_fileName == null) return;
    if (_cats.isEmpty) {
      setState(() => _fileError = 'Pick at least one category to import.');
      return;
    }
    setState(() {
      _stage = 1;
      _progress = 0;
      _fileError = null;
    });

    // No file parser is wired up on this page yet, so the "parse" is a
    // short staged pass. The rows the parent hands back are real
    // IndividualRecords, compared there against the records already on the page.
    final term = _termPair;
    for (var i = 1; i <= 10; i++) {
      await Future.delayed(const Duration(milliseconds: 90));
      if (!mounted) return;
      setState(() => _progress = i / 10);
    }
    final rows = widget.onAnalyze(term.year, term.semester, _cats);
    if (!mounted) return;
    setState(() {
      _result = ImportResult(_fileName ?? 'batch-file.csv', rows,
          ReferenceCatalog.periodIdFor(term.year, term.semester) ?? '');
      _stage = 0;
    });
  }

  @override
  Widget build(BuildContext context) {
    final w = MediaQuery.of(context).size.width < 620
        ? MediaQuery.of(context).size.width * 0.94
        : 700.0;

    return Dialog(
      backgroundColor: kCard,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: Container(
        width: w,
        constraints: const BoxConstraints(maxHeight: 760),
        padding: const EdgeInsets.fromLTRB(26, 22, 26, 20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _header(),
          const SizedBox(height: 16),
          const Divider(color: kBorder, height: 1),
          const SizedBox(height: 16),
          Flexible(child: _body()),
        ]),
      ),
    );
  }

  Widget _header() {
    final results = _result != null;
    return Row(children: [
      Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
            color: AppColors.info.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(10)),
        child: Icon(
            results ? Icons.analytics_outlined : Icons.upload_file_rounded,
            color: AppColors.info,
            size: 20),
      ),
      const SizedBox(width: 12),
      Expanded(
          child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(results ? 'Import Analysis' : 'Import Records',
              style: const TextStyle(
                  fontSize: 19, fontWeight: FontWeight.w700, color: kTextMain)),
          Text(
            results
                ? '$_fileName · ${_result!.total} row(s) read'
                : 'Add a whole batch of student, faculty & staff records in one go',
            style: const TextStyle(fontSize: 13.5, color: kTextSub),
          ),
        ],
      )),
      IconButton(
        onPressed: _stage == 1 ? null : () => Navigator.pop(context),
        icon: const Icon(Icons.close_rounded, color: kTextSub),
        iconSize: 20,
      ),
    ]);
  }

  Widget _body() {
    if (_stage == 1) return _analyzingView();
    if (_result != null) return _resultsView();
    return _configureView();
  }

  // ── Step 1: academic year, semester, category, file ────────────────────

  Widget _configureView() {
    return SingleChildScrollView(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _stepLabel('1', 'Academic Year & Semester'),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                _dlabel('Term'),
                DropdownButtonFormField<String>(
                  initialValue: _term,
                  isExpanded: true,
                  decoration: _ideco('Select term',
                      prefixIcon: Icons.calendar_month_outlined),
                  style: const TextStyle(fontSize: 15, color: kTextMain),
                  items: [
                    for (final t in kAcademicTerms)
                      DropdownMenuItem(
                        value: academicTermLabel(t.year, t.semester),
                        child: Text(academicTermLabel(t.year, t.semester),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 14)),
                      ),
                  ],
                  onChanged: (v) => setState(() => _term = v ?? _term),
                ),
              ])),
          const SizedBox(width: 12),
          Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                _dlabel('Rows'),
                _readOnlyField(Icons.table_rows_outlined,
                    '${_cats.length} categor${_cats.length == 1 ? 'y' : 'ies'}'),
              ])),
        ]),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: kPrimary.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: kPrimary.withValues(alpha: 0.18)),
          ),
          child: Row(children: [
            const Icon(Icons.info_outline, size: 15, color: kPrimary),
            const SizedBox(width: 8),
            Expanded(
                child: Text(
              // Says what happens to the previous term, because this is the
              // part a clinic is surprised by: their earlier-term rows stop
              // being Active when the new term's file lands.
              'Every row is tagged '
              '$_term. On import, the '
              'same people\' earlier-term records are deactivated, so the roster '
              'shows this term only.',
              style: const TextStyle(
                  fontSize: 12.5, color: kPrimary, fontWeight: FontWeight.w600),
            )),
          ]),
        ),
        const SizedBox(height: 20),
        _stepLabel('2', 'Category'),
        Wrap(spacing: 10, runSpacing: 10, children: [
          _catChip(
              'All',
              Icons.groups_rounded,
              _cats.length == 3,
              () => setState(() {
                    if (_cats.length == 3) {
                      _cats.clear();
                    } else {
                      _cats.addAll(['Student', 'Faculty', 'Staff']);
                    }
                  })),
          _catChip('Student', Icons.school_outlined, _cats.contains('Student'),
              () => _toggleCat('Student', !_cats.contains('Student'))),
          _catChip(
              'Faculty',
              Icons.co_present_outlined,
              _cats.contains('Faculty'),
              () => _toggleCat('Faculty', !_cats.contains('Faculty'))),
          _catChip('Staff', Icons.badge_outlined, _cats.contains('Staff'),
              () => _toggleCat('Staff', !_cats.contains('Staff'))),
        ]),
        const SizedBox(height: 20),
        _stepLabel('3', 'Upload File'),
        _dropZone(),
        if (_fileError != null) ...[
          const SizedBox(height: 10),
          Row(children: [
            const Icon(Icons.error_outline, size: 15, color: kDanger),
            const SizedBox(width: 6),
            Expanded(
                child: Text(_fileError!,
                    style: const TextStyle(fontSize: 13, color: kDanger))),
          ]),
        ],
        const SizedBox(height: 20),
        Row(children: [
          Expanded(
              child: OutlinedButton(
            onPressed: () => Navigator.pop(context),
            style: OutlinedButton.styleFrom(
              side: const BorderSide(color: kBorder),
              foregroundColor: kTextSub,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(vertical: 13),
            ),
            child: const Text('Cancel'),
          )),
          const SizedBox(width: 12),
          Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                onPressed: _fileName == null ? null : _analyze,
                icon: const Icon(Icons.analytics_outlined, size: 17),
                label: const Text('Analyze File'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  foregroundColor: Colors.white,
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                  padding: const EdgeInsets.symmetric(vertical: 13),
                ),
              )),
        ]),
        const SizedBox(height: 10),
        Row(children: [
          const Icon(Icons.storage_rounded, size: 14, color: kTextSub),
          const SizedBox(width: 6),
          Expanded(
              child: Text(
            '${widget.existingCount} record(s) currently on this page will be used as the comparison baseline.',
            style: const TextStyle(fontSize: 12, color: kTextSub),
          )),
        ]),
      ]),
    );
  }

  Widget _stepLabel(String n, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: kPrimary, borderRadius: BorderRadius.circular(7)),
          child: Text(n,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800)),
        ),
        const SizedBox(width: 8),
        Text(label,
            style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w800, color: kTextMain)),
      ]),
    );
  }

  Widget _catChip(
      String label, IconData icon, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: selected
              ? kPrimary.withValues(alpha: 0.1)
              : const Color(0xFFFAFCFE),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
              color: selected ? kPrimary : kBorder, width: selected ? 1.4 : 1),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(
              selected
                  ? Icons.check_box_rounded
                  : Icons.check_box_outline_blank,
              size: 16,
              color: selected ? kPrimary : kTextSub),
          const SizedBox(width: 7),
          Icon(icon, size: 15, color: selected ? kPrimary : kTextSub),
          const SizedBox(width: 7),
          Text(label,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? kPrimary : kTextSub,
              )),
        ]),
      ),
    );
  }

  Widget _readOnlyField(IconData icon, String text) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kBorder),
      ),
      child: Row(children: [
        Icon(icon, size: 18, color: kTextSub),
        const SizedBox(width: 10),
        Expanded(
          child: Text(text,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 15, color: kTextMain, fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }

  Widget _dropZone() {
    final hasFile = _fileName != null;
    return GestureDetector(
      onTap: _chooseFile,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 26, horizontal: 20),
        decoration: BoxDecoration(
          color: hasFile
              ? kPrimary.withValues(alpha: 0.05)
              : const Color(0xFFFAFCFE),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: hasFile
                ? kPrimary.withValues(alpha: 0.4)
                : AppColors.borderStrong,
            width: 1.4,
          ),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(
            hasFile ? Icons.table_chart_rounded : Icons.cloud_upload_outlined,
            size: 34,
            color: hasFile ? kPrimary : kTextSub,
          ),
          const SizedBox(height: 10),
          if (hasFile) ...[
            Text(_fileName!,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: kTextMain)),
            const SizedBox(height: 4),
            Text('${_formatBytes(_fileSize)} · tap to choose a different file',
                style: const TextStyle(fontSize: 12.5, color: kTextSub)),
          ] else ...[
            const Text('Tap to choose a file',
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: kTextMain)),
            const SizedBox(height: 4),
            const Text('Excel (.xlsx, .xls) or CSV — one row per person',
                style: TextStyle(fontSize: 12.5, color: kTextSub)),
          ],
        ]),
      ),
    );
  }

  // ── Step 2: analyzing ─────────────────────────────────────────────────

  Widget _analyzingView() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 40),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 54,
          height: 54,
          child: CircularProgressIndicator(
            value: _progress > 0 ? _progress : null,
            strokeWidth: 4,
            color: kPrimary,
            backgroundColor: const Color(0xFFEEF2F6),
          ),
        ),
        const SizedBox(height: 20),
        const Text('Analyzing file...',
            style: TextStyle(
                fontSize: 16, fontWeight: FontWeight.w700, color: kTextMain)),
        const SizedBox(height: 6),
        Text(
          _progress >= 1
              ? 'Comparing against existing records'
              : 'Reading rows · ${(_progress * 100).round()}%',
          style: const TextStyle(fontSize: 13.5, color: kTextSub),
        ),
      ]),
    );
  }

  // ── Step 3: results ───────────────────────────────────────────────────

  Widget _resultsView() {
    final r = _result!;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SingleChildScrollView(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Counts
          LayoutBuilder(builder: (ctx, c) {
            final w = c.maxWidth < 560
                ? (c.maxWidth - 10) / 2
                : (c.maxWidth - 30) / 4;
            return Wrap(spacing: 10, runSpacing: 10, children: [
              _statTile(Icons.receipt_long_rounded, 'Total Records', r.total,
                  kPrimary, w),
              _statTile(Icons.new_releases_rounded, 'New', r.added,
                  AppColors.success, w),
              _statTile(Icons.edit_note_rounded, 'Updated', r.updated,
                  AppColors.warning, w),
              _statTile(Icons.remove_circle_outline_rounded,
                  'Unchanged / Skipped', r.unchanged, kTextSub, w),
            ]);
          }),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: kBorder),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Icon(Icons.info_outline, size: 15, color: kTextSub),
              const SizedBox(width: 8),
              Expanded(
                  child: Text(
                'Rows are matched on ID + category + term. New rows are added, Updated rows '
                'overwrite the changed fields, Unchanged rows are skipped. '
                '${academicTermLabel(_termPair.year, _termPair.semester)} is applied to '
                'every row, and that people\'s earlier-term rows are deactivated.',
                style:
                    const TextStyle(fontSize: 12, color: kTextSub, height: 1.4),
              )),
            ]),
          ),
          const SizedBox(height: 16),

          // Breakdown
          Row(children: [
            const Text('Breakdown',
                style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: kTextMain)),
            const Spacer(),
            Text('${r.total} row(s)',
                style: const TextStyle(fontSize: 12.5, color: kTextSub)),
          ]),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: kCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kBorder),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 260),
                child: SingleChildScrollView(
                  child: r.rows.isEmpty
                      ? const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                            child: Text(
                                'No rows found for the selected categories.',
                                style:
                                    TextStyle(fontSize: 13.5, color: kTextSub)),
                          ),
                        )
                      : SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: DataTable(
                            headingRowHeight: 40,
                            dataRowMinHeight: 44,
                            dataRowMaxHeight: 44,
                            showCheckboxColumn: false,
                            headingRowColor: WidgetStateProperty.all(
                                const Color(0xFFF8FAFC)),
                            headingTextStyle: const TextStyle(
                                fontWeight: FontWeight.w700,
                                color: kTextSub,
                                fontSize: 12,
                                letterSpacing: 0.4),
                            dataTextStyle:
                                const TextStyle(color: kTextMain, fontSize: 13),
                            columnSpacing: 20,
                            horizontalMargin: 14,
                            dividerThickness: 1,
                            border: const TableBorder(
                                horizontalInside:
                                    BorderSide(color: kBorder, width: 0.8)),
                            columns: const [
                              DataColumn(label: Text('ID')),
                              DataColumn(label: Text('NAME')),
                              DataColumn(label: Text('CATEGORY')),
                              DataColumn(label: Text('STATUS')),
                              DataColumn(label: Text('NOTE')),
                            ],
                            rows: r.rows.map((row) {
                              final c = row.status == kImportNew
                                  ? AppColors.success
                                  : row.status == kImportUpdated
                                      ? AppColors.warning
                                      : kTextSub;
                              return DataRow(cells: [
                                DataCell(Text(row.record.id,
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700))),
                                DataCell(Text(row.record.fullName,
                                    style: const TextStyle(fontSize: 13))),
                                DataCell(Text(row.record.category,
                                    style: const TextStyle(
                                        fontSize: 12.5, color: kTextSub))),
                                DataCell(_statusBadge(row.status, c)),
                                DataCell(Text(row.note,
                                    style: const TextStyle(
                                        fontSize: 12, color: kTextSub))),
                              ]);
                            }).toList(),
                          ),
                        ),
                ),
              ),
            ),
          ),
        ]),
      ),
      const SizedBox(height: 16),
      Row(children: [
        Expanded(
            child: OutlinedButton.icon(
          onPressed: () => setState(() {
            _result = null;
            _stage = 0;
          }),
          icon: const Icon(Icons.arrow_back_rounded, size: 16, color: kPrimary),
          label: const Text('Back', style: TextStyle(color: kPrimary)),
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: kBorder),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            padding: const EdgeInsets.symmetric(vertical: 13),
          ),
        )),
        const SizedBox(width: 12),
        Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: (r.added + r.updated) == 0
                  ? null
                  : () {
                      widget.onApply(r);
                      Navigator.pop(context);
                    },
              icon: const Icon(Icons.download_done_rounded, size: 17),
              label: Text(r.added + r.updated == 0
                  ? 'Nothing to import'
                  : 'Import ${r.added} new · ${r.updated} updated'),
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 13),
              ),
            )),
      ]),
    ]);
  }

  Widget _statTile(
      IconData icon, String label, int value, Color color, double w) {
    return Container(
      width: w,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Expanded(
              child: Text(label,
                  maxLines: 2,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: color))),
        ]),
        const SizedBox(height: 6),
        Text('$value',
            style: TextStyle(
                fontSize: 24, fontWeight: FontWeight.w800, color: color)),
      ]),
    );
  }

  Widget _statusBadge(String status, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(status,
          style: TextStyle(
              fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
    );
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
  }

  Widget _dlabel(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(label,
            style: const TextStyle(
                fontSize: 13, fontWeight: FontWeight.w600, color: kTextSub)),
      );

  InputDecoration _ideco(String hint, {IconData? prefixIcon}) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: kTextSub, fontSize: 14.5),
      filled: true,
      fillColor: const Color(0xFFFAFCFE),
      prefixIcon: prefixIcon != null
          ? Icon(prefixIcon, size: 18, color: kTextSub)
          : null,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kBorder)),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kBorder)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: kPrimary, width: 1.5)),
    );
  }
}

/// A small centred confirmation that dismisses itself after five seconds.
///
/// Used by `_IndividualRecordScreenState._showResultDialog` for "Saved Record" /
/// "Updated Record" / "Deleted Record". It closes on its own so the clerk never
/// has to dismiss it, and a tap anywhere closes it sooner; `maybePop` is what
/// keeps an early tap from also popping the roster underneath.
class _AutoCloseMessage extends StatefulWidget {
  const _AutoCloseMessage({
    required this.message,
    this.detail,
    this.danger = false,
  });

  final String message;
  final String? detail;
  final bool danger;

  @override
  State<_AutoCloseMessage> createState() => _AutoCloseMessageState();
}

class _AutoCloseMessageState extends State<_AutoCloseMessage> {
  static const Duration _visibleFor = Duration(seconds: 5);
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer(_visibleFor, _close);
  }

  void _close() {
    if (!mounted) return;
    Navigator.of(context).maybePop();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.danger ? AppColors.danger : AppColors.success;
    final detail = widget.detail;
    return Dialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                widget.danger
                    ? Icons.error_outline
                    : Icons.check_circle_outline,
                color: accent,
                size: 30,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              widget.message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textMain),
            ),
            if (detail != null) ...[
              const SizedBox(height: 8),
              Text(
                detail,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: AppColors.textSub),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
