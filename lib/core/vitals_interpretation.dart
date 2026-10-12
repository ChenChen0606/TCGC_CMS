// ─────────────────────────────────────────────────────────────────────────────
//  vitals_interpretation.dart
//  What a number the nurse just typed MEANS, as pure functions.
//
//  WHY BLOOD PRESSURE IS NOT A THRESHOLD TABLE
//  Every other reading the clinic takes is banded by walking an ordered list of
//  ceilings: under 60 is slow, 60–100 is normal, over 100 is fast. Blood
//  pressure is two numbers read as one, and the ORDER the rules are checked in
//  is itself clinical. 180/70 is Severely High even though 70 is
//  unremarkable, and a rule written as "the first band whose ceiling is above
//  the reading" cannot express that — it would sort 180 and 70 into different
//  lists and lose the fact that one reading has one verdict. So a BP verdict is
//  a short-circuit ladder, written out in the order a clinician checks it, and
//  the order is the point.
//
//  WHY A STANDARD IS NAMED
//  The bands come from a guideline, and guidelines disagree — the Philippine /
//  ISH 2020 ladder the clinic works to and the ACC/AHA ladder call the same
//  reading different things. So the numbers live on a [BpStandardConfig] rather
//  than in the code that reads them, and a reading is always interpreted under
//  a standard that is written down next to it. Which standard was used is saved
//  with the reading, so retuning a threshold later cannot rewrite what the
//  nurse saw on the day.
//
//  WHAT NONE OF THIS IS
//  A screening aid for clinic reference only. Nothing in this file diagnoses
//  hypertension or decides treatment; the BP guide the form shows says the same
//  thing, and it says the clinic physician's judgment comes first.
// ─────────────────────────────────────────────────────────────────────────────

import 'vitals_bands.dart';

/// The guideline a blood pressure is read against. [id] is what gets stored on
/// the record, so it has to be a stable string and not the Dart name.
enum BpStandard {
  phIsh('PH_ISH'),
  accAha('ACC_AHA');

  const BpStandard(this.id);

  /// The stored name of this standard.
  final String id;

  /// Reads a stored [id] back, defaulting to the clinic's own standard so a row
  /// written before the standard was recorded still bands rather than throwing.
  static BpStandard byId(Object? id) => values.firstWhere(
        (s) => s.id == '$id',
        orElse: () => BpStandard.phIsh,
      );

  /// The standard the clinic works to. [active] is what the app reads, so the
  /// alternative in this enum is a value in a test and in a saved record rather
  /// than a switch somebody has to remember to update.
  static BpStandard get active => _active;
  static BpStandard _active = BpStandard.phIsh;

  /// Replaces the active standard. One assignment, the way [VitalsThresholds]
  /// works — there is deliberately no UI for this.
  static set active(BpStandard value) => _active = value;

  /// The threshold table for this standard.
  BpStandardConfig get config => switch (this) {
        BpStandard.phIsh => BpStandardConfig.phIsh(),
        BpStandard.accAha => BpStandardConfig.accAha(),
      };
}

/// How far a blood pressure sits from normal, as an ORDERED severity. Six steps
/// because blood pressure is the one reading whose "a bit off" and "a lot off"
/// are told apart on the same line, and a nurse deciding whether to repeat a
/// reading needs to see that difference.
enum BpSeverity {
  low('Low'),
  normal('Normal'),
  highNormal('High-Normal'),
  grade1('High — Grade 1 Range'),
  grade2('High — Grade 2 Range'),
  severe('Severely High');

  const BpSeverity(this.phishLabel);

  /// The name this severity has under [BpStandard.phIsh].
  ///
  /// Only PH/ISH labels live on the enum, because PH/ISH is the clinic's
  /// standard and therefore the one that has to read correctly even when a
  /// reading is shown with no standard attached. The ACC/AHA names come from
  /// [BpStandardConfig.labelFor] instead — see that method for why.
  final String phishLabel;

  /// Shorter, for the six-segment strip, where "High — Grade 1 Range" would not
  /// fit six to a row. The strip is a position, not a sentence.
  String get stripLabel => switch (this) {
        BpSeverity.low => 'Low',
        BpSeverity.normal => 'Normal',
        BpSeverity.highNormal => 'High-Normal',
        BpSeverity.grade1 => 'Grade 1',
        BpSeverity.grade2 => 'Grade 2',
        BpSeverity.severe => 'Severe',
      };

