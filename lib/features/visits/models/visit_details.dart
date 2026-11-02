import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:clinicmanagementsystem/features/inventory/services/medicine_service.dart';
import 'package:clinicmanagementsystem/features/visits/models/clinic_purposes.dart';
import 'package:clinicmanagementsystem/features/visits/models/visit_service_forms.dart';
import 'package:clinicmanagementsystem/features/vitals/models/vitals.dart';

enum ServiceDraftStatus {
  notStarted('Not Started'),
  inProgress('In Progress'),
  completed('Completed');

  const ServiceDraftStatus(this.label);

  final String label;
}

class MedicineDose {
  MedicineDose({
    this.medicineId,
    this.name = '',
    this.quantity,
    this.frequency = '',
    this.action = 'Given',
    this.response = '',
    this.notes = '',
    this.reasonNotGiven = '',
    this.stockAtPick = 0,
  });

  final int? medicineId;
  String name;
  int? quantity;
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
      return medicineId != null && (quantity ?? 0) > 0;
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
        'quantity': quantity,
        'frequency': frequency,
        'action': action,
        'response': response,
        'notes': notes,
        'reason_not_given': reasonNotGiven,
      };

  factory MedicineDose.fromJson(Map<String, dynamic> j) => MedicineDose(
        medicineId: (j['medicine_id'] as num?)?.toInt(),
        name: '${j['name'] ?? ''}',
        quantity: (j['quantity'] as num?)?.toInt(),
        frequency: '${j['frequency'] ?? ''}',
        action: '${j['action'] ?? ''}',
        response: '${j['response'] ?? ''}',
        notes: '${j['notes'] ?? ''}',
        reasonNotGiven: '${j['reason_not_given'] ?? ''}',
        stockAtPick: (j['stock_at_pick'] as num?)?.toInt() ?? 0,
      );

  MedicineDose copy() => MedicineDose.fromJson(toJson());

  String get detail {
    final parts = <String>[];
    if ((quantity ?? 0) > 0) parts.add('Quantity: $quantity');
    final f = frequency.trim();
    if (f.isNotEmpty) parts.add('Frequency: $f');
    final a = action.trim();
    if (a.isNotEmpty && a != 'Given') {
      parts.add(a);
      final why = reasonNotGiven.trim();
      if (why.isNotEmpty) parts.add('Reason not given: $why');
    }
    final r = response.trim();
    if (r.isNotEmpty) parts.add('Response: $r');
    final n = notes.trim();
    if (n.isNotEmpty) parts.add('Notes: $n');
    return parts.join(' · ');
  }

  String get summary => detail.isEmpty ? name : '$name — $detail';
}

class ServiceDraft {
  ServiceDraft({required this.serviceId, this.otherName = ''})
      : spec = VisitServiceForms.forId(serviceId);

  final String serviceId;
  final ServiceFormSpec spec;

  String otherName;

  final Map<String, dynamic> data = {};

  final List<MedicineDose> medicines = [];

  ServiceDraftStatus status = ServiceDraftStatus.notStarted;

  int slide = 0;

  bool dirty = false;

  String get label {
    if (serviceId == VisitServiceForms.otherServiceId) {
      return otherName.trim().isEmpty ? 'Other' : otherName.trim();
    }
    return ClinicPurposes.byId(serviceId)?.label ?? 'Other';
  }

  String get shortLabel => ClinicPurposes.byId(serviceId)?.short ?? label;

  String get slidePosition =>
      '${(slide + 1).clamp(1, spec.slides.length)} / ${spec.slides.length}';

  bool get isLastSlide => slide >= spec.slides.length - 1;

  ServiceSlide get currentSlide =>
      spec.slides[slide.clamp(0, spec.slides.length - 1)];

  void _touch() {
    dirty = true;
    refreshStatus();
  }

  void set(String key, Object? value) {
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

  List<String> get currentSlideRequired {
    final slide = currentSlide;
    return [
      ...slide.fields.where((f) => f.isRequiredIn(data)).map((f) => f.key),
      ...?slide.custom?.requiredKeys,
    ];
  }

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

  String? validationError(String key) => spec.validateInContext(key, data);

  bool get canAdvance => missingOnCurrentSlide().isEmpty;

  bool get isComplete =>
      kBlankFormServiceIds.contains(serviceId) ||
      status == ServiceDraftStatus.completed;

  void refreshStatus() {
    final ownsPrescription =
        spec.requiredKeysIn(data).contains('medicine_name');
    if (ownsPrescription && medicines.isNotEmpty) {
      status = medicines.every((m) => m.isComplete)
          ? ServiceDraftStatus.completed
          : ServiceDraftStatus.inProgress;
      return;
    }
    final answered = spec.isAnswered(data);
        final anything = data.entries
        .any((e) => e.value != null && '${e.value}'.trim().isNotEmpty);
    status = answered
        ? ServiceDraftStatus.completed
        : (anything
            ? ServiceDraftStatus.inProgress
            : ServiceDraftStatus.notStarted);
  }

  Map<String, dynamic> toJson() => {
        ...data,
      };

  void loadFromJson(Map<String, dynamic> json) {
    for (final e in json.entries) {
      data[e.key] = e.value;
    }

    final storedMeds = data.remove('medications_used');
    if (storedMeds != null) {
      for (final row in _decodeMedicineRows(storedMeds)) {
        medicines.add(MedicineDose.fromJson(row));
      }
    }
    if (data.isNotEmpty || medicines.isNotEmpty) {
      status = ServiceDraftStatus.inProgress;
    }
  }

  static List<Map<String, dynamic>> _decodeMedicineRows(Object? value) {
    Object? raw = value;
    if (raw is String) {
      final s = raw.trim();
      if (s.isEmpty) return const [];
      try {
        raw = jsonDecode(s);
      } catch (_) {
        return const [];
      }
    }
    if (raw is! List) return const [];
    return [
      for (final e in raw)
        if (e is Map) e.cast<String, dynamic>(),
    ];
  }
}

class VisitDetailsController extends ChangeNotifier {
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

