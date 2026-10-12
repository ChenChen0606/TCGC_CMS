// ─────────────────────────────────────────────────────────────────────────────
//  vitals_bands.dart
//  The shared vocabulary of a screening band, and nothing else.
//
//  WHY THESE FOUR DECLARATIONS LIVE ALONE
//  A "band" — normal, watch, high, critical — is the one word every screen
//  agrees on, and the colour and icon that go with it. `vitals.dart` builds
//  thresholds out of them and `vitals_interpretation.dart` decides which band a
//  typed number fell into. Both need this file, and neither needs the other, so
//  it sits underneath both rather than one of them importing the other and the
//  two circling round.
//
//  `vitals.dart` re-exports this file, so every existing `import 'vitals.dart'`
//  still finds VitalBand exactly where it did.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:flutter/material.dart';

/// How far a reading sits from the clinic's normal range. Four steps, and the
/// colour of a pill is this and nothing else — so a "High" pill always means the
/// same thing on every screen.
enum VitalBand {
  /// Below the normal range rather than above it. Its own band, and blue, because
  /// "Low" and "High" cannot share a colour on a pill: a low blood pressure is
  /// asked about and re-checked, a high one is acted on, and a nurse glancing at
  /// a blue pill and a red one should not have to read the word to tell.
  low,

  /// Inside the normal range.
  normal,

  /// Outside it, but not urgent. Re-check and advise.
  watch,

  /// Clearly out of range. Act on it during the visit.
  high,

  /// Out of range to the point of immediate referral.
  critical,
}

/// Colour + icon for a band. Lives beside the enum so no two screens can band a
/// reading one colour and its icon another.
extension VitalBandStyle on VitalBand {
  Color get color => switch (this) {
        VitalBand.low => const Color(0xFF2563EB),
        VitalBand.normal => const Color(0xFF16A34A),
        VitalBand.watch => const Color(0xFFEAB308),
        VitalBand.high => const Color(0xFFEA580C),
        VitalBand.critical => const Color(0xFFDC2626),
      };

  Color get container => color.withValues(alpha: 0.12);

  IconData get icon => switch (this) {
        VitalBand.low => Icons.trending_down_rounded,
        VitalBand.normal => Icons.check_circle_outline_rounded,
        VitalBand.watch => Icons.error_outline_rounded,
        VitalBand.high => Icons.warning_amber_rounded,
        VitalBand.critical => Icons.emergency_outlined,
      };

  /// The word a status pill would use, if one ever needs the band alone.
  String get label => switch (this) {
        VitalBand.low => 'Low',
        VitalBand.normal => 'Normal',
        VitalBand.watch => 'Watch',
        VitalBand.high => 'High',
        VitalBand.critical => 'Critical',
      };

  /// What the band means said in a sentence a nurse can act on.
  ///
  /// Deliberately not a diagnosis and deliberately not advice: it is the
  /// "so what" of a band, and it is the same for every reading in that band.
  /// The reading's own [VitalReading.category] carries what *this* number is
  /// called; this carries what the clinic does about it.
  String get conclusion => switch (this) {
        VitalBand.low =>
          'Below the range this reading is normally expected to sit in. Worth '
              'asking about and re-checking before the visitor leaves.',
        VitalBand.normal =>
          'Inside the normal range for this reading — nothing to flag.',
        VitalBand.watch =>
          'Just outside the normal range. Worth re-checking before the '
              'visitor leaves.',
        VitalBand.high =>
          'Outside the normal range. Flag it for the clinician before the '
              'visitor leaves.',
        VitalBand.critical =>
          'Out of range to the point of referral. Act on this now.',
      };
}

/// One measured value and where it landed.
class VitalReading {
  const VitalReading({
    required this.key,
    required this.label,
    required this.value,
    required this.display,
    required this.band,
    this.unit = '',
    this.category,
    this.alert,
  });

  /// Which reading this is — matches the `visit_vitals` column family, e.g.
  /// `heart_rate`, and the `vitals_config.key` the band came from.
  final String key;

  final String label;

  /// The raw number, so a caller can store it without re-parsing [display].
  final num value;

  /// How the reading is shown, e.g. `120/80 mmHg`.
  final String display;

  final VitalBand band;

  final String unit;

  /// The named range it landed in — `Normal`, `Hypertension Stage 1`,
  /// `Low-grade fever`. This is the word the clinician reads and the word stored
  /// against the reading, and it is deliberately NOT derived from [band]: four
  /// readings can all be [VitalBand.watch] while being called "Elevated",
  /// "Low", "Underweight" and "Low-grade fever".
  final String? category;

  /// Present only for the bands that mean "do something now" — the banner
  /// under the field reads it.
  final String? alert;

  bool get isAbnormal => band != VitalBand.normal;

  /// The wording the Notes suggestion is built from, e.g.
  /// `BP 120/80 mmHg (Normal)`.
  String get notesFragment => '$label $display (${category ?? band.label})';
}

/// One horizontal step of a threshold table: "up to [max] this is called
/// [label] and belongs in [band]". A null [max] closes the table.
class VitalThresholdBand {
  const VitalThresholdBand({
    required this.max,
    required this.label,
    required this.band,
    this.alert,
  });

  final double? max;
  final String label;
  final VitalBand band;
  final String? alert;
}
