// ─────────────────────────────────────────────────────────────────────────────
//  visit_details.dart
//  Everything step 3 knows, in one object.
//
//  WHY A CONTROLLER AND NOT A STATEFULWIDGET PER SERVICE
//  A visit's vitals are entered once and read by four different forms; a medical
//  certificate has to be able to pull the visitor's history into a document; and
//  pressing Back must not throw away what was typed. All of that only works if
//  one object holds the whole visit while the widgets come and go. So the
//  widgets are dumb — they read this and call back into it — and this file
//  answers the four questions the screen keeps asking:
//
//    1. Which services were chosen on step 2, and in what order?
//    2. Which of them are started, and which are finished?
//    3. Is the CURRENT slide complete enough to move on?
//    4. Where does Save & Continue go next?
//
//  Every mutation notifies, so a status pill changes the moment a form is
//  completed rather than when somebody remembers to refresh it.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/foundation.dart';

import '../services/medicine_service.dart';
import 'clinic_purposes.dart';
import 'visit_service_forms.dart';
import 'vitals.dart';

/// The three states a service row on the left can be in.
enum ServiceDraftStatus {
  notStarted('Not Started'),
  inProgress('In Progress'),
  completed('Completed');

  const ServiceDraftStatus(this.label);

  /// The exact word the status pill shows.
  final String label;
}

/// One row of medicine prescribed during a visit.
///
/// Carries its own copy of the stock it was picked against, because the picker's
/// "12 in stock" is only true at the moment of picking — and because the visit
/// is saved before the stock is deducted.
class MedicineDose {
  MedicineDose({
    this.medicineId,
    this.name = '',
    this.unit = '',
    this.quantity,
    this.dose = '',
    this.frequency = '',
    this.action = 'Given',
    this.response = '',
    this.notes = '',
    this.reasonNotGiven = '',
    this.stockAtPick = 0,
  });

  final int? medicineId;
  String name;
  String unit;
  int? quantity;
  String dose;
  String frequency;
  String action;
  String response;
  String notes;
  String reasonNotGiven;
  int stockAtPick;

  bool get isComplete {
    final a = action.trim();
    if (a.isEmpty) return false;
    if (a == 'Given' || a == 'Partially Given') {
      return medicineId != null &&
          (quantity ?? 0) > 0 &&
          dose.trim().isNotEmpty;
    }
    if (a == 'Not Given' || a == 'Held' || a == 'Refused') {
      return medicineId != null;
    }
    return medicineId != null;
  }

  int overdraw() {
    final q = quantity ?? 0;
    return q > stockAtPick ? q - stockAtPick : 0;
  }

  Map<String, dynamic> toJson() => {
        'medicine_id': medicineId,
        'name': name,
        'unit': unit,
        'quantity': quantity,
        'dose': dose,
        'frequency': frequency,
        'action': action,
        'response': response,
        'notes': notes,
        'reason_not_given': reasonNotGiven,
      };

  factory MedicineDose.fromJson(Map<String, dynamic> j) => MedicineDose(
        medicineId: (j['medicine_id'] as num?)?.toInt(),
        name: '${j['name'] ?? ''}',
        unit: '${j['unit'] ?? ''}',
        quantity: (j['quantity'] as num?)?.toInt(),
        dose: '${j['dose'] ?? ''}',
        frequency: '${j['frequency'] ?? ''}',
        action: '${j['action'] ?? ''}',
        response: '${j['response'] ?? ''}',
        notes: '${j['notes'] ?? ''}',
        reasonNotGiven: '${j['reason_not_given'] ?? ''}',
        stockAtPick: (j['stock_at_pick'] as num?)?.toInt() ?? 0,
      );

  MedicineDose copy() => MedicineDose.fromJson(toJson());

  String get summary {
    final parts = <String>[name];
    if (quantity != null && quantity! > 0) {
      parts.add(' '.trim());
    }
    if (dose.trim().isNotEmpty) parts.add(dose.trim());
    if (frequency.trim().isNotEmpty) parts.add(frequency.trim());
    if (action != 'Given' && action.isNotEmpty) {
      parts.add('()');
    }
    return parts.join(' — ');
  }
}