  /// Higher wins when the two numbers of one reading disagree.
  int get rank => index;

  VitalBand get band => switch (this) {
        BpSeverity.low => VitalBand.watch,
        BpSeverity.normal => VitalBand.normal,
        BpSeverity.highNormal => VitalBand.watch,
        BpSeverity.grade1 => VitalBand.high,
        BpSeverity.grade2 => VitalBand.high,
        BpSeverity.severe => VitalBand.critical,
      };

  /// What this category means, in a sentence a nurse can act on. Deliberately
  /// not a diagnosis: this is what the reading says, not what the visitor has.
  String get means => switch (this) {
        BpSeverity.low => 'Blood pressure is lower than usual.',
        BpSeverity.normal => 'Blood pressure is within the normal range.',
        BpSeverity.highNormal => 'Slightly above normal but not yet high.',
        BpSeverity.grade1 => 'Blood pressure is high.',
        BpSeverity.grade2 => 'Blood pressure is high.',
        BpSeverity.severe => 'Blood pressure is severely high.',
      };

  /// What the clinic does about it.
  String get action => switch (this) {
        BpSeverity.low =>
          'Ask about dizziness, fainting or weakness. Let the visitor sit or '
              'lie down and rest, then recheck.',
        BpSeverity.normal => 'No action needed.',
        BpSeverity.highNormal => 'Advise rest and recheck at the next visit.',
        BpSeverity.grade1 =>
          'Rest 5 minutes and repeat the reading. If still high, recommend a '
              'consultation.',
        BpSeverity.grade2 =>
          'Repeat after rest. Refer to the clinic nurse or physician for '
              'consultation.',
        BpSeverity.severe =>
          'Repeat after 5 minutes of rest. If still this high, or with warning '
              'signs, refer urgently.',
      };

  /// Whether a repeat reading is worth suggesting, and how soon.
  bool get suggestsRepeat => rank >= BpSeverity.highNormal.rank;

  /// The chip shown when a repeat reading is recommended but only one reading
  /// has been taken. Null for the categories that do not need one.
  String? get repeatAdvice => switch (this) {
        BpSeverity.low => null,
        _ => 'Recommended: repeat reading after 1–2 minutes',
      };

  /// The red banner only the top category gets, because it is the one where
  /// waiting is itself a decision.
  String? get urgentBanner => switch (this) {
        BpSeverity.severe =>
          'Severely high blood pressure. Repeat after 5 minutes of rest. If '
              'still this high, or if there are warning signs, refer urgently.',
        _ => null,
      };
}

/// One standard's numbers, as data, so the rule is read from a config object
/// rather than written into the branch that reads it.
class BpStandardConfig {
  const BpStandardConfig({
    required this.standard,
    required this.severeSystolic,
    required this.severeDiastolic,
    required this.grade2Systolic,
    required this.grade2Diastolic,
    required this.grade1Systolic,
    required this.grade1Diastolic,
    required this.highNormalSystolic,
    required this.highNormalDiastolic,
    required this.lowSystolic,
    required this.lowDiastolic,
    required this.source,
    this.version = '1',
  });

  /// The version of these numbers, stored beside every verdict.
  ///
  /// [standard] on its own is not enough to say how a reading was judged. PH/ISH
  /// will be reissued, and when it is, a record that says only "PH_ISH" gives no
  /// way to tell a verdict produced by today's ladder from one produced by a
  /// different one — and the clinic's records are the evidence of what a nurse
  /// was shown at the time. Bump this whenever a number above changes.
  final String version;

  /// The clinic's own standard: the 2020 Philippine hypertension guideline
  /// (hypertension is office BP 140/90 or higher) together with ISH 2020.
  factory BpStandardConfig.phIsh() => const BpStandardConfig(
        standard: BpStandard.phIsh,
        severeSystolic: 180,
        severeDiastolic: 110,
        grade2Systolic: 160,
        grade2Diastolic: 100,
        grade1Systolic: 140,
        grade1Diastolic: 90,
        highNormalSystolic: 130,
        highNormalDiastolic: 85,
        lowSystolic: 90,
        lowDiastolic: 60,
        source: '2020 Philippine hypertension guideline and ISH 2020.',
      );

