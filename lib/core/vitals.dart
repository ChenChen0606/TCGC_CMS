// ─────────────────────────────────────────────────────────────────────────────
//  vitals.dart
//  The clinic's screening bands for the readings it takes, and the record those
//  readings are stored in.
//
//  WHY THE THRESHOLDS LIVE HERE AND NOT IN A WIDGET
//  Step 3 shows an interpretation pill next to every field as the nurse types.
//  If the numbers that decide the pill's colour sat in the field widget, the
//  clinic could only retune a band by shipping a new build. They are here
//  instead — one class, one table of bands, and [VitalsThresholds] can be
//  replaced at runtime from `public.vitals_config` (see
//  lib/services/visit_details_service.dart) without touching any component.
//
//  WHAT THESE ARE NOT
//  Every band here is a screening aid for clinic reference only, and the UI
//  says so next to the pills. A pill is not a diagnosis and nothing in this
//  file decides what treatment a visitor receives.
// ─────────────────────────────────────────────────────────────────────────────

import 'vitals_bands.dart';
import 'vitals_interpretation.dart';

export 'vitals_bands.dart';

/// Every threshold the clinic uses, in one replaceable object.
///
/// [instance] is what the app reads, so the whole rulebook can be swapped in
/// one assignment (the migration seeds `public.vitals_config` with exactly
/// these numbers; the service layer pushes whatever it finds in the table).
///
/// Blood pressure is not in here. It has its own ladder in
/// `vitals_interpretation.dart`, because a BP verdict is a short-circuit rather
/// than a ceiling lookup — see that file for why.
class VitalsThresholds {
  VitalsThresholds({
    required this.heartRate,
    required this.respiratoryRate,
    required this.temperature,
    required this.o2Saturation,
    required this.bmi,
  });

  /// The bands as the clinic has them today. Changing a number here is a
  /// one-line change and nothing else in the app needs to know.
  static VitalsThresholds defaults() => VitalsThresholds(
        heartRate: const [
          VitalThresholdBand(
              max: 59, label: 'Bradycardia', band: VitalBand.watch),
          VitalThresholdBand(max: 100, label: 'Normal', band: VitalBand.normal),
          VitalThresholdBand(
              max: null,
              label: 'Tachycardia',
              band: VitalBand.high,
              alert: 'Re-check after the visitor has rested, and refer if it '
                  'does not settle.'),
        ],
        respiratoryRate: const [
          VitalThresholdBand(max: 11, label: 'Low', band: VitalBand.watch),
          VitalThresholdBand(max: 20, label: 'Normal', band: VitalBand.normal),
          VitalThresholdBand(
              max: null,
              label: 'High',
              band: VitalBand.high,
              alert: 'Assess breathing effort now and refer if in distress.'),
        ],
        temperature: const [
          VitalThresholdBand(max: 36.0, label: 'Low', band: VitalBand.watch),
          VitalThresholdBand(
              max: 37.2, label: 'Normal', band: VitalBand.normal),
          VitalThresholdBand(
              max: 38.0, label: 'Low-grade fever', band: VitalBand.watch),
          VitalThresholdBand(max: 39.4, label: 'Fever', band: VitalBand.high),
          VitalThresholdBand(
              max: null,
              label: 'High fever',
              band: VitalBand.critical,
              alert: 'Refer immediately — high fever.'),
        ],
        o2Saturation: const [
          VitalThresholdBand(
              max: 90,
              label: 'Low',
              band: VitalBand.critical,
              alert: 'Refer immediately — oxygen saturation critically low.'),
          VitalThresholdBand(max: 94, label: 'Mild low', band: VitalBand.high),
          VitalThresholdBand(
              max: null, label: 'Normal', band: VitalBand.normal),
        ],
        bmi: const [
          VitalThresholdBand(
              max: 18.4, label: 'Underweight', band: VitalBand.watch),
          VitalThresholdBand(
              max: 24.9, label: 'Normal', band: VitalBand.normal),
          VitalThresholdBand(
              max: 29.9, label: 'Overweight', band: VitalBand.watch),
          VitalThresholdBand(max: null, label: 'Obese', band: VitalBand.high),
        ],
      );

  final List<VitalThresholdBand> heartRate;
  final List<VitalThresholdBand> respiratoryRate;
  final List<VitalThresholdBand> temperature;
  final List<VitalThresholdBand> o2Saturation;
  final List<VitalThresholdBand> bmi;