class ServiceDraft {
  ServiceDraft({required this.serviceId, this.otherName = ''})
      : spec = VisitServiceForms.forId(serviceId);

  final String serviceId;
  final ServiceFormSpec spec;

  /// The name typed against "Other" on step 2, so the read-only title on that
  /// form shows what the nurse actually called it.
  ///
  /// Mutable so that clearing a service can put the title back to "Other" —
  /// a draft's whole job is to be editable, and [status], [slide] and [dirty]
  /// beside it are all mutable for the same reason.
  String otherName;

  /// The answers. Field keys come from [VisitServiceForms]; nothing is nested,
  /// because a column-per-field table would need a migration for every new
  /// question and `data` is the one place that does not.
  final Map<String, dynamic> data = {};

  /// The medicine rows, for the medication service only. Kept out of [data] so
  /// saving a draft does not pretend a prescription was issued — that is a
  /// separate call, made when the visit is completed.
  final List<MedicineDose> medicines = [];

  ServiceDraftStatus status = ServiceDraftStatus.notStarted;

  /// Which slide is on screen. Remembered so Back from slide 2 lands on slide 2,
  /// not back at the top of a form the nurse has already half finished.
  int slide = 0;

  /// Set the moment anything is typed, and cleared on save. The footer uses it
  /// to say "Save & Continue" honestly rather than guessing.
  bool dirty = false;

  String get label {
    if (serviceId == VisitServiceForms.otherServiceId) {
      return otherName.trim().isEmpty ? 'Other' : otherName.trim();
    }
    return ClinicPurposes.byId(serviceId)?.label ?? 'Other';
  }

  /// The short word the narrow service list uses where a full label will not
  /// fit, e.g. "Wound" rather than "Wound dressing".
  String get shortLabel => ClinicPurposes.byId(serviceId)?.short ?? label;

  /// How far through this service's slides the nurse is, as `2 / 3`.
  String get slidePosition =>
      '${(slide + 1).clamp(1, spec.slides.length)} / ${spec.slides.length}';

  bool get isLastSlide => slide >= spec.slides.length - 1;

  ServiceSlide get currentSlide =>
      spec.slides[slide.clamp(0, spec.slides.length - 1)];

  /// Marks the service as touched the first time anything is written to it, then
  /// re-derives the status from the answers as they stand.
  ///
  /// This used to stop at "something was written, so In Progress", which meant a
  /// form the nurse had already filled in completely still showed In Progress
  /// until they happened to press Save & Continue — the status pill in the
  /// service list disagreed with the form on screen. Recomputing here is what
  /// makes the pill honest: the answers are the truth, and the status is read off
  /// them rather than remembered from the last button pressed.
  void _touch() {
    dirty = true;
    refreshStatus();
  }

  void set(String key, Object? value) {
    // Normalise to a plain string / list-of-strings before comparing, so
    // re-selecting the same dropdown option, or a rebuild handing back the same
    // value, does not mark a pristine form as In Progress.
    final existing = data[key];
    final unchanged = switch (value) {
      List() => existing is List && existing.join(' ') == value.join(' '),
      null => existing == null,
      _ => '$existing' == '$value' && '$value'.trim().isNotEmpty,
    };
    if (unchanged) return;
    data[key] = value;
    _touch();
  }

  String text(String key) => '${data[key] ?? ''}';

  List<String> chosen(String key) => (data[key] is List)
      ? (data[key] as List).map((e) => '$e').toList()
      : const [];

  bool isChosen(String key, String option) => chosen(key).contains(option);

  /// Required keys of the slide currently on screen, for [VisitDetails.validateSlide].
  ///
  /// Only the ones that are on screen: a box waiting on a Yes that was never
  /// ticked is not on the slide to be filled in, so it must not be able to hold
  /// the nurse there.
  List<String> get currentSlideRequired {
    final slide = currentSlide;
    return [
      ...slide.fields
          .where((f) => f.required && f.isShownIn(data))
          .map((f) => f.key),
      ...?slide.custom?.requiredKeys,
    ];
  }