  static ServiceDraft _seeded(String id, String otherName, String staff) {
    final d = ServiceDraft(serviceId: id, otherName: otherName);
    final who = staff.trim();

    for (final slide in d.spec.slides) {
      for (final f in slide.fields) {
        if (f.kind == ServiceFieldKind.readOnly && f.key == 'session_date') {
          d.data[f.key] = DateTime.now().toIso8601String();
        }
      }
    }
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

  static List<String> _prepare(List<String> ids) {
    final out = <String>[];
    for (final id in ids) {
      final t = id.trim();
      if (t.isNotEmpty && !out.contains(t)) out.add(t);
    }
    return ClinicPurposes.inClinicalOrder(out);
  }

  final List<ServiceDraft> _drafts;

  final List<String> _order;

  final Map<String, String> _otherNames;

  final String staffName;

  final VisitVitals vitals = VisitVitals();

  String? _activeId;

  ServiceDraft? get active =>
      draftFor(_activeId) ?? (_drafts.isEmpty ? null : _drafts.first);

  String otherNameFor(String serviceId) => _otherNames[serviceId] ?? '';

  String? get activeId => _activeId;

  List<ServiceDraft> get drafts => List<ServiceDraft>.unmodifiable(_drafts);

  int get total => _drafts.length;

  int get completedCount =>
      _drafts.where((d) => d.status == ServiceDraftStatus.completed).length;

  int get inProgressCount =>
      _drafts.where((d) => d.status == ServiceDraftStatus.inProgress).length;

  int get notStartedCount => total - completedCount - inProgressCount;

  String get progressLabel => '$completedCount of $total service'
      '${total == 1 ? '' : 's'} complete';

  bool get isEverythingComplete =>
      _drafts.isNotEmpty && _drafts.every((d) => d.isComplete);

  String? get vitalsOwnerId {
    for (final id in const ['vital_signs', 'bpi']) {
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

  bool addService(String serviceId,
      {String otherName = '', bool activate = true, bool notify = true}) {
    final id = serviceId.trim();
    if (id.isEmpty || _order.contains(id)) return false;

    final sorted = ClinicPurposes.inClinicalOrder([..._order, id]);
    final at = sorted.indexOf(id);
    _order.insert(at, id);
    final name = otherName.trim();
    if (name.isNotEmpty) _otherNames[id] = name;
    final draft = _seeded(id, name, staffName);
    _mirrorVitalsInto(draft);
    _drafts.insert(at, draft);
    if (activate) _activeId = id;
    if (notify) notifyListeners();
    return true;
  }

  bool get dirty => _drafts.any((d) => d.dirty);

  bool dirtyOf(String serviceId) => draftFor(serviceId)?.dirty ?? false;

  bool removeService(String serviceId) {
    final i = _order.indexOf(serviceId);
    if (i < 0) return false;

    final owned = <VitalField>{
      for (final s
          in (draftFor(serviceId)?.spec.slides ?? const <ServiceSlide>[]))
        for (final f in s.fields)
          if (f.vital != null) f.vital!,
    };
    if (owned.isNotEmpty) {
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

  bool nextSlide() {
    final d = active;
    if (d == null || d.isLastSlide) return false;
    if (d.missingOnCurrentSlide().isNotEmpty) return false;
    d.slide += 1;
    notifyListeners();
    return true;
  }

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

  bool saveAndContinue() {
    final d = active;
    if (d == null) return false;
    d.refreshStatus();
    if (!d.isComplete) return false;
    d.dirty = false;
    final next = nextIncompleteAfter(d.serviceId);
    if (next == null) {
      notifyListeners();
      return true;
    }
    final target = draftFor(next)!;
    target.slide = _firstUnfinishedSlideOf(target);
    _activeId = next;
    notifyListeners();
    return true;
  }

  int _firstUnfinishedSlideOf(ServiceDraft d) {
    for (var i = 0; i < d.spec.slides.length; i++) {
      final saved = d.slide;
      d.slide = i;
      final missing = d.missingOnCurrentSlide();
      d.slide = saved;
      if (missing.isNotEmpty) return i;
    }

    return 0;
  }

  void setField(String serviceId, String key, Object? value) {
    final d = draftFor(serviceId);
    if (d == null) return;
    d.set(key, value);
    _clearHiddenAnswers(d);
    notifyListeners();
  }

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
    _clearHiddenAnswers(d);
    notifyListeners();
  }

  void _clearHiddenAnswers(ServiceDraft d) {
    if (d.serviceId == 'first_aid_treatment' ||
        d.serviceId == 'medicine_consultation') {
      var removedAny = false;
      for (final f in d.spec.fields) {
        if (f.isShownIn(d.data)) continue;
        if (d.data.remove(f.key) == null) continue;
        d.data.remove('${f.key}_other');
        removedAny = true;
      }
      if (removedAny) d.refreshStatus();
      return;
    }
    return;
  }

    /// Applies the vital-sign tick-boxes. Unticked vitals are cleared to null.
  void setVitalSelection(String serviceId, Iterable<String> requested) {
    final d = draftFor(serviceId);
    if (d == null) return;

    final chosen = <String>{
      for (final c in requested)
        if (kVitalChoiceKeys.containsKey(c)) c,
    };

    for (final entry in kVitalChoiceKeys.entries) {
      if (chosen.contains(entry.key)) continue;
      for (final f in kVitalChoiceFields[entry.key] ?? const <VitalField>[]) {
        setVitalRaw(f, null);
      }
      for (final k in entry.value) {
        d.data.remove(k);
      }
    }

    final all = chosen.length == kVitalChoiceKeys.length;
    d.set(kVitalsSelectedKey, [
      if (all) kSelectAllLabel,
      ...kVitalChoices.where(chosen.contains),
    ]);
    d.refreshStatus();
    notifyListeners();
  }

  void setVital(VitalField field, Object? raw, {String? fromServiceId}) {
    setVitalRaw(field, VitalsInterpreter.parse(raw),
        fromServiceId: fromServiceId);
  }

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

    vitals.measuredAt = DateTime.now();

    final column = field.column;
    if (n == null) {
      vitals.enteredBy.remove(column);
    } else if (fromServiceId != null) {
      vitals.enteredBy[column] = fromServiceId;
    }

    _recaptureBands();
    final source = fromServiceId == null ? null : draftFor(fromServiceId);
    if (source != null &&
        source.data.isNotEmpty &&
        source.status != ServiceDraftStatus.completed) {
      source.status = ServiceDraftStatus.inProgress;
    }
    notifyListeners();
  }

  void _recaptureBands() {
    vitals.interpretations.clear();
    for (final r in vitals.readings) {
      vitals.interpretations[r.key] = r.category ?? r.band.label;
    }
  }

  num? _vitalValue(VitalField v) => switch (v) {
        VitalField.systolic => vitals.systolic,
        VitalField.diastolic => vitals.diastolic,
        VitalField.heartRate => vitals.heartRate,
        VitalField.respRate => vitals.respRate,
        VitalField.temperature => vitals.tempC,
        VitalField.o2Sat => vitals.o2Sat,
        VitalField.heightCm => vitals.heightCm,
        VitalField.weightKg => vitals.weightKg,
      };

  void _mirrorVitalsInto(ServiceDraft d) {
    const decimal = <VitalField>{
      VitalField.temperature,
      VitalField.heightCm,
      VitalField.weightKg,
    };
    for (final slide in d.spec.slides) {
      for (final f in slide.fields) {
        final v = f.vital;
        if (v == null) continue;
        final n = _vitalValue(v);
        d.data[f.key] = decimal.contains(v) ? n?.toDouble() : n?.round();
      }
    }
  }

  String notesSuggestion() => vitals.notesSuggestion;

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

  void addMedicine(ServiceDraft d, Medicine m) {
    final existing = d.medicines.where((x) => x.medicineId == m.id).toList();
    if (existing.isNotEmpty) {
      existing.first.quantity = (existing.first.quantity ?? 0) + 1;
    } else {
      d.medicines.add(MedicineDose(
        medicineId: m.id,
        name: m.name,
        stockAtPick: m.stock,
        quantity: 1,
      ));
    }
    d.status = ServiceDraftStatus.inProgress;
    d.dirty = true;
    notifyListeners();
  }

  void removeMedicine(ServiceDraft d, int index) {
    if (index < 0 || index >= d.medicines.length) return;
    d.medicines.removeAt(index);
    d.dirty = true;
    notifyListeners();
  }

  static bool canPick(Medicine m) => !m.isArchived && m.stock > 0;

  void markSaved([String? serviceId]) {
    for (final d in _drafts) {
      if (serviceId == null || d.serviceId == serviceId) d.dirty = false;
    }
    notifyListeners();
  }

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