  /// The rulebook the whole app reads. Replaced wholesale by
  /// `VisitDetailsService.loadThresholds()` when the clinic's table is
  /// available; the shipped defaults are used when it is not.
  static VitalsThresholds instance = VitalsThresholds.defaults();

  /// The `public.vitals_config.key` for each table in here. The service layer
  /// uses these to look a table up by name; the values are the table's keys
  /// rather than its column names so the two never drift.
  static const String keyHeartRate = 'heart_rate';
  static const String keyRespRate = 'resp_rate';
  static const String keyTemperature = 'temperature';
  static const String keyO2 = 'o2_sat';
  static const String keyBmi = 'bmi';

  /// Every table in this object, by its config key. Reading a threshold is
  /// therefore always a lookup by name, never a hard-wired field path.
  Map<String, List<VitalThresholdBand>> get byKey => {
        keyHeartRate: heartRate,
        keyRespRate: respiratoryRate,
        keyTemperature: temperature,
        keyO2: o2Saturation,
        keyBmi: bmi,
      };

  /// A copy with some tables replaced, leaving the rest at their current
  /// values. A key the overrides do not mention is never touched, so a clinic
  /// that has only edited the oxygen table does not lose its blood pressure
  /// bands.
  VitalsThresholds withTables(Map<String, List<VitalThresholdBand>> overrides) {
    final base = byKey;
    for (final e in overrides.entries) {
      if (e.value.isNotEmpty) base[e.key] = e.value;
    }
    return VitalsThresholds(
      heartRate: base[keyHeartRate]!,
      respiratoryRate: base[keyRespRate]!,
      temperature: base[keyTemperature]!,
      o2Saturation: base[keyO2]!,
      bmi: base[keyBmi]!,
    );
  }

  /// The first band whose `max` is >= [value]; the open-ended last band when
  /// [value] is above every ceiling.
  static VitalThresholdBand resolve(
    List<VitalThresholdBand> bands,
    num value,
  ) {
    for (final b in bands) {
      if (b.max == null || value <= b.max!) return b;
    }
    return bands.last;
  }

  /// The worse of two bands — "higher" meaning further from normal, which is
  /// what a blood pressure needs when its two numbers disagree.
  static VitalBand worst(VitalBand a, VitalBand b) =>
      a.index >= b.index ? a : b;
}

/// Turns a typed number into a [VitalReading] against the current thresholds.
class VitalsInterpreter {
  const VitalsInterpreter._();

  static VitalsThresholds get _t => VitalsThresholds.instance;

  /// Reads a number out of whatever a text field currently holds. Returns null
  /// for anything that is not a number, which is what makes an empty or
  /// half-typed field show no pill at all rather than a wrong one.
  static num? parse(Object? raw) {
    if (raw == null) return null;
    if (raw is num) return raw;
    final cleaned = '$raw'.replaceAll(RegExp(r'[^0-9.]'), '').trim();
    if (cleaned.isEmpty) return null;
    final parsed = double.tryParse(cleaned);
    if (parsed == null || !parsed.isFinite) return null;
    return parsed;
  }

  /// A pill-ready reading, or null when there is no number to band yet.
  static VitalReading? reading(
    String key,
    String label,
    Object? raw, {
    String unit = '',
  }) {
    final value = parse(raw);
    if (value == null) return null;
    return _banded(
      key: key,
      label: label,
      value: value,
      display: '${_trim(value)}$unit',
      bands: _bandsFor(key),
    );
  }

  /// Blood pressure is two numbers and one verdict, and the verdict comes from
  /// the named standard in `vitals_interpretation.dart` rather than from a
  /// threshold table: 180/70 is Severely High even though 70 is unremarkable,
  /// and the order the rules are checked in is part of the answer.
  ///
  /// This is a thin adapter. It exists so that every other screen — the vitals
  /// strip, a Prenatal form's read-only box, the certificate engine — says the
  /// same word the BP form said when the nurse took the reading.
  static VitalReading? bloodPressure(
    Object? systolic,
    Object? diastolic, {
    String unit = ' mmHg',
  }) {
    final r = interpretBP(systolic, diastolic);
    if (r == null) return null;
    return r.toVitalReading(unit: unit);
  }

  /// Body mass index from height in cm and weight in kg. Null unless both are
  /// plausible measurements, so a half-filled form shows no BMI at all instead
  /// of a number worked out from nothing.
  static double? bmiFrom({Object? heightCm, Object? weightKg}) {
    final h = parse(heightCm);
    final w = parse(weightKg);
    if (h == null || w == null) return null;
    if (h <= 0 || w <= 0) return null;
    final m = h / 100;
    return w / (m * m);
  }

