import 'dart:math' as math;

import 'package:clinicmanagementsystem/features/vitals/models/vitals_bands.dart';

// =============================================================================
//  WHO BMI classification
//    19 years and over  -> fixed WHO adult cut-offs        (works now)
//    5 to 18 years      -> WHO BMI-for-age z-score (LMS)   (needs the table at
//                          the bottom of this file to be filled in)
//    under 5 years      -> not covered, BMI is blocked
// =============================================================================

abstract final class WhoBmi {
  // ---------- helpers --------------------------------------------------------

  static int? ageInMonths(DateTime birth, DateTime asOf) {
    var m = (asOf.year - birth.year) * 12 + asOf.month - birth.month;
    if (asOf.day < birth.day) m--;
    return m < 0 ? null : m;
  }

  static String? _sexKey(String sex) {
    final s = sex.trim().toLowerCase();
    if (s.startsWith('m')) return 'male';
    if (s.startsWith('f')) return 'female';
    return null;
  }

  static double? bmiOf(double? heightCm, double? weightKg) {
    if (heightCm == null || weightKg == null) return null;
    if (heightCm <= 0 || weightKg <= 0) return null;
    final m = heightCm / 100;
    return weightKg / (m * m);
  }

  // ---------- why BMI cannot be worked out ----------------------------------

  /// null = fine (or nothing entered yet). Otherwise the message to show.
  static String? blockReason({
    required double? heightCm,
    required double? weightKg,
    required String sex,
    required DateTime? birthDate,
    required DateTime asOf,
  }) {
    if (heightCm == null && weightKg == null) return null;
    if (birthDate == null) {
      return "No birth date on this person's record. Add it first — WHO BMI needs age.";
    }
    if (_sexKey(sex) == null) {
      return "No sex on this person's record. Add it first — WHO BMI needs sex.";
    }
    final months = ageInMonths(birthDate, asOf);
    if (months == null) return 'Birth date is after the visit date.';
    if (months < 60) return 'WHO BMI-for-age here covers 5 years and older.';
    if (months < 228 && kWhoBmiLms[_sexKey(sex)]?[months] == null) {
      return 'WHO reference table is not loaded for this age yet.';
    }
    return null;
  }

  // ---------- classification -------------------------------------------------

  static ({String label, VitalBand band})? classify({
    required double bmi,
    required String sex,
    required DateTime birthDate,
    required DateTime asOf,
  }) {
    final months = ageInMonths(birthDate, asOf);
    final key = _sexKey(sex);
    if (months == null || key == null || months < 60) return null;
    final b = (bmi * 10).round() / 10; // classify the number that is shown

    // --- 19 years and over: WHO adult cut-offs
    if (months >= 228) {
      if (b < 16) return (label: 'Underweight', band: VitalBand.high);  //Severe Underweight
      if (b < 18.5) return (label: 'Underweight', band: VitalBand.watch);
      if (b < 25) return (label: 'Normal', band: VitalBand.normal);
      if (b < 30) return (label: 'Overweight', band: VitalBand.watch);
      if (b < 35) return (label: 'Obese', band: VitalBand.high);  // 'Obese Class I'
      if (b < 40) return (label: 'Obese', band: VitalBand.high); //'Obese Class II'
      return (label: 'Obese', band: VitalBand.critical); //'Obese Class III'
    }

    // --- 5 to 18 years: WHO BMI-for-age z-score
    final lms = kWhoBmiLms[key]?[months];
    if (lms == null) return null;
    final z = _zScore(b, lms);
    if (z < -3) return (label: 'Severe Thinness', band: VitalBand.high); 
    if (z < -2) return (label: 'Thinness', band: VitalBand.watch);
    if (z <= 1) return (label: 'Normal', band: VitalBand.normal);
    if (z <= 2) return (label: 'Overweight', band: VitalBand.watch);
    return (label: 'Obese', band: VitalBand.high);
  }

  static double _zScore(double bmi, List<double> lms) {
    final l = lms[0], m = lms[1], s = lms[2];
    if (l.abs() < 1e-9) return math.log(bmi / m) / s;
    return (math.pow(bmi / m, l).toDouble() - 1) / (l * s);
  }

  // ---------- the reading the app shows -------------------------------------

  static VitalReading? reading({
    required double? heightCm,
    required double? weightKg,
    required String sex,
    required DateTime? birthDate,
    required DateTime asOf,
  }) {
    if (blockReason(
            heightCm: heightCm,
            weightKg: weightKg,
            sex: sex,
            birthDate: birthDate,
            asOf: asOf) !=
        null) {
      return null;
    }
    final bmi = bmiOf(heightCm, weightKg);
    if (bmi == null || birthDate == null) return null;
    final c = classify(bmi: bmi, sex: sex, birthDate: birthDate, asOf: asOf);
    if (c == null) return null;
    return VitalReading(
      key: 'bmi',
      label: 'BMI',
      value: bmi,
      display: bmi.toStringAsFixed(1),
      band: c.band,
      unit: 'kg/m²',
      category: c.label,
      alert: null,
    );
  }
}

// =============================================================================
//  WHO 2007 BMI-for-age LMS table (5 to 19 years)   <-- FILL THIS IN LATER
//  Key   = age in completed months (61 to 227)
//  Value = [L, M, S]
//  Source: who.int/tools/growth-reference-data-for-5to19-years/indicators/bmi-for-age
//          (z-scores: boys / girls, xlsx)
// =============================================================================
const Map<String, Map<int, List<double>>> kWhoBmiLms = {
  'male': {
    // 61: [L, M, S],
  },
  'female': {
    // 61: [L, M, S],
  },
};