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

  static bool isReading(int? systolic, int? diastolic) {
    if (systolic == null || diastolic == null) return false;
    if (systolic < systolicMin || systolic > systolicMax) return false;
    if (diastolic < diastolicMin || diastolic > diastolicMax) return false;
    return systolic > diastolic;
  }

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

  static VitalClassification? classifyBp(Object? systolic, Object? diastolic) {
    final s = asWhole(systolic);
    final d = asWhole(diastolic);
    if (!isReading(s, d)) return null;
    if (s! >= bpSevereSystolic || d! >= bpSevereDiastolic) {
      return const VitalClassification(
        label: 'Severe High (Hypertensive Crisis Range)',
        band: VitalBand.critical,
        alert: kCriticalReferralBanner,
      );
    }
    if (s >= bpGrade2Systolic || d >= bpGrade2Diastolic) {
      return const VitalClassification(
          label: 'High — Grade 2 Range', band: VitalBand.high);
    }
    if (s >= bpGrade1Systolic || d >= bpGrade1Diastolic) {
      return const VitalClassification(
          label: 'High — Grade 1 Range', band: VitalBand.high);
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

  static VitalReading? bpReading(Object? systolic, Object? diastolic) {
    final c = classifyBp(systolic, diastolic);
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

  static VitalClassification? classifyPulse(Object? bpm) {
    final v = asWhole(bpm);
    if (v == null || v < pulseMin || v > pulseMax) return null;
    return _fromBand(heartRateBands, v);
  }

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

  static VitalClassification? classifyResp(Object? perMinute) {
    final v = asWhole(perMinute);
    if (v == null) return null;
    if (v < respMin || v > respMax) return null;
    return _fromBand(respRateBands, v);
  }

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