  /// The keys still missing from the current slide. Empty means Next is allowed.
  ///
  /// A key counts as missing when it is empty OR when what is in it fails the
  /// field's own rules — a systolic of 9999 is present, and it is still not a
  /// reading, so it has to keep Next disabled rather than being waved through.
  List<String> missingOnCurrentSlide() {
    final missing = <String>[];
    for (final key in currentSlideRequired) {
      if (key == 'medicine_name') {
        if (medicines.isEmpty) missing.add(key);
        continue;
      }
      final v = data[key];
      final empty = v == null ||
          (v is String && v.trim().isEmpty) ||
          (v is List && v.isEmpty);
      if (empty) {
        missing.add(key);
        continue;
      }
      if (validationError(key) != null) missing.add(key);
    }
    return missing;
  }

  /// What is wrong with [key]'s answer right now, or null when it is fine.
  String? validationError(String key) => spec.validate(key, data[key]);

  /// Whether the slide on screen is good enough to move on from.
  bool get canAdvance => missingOnCurrentSlide().isEmpty;

  /// Whether this service is finished. A required field is the test; a service
  /// with no required fields just has to have anything in it at all.
  ///
  /// A service whose form is deliberately blank (see [kBlankFormServiceIds]) is
  /// finished from the start, because it asks nothing and so owes nothing.
  /// Without this it could never be completed: there is no box to fill, and the
  /// wizard's Continue is only clickable once every service is done — so a
  /// visit carrying a certificate would be stuck on this step forever.
  bool get isComplete =>
      kBlankFormServiceIds.contains(serviceId) ||
      status == ServiceDraftStatus.completed;

  /// Recomputes the status from the answers, so a pill can never claim
  /// "Completed" for a form whose required field has been cleared again.
  void refreshStatus() {
    if (medicines.isNotEmpty) {
      // A prescription is only finished when every row is — one row with no
      // dosage keeps the whole service In Progress.
      status = medicines.every((m) => m.isComplete)
          ? ServiceDraftStatus.completed
          : ServiceDraftStatus.inProgress;
      return;
    }
    final answered = spec.isAnswered(data);
    final anything = data.entries.any((e) => '${e.value}'.trim().isNotEmpty);
    status = answered
        ? ServiceDraftStatus.completed
        : (anything
            ? ServiceDraftStatus.inProgress
            : ServiceDraftStatus.notStarted);
  }

  /// The whole draft, for `visit_services.data`.
  Map<String, dynamic> toJson() => {
        ...data,
      };

  void loadFromJson(Map<String, dynamic> json) {
    for (final e in json.entries) {
      data[e.key] = e.value;
    }
    if (data.isNotEmpty) status = ServiceDraftStatus.inProgress;
  }
}

/// The whole of step 3's state.
class VisitDetailsController extends ChangeNotifier {
  /// [serviceIds] in clinical order — the fixed flow a nurse works through a
  /// visit in — which is what the left-hand list shows and what Save & Continue
  /// follows. Saving step 2 preserves the order the services were ticked in;
  /// this is where that order becomes the working order.
  VisitDetailsController({
    required List<String> serviceIds,
    Map<String, String> otherNames = const {},
    String staffName = '',
  }) : this._(
          _prepare(serviceIds),
          Map<String, String>.of(otherNames),
          staffName,
        );

  VisitDetailsController._(
    this._order,
    this._otherNames,
    this.staffName,
  ) : _drafts = [
          for (final id in _order)
            _seeded(id, _otherNames[id] ?? '', staffName),
        ];

  /// A new draft, with its "who did this" boxes already carrying the signed-in
  /// name.
  ///
  /// Written straight into [ServiceDraft.data] rather than through
  /// [ServiceDraft.set] on purpose: the nurse did not type it, so it must not
  /// make the service look changed or half-finished. A box that arrived filled
  /// in and read as work in progress was the reason the counsellor field was
  /// dropped once already.
  static ServiceDraft _seeded(String id, String otherName, String staff) {
    final d = ServiceDraft(serviceId: id, otherName: otherName);
    final who = staff.trim();
    if (who.isEmpty) return d;
    for (final slide in d.spec.slides) {
      for (final f in slide.fields) {
        if (f.kind == ServiceFieldKind.staffName &&
            '${d.data[f.key] ?? ''}'.trim().isEmpty) {
          d.data[f.key] = who;
        }
      }
    }
    return d;
  }