  /// The alternative the clinic has not adopted, kept so the numbers it is
  /// measured against are written down somewhere rather than remembered. There
  /// is no UI for it — [BpStandard.active] is the only way in.
  ///
  /// ACC/AHA call a crisis *above* 180/120 rather than 180/120 and above, and
  /// the readings here are whole mmHg, so the first value that counts is
  /// recorded as 181/121. Stating it that way keeps one comparison in
  /// [classify] instead of threading an "is this bound exclusive" flag through
  /// every rung of the ladder for one standard's sake.
  factory BpStandardConfig.accAha() => const BpStandardConfig(
        standard: BpStandard.accAha,
        severeSystolic: 181,
        severeDiastolic: 121,
        grade2Systolic: 140,
        grade2Diastolic: 90,
        grade1Systolic: 130,
        grade1Diastolic: 80,
        highNormalSystolic: 120,
        highNormalDiastolic: 80,
        lowSystolic: 90,
        lowDiastolic: 60,
        source: 'ACC/AHA adult blood pressure categories.',
      );

  final BpStandard standard;

  final int severeSystolic;
  final int severeDiastolic;
  final int grade2Systolic;
  final int grade2Diastolic;
  final int grade1Systolic;
  final int grade1Diastolic;
  final int highNormalSystolic;
  final int highNormalDiastolic;

  /// Below these, the reading is on the low side. Checked LAST, and that
  /// ordering is deliberate: 150/55 is a high reading with a low number in it,
  /// not a low reading.
  final int lowSystolic;
  final int lowDiastolic;

  /// Where these numbers come from, printed under the guide's table.
  final String source;

  /// The one rule, written the way a clinician checks it: top down, first match
  /// wins. Not a lookup table — the short-circuit is the point.
  BpSeverity classify(num systolic, num diastolic) {
    if (systolic >= severeSystolic || diastolic >= severeDiastolic) {
      return BpSeverity.severe;
    }
    if (systolic >= grade2Systolic || diastolic >= grade2Diastolic) {
      return BpSeverity.grade2;
    }
    if (systolic >= grade1Systolic || diastolic >= grade1Diastolic) {
      return BpSeverity.grade1;
    }
    if (systolic >= highNormalSystolic || diastolic >= highNormalDiastolic) {
      return BpSeverity.highNormal;
    }
    if (systolic < lowSystolic || diastolic < lowDiastolic) {
      return BpSeverity.low;
    }
    return BpSeverity.normal;
  }

  /// The systolic on its own, for the "Based on" line. Uses the same cuts as
  /// [classify] so the two can never disagree about where a number sits.
  BpSeverity classifySystolic(num systolic) {
    if (systolic >= severeSystolic) return BpSeverity.severe;
    if (systolic >= grade2Systolic) return BpSeverity.grade2;
    if (systolic >= grade1Systolic) return BpSeverity.grade1;
    if (systolic >= highNormalSystolic) return BpSeverity.highNormal;
    if (systolic < lowSystolic) return BpSeverity.low;
    return BpSeverity.normal;
  }

  /// The diastolic on its own, for the "Based on" line.
  BpSeverity classifyDiastolic(num diastolic) {
    if (diastolic >= severeDiastolic) return BpSeverity.severe;
    if (diastolic >= grade2Diastolic) return BpSeverity.grade2;
    if (diastolic >= grade1Diastolic) return BpSeverity.grade1;
    if (diastolic >= highNormalDiastolic) return BpSeverity.highNormal;
    if (diastolic < lowDiastolic) return BpSeverity.low;
    return BpSeverity.normal;
  }

  /// The word this standard calls [severity].
  ///
  /// [BpSeverity] carries the PH/ISH names because that is the clinic's
  /// standard; the ACC/AHA names exist only here, because a clinic that has not
  /// adopted them never renders one. Six severities, five names, so Low is
  /// ACC/AHA's too — their published categories have no low band, but a reading
  /// of 85/55 has to go somewhere and the answer is not "normal".
  String labelFor(BpSeverity severity) => switch (standard) {
        BpStandard.phIsh => severity.phishLabel,
        BpStandard.accAha => switch (severity) {
            BpSeverity.low => 'Low',
            BpSeverity.normal => 'Normal',
            BpSeverity.highNormal => 'Elevated',
            BpSeverity.grade1 => 'Stage 1 Hypertension',
            BpSeverity.grade2 => 'Stage 2 Hypertension',
            BpSeverity.severe => 'Hypertensive Crisis',
          },
      };