  static VitalReading? bmi({Object? heightCm, Object? weightKg}) {
    final value = bmiFrom(heightCm: heightCm, weightKg: weightKg);
    if (value == null) return null;
    final b = VitalsThresholds.resolve(_t.bmi, value);
    return VitalReading(
      key: 'bmi',
      label: 'BMI',
      value: value,
      display: value.toStringAsFixed(1),
      band: b.band,
      unit: 'kg/m²',
      category: b.label,
      alert: b.alert,
    );
  }

  /// Where the BMI gauge should sit, as a 0..1 position along the printed
  /// scale, clamped to the ends so an extreme reading pins the needle rather
  /// than drawing outside the bar.
  static double bmiGaugePosition(double bmi) =>
      ((bmi - 12) / (40 - 12)).clamp(0.0, 1.0).toDouble();

  /// The four printed markers under the gauge: 15 (underweight), 18.5, 25, 30.
  static const List<double> bmiGaugeMarkers = [18.5, 25, 30];

  static VitalReading _banded({
    required String key,
    required String label,
    required num value,
    required String display,
    required List<VitalThresholdBand> bands,
  }) {
    final b = VitalsThresholds.resolve(bands, value);
    return VitalReading(
      key: key,
      label: label,
      value: value,
      display: display,
      band: b.band,
      category: b.label,
      alert: b.alert,
    );
  }

  static List<VitalThresholdBand> _bandsFor(String key) => switch (key) {
        'heart_rate' => _t.heartRate,
        'resp_rate' => _t.respiratoryRate,
        'temperature' => _t.temperature,
        'o2_sat' => _t.o2Saturation,
        'bmi' => _t.bmi,
        _ => const [
            VitalThresholdBand(max: null, label: '', band: VitalBand.normal)
          ],
      };

  /// Drops a trailing ".0" so 78 reads as "78" and 78.5 as "78.5".
  static String _trim(num v) {
    if (v is int) return '$v';
    final s = v.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }
}

/// The vitals of ONE visit, stored once (`public.visit_vitals`) and shown
/// read-only in every service form that needs them.
///
/// The whole point of this class existing: blood pressure taken for "BP Taking"
/// is not typed again in "Medical Consultation" or "Prenatal". The forms that
/// do not own a reading get [_without] — the same fields, greyed, with a link
/// back to the service that owns them.
class VisitVitals {
  VisitVitals({
    this.systolic,
    this.diastolic,
    this.heartRate,
    this.respRate,
    this.tempC,
    this.o2Sat,
    this.heightCm,
    this.weightKg,
  });

  int? systolic;
  int? diastolic;
  int? heartRate;
  int? respRate;
  double? tempC;
  int? o2Sat;
  double? heightCm;
  double? weightKg;

  /// Bands captured when the reading was taken, so a later threshold change
  /// cannot rewrite what the nurse saw on the day. `key -> "Normal"` style.
  final Map<String, String> interpretations = {};

  /// True when nothing at all has been recorded, which is what the strip says
  /// before the first service has been filled in.
  bool get isEmpty =>
      _n(systolic) == null &&
      _n(diastolic) == null &&
      _n(heartRate) == null &&
      _n(respRate) == null &&
      _n(tempC) == null &&
      _n(o2Sat) == null &&
      _n(heightCm) == null &&
      _n(weightKg) == null;

  bool get isNotEmpty => !isEmpty;

  /// The blood pressure, as one reading, or null unless both halves are there.
  VitalReading? get bloodPressure =>
      VitalsInterpreter.bloodPressure(systolic, diastolic);

  VitalReading? get heartRateReading =>
      VitalsInterpreter.reading('heart_rate', 'HR', heartRate, unit: ' bpm');

  VitalReading? get respRateReading =>
      VitalsInterpreter.reading('resp_rate', 'RR', respRate, unit: '/min');

  VitalReading? get tempReading =>
      VitalsInterpreter.reading('temperature', 'Temp', tempC, unit: '°C');

  VitalReading? get o2Reading =>
      VitalsInterpreter.reading('o2_sat', 'O2', o2Sat, unit: '%');

  double? get bmi =>
      VitalsInterpreter.bmiFrom(heightCm: heightCm, weightKg: weightKg);