  /// Trims, drops blanks, removes repeats, then sorts into the clinic's working
  /// order. Step 2 can produce a duplicate if a purpose is tapped twice, and two
  /// rows for one service would mean two saved records for one visit. The sort
  /// turns step 2's tick order into the nurses' flow — the consultation first,
  /// Vital Signs last — so the left-hand list and Save & Continue walk the visit
  /// the way the clinic does.
  static List<String> _prepare(List<String> ids) {
    final out = <String>[];
    for (final id in ids) {
      final t = id.trim();
      if (t.isNotEmpty && !out.contains(t)) out.add(t);
    }
    return ClinicPurposes.inClinicalOrder(out);
  }

  /// One draft per chosen service, in the order they were chosen. Public because
  /// the left-hand service list renders straight off it.
  final List<ServiceDraft> _drafts;

  /// Growable, because "+ Add New Service" appends to it while the visit is
  /// open. Read through [drafts], which is unmodifiable, so nothing outside can
  /// reorder or remove.
  final List<String> _order;

  final Map<String, String> _otherNames;

  /// The signed-in staff member, used to pre-fill "Counsellor" and
  /// "Attending" so a nurse who is both does not have to type their own name.
  final String staffName;

  /// The visit's single vitals record. Every form that owns a reading writes
  /// here; every form that does not, reads it.
  final VisitVitals vitals = VisitVitals();

  String? _activeId;

  /// The service the nurse is looking at. Falls back to the first service so
  /// the screen is never showing "nothing selected" when step 2 clearly chose
  /// something, and null only when step 2 chose nothing at all.
  ServiceDraft? get active =>
      draftFor(_activeId) ?? (_drafts.isEmpty ? null : _drafts.first);

  /// The name typed against "Other", for the drawer and the certificates.
  String otherNameFor(String serviceId) => _otherNames[serviceId] ?? '';

  String? get activeId => _activeId;

  List<ServiceDraft> get drafts => List<ServiceDraft>.unmodifiable(_drafts);

  int get total => _drafts.length;

  int get completedCount =>
      _drafts.where((d) => d.status == ServiceDraftStatus.completed).length;

  int get inProgressCount =>
      _drafts.where((d) => d.status == ServiceDraftStatus.inProgress).length;

  int get notStartedCount => total - completedCount - inProgressCount;

  /// "2 of 3 services complete" for the header.
  String get progressLabel => '$completedCount of $total service'
      '${total == 1 ? '' : 's'} complete';

  /// Every selected service is finished.
  bool get isEverythingComplete =>
      _drafts.isNotEmpty && _drafts.every((d) => d.isComplete);

  /// Which of the chosen services owns the visit's vitals, or null when none
  /// does. A nurse who ticked Medical Consultation but not BP Taking has no
  /// owner, and the read-only strip then says so instead of pointing at a
  /// service that is not on the list.
  String? get vitalsOwnerId {
    for (final id in const ['bp_tracking', 'temperature_checking', 'bpi']) {
      if (_order.contains(id)) return id;
    }
    return null;
  }

  ServiceDraft? draftFor(String? serviceId) {
    if (serviceId == null) return null;
    for (final d in _drafts) {
      if (d.serviceId == serviceId) return d;
    }
    return null;
  }

  bool has(String serviceId) => _order.contains(serviceId);

  /// Appends a service to a visit that is already open, which is what the "+ Add
  /// New Service" row on step 3 is for: a visitor turns up needing something the
  /// nurse did not tick on step 2, and making her walk back to change the list
  /// would mean redoing the whole visit.
  ///
  /// Returns false when the visit already has that service, so a double tap on
  /// the sheet cannot produce two rows - and two saved records - for one visit.
  ///
  /// [activate] is false when the wizard is catching the controller up with a
  /// selection that grew on step 2: the service joins the visit, but the nurse
  /// is left on whatever she was recording.
  bool addService(String serviceId,
      {String otherName = '', bool activate = true}) {
    final id = serviceId.trim();
    if (id.isEmpty || _order.contains(id)) return false;
    // Dropped into the clinic's working order rather than appended to the end,
    // so a service added mid-visit lands where the nurse would expect it in the
    // flow — a Vital Signs check added at the end really is last.
    final sorted = ClinicPurposes.inClinicalOrder([..._order, id]);
    final at = sorted.indexOf(id);
    _order.insert(at, id);
    final name = otherName.trim();
    if (name.isNotEmpty) _otherNames[id] = name;
    _drafts.insert(at, _seeded(id, name, staffName));
    if (activate) _activeId = id;
    notifyListeners();
    return true;
  }

