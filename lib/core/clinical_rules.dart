import 'clinic_purposes.dart';

/// How far a reading sits from the normal screening range. These are screening
/// bands for the clinic nurse, not a diagnosis — the wording in the UI always
/// says "flagged" and leaves the call to the staff member.
enum InsightSeverity { normal, watch, alert }

/// One reading, what it means, and what to do about it.
class VitalInsight {
  const VitalInsight({
    required this.key,
    required this.label,
    required this.reading,
    required this.severity,
    required this.finding,
    required this.action,
    this.medicineHints = const [],
    this.derived = false,
  });

  /// The `details` key this reading came from, e.g. `bloodPressure`.
  final String key;
  final String label;
  final String reading;
  final InsightSeverity severity;

  /// Short plain-language name for the band, e.g. "Hypertensive range".
  final String finding;

  /// What the nurse should do next.
  final String action;

  /// Words used to look for relevant stock in the inventory. Never a
  /// prescription on its own — the suggestions are pre-filtered for the nurse
  /// to confirm.
  final List<String> medicineHints;

  /// True when this reading was worked out from others (BMI from height and
  /// weight) instead of typed in directly.
  final bool derived;

  bool get isAbnormal => severity != InsightSeverity.normal;
}

/// A stocked item the nurse could plausibly ask for, matched against a name
/// from the inventory. A pre-filter for the supplies list, not a prescription.
class MedicineSuggestion {
  const MedicineSuggestion({
    required this.match,
    required this.reason,
    required this.term,
  });

  /// The inventory item's name.
  final String match;

  /// The flagged reading that made it show up.
  final String reason;

  /// The word that matched inside the name.
  final String term;
}

/// Everything the recorded procedure details say about the patient right now.
class VitalsAnalysis {
  const VitalsAnalysis(this.readings);

  final List<VitalInsight> readings;

  List<VitalInsight> get all => readings;
  List<VitalInsight> get abnormal =>
      readings.where((r) => r.isAbnormal).toList();
  List<VitalInsight> get derived => readings.where((r) => r.derived).toList();
  bool get hasAny => readings.isNotEmpty;
  bool get hasAbnormal => abnormal.isNotEmpty;

  /// One sentence for the summary strip.
  String get headline {
    if (readings.isEmpty) return 'No measurements recorded yet';
    if (!hasAbnormal) {
      return '${readings.length} reading${readings.length == 1 ? '' : 's'}, all in range';
    }
    final n = abnormal.length;
    return '$n reading${n == 1 ? '' : 's'} flagged: ${abnormal.map((a) => a.label).join(', ')}';
  }

  /// Findings text ready to paste into the Findings box.
  String get findingsText => all
      .map((r) => '${r.label}: ${r.reading} — ${r.finding}. ${r.action}')
      .join('\n');

  /// Looks for stocked items that match the flagged readings, e.g. an
  /// antipyretic for a fever or an antiseptic for a wound.
  List<MedicineSuggestion> medicineSuggestions(List<String> inventoryNames) {
    final out = <MedicineSuggestion>[];
    final seen = <String>{};
    for (final r in abnormal) {
      for (final term in r.medicineHints) {
        for (final name in inventoryNames) {
          if (!name.toLowerCase().contains(term)) continue;
          if (!seen.add(name.toLowerCase())) continue;
          out.add(
              MedicineSuggestion(match: name, reason: r.finding, term: term));
        }
      }
    }
    return out;
  }
}

/// Screening rules for the readings the clinic records.
class ClinicalRules {
  const ClinicalRules._();

  static double? num_(String? raw) {
    if (raw == null) return null;
    final cleaned = raw.replaceAll(RegExp(r'[^0-9.]'), '').trim();
    if (cleaned.isEmpty) return null;
    return double.tryParse(cleaned);
  }

  /// Packs a "120/80" style reading into one number so it can travel inside
  /// the ints-only part of the analysis. The diastolic is carried in the last
  /// three digits: a x1000 multiplier, *not* x100, because a diastolic of
  /// 100 (100/70 -> 10070 vs 100/100 -> 10100) would otherwise carry into the
  /// systolic and read back as 101/0.
  static const int _bpScale = 1000;