  VitalReading? get bmiReading =>
      VitalsInterpreter.bmi(heightCm: heightCm, weightKg: weightKg);

  /// Every reading that has been taken, in the order a nurse reads them.
  List<VitalReading> get readings => [
        bloodPressure,
        heartRateReading,
        respRateReading,
        tempReading,
        o2Reading,
        bmiReading,
      ].whereType<VitalReading>().toList();

  /// Anything banded at the point of care that needs acting on. Drives the
  /// alert banners, so a "Refer immediately" reading is never just a pill.
  List<VitalReading> get alerts =>
      readings.where((r) => r.alert != null).toList();

  /// "BP 120/80 (Normal), HR 78 (Normal)" — the sentence the Notes field is
  /// seeded with. The nurse edits it; nothing regenerates it over the top.
  String get notesSuggestion {
    final parts = readings.map((r) => r.notesFragment).toList();
    return parts.isEmpty ? '' : parts.join(', ');
  }

  /// A copy that a service form can show without being able to change the
  /// visit's own record. Used for the read-only vitals strip.
  VisitVitals copy() => VisitVitals()
    ..systolic = systolic
    ..diastolic = diastolic
    ..heartRate = heartRate
    ..respRate = respRate
    ..tempC = tempC
    ..o2Sat = o2Sat
    ..heightCm = heightCm
    ..weightKg = weightKg
    ..interpretations.addAll(interpretations);

  /// Folds a service form's own readings back into the visit record. A field
  /// the form left empty keeps whatever was already there, so a nurse who only
  /// typed a temperature does not blank out the blood pressure.
  void mergeFrom({
    int? systolic,
    int? diastolic,
    int? heartRate,
    int? respRate,
    double? tempC,
    int? o2Sat,
    double? heightCm,
    double? weightKg,
  }) {
    this.systolic = systolic ?? this.systolic;
    this.diastolic = diastolic ?? this.diastolic;
    this.heartRate = heartRate ?? this.heartRate;
    this.respRate = respRate ?? this.respRate;
    this.tempC = tempC ?? this.tempC;
    this.o2Sat = o2Sat ?? this.o2Sat;
    this.heightCm = heightCm ?? this.heightCm;
    this.weightKg = weightKg ?? this.weightKg;
    _captureBands();
  }

  /// The named range of every reading that is present, as `key -> label`
  /// ("heart_rate" -> "Tachycardia"). Written to
  /// `visit_vitals.interpretations` when the visit is saved, so the record
  /// keeps the wording the clinician actually saw.
  void _captureBands() {
    for (final r in readings) {
      interpretations[r.key] = r.category ?? r.band.label;
    }
  }

  /// The `visit_vitals` payload. [visitId] is required because the row is one
  /// per visit.
  Map<String, dynamic> toSupabase(int visitId) => {
        'visit_id': visitId,
        'systolic': systolic,
        'diastolic': diastolic,
        'heart_rate': heartRate,
        'resp_rate': respRate,
        'temp_c': tempC,
        'o2_sat': o2Sat,
        'height_cm': heightCm,
        'weight_kg': weightKg,
        'bmi': _round(bmi),
        'interpretations': interpretations,
      };

  factory VisitVitals.fromSupabase(Map<String, dynamic> row) {
    final v = VisitVitals(
      systolic: _i(row['systolic']),
      diastolic: _i(row['diastolic']),
      heartRate: _i(row['heart_rate']),
      respRate: _i(row['resp_rate']),
      tempC: _d(row['temp_c']),
      o2Sat: _i(row['o2_sat']),
      heightCm: _d(row['height_cm']),
      weightKg: _d(row['weight_kg']),
    );
    final raw = row['interpretations'];
    if (raw is Map) {
      raw.forEach((k, val) => v.interpretations['$k'] = '$val');
    }
    return v;
  }

  static int? _i(Object? v) => v == null
      ? null
      : (v is int ? v : (v is num ? v.round() : int.tryParse('$v')));

  static double? _d(Object? v) =>
      v == null ? null : (v is num ? v.toDouble() : double.tryParse('$v'));

  static double? _round(double? v) =>
      v == null ? null : double.parse(v.toStringAsFixed(1));

  static int? _n(num? v) => v?.round();
}

/// The one sentence under a group of pills, on every screen that shows one.
/// Not decoration: these bands are screening aids, and the screen has to say so
/// where the bands are read.
const String kClinicalReferenceNote = 'For clinic reference only.';
