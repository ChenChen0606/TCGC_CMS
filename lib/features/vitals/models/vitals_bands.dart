import 'package:flutter/material.dart';

enum VitalBand {
  low,

  normal,

  watch,

  high,

  critical,
}

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

  String get label => switch (this) {
        VitalBand.low => 'Low',
        VitalBand.normal => 'Normal',
        VitalBand.watch => 'Watch',
        VitalBand.high => 'High',
        VitalBand.critical => 'Critical',
      };

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

  final String key;

  final String label;

  final num value;

  final String display;

  final VitalBand band;

  final String unit;

  final String? category;

  final String? alert;

  bool get isAbnormal => band != VitalBand.normal;

  String get notesFragment => '$label $display (${category ?? band.label})';
}

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