  /// Whether a service has unsaved changes. The footer uses this to decide
  /// whether Save & Continue is worth offering.
  bool get dirty => _drafts.any((d) => d.dirty);

  bool dirtyOf(String serviceId) => draftFor(serviceId)?.dirty ?? false;

  /// Takes a service back off the visit.
  ///
  /// Step 3 can add a service, so it has to be able to take one off again
  /// without sending the nurse back to step 2 to do it: she realises on slide 3
  /// that the visitor does not need the physiotherapy after all, and the fix is
  /// one tap away rather than a walk backwards through the wizard.
  ///
  /// The draft goes with it — a service that is not on the visit must not keep
  /// answers that would be saved into its `visit_services` row — and so do the
  /// readings that service owned, so a later service on the same visit is not
  /// silently credited with somebody else's blood pressure.
  ///
  /// The active service moves to the next one in the list, or the one before it
  /// when the last was removed, so the form is never left pointing at nothing.
  /// Returns false when the visit does not have that service.
  bool removeService(String serviceId) {
    final i = _order.indexOf(serviceId);
    if (i < 0) return false;

    // Anything the removed form was the only way to enter goes with it.
    final owned = <VitalField>{
      for (final s
          in (draftFor(serviceId)?.spec.slides ?? const <ServiceSlide>[]))
        for (final f in s.fields)
          if (f.vital != null) f.vital!,
    };
    if (owned.isNotEmpty) {
      // Only give a reading back if no *other* service on the visit still asks
      // for it — the readings belong to the visit, not to one form.
      final stillWanted = <VitalField>{
        for (final d in _drafts)
          if (d.serviceId != serviceId)
            for (final s in d.spec.slides)
              for (final f in s.fields)
                if (f.vital != null) f.vital!,
      };
      for (final v in owned) {
        if (stillWanted.contains(v)) continue;
        setVital(v, null);
      }
    }

    _order.removeAt(i);
    _drafts.removeWhere((d) => d.serviceId == serviceId);
    _otherNames.remove(serviceId);

    if (_activeId == serviceId) {
      _activeId = _order.isEmpty ? null : _order[i.clamp(0, _order.length - 1)];
    }
    notifyListeners();
    return true;
  }

  /// Throws away everything typed into one service and puts it back to Not
  /// Started, as if it had just been added.
  ///
  /// The answer to "I ticked the wrong box and filled the form in" that does not
  /// involve removing the service and adding it again. Readings that the
  /// *visit* keeps are left alone unless this form was the only way to enter
  /// them, because a blood pressure belongs to the visitor, not to the form.
  bool clearService(String serviceId) {
    final d = draftFor(serviceId);
    if (d == null) return false;

    final owned = <VitalField>{
      for (final s in d.spec.slides)
        for (final f in s.fields)
          if (f.vital != null) f.vital!,
    };
    final stillWanted = <VitalField>{
      for (final o in _drafts)
        if (o.serviceId != serviceId)
          for (final s in o.spec.slides)
            for (final f in s.fields)
              if (f.vital != null) f.vital!,
    };

    // Give the readings back first. [setVital] mirrors a null reading into this
    // draft's own data as `key: null`, so clearing the data first would only be
    // undone by the next line — and a draft whose data still holds a key, even a
    // null one, never reads as empty again.
    for (final v in owned) {
      if (stillWanted.contains(v)) continue;
      setVital(v, null);
    }

    d.data.clear();
    d.medicines.clear();
    d.slide = 0;
    d.dirty = false;
    d.status = ServiceDraftStatus.notStarted;
    _otherNames.remove(serviceId);
    d.otherName = '';

    notifyListeners();
    return true;
  }

