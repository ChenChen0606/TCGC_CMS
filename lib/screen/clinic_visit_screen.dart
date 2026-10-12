// ─────────────────────────────────────────────────────────────────────────────
//  clinic_visit_screen.dart
//  The Clinic Consultation page, as a four-step wizard.
//
//  THE SHARED DIRECTORY
//  Visitors come from `PatientDirectory` (lib/core/patient_directory.dart), the
//  same in-memory projection of `public.individual_records` that Individual
//  Record publishes. That is what makes an ID typed here resolve to the very
//  same person, and it is where the Visitor Information card gets sex, birth
//  date, email, address, academic year and semester.
//
//  THE VISIT KEY
//  A visit is filed under the visitor's own `person_id`, written to
//  `clinic_visits.person_id`. There is NO `public.patients` table in this
//  project and no bridge row: the roster already holds the person the visit
//  belongs to, so picking a visitor is enough to make the visit saveable.
//
//  MEDICINE
//  Issuing medicine is no longer part of this page. The Inventory page still
//  owns dispensing; a visit created here simply leaves `medicine_id` /
//  `medicine_name` / `qty` null.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../core/patient_directory.dart';
import '../core/visit_details.dart';
import '../core/vitals.dart';
import '../core/visit_service_summary.dart';
import '../core/visit_times.dart';
import '../services/data_tracker.dart';
import '../services/individual_record_service.dart';
import '../services/reference_data_service.dart';
import '../services/visit_details_service.dart';
import '../services/visit_service.dart';
import '../core/clinic_purposes.dart';
import 'app_colors.dart';
import 'individual_record_data.dart';
import 'clinic_visit_step_three.dart';
import 'record_drawer.dart';
import 'visit_review_card.dart';

/// One line inside a review card.
///
/// Three shapes, because a card carries three kinds of thing: a label and what
/// was put in it, a sub-heading naming the part of a form a run of rows came
/// from, and a line that stands on its own (a service name in a list, a note
/// about a service with no answers yet).
///
class ClinicVisitScreen extends StatefulWidget {
  // Who is currently logged in — passed down from ClinicDashboard so every
  // record created on this page can be tagged with who created it.
  final String userName;
  final String userRole;

  // True while the Clinic Visits tab is the active dashboard page. The
  // dashboard keeps every page alive in an IndexedStack, so initState runs
  // only once — without this, the visitor search would keep a stale roster
  // and never pick up people saved on other tabs / in the database.
  final bool isActive;

  /// Where the visit's two times come from. `DateTime.now` in the clinic; a
  /// fixed clock in a test, so "the check-in is held and the out-time is taken
  /// when the visit ends" is something a test can actually show rather than
  /// something it has to take on trust. Never passed by the app.
  final DateTime Function() clock;

  /// When non-null, the wizard edits this visit instead of filing a new one.
  /// The header is updated on the same `clinic_visits` row and its services and
  /// recorded answers are rewritten against the same visit id, so an edit
  /// corrects a visit rather than duplicating it.
  final String? editVisitId;

  /// The roster record the edited visit was filed against. Seeded directly
  /// rather than looked up, because the screen may open before the shared
  /// directory has been read.
  final IndividualRecord? editVisitor;

  /// What the edited visit already carries: the services worked, the answers
  /// recorded on each, the visit's vitals, its prescription and its check-in.
  final List<String> editServiceIds;
  final Map<String, Map<String, dynamic>> editServiceData;
  final VisitVitals? editVitals;
  final List<MedicineDose>? editMedicines;
  final DateTime? editCheckedInAt;
  final String? editReasonForVisit;

  const ClinicVisitScreen({
    super.key,
    this.userName = '',
    // 'Clinic Staff' rather than '': the two roles the clinic actually has are
    // 'Clinic Head' and 'Clinic Staff', and an empty string was neither, so it
    // fell through every role check in the app.
    this.userRole = 'Clinic Staff',
    this.isActive = false,
    this.clock = DateTime.now,
    this.editVisitId,
    this.editVisitor,
    this.editServiceIds = const [],
    this.editServiceData = const {},
    this.editVitals,
    this.editMedicines,
    this.editCheckedInAt,
    this.editReasonForVisit,
  });

  @override
  State<ClinicVisitScreen> createState() => _ClinicVisitScreenState();
}

class _ClinicVisitScreenState extends State<ClinicVisitScreen> {
  // ── DESIGN TOKENS (single source of truth: app_colors.dart) ─────────────
  static const Color kPrimary = AppColors.primary;
  static const Color kPrimaryDk = AppColors.primaryDark;
  static const Color kPrimaryDeep = AppColors.primaryDeep;
  static const Color kCard = AppColors.surface;
  static const Color kBorder = AppColors.border;
  static const Color kBorderStrong = AppColors.borderStrong;
  static const Color kTextMain = AppColors.textMain;
  static const Color kTextSub = AppColors.textSub;
  static const Color kTextMuted = AppColors.textMuted;
  static const Color kDanger = AppColors.danger;
  static const Color kWarning = AppColors.warning;
  static const Color kFieldFill = AppColors.fieldFill;

