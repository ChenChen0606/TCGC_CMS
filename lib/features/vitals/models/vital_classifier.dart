import 'package:clinicmanagementsystem/features/vitals/models/vitals_bands.dart';

const String kCriticalReferralBanner =
    'Critical reading — refer to a physician / emergency care immediately.';

class VitalClassification {
  const VitalClassification({
    required this.label,
    required this.band,
    this.alert,
  });

  final String label;

  final VitalBand band;

  final String? alert;

  bool get isAbnormal => band != VitalBand.normal;
  VitalReading toReading({
    required String key,
    required String label,
    required num value,
    required String display,
    String unit = '',
  }) =>
      VitalReading(
        key: key,
        label: label,
        value: value,
        display: display,
        band: band,
        unit: unit,
        category: this.label,
        alert: alert,
      );
}

abstract final class VitalClassifier {
  const VitalClassifier._();

  static num? asNumber(Object? raw) {
    if (raw == null) return null;
    if (raw is num) return raw;
    final s = '$raw'.trim();
    if (s.isEmpty) return null;
    final parsed = num.tryParse(s);
    if (parsed == null || !parsed.isFinite) return null;
    return parsed;
  }

  static int? asWhole(Object? raw) => asNumber(raw)?.round();

  static const int systolicMin = 60;
  static const int systolicMax = 260;
  static const int diastolicMin = 30;
  static const int diastolicMax = 150;
  static const double temperatureMin = 30.0;
  static const double temperatureMax = 43.0;
  static const int pulseMin = 20;
  static const int pulseMax = 250;
  static const int respMin = 4;
  static const int respMax = 60;
  static const int spo2Min = 50;
  static const int spo2Max = 100;

  static String rangeError(num min, num max) =>
      'Enter a value between $min and $max.';

  static const String systolicMustBeHigher =
      'Systolic must be higher than diastolic.';

  // ---------------------------------------------------------------------
  // Age groups (Vital Signs Classification Guide)
  //   19 and older : adult tables (page 1)
  //   13 to 18     : teen BP (AAP 2017) + PALS pulse / breathing
  //   5 to 12      : AAP 2017 screening limits + PALS pulse / breathing
  //   under 5      : not covered by the guide -> no classification
  //   age unknown  : adult tables
  // ---------------------------------------------------------------------

  static const int adultFromAge = 19;
  static const int teenFromAge = 13;
  static const int childFromAge = 5;

  /// True when the guide has no table for this age (under 5).
  static bool isUnsupportedAge(int? ageYears) =>
      ageYears != null && ageYears < childFromAge;

  static bool isReading(int? systolic, int? diastolic) {
    if (systolic == null || diastolic == null) return false;
    if (systolic < systolicMin || systolic > systolicMax) return false;
    if (diastolic < diastolicMin || diastolic > diastolicMax) return false;
    return systolic > diastolic;
  }

  // ---- Adult blood pressure (ESC/ESH 2018) ----
  static const int bpSevereSystolic = 180;
  static const int bpSevereDiastolic = 110;
  static const int bpGrade2Systolic = 160;
  static const int bpGrade2Diastolic = 100;
  static const int bpGrade1Systolic = 140;
  static const int bpGrade1Diastolic = 90;
  static const int bpHighNormalSystolic = 130;
  static const int bpHighNormalDiastolic = 85;
  static const int bpLowSystolic = 90;
  static const int bpLowDiastolic = 60;
  static const int bpOptimalSystolic = 120;
  static const int bpOptimalDiastolic = 80;

  /// AAP 2017 screening limits, ages 5 to 12.
  /// [boys systolic, boys diastolic, girls systolic, girls diastolic]
  static const Map<int, List<int>> _aapScreeningLimits = {
    5: [103, 63, 104, 64],
    6: [105, 66, 105, 67],
    7: [106, 68, 106, 68],
    8: [107, 69, 107, 69],
    9: [107, 70, 108, 71],
    10: [108, 72, 109, 72],
    11: [110, 74, 111, 74],
    12: [113, 75, 114, 75],
  };

  static VitalClassification? classifyBp(
    Object? systolic,
    Object? diastolic, {
    int? ageYears,
    String? sex,
  }) {
    final s = asWhole(systolic);
    final d = asWhole(diastolic);
    if (!isReading(s, d)) return null;
    final sv = s!;
    final dv = d!;

    if (ageYears != null) {
      if (ageYears < childFromAge) return null;
      if (ageYears < teenFromAge) return _childBp(sv, dv, ageYears, sex);
      if (ageYears < adultFromAge) return _teenBp(sv, dv);
    }
    return _adultBp(sv, dv);
  }