  /// The two-number form printed in the guide's table.
  String systolicRangeFor(BpSeverity severity) => switch (severity) {
        BpSeverity.low => 'below $lowSystolic',
        BpSeverity.normal => 'below $highNormalSystolic',
        BpSeverity.highNormal => '$highNormalSystolic–${grade1Systolic - 1}',
        BpSeverity.grade1 => '$grade1Systolic–${grade2Systolic - 1}',
        BpSeverity.grade2 => '$grade2Systolic–${severeSystolic - 1}',
        BpSeverity.severe => '$severeSystolic or above',
      };

  /// The lower-number form printed in the guide's table. The `and/or` matters
  /// and is spelled out in the note under the table rather than in every cell.
  String diastolicRangeFor(BpSeverity severity) => switch (severity) {
        BpSeverity.low => 'or below $lowDiastolic',
        BpSeverity.normal => 'and below $highNormalDiastolic',
        BpSeverity.highNormal =>
          'and/or $highNormalDiastolic–${grade1Diastolic - 1}',
        BpSeverity.grade1 => 'and/or $grade1Diastolic–${grade2Diastolic - 1}',
        BpSeverity.grade2 => 'and/or $grade2Diastolic–${severeDiastolic - 1}',
        BpSeverity.severe => 'and/or $severeDiastolic or above',
      };
}

/// One typed-in blood pressure: a systolic and a diastolic and nothing else.
class BpReading {
  const BpReading({required this.systolic, required this.diastolic});

  final int systolic;
  final int diastolic;

  String get display => '$systolic / $diastolic mmHg';

  /// The reading as it is written on the record and in a note — no spaces round
  /// the slash, because that is how it is written everywhere else.
  String get compact => '$systolic/$diastolic';

  Map<String, dynamic> toJson() =>
      {'systolic': systolic, 'diastolic': diastolic};

  static BpReading? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final s = raw['systolic'];
    final d = raw['diastolic'];
    if (s is! num || d is! num) return null;
    return BpReading(systolic: s.round(), diastolic: d.round());
  }

  @override
  bool operator ==(Object other) =>
      other is BpReading &&
      other.systolic == systolic &&
      other.diastolic == diastolic;

  @override
  int get hashCode => Object.hash(systolic, diastolic);

  @override
  String toString() => compact;
}

/// What a blood pressure came to: the numbers, the verdict, and enough of the
/// working to show that the verdict was reached honestly.
class BpResult {
  const BpResult({
    required this.reading,
    required this.severity,
    required this.systolicSeverity,
    required this.diastolicSeverity,
    required this.standard,
  });

  final BpReading reading;

  /// The one verdict for the reading as a whole.
  final BpSeverity severity;

  /// Where the upper number sits on its own.
  final BpSeverity systolicSeverity;

  /// Where the lower number sits on its own.
  final BpSeverity diastolicSeverity;

  /// The guideline this was judged under, saved with the reading.
  final BpStandard standard;

  int get systolic => reading.systolic;
  int get diastolic => reading.diastolic;

  BpStandardConfig get config => standard.config;

  /// The version of the ladder that produced this verdict, for the record.
  String get version => config.version;

  /// The name of the verdict under the standard that produced it.
  String get label => config.labelFor(severity);

  /// The name the systolic and the diastolic get on their own.
  String get systolicLabel => config.labelFor(systolicSeverity);
  String get diastolicLabel => config.labelFor(diastolicSeverity);

  String get means => severity.means;
  String get action => severity.action;
  VitalBand get band => severity.band;

  bool get isNormal => severity == BpSeverity.normal;

  /// True when the two numbers disagreed and one of them decided it, which is
  /// the line under the result card that stops a nurse wondering why 128/92 is
  /// called high when 128 is not.
  bool get numbersDisagree => systolicSeverity != diastolicSeverity;

  /// "Based on: systolic 148 (High — Grade 1 Range), diastolic 92 (High —
  /// Grade 1 Range) — the higher category applies."
  ///
  /// The trailing clause only appears when the two actually landed in different
  /// places, so a reading where both agree is not told it agreed.
  String get basedOn {
    final parts = [
      'systolic $systolic ($systolicLabel)',
      'diastolic $diastolic ($diastolicLabel)',
    ];
    return 'Based on: ${parts.join(', ')}'
        '${numbersDisagree ? ' — the higher category applies.' : '.'}';
  }