  static int? bp(String? raw) {
    if (raw == null) return null;
    final parts =
        raw.split(RegExp(r'[/\\-]')).where((s) => s.trim().isNotEmpty).toList();
    if (parts.length < 2) return null;
    final sys = num_(parts[0]);
    final dia = num_(parts[1]);
    if (sys == null || dia == null) return null;
    return (sys * _bpScale + dia).round();
  }

  /// Turns the free-text `details` bag of a procedure record into readings.
  /// Anything missing is simply skipped, so a partial record (one person, one
  /// procedure, one field filled) still analyses cleanly.
  static VitalsAnalysis analyze(Map<String, String> details) {
    final out = <VitalInsight>[];

    final bpRaw = details['bloodPressure'];
    final bpv = bp(bpRaw);
    if (bpRaw != null && bpRaw.trim().isNotEmpty && bpv != null) {
      final sys = (bpv / _bpScale).floor();
      final dia = bpv % _bpScale;
      InsightSeverity sev;
      String finding;
      String action;
      if (sys < 90 || dia < 60) {
        sev = InsightSeverity.alert;
        finding = 'Low blood pressure';
        action =
            'Let the patient lie down, re-check after 5 minutes, and escalate if it does not recover.';
      } else if (sys >= 140 || dia >= 90) {
        sev = InsightSeverity.alert;
        finding = 'High blood pressure';
        action =
            'Seat the patient for 5 minutes, take a second reading, and refer if it stays high.';
      } else if (sys >= 130 || dia >= 85) {
        sev = InsightSeverity.watch;
        finding = 'Blood pressure slightly raised';
        action =
            'Advise rest, less salt and caffeine, then re-check on the next visit.';
      } else {
        sev = InsightSeverity.normal;
        finding = 'Within range';
        action = 'Nothing to follow up on.';
      }
      out.add(VitalInsight(
        key: 'bloodPressure',
        label: 'Blood Pressure',
        reading: '$sys/$dia mmHg',
        severity: sev,
        finding: finding,
        action: action,
        medicineHints: sev == InsightSeverity.normal
            ? const []
            : const [
                'amlodipine',
                'losartan',
                'captopril',
                'nifedipine',
                'antihypertensive'
              ],
      ));
    }

    final t = num_(details['temperature']);
    if (t != null && t.isFinite) {
      InsightSeverity sev;
      String finding;
      String action;
      if (t < 35) {
        sev = InsightSeverity.alert;
        finding = 'Very low temperature';
        action = 'Warm the patient and refer for urgent assessment.';
      } else if (t >= 38) {
        sev = InsightSeverity.alert;
        finding = 'Fever';
        action =
            'Ask about chills and flu symptoms, advise fluids and rest, and consider an antipyretic.';
      } else if (t >= 37.5) {
        sev = InsightSeverity.watch;
        finding = 'Low-grade fever';
        action = 'Re-check after 2 hours and advise fluids and rest.';
      } else {
        sev = InsightSeverity.normal;
        finding = 'Within range';
        action = 'Nothing to follow up on.';
      }
      out.add(VitalInsight(
        key: 'temperature',
        label: 'Temperature',
        reading: '$t°C',
        severity: sev,
        finding: finding,
        action: action,
        medicineHints: sev == InsightSeverity.normal
            ? const []
            : const ['paracetamol', 'biogesic', 'ibuprofen', 'antipyretic'],
      ));
    }

    final p = num_(details['pulseRate']);
    if (p != null && p.isFinite) {
      InsightSeverity sev;
      String finding;
      String action;
      if (p < 50 || p > 120) {
        sev = InsightSeverity.alert;
        finding = p < 50 ? 'Slow pulse' : 'Fast pulse';
        action =
            'Re-check after the patient has been resting and escalate if it persists.';
      } else if (p < 60 || p > 100) {
        sev = InsightSeverity.watch;
        finding = p < 60 ? 'Pulse on the low side' : 'Pulse on the high side';
        action = 'Re-check after 10 minutes of rest.';
      } else {
        sev = InsightSeverity.normal;
        finding = 'Within range';
        action = 'Nothing to follow up on.';
      }
      out.add(VitalInsight(
        key: 'pulseRate',
        label: 'Pulse Rate',
        reading: '$p bpm',
        severity: sev,
        finding: finding,
        action: action,
        medicineHints: sev == InsightSeverity.normal
            ? const []
            : const ['propranolol', 'salbutamol'],
      ));
    }

    final r = num_(details['respRate']);
    if (r != null && r.isFinite) {
      InsightSeverity sev;
      String finding;
      String action;
      if (r < 10 || r > 24) {
        sev = InsightSeverity.alert;
        finding = r < 10 ? 'Slow breathing' : 'Fast breathing';
        action =
            'Assess breathing effort now and refer if the patient is in distress.';
      } else if (r < 12 || r > 20) {
        sev = InsightSeverity.watch;
        finding =
            r < 12 ? 'Breathing slightly slow' : 'Breathing slightly fast';
        action = 'Re-check after the patient has been sitting for 5 minutes.';
      } else {
        sev = InsightSeverity.normal;
        finding = 'Within range';
        action = 'Nothing to follow up on.';
      }
      out.add(VitalInsight(
        key: 'respRate',
        label: 'Respiratory Rate',
        reading: '$r breaths/min',
        severity: sev,
        finding: finding,
        action: action,
        medicineHints: sev == InsightSeverity.normal
            ? const []
            : const ['salbutamol', 'ipratropium', 'neb'],
      ));
    }

    final o = num_(details['spo2']);
    if (o != null && o.isFinite) {
      InsightSeverity sev;
      String finding;
      String action;
      if (o < 90) {
        sev = InsightSeverity.alert;
        finding = 'Oxygen saturation critically low';
        action =
            'Start oxygen, check for a chest complaint and refer urgently.';
      } else if (o < 95) {
        sev = InsightSeverity.watch;
        finding = 'Oxygen saturation on the low side';
        action =
            'Re-check after the patient has rested and is breathing calmly.';
      } else {
        sev = InsightSeverity.normal;
        finding = 'Within range';
        action = 'Nothing to follow up on.';
      }
      out.add(VitalInsight(
        key: 'spo2',
        label: 'Oxygen Saturation',
        reading: '$o%',
        severity: sev,
        finding: finding,
        action: action,
        medicineHints: sev == InsightSeverity.normal
            ? const []
            : const ['salbutamol', 'oxygen'],
      ));
    }

    final g = num_(details['glucoseLevel']);
    if (g != null && g.isFinite) {
      InsightSeverity sev;
      String finding;
      String action;
      if (g < 70) {
        sev = InsightSeverity.alert;
        finding = 'Blood sugar low';
        action =
            'Give a sweet drink or snack, re-check after 15 minutes, and refer if it does not recover.';
      } else if (g >= 200) {
        sev = InsightSeverity.alert;
        finding = 'Blood sugar high';
        action =
            'Advise water and no sugary food, and refer for a medical check.';
      } else if (g >= 140) {
        sev = InsightSeverity.watch;
        finding = 'Blood sugar raised';
        action =
            'Repeat the test before the next meal and ask about the last meal.';
      } else {
        sev = InsightSeverity.normal;
        finding = 'Within range';
        action = 'Nothing to follow up on.';
      }
      out.add(VitalInsight(
        key: 'glucoseLevel',
        label: 'Blood Glucose',
        reading: '$g mg/dL',
        severity: sev,
        finding: finding,
        action: action,
        medicineHints:
            sev == InsightSeverity.normal ? const [] : const ['metformin'],
      ));
    }

    final h = num_(details['height']);
    final w = num_(details['weight']);
    final typedBmi = num_(details['bmi']);
    double? bmi;
    bool bmiDerived = false;
    if (typedBmi != null && typedBmi.isFinite) {
      bmi = typedBmi;
    } else if (h != null && h.isFinite && w != null && w.isFinite && h > 0) {
      // Worked out here so the nurse does not have to divide by height twice.
      bmi = w / ((h / 100) * (h / 100));
      bmiDerived = true;
    }
    if (bmi != null) {
      out.add(_bmiInsight('bmi', bmi, bmiDerived));
    }

    return VitalsAnalysis(out);
  }

