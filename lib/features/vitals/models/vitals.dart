import 'package:clinicmanagementsystem/features/vitals/models/vital_classifier.dart';
import 'package:clinicmanagementsystem/features/vitals/models/vitals_bands.dart';

export 'package:clinicmanagementsystem/features/vitals/models/vitals_bands.dart';

class VitalsThresholds {
  VitalsThresholds({
    required this.heartRate,
    required this.respiratoryRate,
    required this.temperature,
    required this.o2Saturation,
    required this.bmi,
  });

  static VitalsThresholds defaults() => VitalsThresholds(
        heartRate: VitalClassifier.heartRateBands,
        respiratoryRate: VitalClassifier.respRateBands,
        temperature: VitalClassifier.temperatureBands,
        o2Saturation: VitalClassifier.o2Bands,
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

  static VitalsThresholds instance = VitalsThresholds.defaults();

  static const String keyHeartRate = 'heart_rate';
  static const String keyRespRate = 'resp_rate';
  static const String keyTemperature = 'temperature';
  static const String keyO2 = 'o2_sat';
  static const String keyBmi = 'bmi';

  Map<String, List<VitalThresholdBand>> get byKey => {
        keyHeartRate: heartRate,
        keyRespRate: respiratoryRate,
        keyTemperature: temperature,
        keyO2: o2Saturation,
        keyBmi: bmi,
      };

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

  static VitalThresholdBand resolve(
    List<VitalThresholdBand> bands,
    num value,
  ) {
    for (final b in bands) {
      if (b.max == null || value <= b.max!) return b;
    }
    return bands.last;
  }
}

class VitalsInterpreter {
  const VitalsInterpreter._();

  static VitalsThresholds get _t => VitalsThresholds.instance;

  static num? parse(Object? raw) {
    if (raw == null) return null;
    if (raw is num) return raw;
    final cleaned = '$raw'.replaceAll(RegExp(r'[^0-9.]'), '').trim();
    if (cleaned.isEmpty) return null;
    final parsed = double.tryParse(cleaned);
    if (parsed == null || !parsed.isFinite) return null;
    return parsed;
  }

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

  static VitalReading? bloodPressure(
    Object? systolic,
    Object? diastolic, {
    String unit = ' mmHg',
  }) {
    return VitalClassifier.bpReading(systolic, diastolic);
  }

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

  static String _trim(num v) {
    if (v is int) return '$v';
    final s = v.toStringAsFixed(1);
    return s.endsWith('.0') ? s.substring(0, s.length - 2) : s;
  }
}

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
    this.measuredAt,
  });

  int? systolic;
  int? diastolic;
  int? heartRate;
  int? respRate;
  double? tempC;
  int? o2Sat;
  double? heightCm;
  double? weightKg;

  DateTime? measuredAt;

  final Map<String, String> interpretations = {};

  final Map<String, String> enteredBy = {};

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

  List<VitalReading> get readings => [
        bloodPressure,
        heartRateReading,
        respRateReading,
        tempReading,
        o2Reading,
        bmiReading,
      ].whereType<VitalReading>().toList();

  List<VitalReading> get alerts =>
      readings.where((r) => r.alert != null).toList();

  String get notesSuggestion {
    final parts = readings.map((r) => r.notesFragment).toList();
    return parts.isEmpty ? '' : parts.join(', ');
  }

  VisitVitals copy() => VisitVitals()
    ..systolic = systolic
    ..diastolic = diastolic
    ..heartRate = heartRate
    ..respRate = respRate
    ..tempC = tempC
    ..o2Sat = o2Sat
    ..heightCm = heightCm
    ..weightKg = weightKg
    ..measuredAt = measuredAt
    ..interpretations.addAll(interpretations)
    ..enteredBy.addAll(enteredBy);

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