  VitalReading toVitalReading({String unit = ' mmHg'}) => VitalReading(
        key: 'blood_pressure',
        label: 'BP',
        value: systolic,
        display: '${reading.compact}$unit',
        band: severity.band,
        unit: unit.trim(),
        category: label,
        // Carries the urgent banner to wherever the reading is shown again,
        // so a BP form and a Prenatal box cannot disagree about whether this
        // reading needs a doctor now.
        alert: severity.urgentBanner,
      );
}

/// Reads whatever a text field currently holds as a whole number, or null.
///
/// The BP form only accepts whole numbers — a cuff does not read 118.4 — so
/// this rounds rather than parses a decimal. A half-typed field, an empty one
/// or anything that is not a number comes back null, which is what makes an
/// unfinished box show no verdict at all rather than a wrong one.
///
/// Strict on purpose. An earlier version stripped every non-digit out of the
/// string first, which turned a stray "95.0" into 950 — a reading nobody took,
/// banded as Severely High and written to the record. So a value is only read
/// when the WHOLE string is a number, and any leftover text means "not a
/// reading yet" rather than a guess.
int? _wholeNumber(Object? raw) {
  if (raw == null) return null;
  if (raw is num) return raw.round();
  final cleaned = '$raw'.trim();
  if (cleaned.isEmpty) return null;
  final asNum = num.tryParse(cleaned);
  if (asNum != null) return asNum.round();
  return null;
}

/// What one blood pressure means, or null while there is not one to read.
///
/// Both numbers are required: a systolic on its own is half a measurement, and
/// the clinic's own rule cannot be applied to it. [standard] defaults to the
/// clinic's active standard.
/// The same judgement for a reading that already exists, such as an average.
///
/// A convenience so callers holding a [BpReading] — the form's repeat readings,
/// a resumed visit's stored list — do not have to take it apart to ask what it
/// means. A null reading means "no verdict", exactly as null numbers do above.
BpResult? interpretBpReading(BpReading? reading, {BpStandard? standard}) {
  if (reading == null) return null;
  return interpretBP(reading.systolic, reading.diastolic, standard: standard);
}

/// Whether a systolic and a diastolic are a measurement, as opposed to two
/// numbers.
///
/// Two things rule a pair out, and both are the rule rather than the UI, so a
/// form and a saved record cannot disagree about it:
///
///   * outside [BpLimits] — a cuff does not read 400/95; and
///   * a systolic that is not above the diastolic — 90/120 is not a blood
///     pressure, it is two numbers typed in the wrong order or the wrong boxes,
///     and banding it would put "Normal" on a record for a measurement nobody
///     took.
///
/// The form shows [BpLimits.systolicMustBeHigher] for the second case, and the
/// boxes are required, so an inverted pair also keeps Next disabled.
bool isBpReading(Object? systolic, Object? diastolic) {
  final s = _wholeNumber(systolic);
  final d = _wholeNumber(diastolic);
  if (s == null || d == null) return false;
  if (!BpLimits.systolic.accepts(s) || !BpLimits.diastolic.accepts(d)) {
    return false;
  }
  return s > d;
}

BpResult? interpretBP(
  Object? systolic,
  Object? diastolic, {
  BpStandard? standard,
}) {
  final s = _wholeNumber(systolic);
  final d = _wholeNumber(diastolic);
  // Anything that is not a measurement has no verdict, and must not be given
  // one by climbing the ladder: a number no cuff produces, or a systolic that is
  // not above the diastolic, is a slip — not "very high", and not "Normal"
  // either. See [isBpReading] for why the rule lives here and not in the form.
  if (s == null || d == null) return null;
  if (!isBpReading(s, d)) return null;
  final std = standard ?? BpStandard.active;
  final config = std.config;
  return BpResult(
    reading: BpReading(systolic: s, diastolic: d),
    severity: config.classify(s, d),
    systolicSeverity: config.classifySystolic(s),
    diastolicSeverity: config.classifyDiastolic(d),
    standard: std,
  );
}

/// The reading a visit should be judged on: the average of every complete
/// reading once there is more than one, and the reading itself when there is
/// only one.
///
/// Rounded to whole mmHg, because the result card shows a number a nurse reads
/// off a cuff and "146.5" is not one. Null when nothing complete has been
/// entered.
BpReading? bpAverage(List<BpReading> readings) {
  final whole =
      readings.where((r) => r.systolic > 0 && r.diastolic > 0).toList();
  if (whole.isEmpty) return null;
  if (whole.length == 1) return whole.first;
  final s = whole.map((r) => r.systolic).reduce((a, b) => a + b) / whole.length;
  final d =
      whole.map((r) => r.diastolic).reduce((a, b) => a + b) / whole.length;
  return BpReading(systolic: s.round(), diastolic: d.round());
}