  static VitalInsight _bmiInsight(String key, double bmi, bool derived) {
    final value = double.parse(bmi.toStringAsFixed(1));
    InsightSeverity sev;
    String finding;
    String action;
    if (value < 18.5) {
      sev = InsightSeverity.watch;
      finding = 'Underweight';
      action = 'Suggest a higher-calorie diet and re-check at the next visit.';
    } else if (value < 25) {
      sev = InsightSeverity.normal;
      finding = 'Within range';
      action = 'Nothing to follow up on.';
    } else if (value < 30) {
      sev = InsightSeverity.watch;
      finding = 'Overweight';
      action = 'Advise on diet and activity, and re-weigh at the next visit.';
    } else {
      sev = InsightSeverity.alert;
      finding = 'Obese range';
      action = 'Refer for a medical check and record the blood pressure today.';
    }
    return VitalInsight(
      key: key,
      label: 'BMI',
      reading: '$value',
      severity: sev,
      finding: finding,
      action: action,
      derived: derived,
      medicineHints: sev == InsightSeverity.normal
          ? const []
          : const ['vitamin', 'metformin'],
    );
  }
}

/// What the checklist for a set of purposes looks like: the fields the clinic
/// has to fill in for this visit, the procedures to offer first, the result
/// that can be recorded, and the extras the UI shows.
class PurposePlan {
  const PurposePlan({
    required this.purposes,
    required this.suggestedProcedures,
    required this.fields,
    required this.outcomes,
    required this.wantsVitals,
    required this.wantsMedicine,
    required this.wantsAttachment,
    required this.attachmentNote,
    required this.records,
  });