  // Sizes are matched to the clinic's other pages rather than invented here, so
  // this page reads the same as the ones around it, but a step down from where
  // the sibling pages sit. The page has to fit a tracker, two card columns and
  // a pinned action bar into one window without scrolling, and at the old scale
  // the text needed a 23px display size to fill its column, which left the
  // cards looking padded rather than full. A field label larger than the value
  // under it reads as a second heading, so labels sit a step under the values
  // they name; anything a user must read in order to act stays at 12.5px or
  // above, and only badges and status chips go below that.
  static const TextStyle kSectionTitleStyle =
      TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: kTextMain);
  static const TextStyle kSectionSubtitleStyle =
      TextStyle(fontSize: 12.5, color: kTextSub);
  static const TextStyle kFieldLabelStyle =
      TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: kTextSub);
  static const TextStyle kCaptionStyle =
      TextStyle(fontSize: 12, color: kTextSub);

  /// The uppercase icon-and-label head a step's card opens with, matching the
  /// section eyebrows on Individual Record.
  static const TextStyle kEyebrowStyle = TextStyle(
      fontSize: 12.5,
      fontWeight: FontWeight.w800,
      letterSpacing: 0.7,
      color: kTextMain);

  // ── STEP 1: SEARCH VISITOR ─────────────────────────────────────────────
  /// The single-select filter pills above the search box. "All" is the
  /// default, so an empty box lists the whole roster.
  static const List<String> _visitorFilters = [
    'All',
    'Student',
    'Faculty',
    'Staff'
  ];
  String _visitorFilter = 'All';

  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _reasonForVisitCtrl = TextEditingController();

  /// The person currently picked in the search results. Null until one is
  /// chosen, which is also what gates the Proceed button.
  ClinicProfile? _visitor;

  /// `public.patients.id` for [_visitor] — the FK `public.visits` requires.
  /// Resolved on selection; null means the row could not be created yet, and
  /// the visit cannot be saved.
  String? _patientUuid;

  /// When this visitor was picked off the roster, and when the consultation
  /// ended. The check-in is set once and never re-read from the clock: a length
  /// worked out from two separately-taken `now()`s would be the time the nurse
  /// spent on the form, not the time the patient spent in the clinic.
  ///
  /// Only the check-in is held. The out-time is taken at the moment the nurse
  /// asks to complete, shown to her in the same dialog, and written to the row
  /// in the same breath — so there is no window in which the two could disagree,
  /// and nothing to carry in state while the save runs.
  ///
  /// Null [_checkedInAt] means no visitor has been chosen, which is the same
  /// condition that blocks the Proceed button.
  DateTime? _checkedInAt;

  /// The check-in in the words the record stores it in. Empty rather than a
  /// dash when nobody has been picked, because there is nothing to write yet.
  String get _timeInText =>
      _checkedInAt == null ? '' : VisitTimes.clock(_checkedInAt!);

  // ── VISIT SERVICES ──────────────────────────────────────────────────────
  //
  // The services themselves are NOT listed here. They live in
  // `ClinicPurposes`, which is already the single source of truth for them: the
  // Dashboard's "Top Reason for Visit" buckets saved visits by matching
  // `visits.complaint` back against it, and the clinic can rename a service in
  // one place. A second list in this file would drift from it.

  /// The services picked on step 2, in the order they were ticked. Order is the
  /// visit's order: step 3 walks this list to build one details sub-screen per
  /// service, and `visits.complaint` stores the labels in the same order.
  final List<String> _selectedServiceIds = [];

  /// The free-text name behind the "Other" service. Only meaningful while
  /// "Other" is one of the selected ids.
  // "Others" removed per request - services are fixed list

  // ── WIZARD ─────────────────────────────────────────────────────────────
  static const List<String> _stepTitles = [
    'Search Visitor',
    'Select Services',
    'Service Details',
    'Review & Complete',
  ];
  int _step = 0;

  // ── LISTENERS / FLAGS ──────────────────────────────────────────────────
  VoidCallback? _dataListener;
  VoidCallback? _directoryListener;

  /// The outstanding directory load, so the DataTracker bump and the
  /// `PatientDirectory` notification that one save causes do not race, and so a
  /// caller arriving late reads again rather than dropping the write.
  Future<void>? _directoryLoad;

  /// True only for the duration of our own hydrate call, so the notification
  /// it raises does not bounce straight back into another fetch.
  bool _hydrating = false;
  bool _saving = false;

  // ── STEP 3 STATE ───────────────────────────────────────────────────────
  //
  // Step 3's drafts live in a [VisitDetailsController] rather than in widget
  // state, for two reasons: the form descriptions, the completion rules and the
  // vitals banding are all testable without a widget, and the controller has to
  // outlive the step-3 widget anyway — the wizard's own Save & Continue button
  // in the footer is what drives it.
  VisitDetailsController? _details;

  /// What [_details] was built from. When the services ticked on step 2 change,
  /// the controller is stale and the drafts it holds are for a visit that no
  /// longer exists, so it is thrown away and rebuilt.
  String _detailsSignature = '';

  String get _currentUserName =>
      widget.userName.isNotEmpty ? widget.userName : 'Unknown User';

  /// True while an existing visit is open for correction rather than a new one
  /// being filed. Switches the save path from `create` to `update`.
  bool get _isEditing => widget.editVisitId != null;

  // ── LIFECYCLE ──────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _loadDirectory();
    if (_isEditing) _seedEditMode();

    _directoryListener = () {
      if (!mounted || _hydrating) return;
      // Somebody edited the roster on another tab — pick up the new values
      // for whoever is selected, without dropping the selection.
      setState(_syncVisitorWithDirectory);
    };
    PatientDirectory.instance.subscribe(_directoryListener!);

    // The Add Visitor dialog reads the reference catalog for its Program,
    // Institute, Office and Position lists. The dashboard keeps every page alive
    // in an IndexedStack, so this screen is built once and then sits there while
    // somebody adds a department on the Individual Record tab; without this the
    // list would still be the one from when the page was first built. A `setState`
    // is enough — the dialog itself is a separate route and is built fresh from
    // the catalog each time it is opened.
    ReferenceCatalog.subscribe(_catalogListener);

    _dataListener = _loadDirectory;
    DataTracker.listen(_dataListener!);
  }

  void _catalogListener() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(ClinicVisitScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.isActive && !oldWidget.isActive) {
      _loadDirectory();
    }
  }

  @override
  void dispose() {
    if (_dataListener != null) DataTracker.unlisten(_dataListener!);
    if (_directoryListener != null) {
      PatientDirectory.instance.unsubscribe(_directoryListener!);
    }
    // Paired with the subscribe in initState: a screen the dashboard keeps alive
    // for the whole session would otherwise stay in this list after it is gone.
    ReferenceCatalog.unsubscribe(_catalogListener);
    _searchCtrl.dispose();
    _reasonForVisitCtrl.dispose();
    _details?.dispose();
    super.dispose();
  }

  // ── SHARED DIRECTORY ───────────────────────────────────────────────────

  /// Reads the roster from `public.individual_records` and publishes it to the
  /// shared directory. A failure leaves whatever is already on screen (the
  /// directory ships with a hard-coded fallback list) rather than blanking the
  /// search box.
  ///
  /// Active records only. This read used to ask for `includeInactive: true`, so
  /// the visitor picker offered everybody the school has ever enrolled — the
  /// same person once per term, all of them rows that are retired. Picking a
  /// name here files a visit against the person, and it must be somebody on the
  /// roster now: a visitor who has not been on it since last year is an archive
  /// entry, and the Archive is where their history lives.
  Future<void> _loadDirectory() async {
    // Collapses a burst into one query, the same way the roster screen does.
    // `_loadDirectory` is both the DataTracker listener and the mount-time load,
    // so a record saved anywhere — including from the Individual Record screen,
    // which pushes the new profile in with `PatientDirectory.upsert` while this
    // screen is alive in an IndexedStack — fires both at once.
    //
    // Waiting for the running load and then loading again, rather than
    // returning, is the part that matters. `hydrate()` *replaces* the whole
    // directory, so a load whose query was issued before that upsert commits
    // lands afterwards and removes the person who was just saved. That is the
    // Clinic Visit half of "it saved, it is not in the list" — the visitor
    // picker reads this directory and nothing else.
    final pending = _directoryLoad;
    if (pending != null) await pending;
    final mine = _loadDirectoryInner();
    _directoryLoad = mine;
    try {
      await mine;
    } finally {
      if (identical(_directoryLoad, mine)) _directoryLoad = null;
    }
  }

  Future<void> _loadDirectoryInner() async {
    try {
      final records = await IndividualRecordService.fetchAll(
        includeInactive: false,
      );
      if (!mounted) return;
      _hydrating = true;
      try {
        PatientDirectory.instance
            .hydrate(records.map(_profileFromRecord).toList());
      } finally {
        _hydrating = false;
      }
      setState(_syncVisitorWithDirectory);
    } catch (e) {
      debugPrint('clinic visit: could not load roster: $e');
    }
  }

  /// Projects an `individual_records` row into the directory. The emergency
  /// contact is a clinic-side extra the roster does not own, so it is carried
  /// over from whatever the directory already holds for that person.
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
    );
  }

  /// Re-points [_visitor] at the directory's current record for the same
  /// person, so a rename on the Individual Record tab is reflected here
  /// without the user having to search again.
  void _syncVisitorWithDirectory() {
    final current = _visitor;
    if (current == null) return;
    final fresh = PatientDirectory.instance.byId(current.id);
    if (fresh == null || identical(fresh, current)) return;
    _visitor = fresh;
  }

  /// Fills the wizard with a visit that is being corrected.
  ///
  /// Runs once, at mount. The visitor is seeded from the roster record the
  /// booklet held rather than resolved from the shared directory — that read is
  /// async and may not have landed yet — and the step-3 drafts are rebuilt from
  /// the same saved answers the booklet's detail view printed, so the form opens
  /// on work that was actually done rather than blank. The order matters: the
  /// visitor and service selection are set before [_detailsFor] so the
  /// controller is built for this visit's signature.
  void _seedEditMode() {
    final r = widget.editVisitor;
    if (r == null) return;
    _visitor = _profileFromRecord(r);
    _patientUuid = r.id;
    _checkedInAt = widget.editCheckedInAt ?? widget.clock();
    _reasonForVisitCtrl.text = widget.editReasonForVisit ?? '';
    _selectedServiceIds
      ..clear()
      ..addAll(widget.editServiceIds);
    _step = 1;
    final details = _detailsFor();
    details.hydrate(
      serviceData: widget.editServiceData,
      visitVitals: widget.editVitals,
      restoredMedicines: widget.editMedicines,
    );
  }

  List<ClinicProfile> get _results => PatientDirectory.instance.search(
        _searchCtrl.text,
        category: _visitorFilter == 'All' ? null : _visitorFilter,
      );

  // ── STEP COMPLETION ────────────────────────────────────────────────────

  /// The ticked services as catalog entries, in selection order. "Other" is
  /// skipped here — it has no catalog entry, and it is folded into
  /// [_complaintText] separately so it always lands last in the saved text.
  List<ClinicPurpose> get _selectedPurposes {
    final out = <ClinicPurpose>[];
    for (final id in _selectedServiceIds) {
      final p = ClinicPurposes.byId(id);
      if (p != null) out.add(p);
    }
    return out;
  }

  /// What goes into `visits.complaint`: the catalog's own labels, joined, with
  /// the "Other" name last. These have to be the catalog labels rather than
  /// whatever wording this screen happens to use — the Dashboard buckets a saved
  /// visit by matching this text back against `ClinicPurposes`.
  String get _complaintText => ClinicPurposes.joinLabels(_selectedPurposes);

  bool get _hasVisitor => _visitor != null;

  bool get _hasServices {
    if (_selectedServiceIds.isEmpty) return false;
    return true;
  }

  /// A visit needs a visitor, a service, and the `patients` row that carries
  /// the FK — all three before the record can be written.
  bool get _canSave => _hasVisitor && _hasServices && _patientUuid != null;

  /// Every service ticked on step 2 has actually been answered — not merely
  /// ticked, but recorded. The controller owns the test; this is only the
  /// wizard's copy of it, so the Continue button and the tracker cannot
  /// disagree about what "done" means.
  ///
  /// This is what gates Continue out of step 3. Leaving a form part-answered is
  /// exactly what the left-hand service list exists to show, so the button
  /// waits until there is nothing left on that list.
  bool get _allServicesDone => _details?.isEverythingComplete ?? false;

  /// How far the wizard will let the user walk. Review is reachable only once
  /// every chosen service has been finished — the same test that gates Save &
  /// Continue — so the tracker cannot jump to the summary round a service that
  /// still has required boxes open. A visit that merely has services ticked
  /// reaches step 2's form, and a visit with a visitor reaches step 1.
  int get _maxReachable {
    if (_allServicesDone) return _stepTitles.length - 1;
    if (_hasServices) return 2;
    if (_hasVisitor) return 1;
    return 0;
  }

  bool _stepDone(int i) {
    switch (i) {
      case 0:
        return _hasVisitor;
      case 1:
        return _hasServices;
      case 2:
        // Step 3 is done when every service on the visit has been answered —
        // which is the same thing the left-hand list counts, and is what makes
        // the tracker offer step 3 as a way back rather than a way forward.
        return _details == null ? _hasServices : _allServicesDone;
      default:
        // The last step is completed by saving, which is what leaves this page.
        return false;
    }
  }

  void _goToStep(int i) {
    final target = i.clamp(0, _stepTitles.length - 1);
    if (target == _step) return;
    if (target > _maxReachable) {
      _toast(_blockReasonFor(target), kWarning);
      return;
    }
    setState(() => _step = target);
  }

  /// Why a step is still out of reach, phrased as the missing input.
  String _blockReasonFor(int target) {
    if (target >= 1 && !_hasVisitor) {
      return 'Search for a visitor and pick them from the list first.';
    }
    if (target >= 2 && !_hasServices) {
      return 'Tick at least one service before continuing.';
    }
    return 'Complete the previous step first.';
  }

  // ── VISITOR SELECTION ──────────────────────────────────────────────────

  Future<void> _selectVisitor(ClinicProfile p) async {
    final changed = _visitor?.id != p.id;
    setState(() {
      _visitor = p;
      // `visits.patient_id` used to be a FK to a `public.patients` bridge row.
      // That table does not exist in this project any more — the roster is
      // `public.individual_records` — and the visit stores the person_id as
      // text, so the visitor's own id IS the key. No lookup, no bridge row.
      _patientUuid = p.id;
      // A new person means a new consultation: drop the previous visitor's
      // services so they can never be saved against this one.
      if (changed) {
        _clearServices();
        // The clock starts when the visitor is picked off the roster, not when
        // the paperwork is filed. Holding the time here is the whole point: a
        // record stamped at completion says the patient arrived at the moment
        // the nurse got round to pressing the button, which is exactly the
        // figure a waiting-time report is supposed to rule out.
        _checkedInAt = widget.clock();
      }
    });
  }

  // ── REASON-FOR-VISIT → PROCEDURE TRIGGER ───────────────────────────────
  // Some complaints are "just a consult" (fever, headache) — nothing hands-on
  // to log. Others (injury, wound, burns) always involve an actual procedure
  // (cleaning, dressing, vitals) that the visit record has no fields for.
  // NOTE on "is BP / nebulization a service or a procedure?": they're both,
  // just on different sides — "BP tracking" here is the *service the visitor is
  // here for*. "Vital Signs Monitoring" (which records the BP reading) is a
  // procedure, so this routing logs one against the visit. Each service's own
  // `procedures` list is what links the two.
  static const List<String> _freeTextProcedureKeywords = [
    'wound',
    'cut',
    'burn',
    'sprain',
    'fracture',
    'bleeding',
    'injury',
    'faint',
    'unconscious',
    'nosebleed',
    'dislocat',
    'seizure',
    'blood pressure',
    'asthma',
    'breath',
    'chest pain',
  ];

  @pragma('vm:prefer-inline')
  bool _keywordTriggersProcedure(String text) =>
      _freeTextProcedureKeywords.any((k) => text.contains(k));

  /// Whether anything ticked needs a procedure record.
  ///
  /// Derived from the catalog instead of a list of names kept in this file. The
  /// old version matched a hardcoded set of *symptom* strings, which no longer
  /// exists as a thing the user picks — a service is what gets ticked, so the
  /// question has to be asked of the service. Every service in `ClinicPurposes`
  /// lists at least one procedure, so in practice this is true for any visit
  /// with a service on it; narrowing it to only the hands-on services is a
  /// one-line change here once the clinic says which those are.
  bool get _requiresProcedure {
    final t = _reasonForVisitCtrl.text.trim().toLowerCase();
    return _selectedPurposes.any((p) => p.procedures.isNotEmpty) ||
        (t.isNotEmpty && _keywordTriggersProcedure(t));
  }

  // ── COMPLETE CONSULTATION ──────────────────────────────────────────────

  Future<void> _completeConsultation() async {
    final v = _visitor;
    if (v == null || !_hasServices) {
      _toast('Pick a visitor and tick at least one service first.', kWarning);
      _goToStep(v == null ? 0 : 1);
      return;
    }
    if (_patientUuid == null) {
      _toast(
        "Still preparing this visitor's record — try again in a moment.",
        kWarning,
      );
      return;
    }

    // "Delacruz, Cresa S." — the shape the Records Booklet already stores.
    final name = v.middleInitial.isEmpty
        ? '${v.lastName}, ${v.firstName}'
        : '${v.lastName}, ${v.firstName} ${v.middleInitial}';
    final nowStamp = widget.clock();
    // Check-in was taken when the visitor was picked, on step 1, and is held.
    // The out-time is taken here — the moment the nurse asks to complete, which
    // is when the confirmation is opened rather than when it is dismissed — and
    // the same instant is what gets written, so what she confirmed and what is
    // filed cannot be two different minutes. Neither end is ever re-read, so the
    // interval is the visit's and not the length of a form.
    final timeIn = _timeInText;
    final timeOut = VisitTimes.clock(nowStamp);
    // Worked out from the two instants, not from the two formatted strings:
    // "10:30 AM" to "10:05 AM" is the next day, and a subtraction that cannot
    // tell the two apart is a subtraction that lies.
    final stay = VisitTimes.stayBetween(_checkedInAt, nowStamp);
    final complaint = _complaintText;
    final needsProcedure = _requiresProcedure;

    final confirmed = await _confirmVisitDialog(
      name: name,
      id: v.id,
      category: v.category,
      affiliation: v.affiliationLabel,
      complaint: complaint,
      visitDate: DateFormat('MMM d, yyyy').format(nowStamp),
      visitTime: timeIn,
      timeOut: timeOut,
      stay: stay,
      needsProcedure: needsProcedure,
      editing: _isEditing,
    );
    if (confirmed != true || !mounted) return;

    // Editing an existing visit: the header row already exists, so only its
    // reason is refreshed and the services/answers are rewritten against the
    // same visit id. Nothing is created, which is what keeps an edit a
    // correction rather than a second record of the same consultation.
    if (_isEditing) {
      final updateReason = _reasonForVisitCtrl.text.trim();
      setState(() => _saving = true);
      try {
        await VisitService.update(
          widget.editVisitId!,
          complaint: updateReason.isNotEmpty ? updateReason : complaint,
        );
        await _saveStepThreeToServer(widget.editVisitId!);
      } catch (e) {
        if (!mounted) return;
        setState(() => _saving = false);
        _toast('Could not update visit: $e', kDanger);
        return;
      }
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('Visit updated by $_currentUserName.', kPrimary);
      Navigator.of(context).pop(true);
      return;
    }

    setState(() => _saving = true);
    final String? patientUuid = _patientUuid;
    Visit? savedVisit;
    try {
      savedVisit = await VisitService.create(
        patientId: patientUuid!,
        patientNo: v.id,
        patientName: name,
        category: v.category,
        department: v.isStudent ? v.program : v.department,
        yearPosition: v.isStudent ? v.yearLevel : v.position,
        complaint: complaint,
        reasonForVisit: _reasonForVisitCtrl.text.trim().isNotEmpty
            ? _reasonForVisitCtrl.text.trim()
            : complaint,
        visitDate: nowStamp,
        visitTime: timeIn,
      );
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      _toast('Could not save visit: $e', kDanger);
      return;
    }
    if (!mounted) return;
    setState(() => _saving = false);

    // Step 3's readings, service forms and prescription are written here,
    // against the visit this call has just created.
    //
    // Here and not on step 3's own Save & Continue, because
    // `clinic_visit_services` and `medication_services` are keyed by `visit_id`
    // and the visit row does not exist until this point. Writing earlier would
    // mean inventing a visit id on step 3 and then having to reconcile it, or
    // leaving rows that point at nothing. The controller has been holding the
    // whole of step 3 in memory, so nothing is lost by waiting.
    if (savedVisit.id != null) {
      await _saveStepThreeToServer(savedVisit.id!);
      if (!mounted) return;
    }

    if (!mounted) return;
    _toast('Saved Record', kPrimary);

    _resetVisit();
  }

  Future<bool?> _confirmVisitDialog({
    required String name,
    required String id,
    required String category,
    required String affiliation,
    required String complaint,
    required String visitDate,
    required String visitTime,
    required String timeOut,
    String? stay,
    required bool needsProcedure,
    bool editing = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(children: [
          Icon(editing ? Icons.edit_outlined : Icons.check_circle_outline,
              color: kPrimary, size: 22),
          const SizedBox(width: 8),
          Text(editing ? "Update Record" : "Confirm Record"),
        ]),
        content: SizedBox(
          width: 380,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              VisitReviewRow("Visitor", name),
              VisitReviewRow("School ID", id),
              VisitReviewRow("Role", category),
              VisitReviewRow("Affiliation", affiliation),
              VisitReviewRow("Service", complaint),
              VisitReviewRow("Date", visitDate),
              // Both ends of the stay, on the last screen before it is filed:
              // the time the visitor was picked off the roster and the time they
              // are being signed out. A single "Time" line here would leave the
              // nurse unable to see which of the two it was.
              VisitReviewRow("Time in", visitTime),
              // An update corrects the record; it does not sign the visitor out
              // a second time, so the out-time and stay length are left alone
              // rather than shown as if they were about to be rewritten.
              if (!editing) ...[
                VisitReviewRow("Time out", timeOut),
                if (stay != null) VisitReviewRow("Stay length", stay),
              ],
              const SizedBox(height: 4),
              VisitReviewRow(
                  editing ? "Updated by" : "Recorded by", _currentUserName),
              // removed procedure note per request
            ],
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Cancel")),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            onPressed: () => Navigator.pop(context, true),
            child: Text(editing ? "Confirm & Update" : "Confirm & Save"),
          ),
        ],
      ),
    );
  }

  /// Clears everything a single visit owns and drops back to step 1. The
  /// roster, the filter tabs and the search box reset too, so the next visit
  /// starts from a blank slate.
  void _resetVisit() {
    setState(() {
      _step = 0;
      _visitor = null;
      _patientUuid = null;
      // A new visit starts a new clock. Leaving the last one behind would show
      // the next visitor the time the previous one was signed out.
      _checkedInAt = null;
      _clearServices();
      _searchCtrl.clear();
      _visitorFilter = 'All';
    });
  }

  /// Drops the step-2 service selection. Called whenever the visit is reset or
  /// the visitor is swapped, so one visitor's services can never be carried on
  /// to another's record.
  void _clearServices() {
    _selectedServiceIds.clear();
    _disposeDetails();
  }

  // ── BUILD ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // The page is a fixed frame, not a scrolling document: the header, the
    // tracker and the footer stay put and the step fills what is left. A
    // `SingleChildScrollView` around the whole page meant a short laptop window
    // pushed the step's own Continue button below the fold.
    //
    // Height that a single step genuinely cannot use is given back to that
    // step's own list rather than to the page — see [_cardBody].
    return Scaffold(
      backgroundColor: AppColors.bgAlt,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _pageHeader(),
                const SizedBox(height: 14),
                _stepTracker(),
                const SizedBox(height: 14),
              ],
            ),
          ),
          Expanded(
            // The header and the tracker above sit inside a 20px page gutter, so
            // the step's cards have to sit in the same one. They used to be a
            // bare Expanded and the two columns ran straight to the window
            // edges, which put the step out of line with everything else on
            // the page. The bottom inset closes the gutter too, so a card ends
            // above the window edge rather than against it.
            //
            // 10, not 18. The footer below it is no longer a bar with a
            // background and a rule — it is two buttons sitting in the same
            // gutter — so the gap between the bottom of the cards and the top of
            // the buttons is the gutter and nothing else. The 8px that came back
            // went to the step: on step 3 that is 8px of form.
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
              child: _stepBody(),
            ),
          ),

          // Step 2's own cards carry its Back and Continue, so the pinned bar
          // would be a second set of controls for the same step. Step 1 hosts
          // its action inside the visitor card for the same reason.
          //
          // Step 3 is in that row too, for a different reason: the wizard's Back
          // and Continue live in the form card's own footer, beside the slide
          // arrows, so that a step with forms inside it has one bar of controls
          // rather than a bar of its own and a bar inside the card.
          if (_step > 0 && _step != 1 && _step != 2) _wizardFooter(),
        ]),
      ),
    );
  }

  /// A region inside a card that has to live inside a height the page dictates.
  ///
  /// It is the page that refuses to scroll, not the content: if a roster, a
  /// checklist or a long record is taller than the space it has been given, it
  /// scrolls *within the card* and the page frame — tracker above, action
  /// button below — stays exactly where it is. On a tall window nothing here
  /// scrolls at all.
  Widget _cardBody({required Widget child}) {
    return Expanded(
      child: ClipRect(child: SingleChildScrollView(child: child)),
    );
  }

  Widget _pageHeader() {
    return Row(children: [
      Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [kPrimary, kPrimaryDk],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(11),
        ),
        child: const Icon(Icons.medical_services_outlined,
            color: Colors.white, size: 19),
      ),
      const SizedBox(width: 12),
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_isEditing ? 'Edit Visit' : 'Clinic Consultation',
            style: const TextStyle(
                fontSize: 19, fontWeight: FontWeight.w800, color: kTextMain)),
        const SizedBox(height: 2),
        Text(
            _isEditing
                ? 'Correct the services and the answers recorded on this visit'
                : 'Search the visitor, record the service, complete the visit',
            style: const TextStyle(fontSize: 12.5, color: kTextSub)),
      ]),
    ]);
  }

  Widget _stepBody() {
    switch (_step) {
      case 0:
        return _searchVisitorLayout();
      case 1:
        return _selectServicesStep();
      case 2:
        return _serviceDetailsStep();
      default:
        return _reviewStep();
    }
  }

  // ── STEP 3: SERVICE DETAILS ────────────────────────────────────────────

  /// Everything on this step's behalf. The one thing it owns is the drafts; the
  /// step's own widgets live in `clinic_visit_step_three.dart`, which draws
  /// them and pushes the nurse's answers back into this controller.
  Widget _serviceDetailsStep() {
    final v = _visitor;
    if (v == null) return _noVisitorSelected();
    final isLast = _step == _stepTitles.length - 1;
    return ClinicVisitStepThree(
      controller: _detailsFor(),
      visitor: v,
      userName: _currentUserName,
      // The wizard's own Back and Continue, drawn in the form card's footer.
      //
      // They used to be a row of their own under the cards, which meant two bars
      // of controls on one step: this one and the slide arrows in the form. The
      // form's footer carries both now, so the page draws no bar under the cards
      // on this step — see the `build` method.
      nav: StepThreeNav(
        onBack: () => _goToStep(1),
        onContinue: isLast ? _completeConsultation : _saveStepThree,
        continueLabel: isLast ? 'Complete Consultation' : 'Continue',
        // Offered only when the step is finished: every service the visit
        // carries has been recorded. Leaving one part-answered is legitimate
        // work in progress, but it is not somewhere the wizard should be
        // able to leave from — the left-hand list is what shows which
        // ones are outstanding, and Continue waits until that list is clear.
        continueEnabled: isLast ? _canSave : _hasServices,
        saving: _saving,
      ),
      onServiceAdded: (id) {
        // Appended, not sorted in: a service added mid-visit is one the nurse
        // thought of while recording, and it belongs after what step 2 chose.
        // Rebuilding the controller here would throw away the drafts, because
        // the drafts are the visit so far.
        if (_selectedServiceIds.contains(id)) return;
        setState(() => _selectedServiceIds.add(id));
      },
      onServiceRemoved: (id) {
        // The other half of the same deal. Step 2's selection is the visit's
        // list of services, so a service dropped on step 3 has to be dropped
        // here as well — otherwise the review step still counts it, the save
        // writes a `visit_services` row for a form the nurse threw away, and
        // the controller gets rebuilt with it on the next build.
        if (!_selectedServiceIds.remove(id)) return;
        // Only safe because the draft for it is already gone: this runs after
        // the controller has dropped it, so the signature check below cannot
        // see a service the drafts no longer have and rebuild them.
        setState(() {});
      },
    );
  }

  /// The step-3 controller, kept in step with the service selection.
  ///
  /// Three cases, and they are different on purpose:
  ///
  ///  - A different visitor, or a different name behind "Other": rebuilt. The
  ///    drafts are a record of what was typed for *those* services, and carrying
  ///    them onto another person's visit would be a record of a visit that never
  ///    happened.
  ///  - A service removed on step 2: rebuilt, for the same reason in reverse. A
  ///    form the list no longer shows must not still be savable.
  ///  - A service added — on step 2, or from step 3's own sheet: appended to the
  ///    existing controller. Rebuilding here would throw away everything already
  ///    recorded on the visit, which is the one thing a nurse adding a service
  ///    half-way through a visit is not expecting.
  VisitDetailsController _detailsFor() {
    final signature = _detailsSignatureFor;
    final existing = _details;

    if (existing == null || _detailsSignature != signature) {
      // The signature carries the whole selection, so a shrinking one lands here
      // too. Split out so the rebuild and the grow are not confused.
      final grew = existing != null &&
          _detailsSignature == _detailsVisitSignature &&
          existing.drafts.length <= _selectedServiceIds.length &&
          _selectedServiceIds.every((id) => existing.draftFor(id) != null);
      if (grew) {
        for (final id in _selectedServiceIds) {
          if (existing.draftFor(id) == null) {
            existing.addService(
              id,
              otherName: '',
              activate: false,
            );
          }
        }
        _detailsSignature = signature;
        return existing;
      }
      existing?.dispose();
      _details = VisitDetailsController(
        serviceIds: _selectedServiceIds,
        otherNames: const {},
        staffName: _currentUserName,
      );
      _detailsSignature = signature;
      _detailsVisitSignature = signature;
      return _details!;
    }
    return existing;
  }

  /// What identifies a set of step-3 drafts: the visitor, because a different
  /// person is a different visit; the services, because they decide which forms
  /// exist at all; and the name behind "Other", which is the service's own title
  /// and appears on the list and on the saved record.
  String get _detailsSignatureFor =>
      '${_visitor?.id ?? ''}|${_selectedServiceIds.join(',')}';

  /// [\_detailsSignature] as it was when the current controller was built, so a
  /// selection that has merely grown can be told apart from one that has changed
  /// shape.
  String _detailsVisitSignature = '';

  /// Throws the step-3 drafts away. Called when the visit itself is reset, and
  /// when a different visitor is picked.
  void _disposeDetails() {
    _details?.dispose();
    _details = null;
    _detailsSignature = '';
  }

  // ── STEP TRACKER ───────────────────────────────────────────────────────

  Widget _stepTracker() {
    // The tracker is a strip, not a panel of its own: it is four numbered steps
    // and a rule, and it used to also restate the current step as a sentence
    // ("Search Visitor — Find the person coming in") in a tinted banner under
    // the circles. That sentence repeated what the highlighted step already
    // says and cost the step below it roughly 40px, so the banner is gone and
    // the tracker is a single compact row.
    return _panel(
      // Named so a test can measure the strip itself rather than a step name,
      // which also appears on the card below it.
      key: const ValueKey('step-tracker'),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      // MediaQuery rather than LayoutBuilder: this card can end up inside the
      // stretched Row that the two-column layout needs, and a LayoutBuilder
      // there renders a blank screen.
      child: MediaQuery.of(context).size.width < 620
          ? _trackerColumn()
          : _trackerRow(),
    );
  }

  Widget _trackerRow() {
    // Number first, then the name, then a rule to the next one — the whole
    // tracker read as a single sentence left to right:
    //
    //   ── ① Search Visitor ───── ② Select Services ───── ③ … ──
    //
    // The node is a fixed-width block so the rules meet the numbers at the same
    // height on every step, and the labels sit beside their numbers rather than
    // underneath them, which is what halves the height of the strip.
    //
    // There is a rule before the first step and after the last one as well. They
    // carry no meaning — nothing has been done either side of the run — but
    // without them the strip starts and stops dead against the card's padding
    // and the first circle looks like it is falling off the edge, which on a wide
    // monitor is exactly what it looks like.
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _rule(done: _step > 0),
          for (int i = 0; i < _stepTitles.length; i++) ...[
            if (i > 0) _rule(done: i <= _step),
            _trackerNode(i),
          ],
          _rule(done: _step >= _stepTitles.length - 1),
        ],
      ),
    );
  }

  Widget _trackerColumn() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < _stepTitles.length; i++) ...[
          if (i > 0) _verticalConnector(i),
          _trackerNode(i),
        ],
      ],
    );
  }

  /// The rule between two steps, or the stub at either end of the run.
  ///
  /// Teal once what it leads to is behind us, grey while it is still ahead. It
  /// grows to whatever width the steps either side of it leave over, so the
  /// tracker fills the card at any window size instead of bunching up in the
  /// middle.
  Widget _rule({required bool done}) {
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: done ? kPrimary : kBorder,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _verticalConnector(int i) {
    final done = i <= _step;
    return Container(
      width: 2,
      height: 12,
      margin: const EdgeInsets.only(left: 11.5, top: 2, bottom: 2),
      decoration: BoxDecoration(
        color: done ? kPrimary : kBorder,
        borderRadius: BorderRadius.circular(2),
      ),
    );
  }

  /// One step of the tracker: a numbered circle and its name, side by side.
  /// Completed steps get a filled teal circle and a checkmark, the active one
  /// gets its number on teal and a bold name; upcoming ones stay grey.
  ///
  /// The name is text, not a control. Steps are moved through with the Back /
  /// Proceed / Continue buttons each step actually shows, so a tap on a step
  /// name can never skip past the input a step needs — which is what the old
  /// clickable tracker allowed. [ValueKey('tracker-active')] is on the active
  /// label so tests can read which step is showing without going through the
  /// buttons.
  Widget _trackerNode(int i) {
    final active = i == _step;
    final done = !active && _stepDone(i) && i < _step;
    final reachable = i <= _maxReachable;
    final circleColor = done || active ? kPrimary : kFieldFill;
    final borderColor =
        done || active ? kPrimary : (reachable ? kBorderStrong : kBorder);
    final labelColor =
        done || active ? kPrimary : (reachable ? kTextSub : kTextMuted);

    final circle = Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: circleColor,
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 1.5),
      ),
      child: done
          ? const Icon(Icons.check_rounded, size: 14, color: Colors.white)
          : Text(
              '${i + 1}',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: done || active ? Colors.white : kTextSub,
              ),
            ),
    );

    final label = Text(
      _stepTitles[i],
      key: active ? const ValueKey('tracker-active') : null,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      softWrap: false,
      style: TextStyle(
        fontSize: 12.5,
        height: 1.1,
        fontWeight: active
            ? FontWeight.w800
            : (done ? FontWeight.w700 : FontWeight.w500),
        color: labelColor,
      ),
    );

    final node = Semantics(
      selected: active,
      label: 'Step ${i + 1} of ${_stepTitles.length}, ${_stepTitles[i]}',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          circle,
          const SizedBox(width: 8),
          label,
        ],
      ),
    );

    // A step that is behind us can be walked back to. A nurse who realises on
    // step 3 that the wrong service was ticked is already looking at the
    // tracker, and making them hunt for the Back button first is a step between
    // them and the mistake. Only *completed* steps take the tap: a step that is
    // still ahead is not a shortcut past the work in front of it, and the
    // tracker's job is to show where that work is, not to skip it.
    if (!done) return node;
    return Tooltip(
      message: 'Back to ${_stepTitles[i]}',
      child: InkWell(
        onTap: () => _goToStep(i),
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
          child: node,
        ),
      ),
    );
  }

  // ── STEP 1 — TWO-COLUMN LAYOUT ─────────────────────────────────────────

  Widget _searchVisitorLayout() {
    return LayoutBuilder(builder: (context, constraints) {
      // Stacking is only the right answer on a window that is both narrow and
      // tall. A narrow *short* window — a 900x600 laptop — has too little height
      // to give two cards a useful share of it, and two thin columns beat two
      // useless ones: the lists still scroll, but every card keeps its header
      // and its button.
      final stack = constraints.maxWidth < 980 && constraints.maxHeight >= 700;
      if (stack) {
        // Stacked, the two cards share what the page has left: the search card
        // gets the larger share because the list is what you work in.
        return Column(children: [
          Expanded(flex: 5, child: _searchVisitorCard()),
          const SizedBox(height: 14),
          Expanded(flex: 4, child: _visitorInfoCard()),
        ]);
      }
      // A plain stretched Row. This used to need IntrinsicHeight, which was only
      // ever there because the page scrolled and a Row then had no height to
      // stretch into; the step is now laid out inside a bounded Expanded, so the
      // cards are the height of the step and equal to each other for free.
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 5, child: _searchVisitorCard()),
          const SizedBox(width: 20),
          Expanded(flex: 6, child: _visitorInfoCard()),
        ],
      );
    });
  }

  // ── LEFT CARD — SEARCH VISITOR ─────────────────────────────────────────

  Widget _searchVisitorCard() {
    final results = _results;
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.search_rounded, size: 20, color: kPrimary),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Search Visitor', style: kSectionTitleStyle),
                  SizedBox(height: 2),
                  Text('Enter School ID or Name', style: kSectionSubtitleStyle),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 14),
          _filterPills(),
          const SizedBox(height: 10),
          _searchField(),
          const SizedBox(height: 10),
          // The result list takes whatever height the filters and the search box
          // did not use, rather than a fixed 360px that either wasted space or
          // pushed the visitor card's Proceed button off a short screen.
          //
          // A Column, not a ListView: [_cardBody] is the scrollable here, and a
          // viewport inside a viewport is handed an unbounded axis.
          _cardBody(
            child: results.isEmpty
                ? _noVisitorFound()
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (var i = 0; i < results.length; i++) ...[
                        _visitorRow(results[i]),
                        if (i < results.length - 1) const SizedBox(height: 6),
                      ],
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  /// All | Student | Faculty | Staff — single select, teal when chosen.
  ///
  /// These used to be a `Wrap` of pills sized to their own text, which meant the
  /// row stopped a third of the way across a wide card and left a band of empty
  /// white to its right. The category chips are the only control on the card
  /// that changes what the list below shows, so they are given the full width
  /// and share it evenly: four equal segments, like tabs, which is what they
  /// behave like. Below the width where an even share stops being readable they
  /// fall back to a `Wrap` and wrap onto a second line rather than squeeze.
  Widget _filterPills() {
    return LayoutBuilder(builder: (context, c) {
      final filters = _visitorFilters;
      // How many active records each chip can actually produce. Without it, a
      // search that finds nothing is indistinguishable from a wrong category —
      // and with the roster now Active-only, "Faculty 0" is a real answer worth
      // showing rather than an empty chip that looks broken.
      int countFor(String f) {
        final all = PatientDirectory.instance.all;
        if (f == 'All') return all.length;
        return all.where((p) => p.category == f).length;
      }

      Widget pill(String f) {
        final selected = _visitorFilter == f;
        final n = countFor(f);
        return InkWell(
          key: ValueKey('visitor_filter_$f'),
          onTap: () => setState(() => _visitorFilter = f),
          borderRadius: BorderRadius.circular(999),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: selected ? kPrimary : AppColors.bgAlt,
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: selected ? kPrimary : kBorder),
            ),
            child: Text(
              '$f  $n',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? Colors.white : kTextSub,
              ),
            ),
          ),
        );
      }

      // Enough width for every chip to hold its own name at a readable size.
      const minPerChip = 78.0;
      if (c.maxWidth >= filters.length * minPerChip) {
        return Row(
          children: [
            for (var i = 0; i < filters.length; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              Expanded(child: pill(filters[i])),
            ],
          ],
        );
      }
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [for (final f in filters) pill(f)],
      );
    });
  }

  Widget _searchField() {
    return TextField(
      key: const ValueKey('visitor_search_field'),
      controller: _searchCtrl,
      onChanged: (_) => setState(() {}),
      style: const TextStyle(fontSize: 14, color: kTextMain),
      decoration: InputDecoration(
        hintText: "Search by ID number or name...",
        hintStyle: const TextStyle(fontSize: 12.5, color: kTextSub),
        prefixIcon: const Icon(Icons.search_rounded, size: 20, color: kPrimary),
        // There was a "Filter by role" tuning-fork button in the suffix here
        // that opened a sheet listing the same four categories the chips above
        // already offer, one of which is "All" — the same thing with a sheet in
        // the way. Two controls for one setting is one too many, and the sheet
        // also took a tap and a dismiss to change something the chips change in
        // one. The category chips are now the only place the list is filtered.
        suffixIcon: _searchCtrl.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon:
                    const Icon(Icons.close_rounded, size: 18, color: kTextSub),
                onPressed: () {
                  _searchCtrl.clear();
                  setState(() {});
                },
              ),
        filled: true,
        fillColor: kFieldFill,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kPrimary, width: 1.5)),
      ),
    );
  }

  Widget _visitorRow(ClinicProfile p) {
    final selected = _visitor?.id == p.id;
    return Semantics(
      button: true,
      selected: selected,
      label: '${p.fullName}, ${p.category}, ID ${p.id}',
      child: InkWell(
        onTap: () => _selectVisitor(p),
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
          decoration: BoxDecoration(
            color: selected
                ? kPrimary.withValues(alpha: 0.06)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            border: Border(
              left: BorderSide(
                color: selected ? kPrimary : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          // Two lines and no more. The row is a means of finding a person, not
          // a record of them, so the name is the first line and the second is
          // the number the clinic files them under — the one thing that tells
          // two same-named people apart — then a rule, then where they belong:
          //
          //     Cresa S Delacruz            Student
          //     234567 │ BSCS · 2nd Year
          //
          // Everything else is on the card to the right.
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              _initialsAvatar(p, 14),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text(
                          p.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.1,
                            fontWeight: FontWeight.w700,
                            color: selected ? kPrimaryDeep : kTextMain,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      _roleBadge(p.category, fontSize: 10.5),
                    ]),
                    const SizedBox(height: 3),
                    Row(children: [
                      _idChip(p),
                      const SizedBox(width: 7),
                      // The rule that separates "who" from "where". As tall as
                      // the line it sits in, so it reads as a divider and not
                      // as a stray character.
                      Container(width: 1, height: 12, color: kBorder),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          _affiliationLine(p),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: kCaptionStyle,
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                size: 18,
                color: selected ? kPrimary : kTextMuted,
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// The number the clinic files the person under, in a small badge. A badge
  /// rather than plain text because it is an identifier, not a word, and it is
  /// what the clinic looks someone up by.
  ///
  /// A lozenge rather than a true circle: a circle has one size, and student
  /// numbers run to ten digits. At a 20px height this is a circle for the short
  /// ones (F001, S002) and simply rounds off for the long ones, instead of
  /// cutting the number off mid-digit.
  Widget _idChip(ClinicProfile p) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7),
      constraints: const BoxConstraints(minWidth: 20),
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.bgAlt,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kBorder),
      ),
      child: Text(
        p.id,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(
          fontSize: 10.5,
          height: 1.1,
          fontWeight: FontWeight.w700,
          color: kTextSub,
        ),
      ),
    );
  }

  /// The second line of a search row, after the number: a student's program and
  /// year level, or the office and post a faculty / staff member belongs to.
  String _affiliationLine(ClinicProfile p) => p.isStudent
      ? _joined([p.program, p.yearLevel])
      : _joined([p.department, p.position]);

  /// Joins the parts that are actually on file, so a student with no year level
  /// yet reads as the program alone rather than as "BSCS · ".
  static String _joined(List<String> parts) =>
      parts.map((e) => e.trim()).where((e) => e.isNotEmpty).join(' · ');

  Widget _noVisitorFound() {
    final term = _searchCtrl.text.trim();
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.person_search_outlined, size: 44, color: kTextMuted),
          const SizedBox(height: 12),
          const Text('No visitor found',
              style: TextStyle(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                  color: kTextMain)),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              term.isEmpty
                  ? 'The roster is empty in this category.'
                  : "Nobody matches \"$term\"${_visitorFilter == 'All' ? '' : ' in $_visitorFilter'}.",
              textAlign: TextAlign.center,
              style: kCaptionStyle,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              foregroundColor: kPrimary,
              side: const BorderSide(color: kPrimary),
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: _showAddVisitorDialog,
            icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
            label: const Text('+ Add New Visitor'),
          ),
        ],
      ),
    );
  }

  // ── RIGHT CARD — VISITOR INFORMATION ───────────────────────────────────

  Widget _visitorInfoCard() {
    final v = _visitor;
    return _panel(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Icon(Icons.badge_outlined, size: 20, color: kPrimary),
            const SizedBox(width: 10),
            const Expanded(
                child: Text('Visitor Information', style: kSectionTitleStyle)),
          ]),
          const SizedBox(height: 12),
          const Divider(color: kBorder, height: 1),
          const SizedBox(height: 12),
          if (v == null)
            _cardBody(child: _noVisitorSelected())
          else ...[
            // No scroll view on this side of the card. The three parts here are
            // a fixed set of boxes with no list in them, so the only sensible
            // thing to do with a short window is to let the detail grid give
            // the height back — which is what the Expanded on it does, and what
            // fills the card to the Proceed button instead of leaving a band of
            // white underneath.
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _visitorIdentity(v),
                  const SizedBox(height: 12),
                  _academicBox(v),
                  const SizedBox(height: 12),
                  Expanded(child: _detailGrid(v)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: ElevatedButton.icon(
                onPressed: _hasVisitor ? _proceedFromStepOne : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  foregroundColor: Colors.white,
                  disabledBackgroundColor: AppColors.borderStrong,
                  disabledForegroundColor: Colors.white,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                  // Sized to the step 3 buttons on purpose. This one used to be
                  // a 48px-tall Material default on a card whose content is a
                  // fixed set of read-only boxes, so the button was the largest
                  // thing in the panel and the panel gave up the height to it.
                  minimumSize: const Size(0, 40),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(9)),
                ),
                icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                label: const Text('Proceed',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _proceedFromStepOne() {
    if (!_hasVisitor) {
      _toast('Pick a visitor from the list first.', kWarning);
      return;
    }
    _goToStep(1);
  }

  Widget _noVisitorSelected() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kBorder),
      ),
      child: Column(children: [
        const Icon(Icons.person_outline, size: 44, color: kTextMuted),
        const SizedBox(height: 12),
        const Text('No visitor selected',
            style: TextStyle(
                fontSize: 14.5, fontWeight: FontWeight.w700, color: kTextMain)),
        const SizedBox(height: 4),
        const Text(
          'Search by School ID or name on the left, then pick the person '
          'this visit is for.',
          textAlign: TextAlign.center,
          style: kCaptionStyle,
        ),
      ]),
    );
  }

  Widget _visitorIdentity(ClinicProfile v) {
    return Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
      _initialsAvatar(v, 24),
      const SizedBox(width: 12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Flexible(
                child: Text(
                  v.fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: kTextMain),
                ),
              ),
              const SizedBox(width: 8),
              _roleBadge(v.category, fontSize: 11.5),
            ]),
            const SizedBox(height: 2),
            Text('School ID: ${v.id}',
                style: const TextStyle(fontSize: 12, color: kTextSub)),
          ],
        ),
      ),
    ]);
  }

  /// The light-teal academic box. A student is filed by program and year, a
  /// faculty or staff member by office and post — so the second line is not
  /// the same idea for either.
  Widget _academicBox(ClinicProfile v) {
    String headline;
    String subline;

    if (v.isStudent) {
      // Student → institute code - program code - year level (headline)
      headline = [v.institute, v.program, v.yearLevel]
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .join(' - ');
      // year · semester (subline)
      subline = '${_orDash(v.academicYear)} · ${_orDash(v.semester)}';
    } else if (v.isFaculty) {
      // Faculty → institute - position, remove ID number
      headline = [v.institute, v.position]
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .join(' - ');
      // subline = academic year · semester
      subline = '${_orDash(v.academicYear)} · ${_orDash(v.semester)}';
    } else if (v.isStaff) {
      // Staff → department/office - position (headline)
      headline = [v.department, v.position]
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .join(' - ');
      // year · semester (subline)
      subline = '${_orDash(v.academicYear)} · ${_orDash(v.semester)}';
    } else {
      headline = v.department;
      subline = '${_orDash(v.position)}, ${_orDash(v.id)}';
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kPrimary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kPrimary.withValues(alpha: 0.22)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Icon(Icons.school_outlined, size: 20, color: kPrimary),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Current Academic Information',
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w800,
                      color: kPrimaryDk,
                      letterSpacing: 0.2)),
              const SizedBox(height: 4),
              Text(_orDash(headline),
                  style: const TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                      color: kTextMain)),
              Text(subline, style: kCaptionStyle),
            ],
          ),
        ),
      ]),
    );
  }

  /// The six facts about the visitor that are not already in the identity line
  /// or the academic box, as a two-column grid of labelled boxes.
  ///
  /// The rows keep their natural height and the space between them is what
  /// stretches. Giving the rows `Expanded` instead would fill the card the same
  /// way, but then a short window squeezes a box below the height its text
  /// needs and prints an overflow stripe across the visitor's record — which is
  /// the one thing on this page that must not be wrong-looking.
  Widget _detailGrid(ClinicProfile v) {
    final cells = <Widget>[
      _detailCell(Icons.wc_outlined, 'Sex', _orDash(v.sex)),
      _detailCell(Icons.alternate_email, 'Email', _orDash(v.email)),
      _detailCell(
          Icons.cake_outlined, 'Date of Birth', _formatDate(v.birthDate)),
      _detailCell(Icons.home_outlined, 'Address', _orDash(v.address)),
      _detailCell(Icons.phone_outlined, 'Contact Number', _orDash(v.contact)),
      _detailCell(Icons.contact_emergency_outlined, 'Emergency Contact',
          _emergencyText(v)),
    ];

    // The six facts, laid out as a grid whose column count follows the width the
    // card actually has.
    //
    // It used to be two fixed columns under a `spaceBetween`, which looked right
    // on a laptop because the rows happened to land near enough together. On a
    // desktop monitor the same Column is handed twice the height, and
    // `spaceBetween` spends all of it on the gaps: three rows of boxes marooned
    // in the middle of the card with rivers of white above and below. The
    // spacing is now a fixed gap, and the leftover height goes to a third column
    // on a wide card instead of to whitespace.
    return LayoutBuilder(builder: (context, c) {
      final columns = c.maxWidth >= 620 ? 3 : 2;
      const gap = 10.0;
      final rows = <Widget>[];
      for (var i = 0; i < cells.length; i += columns) {
        final slice = cells.skip(i).take(columns).toList();
        rows.add(Padding(
          padding:
              EdgeInsets.only(bottom: i + columns < cells.length ? gap : 0),
          child: Row(
            // `start`, never `stretch`: these rows sit inside a vertical scroll
            // view, and a Row that stretches its children across the cross axis
            // asks for an unbounded height — which is an assertion, not a layout.
            // The cells carry their own minimum height instead, which is what
            // keeps the boxes in a row level anyway.
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var c2 = 0; c2 < columns; c2++) ...[
                if (c2 > 0) const SizedBox(width: gap),
                Expanded(
                  child:
                      c2 < slice.length ? slice[c2] : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        ));
      }
      return SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rows,
        ),
      );
    });
  }

  String _emergencyText(ClinicProfile v) {
    final name = v.emergencyName.trim();
    final number = v.emergencyContact.trim();
    if (name.isEmpty && number.isEmpty) return '—';
    if (name.isEmpty) return number;
    if (number.isEmpty) return name;
    return '$name · $number';
  }

  /// One fact on the visitor's record: an icon, a small caption, and the value.
  ///
  /// A tinted box rather than a bare line. These six sit under the identity and
  /// the academic box, and as free-floating icon-and-text pairs they read as
  /// loose notes; boxed, they read as the record itself, and the boxes are what
  /// give the grid its structure when the values are different lengths.
  Widget _detailCell(IconData icon, String label, String value) {
    return Container(
      // A floor, not a height: a value that wraps to two lines is still allowed
      // to grow, but a one-line value does not leave a stub of a box.
      constraints: const BoxConstraints(minHeight: 56),
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 9),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: kBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: kPrimary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(icon, size: 15, color: kPrimary),
          ),
          const SizedBox(width: 9),
          // FittedBox is the safety valve for a short window: the text is laid
          // out at its natural size and scaled down only when the box is too
          // small to hold it, so the caption and the value are never cut off.
          // On any normal window it renders at 1:1 and is invisible.
          Expanded(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 11, color: kTextMuted, height: 1.1),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _orDash(value),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 10.5,
                      height: 1.15,
                      color: kTextSub,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── STEP 2 — SELECT SERVICES ────────────────────────────────────────────
  //
  // Two columns: the checklist of what this visitor needs on the left, and what
  // has been ticked so far on the right. Both read the same
  // `_selectedServiceIds`, so ticking on one side and removing on the other are
  // the same operation seen twice — there is no second copy of the selection to
  // fall out of step.

  /// The catalog's services, in the order this step reads them: six down the
  /// left column, five plus "Other" down the right.
  ///
  /// `ClinicPurposes.all` is in the clinic's own order, which is not this one,
  /// so the mapping is spelled out here. `test/clinic_visit_wizard_test.dart`
  /// fails if the two ever disagree, so a service added to the catalog but not
  /// placed in a column is caught rather than silently dropped.
  // Available Services ordering: Vital Signs first, BP Tracking next, then rest
  static const List<String> _serviceColumn1 = [
    'vital_signs',
    'bp_tracking',
    'temperature_checking',
    'bpi',
    'wound_dressing',
    'first_aid_treatment',
    'health_counselling',
  ];
  static const List<String> _serviceColumn2 = [
    'prenatal',
    'medication',
    'medicine_consultation',
    'medicine_certificate',
    'medical_clearance',
  ];

  /// The "Other" row, which is not a catalog service — it is the way out of the
  /// catalog for a service the clinic has not written down yet. Its id, label
  /// and icon are declared with the rest of the visit state above.

  /// The rows for one checklist column, in order. A name missing from the
  /// catalog is skipped rather than rendered as a blank row; the test guards
  /// that this never actually happens.
  List<({String id, String label, IconData icon})> _serviceRowsFor(int column) {
    final ids = column == 0 ? _serviceColumn1 : _serviceColumn2;
    final rows = <({String id, String label, IconData icon})>[];
    for (final id in ids) {
      final p = ClinicPurposes.byId(id);
      if (p == null) continue;
      rows.add((id: p.id, label: p.label, icon: p.icon));
    }
    // "Other" closes the second column, so the two columns end level.

    return rows;
  }

  /// How a ticked service is named in the right-hand list. "Other" shows what
  /// was typed, falling back to the row's own name while that box is still
  /// empty — so an incomplete "Other" is visible as incomplete, rather than
  /// silently appearing to be answered.
  String _serviceLabel(String id) {
    return ClinicPurposes.byId(id)?.label ?? id;
  }

  IconData _iconForService(String id) =>
      ClinicPurposes.byId(id)?.icon ?? Icons.medical_services_outlined;

  /// Ticking and unticking are the same operation wherever they are tapped, so
  /// the two cards cannot disagree about what is selected.
  void _toggleService(String id) {
    setState(() {
      if (_selectedServiceIds.contains(id)) {
        _selectedServiceIds.remove(id);
        // Untick "Other" and its typed name goes with it, so a later tick never
        // shows the last service's wording.
      } else {
        _selectedServiceIds.add(id);
      }
    });
  }

  void _continueFromStepTwo() {
    if (_selectedServiceIds.isEmpty) {
      _toast('Tick at least one service before continuing.', kWarning);
      return;
    }
    if (!_hasServices) {
      _toast('Name the service under "Other", or untick it.', kWarning);
      return;
    }
    _goToStep(2);
  }

  Widget _selectServicesStep() {
    return LayoutBuilder(builder: (context, constraints) {
      // Same rule as step 1: stack only when the window is narrow *and* tall
      // enough to give two cards a workable share of it.
      final stack = constraints.maxWidth < 980 && constraints.maxHeight >= 700;
      if (stack) {
        return Column(children: [
          Expanded(flex: 5, child: _newVisitCard()),
          const SizedBox(height: 14),
          Expanded(flex: 4, child: _visitInformationCard()),
        ]);
      }
      // Same shape as step 1: a stretched Row, so the cards are the height of
      // the step and equal to each other without an IntrinsicHeight pass.
      //
      // The split is not a flex ratio. The right card holds the visitor, a date,
      // a time and a list of ticked services, and it used to be handed 5/12 of
      // the window, so on a desktop it was most of a metre wide holding three
      // short lines and a handful of chips, while the checklist beside it, which
      // is twelve services the nurse has to read, was squeezed into whatever was
      // left and had to scroll.
      //
      // So the right card is given a width it can actually fill, and the
      // checklist takes everything that is left over. Sized explicitly rather
      // than with a flex ratio, because a flex allocation is spent whether the
      // child uses it or not: capping a `Flexible` at 340 would still have
      // reserved the 5/12 share for it and handed the checklist the remainder.
      //
      // The ceiling is 380 rather than 340 because the visitor moved in here: the
      // visitor's name and number on one side, the office and post on the other,
      // is two columns of text, and at 340 it was being ellipsised on a laptop.
      //
      // The floor keeps the card readable on a window that is not much wider
      // than the 980 that keeps the two columns apart in the first place.
      final infoWidth =
          (constraints.maxWidth * 5 / 12).clamp(260.0, 380.0).toDouble();
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: _newVisitCard()),
          const SizedBox(width: 20),
          SizedBox(width: infoWidth, child: _visitInformationCard()),
        ],
      );
    });
  }

  // ── STEP 2 LEFT CARD — SELECT SERVICES ──────────────────────────────────

  Widget _newVisitCard() {
    return _panel(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // One heading, and it names the job rather than the step. This card
          // used to carry "Select Services" at the top and "Reason for Visit /
          // Services Needed" twelve pixels below it — the same instruction said
          // twice, in two different sets of words, with the service list under
          // both. The step tracker already says this is the services step, so
          // the heading says what the nurse is here to do: say why the visit is
          // happening and what it is for.
          _eyebrow(Icons.medical_services_outlined,
              'Reason for Visit / Services Needed'),
          const SizedBox(height: 12),
          // Everything from the checklist down is the one part of the card with
          // no fixed height, so it takes what is left and scrolls inside the card
          // if that is not all of it. The Back button stays put, and the page
          // itself never grows.
          //
          // The visitor is not here any more. It is in the Visit Information
          // card, above the date and the time — which is where a nurse looks to
          // answer "whose visit is this, and when": the two belong in one place,
          // and the checklist below is twelve services that needed the row.
          _cardBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _reasonOfVisitField(),
                const SizedBox(height: 8),
                _assistBanner(),
                const SizedBox(height: 10),
                const Text('Available Services', style: kFieldLabelStyle),
                const SizedBox(height: 6),
                _serviceChecklist(),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }

  /// The visitor as this step needs to show them: two rows and no more.
  ///
  /// Row one is who they are and the number the record is filed under. Row two is
  /// what they do or study, in the words the clinic files them under — "Dept. &
  /// Position", "Program & Year" — on one line, under the name.
  ///
  /// It was two columns, and each column had a heading of its own. Four pieces of
  /// text, two of them labels, on a card whose actual job is the date and the
  /// time below it: a visitor is a check that the right person was picked, and
  /// four rows of type to make that check is a whole paragraph standing between
  /// the nurse and the question they came to answer.
  Widget _stepTwoVisitorSummary(ClinicProfile v) {
    String affiliation;
    if (v.isStudent) {
      affiliation = [v.institute, v.program, v.yearLevel]
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .join(' - ');
    } else if (v.isFaculty) {
      affiliation = [v.institute, v.position]
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .join(' - ');
    } else if (v.isStaff) {
      affiliation = [v.department, v.position]
          .map((e) => e.trim())
          .where((e) => e.isNotEmpty)
          .join(' - ');
    } else {
      affiliation = [
        v.department,
        v.position,
        v.institute,
        v.program,
        v.yearLevel
      ].map((e) => e.trim()).where((e) => e.isNotEmpty).join(' · ');
    }

    return Container(
      key: const ValueKey('step2/visitor_block'),
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 6),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _initialsAvatar(v, 15),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  v.fullName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.1,
                    fontWeight: FontWeight.w800,
                    color: kTextMain,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(
                key: const ValueKey('view_full_record'),
                onPressed: _showRecordDrawer,
                icon: const Icon(Icons.menu_book_outlined, size: 15),
                color: AppColors.primaryDark,
                tooltip: 'View Full Record',
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: kBorder),
                ),
                child: Text(
                  v.id,
                  style: const TextStyle(
                    fontSize: 10,
                    height: 1.1,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.2,
                    color: kTextSub,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 38),
            child: Text(
              '${v.id} | ${_orDash(affiliation)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 10.5,
                height: 1.15,
                color: kTextSub,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// The visitor's own record, over the wizard rather than in a new page.
  ///
  /// A route would lose the visit: a nurse is part-way through a form with half
  /// a set of vitals typed, and a back gesture that discards the draft is not a
  /// thing to hand someone who is mid-sentence with a patient. So this is an
  /// overlay that sits on top of a form that is still there when it closes.
  ///
  /// It is opened from step 2, beside the visitor the nurse is about to record
  /// services against — which is the last point at which the whole record is
  /// cheap to check, because nothing has been written against the wrong person
  /// yet. It used to be a button in step 3's visitor strip, which put a control
  /// for looking a person up on the step for writing a person down, and cost that
  /// form sixty pixels of height to do it.
  void _showRecordDrawer() {
    final v = _visitor;
    if (v == null) return;
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Close record',
      barrierColor: AppColors.textDark.withValues(alpha: 0.42),
      transitionDuration: const Duration(milliseconds: 180),
      pageBuilder: (_, __, ___) => RecordDrawer(
        profile: v,
        controller: _detailsFor(),
        // Nothing fetched yet: the drawer reads its own tabs on first visit.
        history: const [],
        historyFor: () => VisitDetailsService.historyFor(v.id),
        onOpenService: (id, slide) {
          Navigator.of(context).pop();
          // Opened from step 2, so the drawer can only read the visit; the
          // service it names is opened by going on to step 3.
          _toast(
              'Open ${_labelOf(id)} on the next step to record it.', kWarning);
        },
      ),
      transitionBuilder: (_, anim, __, child) => SlideTransition(
        position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(
          CurvedAnimation(parent: anim, curve: Curves.easeOutCubic),
        ),
        child: child,
      ),
    );
  }

  String _labelOf(String serviceId) =>
      ClinicPurposes.byId(serviceId)?.label ?? serviceId;

  Widget _assistBanner() {
    return _tealBanner(
      icon: Icons.chat_bubble_outline_rounded,
      title: 'How can we assist you today?',
      message: 'Select one or more services. You can choose multiple '
          'services for the same visit.',
    );
  }

  /// A two-column checklist, collapsing to one column when the card is too
  /// narrow for the service names to stay on one line each.
  Widget _serviceChecklist() {
    Widget rowsOf(int index) {
      final rows = _serviceRowsFor(index);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            _serviceRow(rows[i]),
            // No gap under the last row, so the columns end level instead of
            // each carrying a tail of empty space.
            if (i < rows.length - 1) const SizedBox(height: 6),
          ],
        ],
      );
    }

    // How many columns the checklist is split into, decided by the width the
    // checklist itself has been given.
    //
    // It used to read the *page* width, which is the same thing as saying the
    // checklist is always split two-up whenever the window is more than 700
    // across — including on a narrow window that had stacked into one column
    // anyway, where the twelve services were then crammed into a column as wide
    // as a phone. A service row is a checkbox, an icon and a name; below about
    // 480px there is no room for two of those side by side without the names
    // wrapping onto three lines, so it stays one column instead.
    return LayoutBuilder(builder: (context, c) {
      final twoUp = c.maxWidth >= 480;
      if (!twoUp) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [rowsOf(0), const SizedBox(height: 6), rowsOf(1)],
        );
      }
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: rowsOf(0)),
          const SizedBox(width: 12),
          Expanded(child: rowsOf(1)),
        ],
      );
    });
  }

  Widget _serviceRow(({String id, String label, IconData icon}) row) {
    final checked = _selectedServiceIds.contains(row.id);

    return Semantics(
      button: true,
      checked: checked,
      label: row.label,
      child: InkWell(
        onTap: () => _toggleService(row.id),
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: checked ? kPrimary.withValues(alpha: 0.07) : Colors.white,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: checked ? kPrimary : kBorder,
              width: checked ? 1.5 : 1,
            ),
          ),
          child: Row(children: [
            _checkBox(checked),
            const SizedBox(width: 10),
            Icon(row.icon, size: 17, color: checked ? kPrimary : kTextSub),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                row.label,
                maxLines: 2,
                style: TextStyle(
                  fontSize: 12.5,
                  height: 1.25,
                  fontWeight: checked ? FontWeight.w700 : FontWeight.w500,
                  color: checked ? kPrimaryDeep : kTextMain,
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _checkBox(bool checked) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: checked ? kPrimary : Colors.white,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: checked ? kPrimary : kBorderStrong,
          width: 1.5,
        ),
      ),
      child: checked
          ? const Icon(Icons.check_rounded, size: 13, color: Colors.white)
          : null,
    );
  }

  // ── STEP 2 RIGHT CARD — VISIT INFORMATION ───────────────────────────────

  Widget _visitInformationCard() {
    final v = _visitor;
    final now = DateTime.now();
    final count = _selectedServiceIds.length;
    // The right card is where the visit is checked before it moves on, so a
    // half-finished "Other" is called out here too, not only on its own row.

    return _panel(
      key: const ValueKey('step2/visit_info_card'),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _eyebrow(Icons.calendar_month_outlined, 'Visit Information'),
          const SizedBox(height: 12),
          // Who the visit is for, above the date and the time it is happening.
          // They are one question — "whose visit, and when" — and they were
          // answered in two places: the visitor in the card on the left, the
          // date and time in this one. A nurse checking the visit before it
          // moves on had to look left for one and right for the other, and the
          // checklist beside the visitor lost a row to hold it.
          if (v != null) ...[
            _stepTwoVisitorSummary(v),
            const SizedBox(height: 12),
          ],
          Row(
            children: [
              Expanded(
                child: _visitInfoColumn(Icons.calendar_today_outlined, 'Date',
                    DateFormat('MMM d, yyyy').format(now)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _visitInfoColumn(Icons.schedule_outlined, 'Time',
                    DateFormat('hh:mm a').format(now)),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(color: kBorder, height: 1),
          const SizedBox(height: 12),
          _eyebrow(Icons.checklist_rounded, 'Selected Services ($count)'),
          const SizedBox(height: 10),
          // The list of what has been ticked grows with the selection, so it
          // takes the space that is left and scrolls inside the card rather than
          // pushing the Continue button off a short screen.
          _cardBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (count == 0)
                  _noServicesSelected()
                else
                  for (final id in _selectedServiceIds) _selectedServiceRow(id),
              ],
            ),
          ),
          const SizedBox(height: 12),
          // The step's whole navigation, side by side and sized exactly as step
          // 3's pair is.
          //
          // Back used to sit alone under the left-hand card. That put the two
          // buttons at opposite ends of a 1366-wide window with a card edge
          // between them, so they read as two unrelated controls rather than as
          // the way in and the way out of one step — and a nurse working through
          // the wizard had to look in two places to find either. The left card
          // keeps its checklist and nothing else.
          Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            OutlinedButton.icon(
              onPressed: () => _goToStep(0),
              style: OutlinedButton.styleFrom(
                foregroundColor: kTextMain,
                side: const BorderSide(color: kBorder),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                // 40, not Material's 48. The pair sits in the footer of a card
                // that has to fit a 1366x768 laptop with no page scrolling, and
                // the height is worth more here than the padding is to the tap
                // target — this wizard is stepped through with a mouse.
                minimumSize: const Size(0, 40),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9)),
              ),
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Back',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              onPressed: _hasServices ? _continueFromStepTwo : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: kPrimary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.borderStrong,
                disabledForegroundColor: Colors.white,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
                minimumSize: const Size(0, 40),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9)),
              ),
              icon: const Icon(Icons.arrow_forward_rounded, size: 16),
              label: const Text('Continue',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
            ),
          ]),
        ],
      ),
    );
  }

  Widget _visitInfoColumn(IconData icon, String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(icon, size: 16, color: kPrimary),
            const SizedBox(width: 6),
            Text(label,
                style: const TextStyle(fontSize: 11.5, color: kTextSub)),
          ]),
          const SizedBox(height: 4),
          Text(value,
              style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: kTextMain)),
        ],
      ),
    );
  }

  Widget _selectedServiceRow(String id) {
    final label = _serviceLabel(id);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
      decoration: BoxDecoration(
        color: kPrimary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kPrimary.withValues(alpha: 0.35)),
      ),
      child: Row(children: [
        Icon(_iconForService(id), size: 18, color: kPrimary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
                fontSize: 12.5, fontWeight: FontWeight.w700, color: kTextMain),
          ),
        ),
        IconButton(
          onPressed: () => _toggleService(id),
          icon: const Icon(Icons.close_rounded, size: 18),
          color: kPrimary,
          tooltip: 'Remove $label',
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
        ),
      ]),
    );
  }

  Widget _noServicesSelected() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder),
      ),
      child: const Column(children: [
        Icon(Icons.playlist_add_check_rounded, size: 36, color: kTextMuted),
        SizedBox(height: 10),
        Text('No services selected yet',
            style: TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: kTextMain)),
        SizedBox(height: 4),
        Text(
          'Tick a service on the left to add it here.',
          textAlign: TextAlign.center,
          style: kCaptionStyle,
        ),
      ]),
    );
  }

  /// The small uppercase icon-and-label head each step-2 card opens with.
  Widget _eyebrow(IconData icon, String label) {
    return Row(children: [
      Icon(icon, size: 20, color: kPrimary),
      const SizedBox(width: 10),
      Expanded(child: Text(label.toUpperCase(), style: kEyebrowStyle)),
    ]);
  }

  /// A light-teal note. The optional [title] makes it a prompt rather than a
  /// statement, which is how the left card uses its two.
  Widget _tealBanner({
    required IconData icon,
    required String message,
    String? title,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kPrimary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: kPrimary.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: kPrimary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null) ...[
                  Text(title,
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w700,
                          color: kTextMain)),
                  const SizedBox(height: 2),
                ],
                Text(message,
                    style: TextStyle(
                        fontSize: 12.5,
                        color: title != null ? kTextSub : kTextMain,
                        height: 1.4)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── STEP 4 — REVIEW & COMPLETE ─────────────────────────────────────────

  Widget _reviewStep() {
    final v = _visitor;
    return _panel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(children: [
            Icon(Icons.fact_check_outlined, size: 20, color: kPrimary),
            SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Review & Complete', style: kSectionTitleStyle),
                  SizedBox(height: 2),
                  Text('Check the visit before it is written to the record',
                      style: kSectionSubtitleStyle),
                ],
              ),
            ),
          ]),
          const SizedBox(height: 12),
          const Divider(color: kBorder, height: 1),
          const SizedBox(height: 12),
          _cardBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (v == null)
                  _noteBanner(kWarning, Icons.person_search_outlined,
                      'Pick a visitor on step 1 before completing a visit.')
                else if (!_hasServices)
                  _noteBanner(kWarning, Icons.healing_outlined,
                      'Tick at least one service for this visit on step 2.')
                else ...[
                  VisitReviewCard(title: 'Visitor', lines: [
                    VisitReviewLine.pair('Name', v.fullName),
                    VisitReviewLine.pair('School ID', v.id),
                    VisitReviewLine.pair('Role', v.category),
                    VisitReviewLine.pair('Affiliation', v.affiliationLabel),
                    VisitReviewLine.pair('Contact', _orDash(v.contact)),
                  ]),
                  const SizedBox(height: 14),
                  VisitReviewCard(title: 'Service', lines: [
                    // A visit can carry several services, so the count is stated
                    // and the names are listed rather than crammed into one
                    // "reason".
                    VisitReviewLine.pair(
                        'Services ticked', '${_selectedServiceIds.length}'),
                    for (final id in _selectedServiceIds)
                      VisitReviewLine.plain(_serviceLabel(id)),
                    VisitReviewLine.pair('Procedure required',
                        _requiresProcedure ? 'Yes' : 'No'),
                  ]),
                  const SizedBox(height: 14),
                  _serviceDetailGroups(),
                  const SizedBox(height: 14),
                  VisitReviewCard(title: 'Record', lines: [
                    VisitReviewLine.pair('Date',
                        DateFormat('MMM d, yyyy').format(DateTime.now())),
                    // The check-in is a fact about the visit; the out-time is not
                    // known until it ends, so it is shown as what it is rather
                    // than filled in with the time the review was opened.
                    VisitReviewLine.pair('Time in', _timeInText),
                    VisitReviewLine.pair('Time out', 'On completion'),
                    VisitReviewLine.pair('Recorded by', _currentUserName),
                  ]),
                  if (_patientUuid == null) ...[
                    const SizedBox(height: 14),
                    _noteBanner(
                      kDanger,
                      Icons.error_outline,
                      "This visitor's clinic record is not ready yet, so the "
                      'visit cannot be saved. Go back to step 1 and pick '
                      'them again.',
                    ),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// One card per service, each holding everything that was entered for it.
  ///
  /// This is the whole point of step 4: the nurse has just walked past nine
  /// forms, and the question before "Complete Consultation" is not "is the visit
  /// complete" but "is this what I meant to record". A list of service names
  /// cannot answer that, and asking her to go back to step 3 to check is how a
  /// wrong record gets written.
  ///
  /// The rows come from [serviceSummary] - the same reader that prints a
  /// service's own review slide at the end of its last step - so what is
  /// confirmed here is exactly what was shown there, and a field cannot appear
  /// in one and not the other.
  ///
  /// A service nobody has started gets a card that says so rather than being
  /// dropped: "ticked but empty" is itself something a nurse needs to see before
  /// completing, and silently omitting it would leave the count on the card
  /// above quietly wrong.
  Widget _serviceDetailGroups() {
    final controller = _details;
    if (controller == null || controller.drafts.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final draft in controller.drafts) ...[
          VisitReviewCard(
              title: draft.label,
              lines: visitReviewLines(draft, _details!.vitals)),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  // ── WIZARD FOOTER ──────────────────────────────────────────────────────
  //
  // Step 1's action lives inside the Visitor Information card, where the
  // design puts it. From step 2 on there is no card left to host it, so the
  // pinned bar takes over.

  Widget _wizardFooter() {
    final isLast = _step == _stepTitles.length - 1;
    // Step 3 writes the service and moves on, so its button says "Continue": it
    // is the same journey as every other step, and "Save & Continue" made a
    // nurse stop and wonder what was being saved and where. It is offered
    // whenever there is anything to save rather than when the step is finished:
    // an unfinished service is a legitimate thing to leave behind, and the
    // left-hand list is what shows which ones still are.
    final isDetails = _step == 2;
    final canAdvance = isLast
        ? _canSave
        : isDetails
            ? _hasServices
            : _step + 1 <= _maxReachable;
    final label = isLast
        ? 'Complete Consultation'
        : isDetails
            ? 'Continue'
            : 'Proceed';

    // The buttons and nothing else.
    //
    // This was a white bar with a rule across the top of it, which is a fourth
    // container on a step that already has two. It also cost the step the height
    // it was standing in the middle of: the bar was as tall as its buttons plus
    // its own padding, and on a 1366x768 laptop that is a band of the form's
    // width given to holding two buttons up. The buttons sit on the page now, in
    // the same 20px gutter as the cards above them, so the cards run down to
    // where the buttons begin instead of stopping short of them.
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
      child: SafeArea(
        top: false,
        child: Row(children: [
          if (_step > 0) ...[
            OutlinedButton.icon(
              onPressed: () => _goToStep(_step - 1),
              style: OutlinedButton.styleFrom(
                foregroundColor: kTextMain,
                side: const BorderSide(color: kBorder),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                minimumSize: const Size(0, 40),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9)),
              ),
              icon: const Icon(Icons.arrow_back_rounded, size: 16),
              label: const Text('Back',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 10),
          ],
          // A Spacer, not an Expanded. The action used to stretch the full width
          // of the window, which made it the largest object on a 1366-wide
          // screen and pulled the eye away from the form being filled in above
          // it. Sized to its own label and pushed right, it reads as a button
          // again, and the thin bar it sits in gives the form back the height.
          const Spacer(),
          ElevatedButton.icon(
            onPressed: (_saving || !canAdvance)
                ? null
                : (isLast
                    ? _completeConsultation
                    : isDetails
                        ? _saveStepThree
                        : () => _goToStep(_step + 1)),
            style: ElevatedButton.styleFrom(
              backgroundColor: kPrimary,
              foregroundColor: Colors.white,
              disabledBackgroundColor: AppColors.borderStrong,
              disabledForegroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
              // 40, an explicit one, and shrinkWrap on the tap target.
              // Material pads every button out to 48px so a fingertip can hit
              // it on a phone — which put a 48px band under a form that a nurse
              // is typing into with a keyboard. This wizard is stepped through
              // with a mouse on a laptop, and the height is worth more to the
              // form than the padding is to the target.
              minimumSize: const Size(0, 40),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9)),
            ),
            icon: _saving
                ? const SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.white),
                  )
                : Icon(
                    isLast ? Icons.check_rounded : Icons.arrow_forward_rounded,
                    size: 16,
                  ),
            label: Text(
              label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
            ),
          ),
        ]),
      ),
    );
  }

  // ── STEP 3: SAVING A SERVICE ───────────────────────────────────────────

  /// Writes the whole of step 3 against a visit that now exists.
  ///
  /// A failure here does not stop the consultation being recorded: the visit
  /// itself is saved, and step 3's answers are still on screen. Saying so is
  /// better than blocking a nurse on a write that may only be the network.
  Future<void> _saveStepThreeToServer(String visitId) async {
    final controller = _details;
    if (controller == null || controller.drafts.isEmpty) return;
    try {
      await VisitDetailsService.saveAll(
        visitId: visitId,
        controller: controller,
        userName: _currentUserName,
      );
    } catch (e) {
      debugPrint('clinic visit: step 3 save failed: $e');
      if (!mounted) return;
      _toast('Visit saved, but the service details did not. Re-check step 3.',
          kWarning);
    }
  }

  /// What "Save & Continue" means on step 3: settle the service on screen,
  /// then move to the next one that is not finished, and only leave the step
  /// when there is nothing left to fill in.
  ///
  /// The order is the one step 2 chose, so a visit with six services is walked
  /// in the order the nurse planned it rather than in whatever order the list
  /// happens to be sorted into.
  void _saveStepThree() {
    final controller = _detailsFor();
    final label = controller.active?.label ?? 'Service';
    if (controller.active == null) {
      _toast('Pick a service to record first.', kWarning);
      return;
    }

    // The controller owns the rule — mark complete if it can be, otherwise open
    // the next unfinished one — and it is unit-tested on its own. It returns
    // true only when the whole visit is answered, which is the one case where
    // the wizard itself moves.
    final allDone = controller.saveAndContinue();

    // Anything a nurse must not leave behind: a prescription the inventory
    // cannot cover, a reading that means refer now. Said before moving on
    // rather than allowed to disappear into the step below.
    final outstanding = controller.outstanding;
    setState(() {});
    if (!allDone) {
      _toast(
          outstanding.isEmpty
              ? '$label not finished yet — fill in the required boxes.'
              : '$label saved. Before you continue: ${outstanding.first}',
          outstanding.isEmpty ? kWarning : kWarning);
      return;
    }
    if (outstanding.isEmpty) {
      _goToStep(_stepTitles.length - 1);
    } else {
      _toast('All services recorded. Before you continue: ${outstanding.first}',
          kWarning);
    }
  }

  // ── ADD NEW VISITOR ────────────────────────────────────────────────────

  Future<void> _showAddVisitorDialog() async {
    final firstCtrl = TextEditingController();
    final lastCtrl = TextEditingController();
    final idCtrl = TextEditingController();
    final contactCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    String role = 'Student';
    String? program;
    String? yearLevel;
    String? institute;
    String? department;
    String? position;

    final created = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setLocal) {
          final isStudent = role == 'Student';
          final isFaculty = role == 'Faculty';
          return AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
            title: const Row(children: [
              Icon(Icons.person_add_alt_1_rounded, color: kPrimary, size: 22),
              SizedBox(width: 8),
              Text('Add New Visitor'),
            ]),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _dialogLabel('First Name'),
                      _dialogField(firstCtrl,
                          placeholder: 'e.g. Maria',
                          prefixIcon: Icons.person_outline),
                      const SizedBox(height: 12),
                      _dialogLabel('Last Name'),
                      _dialogField(lastCtrl,
                          placeholder: 'e.g. Santos',
                          prefixIcon: Icons.person_outline),
                      const SizedBox(height: 12),
                      _dialogLabel('School ID'),
                      _dialogField(
                        idCtrl,
                        placeholder: isStudent
                            ? '6-digit student number'
                            : 'leave blank to auto-generate',
                        prefixIcon: Icons.badge_outlined,
                        keyboardType: TextInputType.number,
                        inputFormatters: isStudent
                            ? [
                                FilteringTextInputFormatter.digitsOnly,
                                LengthLimitingTextInputFormatter(6),
                              ]
                            : null,
                      ),
                      const SizedBox(height: 12),
                      _dialogLabel('Role Type'),
                      _dialogDropdown(
                        value: role,
                        items: const ['Student', 'Faculty', 'Staff'],
                        onChanged: (v) => setLocal(() {
                          role = v ?? 'Student';
                          program = null;
                          yearLevel = null;
                          institute = null;
                          department = null;
                          position = null;
                        }),
                      ),
                      const SizedBox(height: 12),

                      // Each role files under a different thing, and the schema's
                      // CHECK constraints enforce that: a student under a
                      // program, faculty under an institute, staff under an
                      // office. Offering faculty a "Department" here is what put
                      // a department on a row the database will not accept.
                      _dialogLabel(isStudent
                          ? 'Program'
                          : isFaculty
                              ? 'Institute'
                              : 'Department'),
                      if (isStudent)
                        _programDropdown(
                            value: program,
                            onChanged: (v) => setLocal(() => program = v))
                      else if (isFaculty)
                        _dialogDropdown(
                          value: institute ?? '',
                          items: kInstitutes,
                          allowEmpty: true,
                          emptyLabel: 'Select an institute',
                          onChanged: (v) => setLocal(() => institute = v),
                        )
                      else
                        _dialogDropdown(
                          value: department ?? '',
                          items: departmentOptionsFor(role),
                          allowEmpty: true,
                          emptyLabel: 'Select a department',
                          onChanged: (v) => setLocal(() => department = v),
                        ),
                      const SizedBox(height: 12),
                      _dialogLabel(isStudent ? 'Year Level' : 'Position'),
                      _dialogDropdown(
                        value: isStudent ? yearLevel ?? '' : position ?? '',
                        items:
                            isStudent ? kYearLevels : positionOptionsFor(role),
                        allowEmpty: true,
                        emptyLabel: isStudent
                            ? 'Select a year level'
                            : 'Select a position',
                        onChanged: (v) => setLocal(() {
                          if (isStudent) {
                            yearLevel = v;
                          } else {
                            position = v;
                          }
                        }),
                      ),
                      const SizedBox(height: 12),
                      _dialogLabel('Contact Number'),
                      _dialogField(
                        contactCtrl,
                        placeholder: '09XXXXXXXXX',
                        prefixIcon: Icons.phone_outlined,
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(11),
                        ],
                        required: false,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: kPrimary,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                onPressed: () async {
                  if (!formKey.currentState!.validate()) return;
                  final ok = await _createVisitor(
                    ctx: ctx,
                    role: role,
                    first: firstCtrl.text.trim(),
                    last: lastCtrl.text.trim(),
                    requestedId: idCtrl.text.trim(),
                    contact: contactCtrl.text.trim(),
                    program: program ?? '',
                    yearLevel: yearLevel ?? '',
                    institute: institute ?? '',
                    department: department ?? '',
                    position: position ?? '',
                  );
                  if (ctx.mounted) Navigator.pop(ctx, ok);
                },
                child: const Text('Add Visitor'),
              ),
            ],
          );
        },
      ),
    );

    if (created == true) {
      _toast('Visitor added. They are now in the search list.', kPrimary);
    }
  }

  /// Adds somebody to the clinic from the Add Visitor dialog.
  ///
  /// Three outcomes, not two, because a person and an enrolment are separate:
  ///
  ///   * **New** — no `individual_records` row carries that number in that
  ///     category, so a person and an Active enrolment for the term being run are
  ///     written.
  ///   * **Returning** — the number is on file from an earlier term but has no
  ///     enrolment for the term being run. That is a student who came back, and
  ///     refusing them is what used to make it impossible to check in a returning
  ///     student. The person is left exactly as they are and only the enrolment
  ///     is added.
  ///   * **Already here** — the person is on this term's roster. Nothing is
  ///     written; the dialog reports it and closes so the visit can proceed.
  ///
  /// Returns false when the dialog should stay open. `ctx` is the dialog's own
  /// context, used only so a toast appears above it.
  Future<bool> _createVisitor({
    required BuildContext ctx,
    required String role,
    required String first,
    required String last,
    required String requestedId,
    required String contact,
    required String program,
    required String yearLevel,
    required String institute,
    required String department,
    required String position,
  }) async {
    final isStudent = role == 'Student';
    // Faculty and staff numbers come from the database, not from the client's
    // random generator. `generate_person_id` reserves the number against the
    // unique index, so two clinics adding somebody at the same moment cannot both
    // be handed the same one — whereas a number invented here and written blind
    // only fails at the INSERT, as a constraint name in a toast.
    final id = isStudent
        ? requestedId
        : (requestedId.isNotEmpty
            ? requestedId
            : await IndividualRecordService.nextIdFor(role));

    if (id.isEmpty) {
      _toast('Enter the School ID for a new student.', kWarning);
      return false;
    }

    // Everything below needs a term to enrol them into, and an enrolment with no
    // period is not a row this schema can hold. Refusing here beats writing a
    // person who silently never appears on the roster.
    final periodId = kCurrentAcademicPeriodId;
    if (periodId == null || periodId.isEmpty) {
      _toast(
          'There is no current term to enrol them in. Set one on the Individual '
          'Record page first.',
          kWarning);
      return false;
    }

    // The dropdowns hand over names from the catalog; the columns are foreign
    // keys. A student takes their institute from the program they were picked
    // into rather than from a second dropdown, because a program belongs to
    // exactly one institute and asking again only offers an inconsistent pair.
    final programId =
        isStudent ? ReferenceCatalog.programIdFor(null, program) : null;
    final instituteId = isStudent
        ? ReferenceCatalog.instituteIdOfProgram(programId)
        : ReferenceCatalog.instituteByCode(institute)?.id;
    final departmentId =
        isStudent ? null : ReferenceCatalog.departmentIdByName(department);
    final positionId =
        isStudent ? null : ReferenceCatalog.positionIdByName(position);

    // A number identifies one person for good, so this lookup is by number and
    // not by term: somebody on last term's roster is not a different person.
    final existing = await IndividualRecordService.fetchLatest(role, id);

    if (existing != null) {
      // Archived is not the same as "not on this term's roster". Adding a
      // returning enrolment to an archived person would put somebody back on the
      // roster behind an administrator's back.
      if (existing.isArchived) {
        _toast(
            '$role $id is archived. Restore them from the Archive page '
            'before checking them in.',
            kWarning);
        return false;
      }

      if (existing.academicPeriodId == periodId &&
          existing.status == kRecordStatusActive) {
        _toast(
            '$role $id is already on the roster for '
            '${academicTermLabel(kCurrentAcademicYear, kCurrentSemester)}.',
            kWarning);
        return false;
      }

      // Returning: keep the person as they are, add this term's enrolment.
      final reEnrolled = await _enrolExisting(
        existing: existing,
        role: role,
        contact: contact,
        academicPeriodId: periodId,
        instituteId: instituteId,
        programId: programId,
        yearLevel: isStudent ? yearLevel : '',
        departmentOfficeId: departmentId,
        positionId: positionId,
      );
      if (reEnrolled == null) return false;
      if (!mounted) return false;
      PatientDirectory.instance.upsert(_profileFromRecord(reEnrolled));
      await _selectVisitor(_profileFromRecord(reEnrolled));
      return true;
    }

    final record = IndividualRecord(
      id: id,
      category: role,
      firstName: first,
      lastName: last,
      sex: '',
      contact: contact,
      // The term being run, by id, from the shared catalog. This was computed
      // from the month of the clock and paired with kSemesters.first, so a
      // visitor added in October was filed under a term that has not started and
      // a semester that has been over since spring.
      academicPeriodId: periodId,
      academicYear: kCurrentAcademicYear,
      semester: kCurrentSemester,
      // Faculty carry an institute and no office; staff the reverse; students an
      // institute plus a program and neither of the others. The CHECK
      // constraints reject anything else, so the split is made here rather than
      // left to a constraint violation.
      instituteId: instituteId,
      institute: isStudent ? (instituteOfProgram(program) ?? '') : institute,
      programId: programId,
      program: isStudent ? program : '',
      yearLevel: isStudent ? yearLevel : '',
      departmentOfficeId: departmentId,
      department: isStudent ? '' : department,
      positionId: positionId,
      position: isStudent ? '' : position,
    );

    IndividualRecord saved;
    try {
      saved = await IndividualRecordService.create(record);
    } on IndividualRecordSaveIncomplete catch (e) {
      // The person IS on file — only their term enrolment was refused. Abandoning
      // the walk-in here would leave a registered patient with no term, which is
      // the one state the roster cannot show, and the visit would have to be filed
      // all over again. So the visit continues on the record as saved, and the
      // caveat is shown as a warning rather than a refusal, because refusing here
      // would look like the person does not exist.
      saved = e.record;
      _toast(e.message, kWarning);
    } catch (e) {
      // Translated rather than printed: this screen adds the very same person and
      // enrolment rows the roster screen does, so it hits the very same
      // constraints, and `duplicate key value violates unique constraint
      // "uq_individual_email"` tells a nurse at the front desk nothing about what
      // to change.
      _toast(
        IndividualRecordService.describeWriteFailure(
          e,
          category: role,
          recordNo: record.id,
        ),
        kDanger,
      );
      return false;
    }
    if (!mounted) return false;

    final profile = _profileFromRecord(saved);
    PatientDirectory.instance.upsert(profile);
    await _selectVisitor(profile);
    return true;
  }

  /// Adds a term's enrolment to a person who is already on file.
  ///
  /// The person's own fields are rewritten from [existing] rather than from the
  /// dialog: this is a check-in, not an edit, so somebody who has changed their
  /// address since last term should keep the address on file until the roster
  /// screen is used to correct it. Only the affiliation is taken fresh.
  ///
  /// Returns the re-enrolled record, or null after reporting a failure.
  Future<IndividualRecord?> _enrolExisting({
    required IndividualRecord existing,
    required String role,
    required String contact,
    required String academicPeriodId,
    required String? instituteId,
    required String? programId,
    required String yearLevel,
    required String? departmentOfficeId,
    required String? positionId,
  }) async {
    final uuid = existing.uuid;
    if (uuid == null) return null;

    // `update` sees no enrolment for this period and adds one, which is the same
    // insert the new-person path performs, reached through the person that owns
    // it. `academicRecordId` is cleared so it cannot match this period's row by
    // an id from a different term.
    final draft = IndividualRecord(
      uuid: uuid,
      id: existing.id,
      category: role,
      firstName: existing.firstName,
      middleName: existing.middleName,
      lastName: existing.lastName,
      suffix: existing.suffix,
      sex: existing.sex,
      birthDate: existing.birthDate,
      contact: contact.isEmpty ? existing.contact : contact,
      email: existing.email,
      address: existing.address,
      academicPeriodId: academicPeriodId,
      academicYear: kCurrentAcademicYear,
      semester: kCurrentSemester,
      instituteId: instituteId ?? existing.instituteId,
      programId: programId,
      yearLevel: yearLevel,
      departmentOfficeId: departmentOfficeId,
      positionId: positionId,
      status: kRecordStatusActive,
    );

    try {
      return await IndividualRecordService.update(draft);
    } on IndividualRecordSaveIncomplete catch (e) {
      // Same reasoning as the create path above: the details ARE saved. Returning
      // null would tell the front desk the update failed and invite a second one,
      // so the row comes back and the caveat rides on a warning toast.
      _toast(e.message, kWarning);
      return e.record;
    } catch (e) {
      _toast(
        IndividualRecordService.describeWriteFailure(
          e,
          category: role,
          recordNo: draft.id,
        ),
        kDanger,
      );
      return null;
    }
  }

  // ── SHARED SMALL WIDGETS ───────────────────────────────────────────────

  /// The white rounded card every panel on this page is built from.
  Widget _panel({
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(20),
    Key? key,
  }) {
    return Container(
      key: key,
      width: double.infinity,
      padding: padding,
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: kBorder),
      ),
      child: child,
    );
  }

  Widget _noteBanner(Color color, IconData icon, String message) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            message,
            style:
                const TextStyle(fontSize: 12.5, color: kTextMain, height: 1.4),
          ),
        ),
      ]),
    );
  }

  Widget _initialsAvatar(ClinicProfile p, double radius) {
    final letters = [p.firstName, p.lastName]
        .where((e) => e.trim().isNotEmpty)
        .map((e) => e.trim()[0].toUpperCase())
        .take(2)
        .join();
    return CircleAvatar(
      radius: radius,
      backgroundColor: kPrimary.withValues(alpha: 0.10),
      child: Text(
        letters.isEmpty ? '?' : letters,
        style: TextStyle(
          fontSize: radius * 0.72,
          fontWeight: FontWeight.w800,
          color: kPrimary,
        ),
      ),
    );
  }

  /// Student is green, Faculty purple, Staff orange — the same three roles
  /// always read the same colour, here and in the search results.
  Widget _roleBadge(String category, {double fontSize = 11.5}) {
    late final Color bg;
    late final Color fg;
    switch (category) {
      case 'Faculty':
        bg = const Color(0xFFF3E8FF);
        fg = const Color(0xFF7E22CE);
      case 'Staff':
        bg = const Color(0xFFFFEDD5);
        fg = const Color(0xFFC2410C);
      default:
        bg = const Color(0xFFDCFCE7);
        fg = const Color(0xFF15803D);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        category,
        style: TextStyle(
            fontSize: fontSize, fontWeight: FontWeight.w700, color: fg),
      ),
    );
  }

  // ── DIALOG FORM CONTROLS ─────────────────────────────────────────────────

  Widget _dialogLabel(String label) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          label,
          style: const TextStyle(
              fontSize: 12.5, fontWeight: FontWeight.w600, color: kTextSub),
        ),
      );

  InputDecoration _dialogDecoration(
    String hint, {
    IconData? prefixIcon,
    String? errorText,
  }) {
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 12.5, color: kTextSub),
      errorText: errorText,
      filled: true,
      fillColor: kFieldFill,
      prefixIcon: prefixIcon == null
          ? null
          : Icon(prefixIcon, size: 18, color: kTextSub),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      border: _dialogBorder(kBorder),
      enabledBorder: _dialogBorder(kBorder),
      focusedBorder: _dialogBorder(kPrimary, width: 1.5),
      errorBorder: _dialogBorder(kDanger),
      focusedErrorBorder: _dialogBorder(kDanger, width: 1.5),
    );
  }

  OutlineInputBorder _dialogBorder(Color color, {double width = 1}) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: color, width: width),
      );

  Widget _dialogField(
    TextEditingController controller, {
    required String placeholder,
    IconData? prefixIcon,
    bool required = true,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: const TextStyle(fontSize: 14, color: kTextMain),
      validator: (v) =>
          required && (v == null || v.trim().isEmpty) ? 'Required' : null,
      decoration: _dialogDecoration(placeholder, prefixIcon: prefixIcon),
    );
  }

  /// A dropdown that can never be out of sync with its own value.
  ///
  /// The list is de-duplicated and the current value is appended when it is
  /// missing, because a `DropdownButtonFormField` whose `value` is not in
  /// `items` throws "There should be exactly one item with DropdownButton's
  /// value" — which takes the whole dialog down for a stale roster value.
  Widget _dialogDropdown({
    required String value,
    required List<String> items,
    required void Function(String?) onChanged,
    bool allowEmpty = false,
    String emptyLabel = 'Select',
  }) {
    final options = <String>[
      if (allowEmpty) '',
      ...items.where((e) => e.isNotEmpty),
    ];
    if (value.isNotEmpty && !options.contains(value)) options.add(value);

    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      onChanged: onChanged,
      items: options
          .map((e) => DropdownMenuItem(
                value: e,
                child: Text(
                  e.isEmpty ? emptyLabel : e,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    color: e.isEmpty ? kTextSub : kTextMain,
                  ),
                ),
              ))
          .toList(),
      decoration: _dialogDecoration(emptyLabel),
    );
  }

  /// Program is only ever offered from the institute that teaches it, so the
  /// pair can never contradict itself.
  Widget _reasonOfVisitField() {
    return TextFormField(
      controller: _reasonForVisitCtrl,
      decoration: const InputDecoration(
        hintText: 'Enter reason of visit',
        border: OutlineInputBorder(),
        filled: true,
        fillColor: kFieldFill,
        isDense: true,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }

  Widget _programDropdown({
    required String? value,
    required void Function(String?) onChanged,
  }) {
    final list = value == null || value.isEmpty ? kInstitutes : <String>[value];
    return _dialogDropdown(
      value: value ?? '',
      items: list,
      allowEmpty: true,
      emptyLabel: 'Select a program',
      onChanged: onChanged,
    );
  }

  // ── FORMATTERS / HELPERS ───────────────────────────────────────────────

  String _orDash(String? value) {
    final t = (value ?? '').trim();
    return t.isEmpty ? '—' : t;
  }

  String _formatDate(String? iso) {
    final raw = (iso ?? '').trim();
    if (raw.isEmpty) return '—';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return raw;
    return DateFormat('MMM d, yyyy').format(parsed);
  }

  void _toast(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 1),
        // 52, which is the pinned button bar (40) and the gutter under it (10).
        //
        // A toast that lands on top of the buttons is a toast that stops the
        // nurse: "fill in the required box to continue" appears at the exact
        // moment she is reaching for the button it is talking about, and if the
        // message is sitting on the button then the only thing she can do is
        // wait for it to fade. Floated clear of the bar, the nag is read and
        // then the button is there to press.
        margin: const EdgeInsets.fromLTRB(24, 0, 24, 52),
      ),
    );
  }
}