/// "Average: 146 / 90 mmHg" — the line under the result card once there is more
/// than one reading. Null for a single reading, which has no average to state.
String? bpAverageLabel(List<BpReading> readings) {
  if (readings.where((r) => r.systolic > 0 && r.diastolic > 0).length < 2) {
    return null;
  }
  return 'Average: ${bpAverage(readings)!.display}';
}

/// How long a note on a blood pressure may be.
///
/// A count in one place so the form's counter, its "Insert suggested note"
/// button and the field's own maxLength cannot disagree — a counter that says
/// 0/500 above a box that stops at 480 is worse than no counter.
const int kBpNotesMaxChars = 500;

// ── THE OTHER RATES ──────────────────────────────────────────────────────────

/// One rate's verdict: the word on the pill, the colour behind it, and the
/// banner to show when it means "now" rather than "noted".
class RateVerdict {
  const RateVerdict({
    required this.label,
    required this.band,
    this.alert,
  });

  final String label;
  final VitalBand band;

  /// The blood-pressure severity this rate shares a colour with, so the pulse
  /// pill on the BP form is drawn from the same palette as the band next to it
  /// rather than from the generic vital colours. Null for the rates that have no
  /// blood-pressure equivalent.
  BpSeverity? get severity => switch (band) {
        VitalBand.low => BpSeverity.low,
        VitalBand.normal => BpSeverity.normal,
        VitalBand.watch => BpSeverity.highNormal,
        VitalBand.high => BpSeverity.grade1,
        VitalBand.critical => BpSeverity.severe,
      };

  /// Present only for the readings that mean act on this.
  final String? alert;

  bool get isAbnormal => band != VitalBand.normal;
}

/// Heartbeats per minute. Normal adult 60–100; below 60 is slow and can be
/// normal in an athlete; over 100 is fast.
RateVerdict? interpretPulse(Object? bpm) {
  final v = _wholeNumber(bpm);
  if (v == null) return null;
  // Low, not watch: a slow pulse is a different kind of finding from a fast one.
  // It is asked about and re-checked rather than acted on, and it is drawn blue
  // so it cannot be mistaken for the amber of a rate that is merely high.
  if (v < 60) {
    return const RateVerdict(label: 'Slow (Bradycardia)', band: VitalBand.low);
  }
  if (v <= 100)
    return const RateVerdict(label: 'Normal', band: VitalBand.normal);
  return const RateVerdict(
    label: 'Fast (Tachycardia)',
    band: VitalBand.high,
    alert: 'Re-check after the visitor has rested, and refer if it does not '
        'settle.',
  );
}

/// Breaths per minute. Normal adult 12–20.
RateVerdict? interpretRespRate(Object? cpm) {
  final v = _wholeNumber(cpm);
  if (v == null) return null;
  if (v < 12)
    return const RateVerdict(label: 'Slow (Bradypnea)', band: VitalBand.watch);
  if (v <= 20)
    return const RateVerdict(label: 'Normal', band: VitalBand.normal);
  return const RateVerdict(
    label: 'Fast (Tachypnea)',
    band: VitalBand.high,
    alert: 'Assess breathing effort now and refer if in distress.',
  );
}

/// Percent oxygen in the blood. 95–100 is normal, 91–94 is below normal, and 90
/// or lower is the one on this form that carries a red alert rather than a pill.
RateVerdict? interpretSpO2(Object? percent) {
  final v = _wholeNumber(percent);
  if (v == null) return null;
  if (v <= 90) {
    return const RateVerdict(
      label: 'Low (Hypoxemia)',
      band: VitalBand.critical,
      alert: 'Low oxygen. Notify the nurse or physician now.',
    );
  }
  if (v < 95)
    return const RateVerdict(label: 'Below Normal', band: VitalBand.watch);
  return const RateVerdict(label: 'Normal', band: VitalBand.normal);
}

// ── THE FORM'S VOCABULARY ────────────────────────────────────────────────────

/// A symptom the nurse can tick, and whether it is one of the warning signs.
///
/// The warning signs are the symptoms that change what a high reading means, so
/// they are part of the data rather than a bolded run of chips: the red banner
/// and the consultation prompt are both driven off [isWarning] and neither has
/// to restate the list.
class BpSymptom {
  const BpSymptom(this.label, {this.isWarning = false});