  final List<ClinicPurpose> purposes;

  /// Catalog procedure names to offer as one-tap suggestions, in purpose order.
  final List<String> suggestedProcedures;

  /// Every field the chosen purposes need, de-duplicated by key and kept in
  /// purpose order. This is the whole form for the visit: a BP visit gets a
  /// blood pressure and a pulse, not a wound type and an eye test.
  final List<PurposeField> fields;

  /// The results that can be recorded for this visit, de-duplicated and in
  /// purpose order. Empty only when a purpose declares no outcomes.
  final List<String> outcomes;

  final bool wantsVitals;
  final bool wantsMedicine;
  final bool wantsAttachment;
  final String? attachmentNote;

  /// One line per purpose describing what gets recorded.
  final String records;

  /// True when the visit's own fields cover a reading the screening rules can
  /// band, which is what makes the automatic findings box worth showing.
  bool get screensReadings => fields.any((f) => _screenedKeys.contains(f.key));

  static const Set<String> _screenedKeys = {
    'bloodPressure',
    'temperature',
    'pulseRate',
    'respRate',
    'spo2',
    'glucoseLevel',
    'height',
    'weight',
    'bmi',
  };

  static PurposePlan forPurposes(List<ClinicPurpose> purposes) {
    final procs = <String>[];
    final fieldList = <PurposeField>[];
    final fieldKeys = <String>{};
    final outcomeList = <String>[];
    final notes = <String>[];
    String? note;
    for (final p in purposes) {
      for (final name in p.procedures) {
        if (!procs.contains(name)) procs.add(name);
      }
      // First purpose to ask for a field owns it, so a BP + wound visit shows
      // the BP boxes first and the wound boxes after.
      for (final f in p.fields) {
        if (fieldKeys.add(f.key)) fieldList.add(f);
      }
      for (final o in p.outcomes) {
        if (!outcomeList.contains(o)) outcomeList.add(o);
      }
      if (!notes.contains(p.records)) notes.add(p.records);
      if (p.attachment && p.attachmentNote != null && note == null) {
        note = p.attachmentNote;
      }
    }
    return PurposePlan(
      purposes: purposes,
      suggestedProcedures: procs,
      fields: fieldList,
      outcomes: outcomeList,
      wantsVitals: purposes.any((p) => p.vitals),
      wantsMedicine: purposes.any((p) => p.medicine),
      wantsAttachment: purposes.any((p) => p.attachment),
      attachmentNote: note,
      records: notes.join('\n'),
    );
  }

  /// Fallback used when the visit text matches no purpose, so the screen still
  /// works with a free-typed reason. No fields and no outcomes: the form then
  /// falls back to whatever the selected procedure itself asks for.
  static PurposePlan empty() => PurposePlan(
        purposes: const [],
        suggestedProcedures: const [],
        fields: const [],
        outcomes: const [],
        wantsVitals: true,
        wantsMedicine: true,
        wantsAttachment: false,
        attachmentNote: null,
        records: '',
      );
}