  // ── NAVIGATION ──────────────────────────────────────────────────────────

  /// Opens a service. [slide] is honoured so the drawer and the left-hand list
  /// can both send the nurse to the slide that needs attention.
  void open(String serviceId, {int? slide}) {
    final d = draftFor(serviceId);
    if (d == null) return;
    _activeId = serviceId;
    if (slide != null) {
      d.slide = slide.clamp(0, d.spec.slides.length - 1);
    }
    notifyListeners();
  }

  void goToSlide(int slide) {
    final d = active;
    if (d == null) return;
    if (slide < 0 || slide >= d.spec.slides.length) return;
    d.slide = slide;
    notifyListeners();
  }

  /// Next slide of the active service. Returns false — and changes nothing —
  /// when the current slide is not finished, so a half-filled slide cannot be
  /// left behind by a hurried Next.
  bool nextSlide() {
    final d = active;
    if (d == null || d.isLastSlide) return false;
    if (d.missingOnCurrentSlide().isNotEmpty) return false;
    d.slide += 1;
    notifyListeners();
    return true;
  }

  /// Previous slide, or the previous service when already on the first slide.
  /// Going back never validates: being able to fix a field on slide 1 from
  /// slide 2 is the whole point of Prev.
  void previousSlideOrService() {
    final d = active;
    if (d == null) return;
    if (d.slide > 0) {
      d.slide -= 1;
      notifyListeners();
      return;
    }
    final i = _drafts.indexOf(d);
    if (i > 0) open(_drafts[i - 1].serviceId);
  }

  /// The service Save & Continue should move to: the first one after the active
  /// service that is not yet complete, wrapping once so a nurse who finished
  /// the last service lands back on the first unfinished one rather than
  /// nowhere. Null when everything is complete, which is the only time the
  /// wizard may advance to step 4.
  String? nextIncompleteAfter(String serviceId) {
    final start = _drafts.indexWhere((d) => d.serviceId == serviceId);
    if (start < 0) return _firstIncomplete();
    for (var i = start + 1; i < _drafts.length; i++) {
      if (!_drafts[i].isComplete) return _drafts[i].serviceId;
    }
    for (var i = 0; i < start; i++) {
      if (!_drafts[i].isComplete) return _drafts[i].serviceId;
    }
    return null;
  }

  String? _firstIncomplete() {
    for (final d in _drafts) {
      if (!d.isComplete) return d.serviceId;
    }
    return null;
  }

  /// Save & Continue: marks the active service complete when it can be, then
  /// opens the next unfinished service. Returns false when the active service is
  /// not finished, which is the footer's only reason to stay put.
  bool saveAndContinue() {
    final d = active;
    if (d == null) return false;
    d.refreshStatus();
    if (!d.isComplete) return false;
    d.dirty = false;
    final next = nextIncompleteAfter(d.serviceId);
    if (next == null) {
      notifyListeners();
      return true; // everything done — the caller may go to step 4
    }
    final target = draftFor(next)!;
    target.slide = _firstUnfinishedSlideOf(target);
    _activeId = next;
    notifyListeners();
    return true;
  }

  /// The first slide of [d] with a required field still empty, so a service
  /// reopened from the list lands on what needs doing rather than at the top.
  int _firstUnfinishedSlideOf(ServiceDraft d) {
    for (var i = 0; i < d.spec.slides.length; i++) {
      final saved = d.slide;
      d.slide = i;
      final missing = d.missingOnCurrentSlide();
      d.slide = saved;
      if (missing.isNotEmpty) return i;
    }
    // Nothing left to do: the service is already answered, so the top of the form
    // is as good a place to land as any.
    return 0;
  }

  // ── FIELDS ──────────────────────────────────────────────────────────────

  void setField(String serviceId, String key, Object? value) {
    draftFor(serviceId)?.set(key, value);
    notifyListeners();
  }