  final String label;

  /// A symptom that needs acting on now rather than noted.
  final bool isWarning;
}

/// The symptoms asked for at the time of the reading, in the order they are
/// offered. "None" is [kNoSymptom] and is exclusive of the rest — see
/// [withSymptomToggled].
const String kNoSymptom = 'None';

const List<BpSymptom> kBpSymptoms = [
  BpSymptom(kNoSymptom),
  BpSymptom('Headache'),
  BpSymptom('Dizziness'),
  BpSymptom('Nausea'),
  BpSymptom('Palpitations (pounding heartbeat)'),
  BpSymptom('Blurred vision', isWarning: true),
  BpSymptom('Chest pain', isWarning: true),
  BpSymptom('Shortness of breath', isWarning: true),
  BpSymptom('Fainting', isWarning: true),
  BpSymptom('Weakness or numbness', isWarning: true),
  BpSymptom('Confusion', isWarning: true),
];

/// The symptoms that are warning signs, as a set, so a saved record can be
/// re-checked without walking the list.
final Set<String> kBpWarningSymptoms = {
  for (final s in kBpSymptoms)
    if (s.isWarning) s.label,
};

/// Ticks or unticks a symptom, keeping "None" honest.
///
/// "None" is exclusive in both directions, which is the part that is easy to get
/// wrong: ticking "None" beside a ticked "Chest pain" would leave a record
/// saying the visitor had a warning sign and none at the same time, and ticking
/// any symptom has to let "None" go.
List<String> withSymptomToggled(List<String> current, String symptom) {
  final next = List<String>.from(current);
  if (symptom == kNoSymptom) {
    return next.contains(kNoSymptom) ? const [] : [kNoSymptom];
  }
  next.remove(kNoSymptom);
  if (!next.remove(symptom)) next.add(symptom);
  return next;
}

/// Whether any warning sign is ticked.
bool hasWarningSign(Iterable<String> symptoms) =>
    symptoms.any(kBpWarningSymptoms.contains);

// ── VALIDATION ───────────────────────────────────────────────────────────────

/// The bounds a reading has to sit inside before it can be saved.
///
/// A hard limit, not a band: 400 mmHg is a typo, not a finding, and the clinic's
/// own rule has no meaning for it. [min]/[max] are inclusive.
class VitalLimit {
  const VitalLimit(this.min, this.max);

  final int min;
  final int max;

  bool accepts(int? v) => v != null && v >= min && v <= max;

  /// "Enter a value between 50 and 300." — the sentence the form prints under
  /// the box, so the number the nurse typed against is named in the same units
  /// as the box.
  String get errorText => 'Enter a value between $min and $max.';
}

/// The limits on the BP Taking form, in one place so a field and its validator
/// cannot drift apart.
abstract final class BpLimits {
  static const VitalLimit systolic = VitalLimit(50, 300);
  static const VitalLimit diastolic = VitalLimit(30, 200);
  static const VitalLimit pulse = VitalLimit(20, 250);
  static const VitalLimit respRate = VitalLimit(4, 60);
  static const VitalLimit spo2 = VitalLimit(50, 100);

  /// The gap between the two numbers, outside which the reading is probably a
  /// slip rather than a measurement. A warning only — the reading is still
  /// saved, because the nurse was there and the nurse is not wrong.
  static const int minPulsePressure = 20;
  static const int maxPulsePressure = 100;

  static const String unusualDifferenceWarning =
      'Unusual difference between the two numbers. Please recheck the reading.';

  static const String systolicMustBeHigher =
      'Systolic must be higher than diastolic.';

  /// Whether one half of a blood pressure is a real number to save.
  static bool systolicOk(int? v) => systolic.accepts(v);
  static bool diastolicOk(int? v) => diastolic.accepts(v);
  static bool pulseOk(int? v) => pulse.accepts(v);
  static bool respRateOk(int? v) => respRate.accepts(v);
  static bool spo2Ok(int? v) => spo2.accepts(v);

  /// The soft warning for a plausible-but-odd pair, or null when the difference
  /// is ordinary or one of the two is not a real number yet.
  static String? differenceWarning(int? sys, int? dia) {
    if (!systolicOk(sys) || !diastolicOk(dia)) return null;
    if (sys! <= dia!) return null;
    final gap = sys - dia;
    if (gap < minPulsePressure || gap > maxPulsePressure) {
      return unusualDifferenceWarning;
    }
    return null;
  }
}