  static VitalClassification _adultBp(int s, int d) {
    if (s >= bpSevereSystolic || d >= bpSevereDiastolic) {
      return const VitalClassification(
        label: 'Hypertension Grade 3 (severe)',
        band: VitalBand.critical,
        alert: kCriticalReferralBanner,
      );
    }
    if (s >= bpGrade2Systolic || d >= bpGrade2Diastolic) {
      return const VitalClassification(
          label: 'Hypertension Grade 2', band: VitalBand.high);
    }
    if (s >= bpGrade1Systolic || d >= bpGrade1Diastolic) {
      return const VitalClassification(
          label: 'Hypertension Grade 1', band: VitalBand.high);
    }
    if (s >= bpHighNormalSystolic || d >= bpHighNormalDiastolic) {
      return const VitalClassification(
          label: 'High-Normal', band: VitalBand.watch);
    }
    if (s < bpLowSystolic || d < bpLowDiastolic) {
      return const VitalClassification(label: 'Low', band: VitalBand.low);
    }
    if (s < bpOptimalSystolic && d < bpOptimalDiastolic) {
      return const VitalClassification(
          label: 'Optimal', band: VitalBand.normal);
    }
    return const VitalClassification(label: 'Normal', band: VitalBand.normal);
  }

  /// Ages 13 to 18 (AAP 2017).
  static VitalClassification _teenBp(int s, int d) {
    if (s >= 140 || d >= 90) {
      return const VitalClassification(
          label: 'Hypertension Stage 2', band: VitalBand.high);
    }
    if (s >= 130 || d >= 80) {
      return const VitalClassification(
          label: 'Hypertension Stage 1', band: VitalBand.high);
    }
    if (s >= 120) {
      return const VitalClassification(
          label: 'Elevated', band: VitalBand.watch);
    }
    return const VitalClassification(label: 'Normal', band: VitalBand.normal);
  }

  /// Ages 5 to 12 (AAP 2017 screening limits). Below BOTH limits is normal;
  /// at or above EITHER limit means recheck and clinician review.
  /// When the sex is not recorded, the lower (stricter) limit is used.
  static VitalClassification _childBp(int s, int d, int age, String? sex) {
    final row = _aapScreeningLimits[age]!;
    final x = (sex ?? '').trim().toLowerCase();
    final boy = x.startsWith('m');
    final girl = x.startsWith('f');
    final int limitS;
    final int limitD;
    if (boy) {
      limitS = row[0];
      limitD = row[1];
    } else if (girl) {
      limitS = row[2];
      limitD = row[3];
    } else {
      limitS = row[0] < row[2] ? row[0] : row[2];
      limitD = row[1] < row[3] ? row[1] : row[3];
    }
    if (s >= limitS || d >= limitD) {
      return const VitalClassification(
          label: 'At / Above Screening Limit — Recheck',
          band: VitalBand.watch);
    }
    return const VitalClassification(label: 'Normal', band: VitalBand.normal);
  }

  static VitalReading? bpReading(
    Object? systolic,
    Object? diastolic, {
    int? ageYears,
    String? sex,
  }) {
    final c = classifyBp(systolic, diastolic, ageYears: ageYears, sex: sex);
    final s = asWhole(systolic);
    final d = asWhole(diastolic);
    if (c == null || s == null || d == null) return null;
    return c.toReading(
      key: 'blood_pressure',
      label: 'BP',
      value: s,
      display: '$s/$d mmHg',
      unit: 'mmHg',
    );
  }

  // ---- Temperature (same for every age) ----
  static const List<VitalThresholdBand> temperatureBands = [
    VitalThresholdBand(
        max: 34.9,
        label: 'Hypothermia',
        band: VitalBand.critical,
        alert: kCriticalReferralBanner),
    VitalThresholdBand(max: 35.9, label: 'Below Normal', band: VitalBand.watch),
    VitalThresholdBand(max: 37.2, label: 'Normal', band: VitalBand.normal),
    VitalThresholdBand(
        max: 37.9, label: 'Low-grade Fever', band: VitalBand.watch),
    VitalThresholdBand(max: 39.4, label: 'Fever', band: VitalBand.high),
    VitalThresholdBand(
        max: null,
        label: 'High Fever',
        band: VitalBand.critical,
        alert: kCriticalReferralBanner),
  ];

  static VitalClassification? classifyTemp(Object? celsius) {
    final v = asNumber(celsius);
    if (v == null) return null;
    if (v < temperatureMin || v > temperatureMax) return null;
    return _fromBand(temperatureBands, round1(v));
  }

  static VitalReading? tempReading(Object? celsius) {
    final v = asNumber(celsius);
    final c = classifyTemp(celsius);
    if (c == null || v == null) return null;
    final shown = round1(v);
    return c.toReading(
      key: 'temperature',
      label: 'Temperature',
      value: shown,
      display: shown.toStringAsFixed(1),
      unit: '°C',
    );
  }