  /// Ticks or unticks a chip. [max] of 0 means "any number of them"; anything
  /// else makes the group a radio group that lets go of the previous answer
  /// before taking the new one.
  void toggleChoice(String serviceId, String key, String option,
      {int max = 0}) {
    final d = draftFor(serviceId);
    if (d == null) return;
    final current = List<String>.from(d.chosen(key));
    if (max > 0) {
      d.set(key, [option]);
    } else if (current.contains(option)) {
      current.remove(option);
      d.set(key, current);
    } else {
      current.add(option);
      d.set(key, current);
    }
    notifyListeners();
  }

  // ── VITALS ──────────────────────────────────────────────────────────────

  /// Writes a reading that belongs to the VISIT, not to one form. The value
  /// lands in [vitals] — where every other form reads it — and is mirrored into
  /// the data of every service whose form declares the field, so each saved
  /// `visit_services` row still explains where the number came from.
  ///
  /// [fromServiceId] is the service the nurse was actually typing or taking the
  /// reading in. Only that service becomes "in progress" — a mirror landing in
  /// a completed neighbour's data must not knock its status back to half-done.
  void setVital(VitalField field, Object? raw, {String? fromServiceId}) {
    setVitalRaw(field, VitalsInterpreter.parse(raw),
        fromServiceId: fromServiceId);
  }

  /// [setVital] for a value that has already been worked out.
  ///
  /// The BP form needs this: with three repeat readings the visit's systolic is
  /// their average, which is a number no box ever contained. Parsing text here
  /// would be a round trip through a string to arrive back at an int, and it
  /// would also mirror the average into the service's own `systolic` field as a
  /// double, so the saved row would stop matching what the nurse typed.
  void setVitalRaw(VitalField field, num? n, {String? fromServiceId}) {
    switch (field) {
      case VitalField.systolic:
        vitals.systolic = n?.round();
      case VitalField.diastolic:
        vitals.diastolic = n?.round();
      case VitalField.heartRate:
        vitals.heartRate = n?.round();
      case VitalField.respRate:
        vitals.respRate = n?.round();
      case VitalField.temperature:
        vitals.tempC = n?.toDouble();
      case VitalField.o2Sat:
        vitals.o2Sat = n?.round();
      case VitalField.heightCm:
        vitals.heightCm = n?.toDouble();
      case VitalField.weightKg:
        vitals.weightKg = n?.toDouble();
    }
    // The mirror is a copy of the same number into every form that declares the
    // field — each under its OWN key, because BP Taking calls it `pulse_bpm`
    // while the vitals record calls it `heart_rate`. Written as an INT for the
    // integer readings: a form that reads its own field back must see "95", not
    // "95.0" — a box that strips the non-digits out of that gets 950, a reading
    // nobody took.
    final isDecimal = field == VitalField.temperature ||
        field == VitalField.heightCm ||
        field == VitalField.weightKg;
    for (final d in _drafts) {
      for (final slide in d.spec.slides) {
        for (final f in slide.fields) {
          if (f.vital == field) {
            d.data[f.key] = isDecimal ? n?.toDouble() : n?.round();
          }
        }
      }
    }
    // Any reading present re-bands the whole record, so clearing a temperature
    // cannot leave "Fever" behind in the interpretations.
    _recaptureBands();
    final source = fromServiceId == null ? null : draftFor(fromServiceId);
    if (source != null &&
        source.data.isNotEmpty &&
        source.status != ServiceDraftStatus.completed) {
      source.status = ServiceDraftStatus.inProgress;
    }
    notifyListeners();
  }

  /// Refreshes [VisitVitals.interpretations] from the current readings without
  /// going through a set, so a form that edits the strip never has to lie about
  /// which service owns the value.
  void _recaptureBands() {
    vitals.interpretations.clear();
    for (final r in vitals.readings) {
      vitals.interpretations[r.key] = r.category ?? r.band.label;
    }
  }

  /// The sentence the Notes box is seeded with, for the service that has
  /// readings. Empty when nothing has been taken, so the box is not pre-filled
  /// with a stray comma.
  String notesSuggestion() => vitals.notesSuggestion;

  /// Whether a Notes box has already been touched, so a suggestion is never
  /// re-applied over what the nurse wrote.
  bool notesWereEdited(String serviceId) {
    final d = draftFor(serviceId);
    return d == null || d.text('notes').trim().isNotEmpty;
  }