// ── THE NOTE THE FORM SUGGESTS ───────────────────────────────────────────────

/// "BP 148/92 mmHg (High — Grade 1 range), pulse 78 bpm (Normal). Right arm,
/// sitting, rested 5 minutes."
///
/// Built from what was actually entered, so it cannot claim a rested reading or
/// a normal pulse that nobody recorded. This is only ever a STARTING POINT for
/// the notes box: the button that applies it fills an empty box or appends after
/// a line break, and never overwrites what the nurse typed.
String bpSuggestedNote({
  BpResult? bp,
  int? pulseBpm,
  String? arm,
  String? position,
  bool rested = false,
}) {
  final parts = <String>[];
  if (bp != null) {
    parts.add('BP ${bp.reading.compact} mmHg (${bp.label})');
  }
  if (pulseBpm != null && BpLimits.pulseOk(pulseBpm)) {
    final v = interpretPulse(pulseBpm);
    parts.add('pulse $pulseBpm bpm${v == null ? '' : ' (${v.label})'}');
  }
  if (parts.isEmpty) return '';
  final technique = <String>[
    if (arm != null && arm.trim().isNotEmpty) arm.trim().toLowerCase(),
    if (position != null && position.trim().isNotEmpty)
      position.trim().toLowerCase(),
    if (rested) 'rested 5 minutes',
  ];
  if (technique.isNotEmpty) parts.add(technique.join(', '));
  return '${parts.join(', ')}.';
}

// ── THE GUIDE THE FORM SHOWS ─────────────────────────────────────────────────

/// One row of the BP guide's category table. The row matching the current
/// result is highlighted and tagged "Current", so a nurse can see where the
/// number they just took sits in the table rather than being told.
class BpGuideRow {
  const BpGuideRow(this.severity, this.systolicRange, this.diastolicRange);

  final BpSeverity severity;
  final String systolicRange;
  final String diastolicRange;
}

/// The table under "Blood Pressure Guide", printed from whichever standard is
/// active so the guide and the result card can never quote different numbers.
List<BpGuideRow> bpGuideRows([BpStandard? standard]) {
  final config = (standard ?? BpStandard.active).config;
  return [
    for (final s in BpSeverity.values)
      BpGuideRow(
        s,
        config.systolicRangeFor(s),
        config.diastolicRangeFor(s),
      ),
  ];
}

/// The note printed under the guide's table. The `and/or` in every cell needs
/// saying once, in words, or the table reads as though both numbers have to
/// agree.
const String kBpGuideTableNote =
    'If the two numbers fall in different categories, the higher category '
    'applies. Low blood pressure matters most when there is dizziness, '
    'fainting or weakness.';

const String kBpGuideHowToRead =
    'Blood pressure is written as systolic / diastolic, measured in mmHg. '
    'Systolic (upper number) is the pressure when the heart beats. Diastolic '
    '(lower number) is the pressure when the heart rests between beats.';

const String kBpGuideAccurateReading =
    'Let the visitor sit and rest for 5 minutes. Back supported, feet flat, '
    'arm bare and resting at heart level, correct cuff size. No talking. No '
    'caffeine, smoking or exercise for 30 minutes before. If the first reading '
    'is high, repeat after 1–2 minutes and use the average.';

const String kBpGuideImportant =
    'One reading does not diagnose hypertension. A physician confirms it using '
    'repeated readings on separate visits. Categories follow the 2020 '
    'Philippine hypertension guideline (hypertension = office BP 140/90 or '
    'higher) and ISH 2020. The clinic physician\'s judgment comes first.';

/// The one-line explanations behind the ⓘ on the optional fields.
const Map<String, String> kVitalFieldHelp = {
  'pulse': 'Heartbeats per minute at rest. Normal adult: 60–100. Below 60 is '
      'slow (bradycardia), which can be normal in athletes. Above 100 is fast '
      '(tachycardia).',
  'resp_rate': 'Breaths per minute at rest. Normal adult: 12–20. Below 12 is '
      'slow (bradypnea). Above 20 is fast (tachypnea).',
  'spo2': 'Percent of oxygen in the blood, from a pulse oximeter. Normal: '
      '95–100%. 91–94% is below normal. 90% or lower is low and needs '
      'immediate attention.',
};