  // ---- Pulse ----
  static const List<VitalThresholdBand> heartRateBands = [
    VitalThresholdBand(
        max: 39,
        label: 'Severe Bradycardia',
        band: VitalBand.critical,
        alert: kCriticalReferralBanner),
    VitalThresholdBand(max: 59, label: 'Bradycardia', band: VitalBand.watch),
    VitalThresholdBand(max: 100, label: 'Normal', band: VitalBand.normal),
    VitalThresholdBand(max: 129, label: 'Tachycardia', band: VitalBand.watch),
    VitalThresholdBand(
        max: null,
        label: 'Severe Tachycardia',
        band: VitalBand.critical,
        alert: kCriticalReferralBanner),
  ];

  /// Normal awake pulse range for ages 5 to 18 (PALS).
  static (int, int) _childPulseRange(int age) {
    if (age <= 5) return (80, 120);
    if (age <= 12) return (75, 118);
    return (60, 100);
  }

  /// Normal awake breathing range for ages 5 to 18 (PALS).
  static (int, int) _childRespRange(int age) {
    if (age <= 5) return (20, 28);
    if (age <= 12) return (18, 25);
    return (12, 20);
  }

  static VitalClassification? classifyPulse(Object? bpm, {int? ageYears}) {
    final v = asWhole(bpm);
    if (v == null || v < pulseMin || v > pulseMax) return null;
    if (ageYears != null && ageYears < adultFromAge) {
      if (ageYears < childFromAge) return null;
      final (lo, hi) = _childPulseRange(ageYears);
      if (v < lo) {
        return const VitalClassification(
            label: 'Slow (Bradycardia)', band: VitalBand.watch);
      }
      if (v > hi) {
        return const VitalClassification(
            label: 'Fast (Tachycardia)', band: VitalBand.watch);
      }
      return const VitalClassification(
          label: 'Normal', band: VitalBand.normal);
    }
    return _fromBand(heartRateBands, v);
  }

  static VitalReading? pulseReading(Object? bpm, {int? ageYears}) {
    final c = classifyPulse(bpm, ageYears: ageYears);
    final v = asWhole(bpm);
    if (c == null || v == null) return null;
    return c.toReading(
      key: 'heart_rate',
      label: 'HR',
      value: v,
      display: '$v bpm',
      unit: 'bpm',
    );
  }

  // ---- Respiratory rate ----
  static const List<VitalThresholdBand> respRateBands = [
    VitalThresholdBand(
        max: 11, label: 'Slow (Bradypnea)', band: VitalBand.watch),
    VitalThresholdBand(max: 20, label: 'Normal', band: VitalBand.normal),
    VitalThresholdBand(
        max: 29, label: 'Fast (Tachypnea)', band: VitalBand.watch),
    VitalThresholdBand(
        max: null,
        label: 'Critically Fast',
        band: VitalBand.critical,
        alert: kCriticalReferralBanner),
  ];

  static VitalClassification? classifyResp(Object? perMinute, {int? ageYears}) {
    final v = asWhole(perMinute);
    if (v == null) return null;
    if (v < respMin || v > respMax) return null;
    if (ageYears != null && ageYears < adultFromAge) {
      if (ageYears < childFromAge) return null;
      final (lo, hi) = _childRespRange(ageYears);
      if (v < lo) {
        return const VitalClassification(
            label: 'Slow (Bradypnea)', band: VitalBand.watch);
      }
      if (v > hi) {
        return const VitalClassification(
            label: 'Fast (Tachypnea)', band: VitalBand.watch);
      }
      return const VitalClassification(
          label: 'Normal', band: VitalBand.normal);
    }
    return _fromBand(respRateBands, v);
  }

  static VitalReading? respReading(Object? perMinute, {int? ageYears}) {
    final c = classifyResp(perMinute, ageYears: ageYears);
    final v = asWhole(perMinute);
    if (c == null || v == null) return null;
    return c.toReading(
      key: 'resp_rate',
      label: 'RR',
      value: v,
      display: '$v/min',
      unit: '/min',
    );
  }

  // ---- Oxygen saturation (same for every age) ----
  static const List<VitalThresholdBand> o2Bands = [
    VitalThresholdBand(
        max: 89,
        label: 'Critically Low',
        band: VitalBand.critical,
        alert: kCriticalReferralBanner),
    VitalThresholdBand(max: 94, label: 'Low', band: VitalBand.watch),
    VitalThresholdBand(max: null, label: 'Normal', band: VitalBand.normal),
  ];

  static VitalClassification? classifySpo2(Object? percent) {
    final v = asWhole(percent);
    if (v == null) return null;
    if (v < spo2Min || v > spo2Max) return null;
    return _fromBand(o2Bands, v);
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

  static double round1(num v) => (v * 10).round() / 10;

  static VitalClassification _fromBand(
    List<VitalThresholdBand> bands,
    num value,
  ) {
    final b = resolve(bands, value);
    return VitalClassification(label: b.label, band: b.band, alert: b.alert);
  }
}