  void seedNotesIfEmpty(String serviceId) {
    final d = draftFor(serviceId);
    if (d == null || notesWereEdited(serviceId)) return;
    final s = notesSuggestion();
    if (s.isEmpty) return;
    d.data['notes'] = s;
  }

  // ── MEDICINES ───────────────────────────────────────────────────────────

  void addMedicine(Medicine m, {String unit = ''}) {
    final d = draftFor('medication');
    if (d == null) return;
    final existing = d.medicines.where((x) => x.medicineId == m.id).toList();
    if (existing.isNotEmpty) {
      // Picking the same medicine twice bumps the quantity rather than adding
      // a second row that would print twice.
      existing.first.quantity = (existing.first.quantity ?? 0) + 1;
    } else {
      d.medicines.add(MedicineDose(
        medicineId: m.id,
        name: m.name,
        unit: unit,
        stockAtPick: m.stock,
        quantity: 1,
      ));
    }
    d.status = ServiceDraftStatus.inProgress;
    d.dirty = true;
    notifyListeners();
  }

  void removeMedicine(int index) {
    final d = draftFor('medication');
    if (d == null || index < 0 || index >= d.medicines.length) return;
    d.medicines.removeAt(index);
    d.dirty = true;
    notifyListeners();
  }

  /// Whether [medicine] can be picked right now: it has to exist, not be
  /// archived, and have stock. The picker greys the rest out rather than
  /// hiding them, so a nurse can see a medicine is missing rather than find
  /// their search simply empty.
  static bool canPick(Medicine m) => !m.isArchived && m.stock > 0;

  // ── SAVING ──────────────────────────────────────────────────────────────

  /// Clears the dirty flags once the service layer has confirmed the write.
  void markSaved([String? serviceId]) {
    for (final d in _drafts) {
      if (serviceId == null || d.serviceId == serviceId) d.dirty = false;
    }
    notifyListeners();
  }

  /// Replaces the in-memory drafts with what is on the server, for a visit that
  /// is being resumed rather than started. Keeps the vitals in step.
  void hydrate({
    required Map<String, Map<String, dynamic>> serviceData,
    Map<String, int>? slideIndexes,
    VisitVitals? visitVitals,
    List<MedicineDose>? restoredMedicines,
  }) {
    for (final d in _drafts) {
      final data = serviceData[d.serviceId];
      if (data == null) continue;
      d.loadFromJson(data);
      d.refreshStatus();
      final idx = slideIndexes?[d.serviceId];
      if (idx != null) d.slide = idx.clamp(0, d.spec.slides.length - 1);
    }
    if (restoredMedicines != null) {
      final med = draftFor('medication');
      if (med != null) {
        med.medicines
          ..clear()
          ..addAll(restoredMedicines);
      }
    }
    if (visitVitals != null) {
      vitals.systolic = visitVitals.systolic;
      vitals.diastolic = visitVitals.diastolic;
      vitals.heartRate = visitVitals.heartRate;
      vitals.respRate = visitVitals.respRate;
      vitals.tempC = visitVitals.tempC;
      vitals.o2Sat = visitVitals.o2Sat;
      vitals.heightCm = visitVitals.heightCm;
      vitals.weightKg = visitVitals.weightKg;
      vitals.interpretations.addAll(visitVitals.interpretations);
    }
    _recaptureBands();
    final first = _firstIncomplete() ?? (active?.serviceId);
    if (first != null) _activeId = first;
    notifyListeners();
  }

  /// A note for a service about anything that needs attention before the visit
  /// can be completed — an overdraw on a prescription, a vital that needs
  /// referring. Shown in the footer area so it is visible without scrolling.
  List<String> get outstanding {
    final notes = <String>[];
    for (final r in vitals.alerts) {
      notes.add('${r.label}: ${r.alert}');
    }
    final med = draftFor('medication');
    if (med != null) {
      for (final m in med.medicines) {
        final over = m.overdraw();
        if (over > 0) {
          notes.add('${m.name}: $over more than the inventory holds.');
        }
      }
    }
    return notes;
  }
}
