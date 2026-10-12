import 'package:flutter/material.dart';

/// One box on a purpose's form.
///
/// The `key` is the name the reading is stored and screened under, so the
/// measurement keys here (`bloodPressure`, `temperature`, …) are the ones
/// `ClinicalRules` knows how to interpret. A purpose field the rules don't know
/// is simply kept as typed text.
class PurposeField {
  final String key;
  final String label;
  final String type; // 'text' | 'number' | 'dropdown' | 'multiline'
  final String? unit;
  final List<String>? options;
  const PurposeField({
    required this.key,
    required this.label,
    this.type = 'text',
    this.unit,
    this.options,
  });
}

/// The measurements the clinic can take, declared once so a purpose spells its
/// form as "BP and pulse" instead of repeating units, labels and formats in
/// eleven places. The keys are the ones `ClinicalRules` screens, so a reading
/// entered here is banded automatically.
class _Vitals {
  static const PurposeField bp =
      PurposeField(key: 'bloodPressure', label: 'Blood pressure', unit: 'mmHg');
  static const PurposeField pulse = PurposeField(
      key: 'pulseRate', label: 'Pulse rate', type: 'number', unit: 'bpm');
  static const PurposeField temp = PurposeField(
      key: 'temperature', label: 'Temperature', type: 'number', unit: '°C');
  static const PurposeField weight =
      PurposeField(key: 'weight', label: 'Weight', type: 'number', unit: 'kg');
  static const PurposeField height =
      PurposeField(key: 'height', label: 'Height', type: 'number', unit: 'cm');
}

/// One reason a patient comes to the clinic, plus everything the rest of the
/// app needs to know about it.
///
/// This is the single source of truth for the clinic's list of purposes. The
/// Clinic Visit form offers them and the Dashboard's "Top Reason for Visit"
/// counts them — so the two screens can never drift apart the way a duplicated
/// list does.
class ClinicPurpose {
  const ClinicPurpose({
    required this.id,
    required this.label,
    required this.short,
    required this.icon,
    required this.keywords,
    required this.procedures,
    required this.fields,
    required this.outcomes,
    this.vitals = false,
    this.medicine = false,
    this.attachment = false,
    this.attachmentNote,
  });

  /// Stable key used in saved records, e.g. `bp_tracking`.
  final String id;

  /// What the clinic calls it, e.g. `BP tracking`.
  final String label;

  /// Shorter form for chips and narrow columns.
  final String short;

  final IconData icon;

  /// Words that identify this purpose inside a free-text reason. A visit row
  /// only stores text, so the Dashboard buckets it with these.
  final List<String> keywords;

  /// Names of the procedures this purpose normally needs recorded. Used to
  /// decide whether a visit must log a pending procedure row.
  final List<String> procedures;

  /// Exactly what the clinic needs to write down for this purpose — and nothing
  /// more. This is the whole point of the list: a BP visit asks for a blood
  /// pressure and a pulse, it does not ask for a wound type or an eye test.
  /// Order is the order the boxes are shown in.
  final List<PurposeField> fields;

  /// What the clinic walks away with, i.e. the RESULT recorded against the
  /// visit. Derived from the reading wherever `ClinicalRules` can screen one
  /// (a blood pressure is banded automatically), and typed where it cannot.
  final List<String> outcomes;

  /// One line describing what actually gets recorded for this purpose, shown
  /// under the purpose picker so staff know what the next screen will ask.
  /// Generated from [fields] + [outcomes] so the preview can never describe a
  /// form the visit step does not actually show.
  String get records =>
      '${fields.map((f) => f.unit == null ? f.label : '${f.label} (${f.unit})').join(', ')} — then the result';

  /// Whether vital signs belong on the checklist for this purpose.
  final bool vitals;

  /// Whether asking for medicine / supplies makes sense for this purpose.
  /// Certificate and counselling visits, for example, never dispense anything.
  final bool medicine;

  /// Whether a file or picture can be attached (lab result, wound photo,
  /// request letter for a certificate).
  final bool attachment;

  /// Why an attachment is allowed here, shown as the picker hint.
  final String? attachmentNote;
}

/// The services whose detail form is deliberately blank for now.
///
/// The clinic is still finalising these two, so step 3 draws an empty panel
/// instead of the boxes and no answers are asked for. They are listed here
/// rather than checked for at each use because two unrelated questions have to
/// agree about them: the panel has to render nothing, and a form with nothing
/// in it has nothing outstanding, so it must not sit in the way of the
/// Continue button waiting on answers nobody is being asked for.
const Set<String> kBlankFormServiceIds = {
  'medicine_certificate',
  'medical_clearance',
};

/// The clinic's own list of purposes, in the order the clinic lists them.
class ClinicPurposes {
  const ClinicPurposes._();

  /// Where on the body something is. One list, so a wound, an injury and a
  /// burn are always recorded against the same words. Public because the
  /// Clinic Visit form and the procedure screens offer the same words when a
  /// wound or an injury is recorded there.
  static const List<String> bodySites = [
    'Head',
    'Face',
    'Neck',
    'Chest',
    'Back',
    'Abdomen',
    'Left Shoulder',
    'Right Shoulder',
    'Left Arm',
    'Right Arm',
    'Left Elbow',
    'Right Elbow',
    'Left Hand',
    'Right Hand',
    'Left Hip',
    'Right Hip',
    'Left Knee',
    'Right Knee',
    'Left Ankle',
    'Right Ankle',
    'Left Leg',
    'Right Leg',
    'Left Foot',
    'Right Foot',
    'Other',
  ];

  static const List<ClinicPurpose> all = [
    // ── 1. WOUND DRESSING ───────────────────────────────────────────────
    // The clinic needs to know which wound it dressed, what it looked like,
    // what went on it and how much it hurt. Nothing else — a dressing change
    // does not need a blood pressure or a BMI.
    ClinicPurpose(
      id: 'wound_dressing',
      label: 'Wound dressing',
      short: 'Wound',
      icon: Icons.healing_outlined,
      keywords: [
        'wound dressing',
        'dressing change',
        'wound care',
        'wound',
        'cut',
        'laceration',
        'suture',
        'incised wound',
        'abrasion',
      ],
      procedures: [
        'Wound Cleaning',
        'Wound Dressing',
        'Bandaging',
        'Injection / Vaccination',
      ],
      fields: [
        PurposeField(
            key: 'woundSite',
            label: 'Wound site',
            type: 'dropdown',
            options: bodySites),
        PurposeField(
            key: 'woundKind',
            label: 'Wound type',
            type: 'dropdown',
            options: [
              'Abrasion / Scrape',
              'Laceration',
              'Puncture',
              'Burn',
              'Bruise / Contusion',
              'Other',
            ]),
        PurposeField(
            key: 'woundState',
            label: 'Wound condition',
            type: 'dropdown',
            options: [
              'Clean',
              'Mild bleeding',
              'Swollen',
              'Infected',
            ]),
        PurposeField(
            key: 'dressingUsed',
            label: 'Dressing applied',
            type: 'dropdown',
            options: [
              'Sterile Gauze',
              'Adhesive Bandage (Band-Aid)',
              'Elastic Bandage',
              'Non-Stick Pad',
              'Transparent Film Dressing',
              'Micropore Tape Only',
              'Other',
            ]),
        PurposeField(key: 'painScore', label: 'Pain scale', type: 'number'),
      ],
      outcomes: [
        'Healed — no further dressing needed',
        'Dressing changed — return in 2 days',
        'Dressing changed — return in 3 days',
        'Infected — referred to hospital',
      ],
      vitals: false,
      medicine: true,
      attachment: true,
      attachmentNote: 'Photo of the wound before and after dressing (optional)',
    ),

    // ── 2. BP TRACKING ──────────────────────────────────────────────────
    // A BP visit is a reading and a decision. The reading is banded for the
    // nurse automatically; the result records what was decided about it, which
    // is the thing a return visit actually needs to know.
    ClinicPurpose(
      id: 'bp_tracking',
      label: 'BP tracking',
      short: 'BP',
      icon: Icons.favorite_border,
      keywords: [
        'blood pressure',
        'bp tracking',
        'bp monitoring',
        'bp reading',
        'hypertension',
        'high blood pressure',
        'bp',
      ],
      procedures: [
        'Vital Signs Monitoring',
        'Blood Sugar Testing',
        'Referral to Hospital/Doctor',
      ],
      fields: [
        _Vitals.bp,
        _Vitals.pulse,
        PurposeField(
            key: 'onBpMedication',
            label: 'Taking BP medicine?',
            type: 'dropdown',
            options: [
              'Yes — regularly',
              'Yes — sometimes',
              'No',
              'Not sure',
            ]),
        PurposeField(
            key: 'lastBpReading', label: 'Previous BP reading', unit: 'mmHg'),
      ],
      outcomes: [
        'Within range — continue current medication',
        'Slightly raised — lifestyle advice, re-check next visit',
        'High — second reading taken, referred to hospital',
        'High — medication adjusted, follow-up in 1 week',
        'Low — rested and re-checked, referred if it persists',
      ],
      vitals: true,
      medicine: true,
    ),

    // ── 3. TEMPERATURE CHECKING ─────────────────────────────────────────
    // Same shape as a BP visit: the reading decides the result, so only the
    // reading and a pulse are asked for.
    ClinicPurpose(
      id: 'temperature_checking',
      label: 'Temperature checking',
      short: 'Temperature',
      icon: Icons.thermostat_outlined,
      keywords: [
        'temperature',
        'temp check',
        'fever',
        'flu',
        'temp',
      ],
      procedures: ['Vital Signs Monitoring'],
      fields: [
        _Vitals.temp,
        _Vitals.pulse,
      ],
      outcomes: [
        'Normal — no action',
        'Low-grade fever — fluids and rest, re-check in 2 hours',
        'Fever — advised rest and fluids, antipyretic given',
        'Fever — referred to hospital',
      ],
      vitals: true,
      medicine: true,
    ),

    // ── 4. BMI ────────────────────────────────────────────────────
    // Only the two numbers the BMI is worked out from. There is deliberately
    // no BMI box: a typed BMI can disagree with the height and weight beside
    // it, and the rules derive it instead.
    ClinicPurpose(
      id: 'bpi',
      label: 'BMI',
      short: 'BMI',
      icon: Icons.straighten,
      keywords: ['blood pressure index', 'bmi', 'body mass index', 'bpi'],
      procedures: [
        'Height & Weight / BMI',
        'Vital Signs Monitoring',
        'Health Counseling',
      ],
      fields: [
        _Vitals.height,
        _Vitals.weight,
        PurposeField(
            key: 'bmiResult',
            label: 'BMI result',
            type: 'dropdown',
            options: [
              'Underweight',
              'Within range',
              'Overweight',
              'Obese',
              'Referred for medical check',
            ]),
      ],
      outcomes: [
        'Underweight — diet advice given',
        'Within range — nothing to follow up',
        'Overweight — diet and activity advice given',
        'Obese — referred for a medical check',
      ],
      vitals: false,
    ),

    // ── 5. HEALTH COUNSELLING ───────────────────────────────────────────
    // Nothing is measured. What the clinic owes the patient afterwards is the
    // topic and the advice, so that is the entire record — no medicine is
    // issued for this purpose.
    ClinicPurpose(
      id: 'health_counselling',
      label: 'Health counselling',
      short: 'Counselling',
      icon: Icons.forum_outlined,
      keywords: [
        'health counselling',
        'health counseling',
        'counselling',
        'counseling',
        'health education',
        'health advice',
      ],
      procedures: [
        'Health Counseling',
        'Vital Signs Monitoring',
        'Height & Weight / BMI',
      ],
      fields: [
        PurposeField(
            key: 'topic',
            label: 'Topic discussed',
            type: 'dropdown',
            options: [
              'Personal Hygiene',
              'Nutrition & Diet',
              'Mental Health & Stress Management',
              'Reproductive Health',
              'Substance Use Prevention',
              'Sleep Hygiene',
              'Exercise & Physical Activity',
              'Other',
            ]),
        PurposeField(
            key: 'adviceGiven', label: 'Advice given', type: 'multiline'),
      ],
      outcomes: [
        'Resolved — one session',
        'Follow-up session advised',
        'Referred to a specialist',
      ],
    ),

    // ── 6. PRENATAL ─────────────────────────────────────────────────────
    // The three numbers a prenatal check is actually judged on, plus how far
    // along the pregnancy is — without the weeks the weight and BP mean nothing.
    ClinicPurpose(
      id: 'prenatal',
      label: 'Prenatal',
      short: 'Prenatal',
      icon: Icons.child_care_outlined,
      keywords: [
        'prenatal',
        'pre-natal',
        'pregnancy',
        'pregnant',
        'bfp',
        'obstetric',
      ],
      procedures: [
        'Vital Signs Monitoring',
        'Health Counseling',
        'Referral to Hospital/Doctor',
      ],
      fields: [
        PurposeField(
            key: 'gestationalAge',
            label: 'Weeks of pregnancy',
            type: 'number',
            unit: 'weeks'),
        _Vitals.bp,
        _Vitals.weight,
        _Vitals.temp,
      ],
      outcomes: [
        'Normal — continue monthly check-up',
        'Advised on diet and rest, check-up in 2 weeks',
        'Referred to an obstetrician',
      ],
      vitals: true,
      medicine: true,
      attachment: true,
      attachmentNote: 'Lab result or referral letter (optional)',
    ),

    // ── 7. MEDICATION ───────────────────────────────────────────────────
    // What was given and how — the three things a repeat prescription or a
    // stock check has to agree on.
    ClinicPurpose(
      id: 'medication',
      label: 'Medication',
      short: 'Medication',
      icon: Icons.medication_outlined,
      keywords: [
        'medication',
        'prescription',
        'prescribe',
        'refill',
        'medicine',
        'pharmacy',
        'drugs',
      ],
      procedures: [
        'Medication Administration',
        'Injection / Vaccination',
        'Vital Signs Monitoring',
      ],
      fields: [
        PurposeField(
            key: 'medicineName',
            label: 'Medicine name',
            type: 'dropdown',
            options: [
              'Paracetamol',
              'Amoxicillin',
              'Biogesic',
              'Mefenamic Acid',
              'Meclizine',
              'Antacid',
              'Antihistamine',
              'Cough Syrup',
              'Eye Drops',
              'Metoclopramide',
              'Amlodipine',
              'Vitamin C',
              'Other',
            ]),
        PurposeField(key: 'dose', label: 'Dose', type: 'dropdown', options: [
          '1 tablet',
          '2 tablets',
          '1 capsule',
          '5 mL',
          '10 mL',
          '15 mL',
          'Other',
        ]),
        PurposeField(key: 'route', label: 'Route', type: 'dropdown', options: [
          'Oral',
          'Topical',
          'Eye Drop',
          'Other',
        ]),
      ],
      outcomes: [
        'Dispensed from clinic stock',
        'Dispensed with a take-home instruction',
        'Advised to buy over the counter',
        'Prescription issued — patient to buy',
      ],
      vitals: false,
      medicine: true,
    ),

    // ── 8. FIRST AID TREATMENT ──────────────────────────────────────────
    // What was wrong and what was done about it. A first-aid visit that walks
    // out does not need a full vital-sign set.
    ClinicPurpose(
      id: 'first_aid_treatment',
      label: 'First aid treatment',
      short: 'First aid',
      icon: Icons.emergency_outlined,
      keywords: [
        'first aid treatment',
        'first aid',
        'first-aid',
        'burn',
        'sprain',
        'strain',
        'fracture',
        'injury',
        'nosebleed',
        'spillage',
      ],
      procedures: [
        'Burn First Aid',
        'Sprain / Strain First Aid',
        'Splinting / Immobilization',
        'Bandaging',
        'Ice / Cold Compress Application',
        'Wound Cleaning',
      ],
      fields: [
        PurposeField(
            key: 'injurySite',
            label: 'Injury site',
            type: 'dropdown',
            options: bodySites),
        PurposeField(
            key: 'injuryKind',
            label: 'Injury type',
            type: 'dropdown',
            options: [
              'Burn',
              'Sprain',
              'Strain',
              'Fracture / Suspected',
              'Bleeding / Nosebleed',
              'Cut / Laceration',
              'Spillage / Chemical',
              'Other',
            ]),
        PurposeField(
            key: 'firstAidGiven',
            label: 'First aid given',
            type: 'dropdown',
            options: [
              'Cleaned and dressed',
              'Bandaged',
              'Splinted / Immobilised',
              'Cold compress applied',
              'Cooled under running water',
              'Pressure applied',
              'None — referred straight away',
            ]),
      ],
      outcomes: [
        'Treated — discharged',
        'Treated — observed for 30 minutes',
        'Referred to hospital',
      ],
      vitals: false,
      medicine: true,
      attachment: true,
      attachmentNote: 'Photo of the injury (optional)',
    ),

    // ── 9. MEDICINE CONSULTATION ────────────────────────────────────────
    // A consultation is complaint first, so the complaint is the only required
    // box. The readings are triage: taken when the nurse needs them, and
    // screened the moment they are typed.
    ClinicPurpose(
      id: 'medicine_consultation',
      label: 'Medicine consultation',
      short: 'Consultation',
      icon: Icons.medical_information_outlined,
      keywords: [
        'medicine consultation',
        'consultation',
        'checkup',
        'check-up',
        'headache',
        'migraine',
        'cough',
        'cold',
        'sore throat',
        'stomach ache',
        'vomiting',
        'diarrhea',
        'dizziness',
        'body ache',
        'body pain',
        'muscle pain',
        'back pain',
        'toothache',
        'ear pain',
        'allergic',
        'rash',
        'itching',
        'asthma',
        'breathing',
        'chest pain',
        'seizure',
        'faint',
      ],
      procedures: [
        'Vital Signs Monitoring',
        'Blood Sugar Testing',
        'Medication Administration',
        'Referral to Hospital/Doctor',
      ],
      fields: [
        PurposeField(key: 'complaint', label: 'Complaint', type: 'multiline'),
        _Vitals.temp,
        _Vitals.bp,
        _Vitals.pulse,
      ],
      outcomes: [
        'Self-limiting — advised rest, fluids and symptomatic care',
        'Medication given / prescribed',
        'Cleared to return to class',
        'Referred to hospital / specialist',
      ],
      vitals: true,
      medicine: true,
    ),

    // ── 10. MEDICINE CERTIFICATE ────────────────────────────────────────
    // A certificate is a document, so what is recorded is the illness being
    // certified and how long the student is excused. The supporting document
    // is required, not optional.
    ClinicPurpose(
      id: 'medicine_certificate',
      label: 'Medicine certificate',
      short: 'Certificate',
      icon: Icons.description_outlined,
      keywords: [
        'medicine certificate',
        'medical certificate',
        'medcert',
        'certificate',
        'sick leave',
      ],
      procedures: [
        'General Health Screening',
        'Vital Signs Monitoring',
      ],
      fields: [
        PurposeField(
            key: 'illness',
            label: 'Illness / diagnosis certified',
            type: 'dropdown',
            options: [
              'Fever / Flu-like',
              'Dengue',
              'Colds / Cough',
              'Stomach ache',
              'Headache',
              'Injury',
              'Skin condition',
              'Other',
            ]),
        PurposeField(
            key: 'dateOfOnset', label: 'Date of onset', type: 'number'),
        PurposeField(
            key: 'daysOff',
            label: 'Days excused from class',
            type: 'number',
            unit: 'days'),
      ],
      outcomes: [
        'Certificate issued',
        'Certificate issued with a rest recommendation',
        'Certificate declined — see clinic head',
      ],
      vitals: false,
      attachment: true,
      attachmentNote:
          'Required — the request letter or the supporting document',
    ),

    // ── 11. MEDICAL CLEARANCE ───────────────────────────────────────────
    // The one purpose that genuinely needs a full work-up: a clearance is only
    // as good as the exam behind it, so height, weight and blood pressure are
    // all part of the answer.
    ClinicPurpose(
      id: 'medical_clearance',
      label: 'Medical clearance',
      short: 'Clearance',
      icon: Icons.verified_outlined,
      keywords: [
        'medical clearance',
        'clearance',
        'physical exam',
        'pre-employment',
        'medical exam',
      ],
      procedures: [
        'General Health Screening',
        'Vision Screening',
        'Hearing Screening',
        'Vital Signs Monitoring',
        'Height & Weight / BMI',
      ],
      fields: [
        _Vitals.bp,
        _Vitals.height,
        _Vitals.weight,
        PurposeField(
            key: 'visionResult',
            label: 'Vision result',
            type: 'dropdown',
            options: [
              'Normal',
              'Needs referral',
            ]),
        PurposeField(
            key: 'hearingResult',
            label: 'Hearing result',
            type: 'dropdown',
            options: [
              'Normal',
              'Needs referral',
            ]),
        PurposeField(
            key: 'clearanceDecision',
            label: 'Decision',
            type: 'dropdown',
            options: [
              'Cleared',
              'Cleared with conditions',
              'Not cleared — referred',
            ]),
      ],
      outcomes: [
        'Cleared — fit for duty / studies',
        'Cleared with conditions',
        'Not cleared — referred to a physician',
      ],
      vitals: true,
      attachment: true,
      attachmentNote:
          'Required — the request letter or the school/company form',
    ),
    // ── 12. VITAL SIGNS ──────────────────────────────────────────────────
    // The whole set, on one form. This is the general assessment: blood pressure,
    // pulse, temperature, respiratory rate and oxygen saturation, plus the
    // symptoms and remarks that go with them. Where a narrower service (BP
    // Tracking, Temperature Checking) is on the same visit, the reading is still
    // entered once — whichever form declares a vital owns the box, and the rest
    // read the same number.
    ClinicPurpose(
      id: 'vital_signs',
      label: 'Vital signs',
      short: 'Vitals',
      icon: Icons.monitor_heart_outlined,
      keywords: [
        'vital signs',
        'vital signs check',
        'vitals',
        'vital check',
        'general check',
      ],
      procedures: ['Vital Signs Monitoring'],
      fields: [
        _Vitals.bp,
        _Vitals.pulse,
        _Vitals.temp,
      ],
      outcomes: [
        'All readings within range — no action',
        'Raised blood pressure — advised rest and recheck',
        'Fever — advised fluids and rest',
        'Reading outside range — referred to a clinician',
      ],
      vitals: true,
    ),
  ];

  /// The order the clinic works through a visit's services, fixed as a clinical
  /// flow rather than the order services happen to be in the catalog: Vital
  /// Signs opens the visit because the readings are taken first, on arrival,
  /// and the rest of the care lands between them and the "done" checks.
  ///
  /// Services missing from the list (certificates, clearance, "Other") keep
  /// their original relative order after the listed ones, so nothing is dropped
  /// when the clinic adds a new purpose without updating this.
  static const List<String> _workflowOrder = [
    'vital_signs',
    'medicine_consultation',
    'prenatal',
    'wound_dressing',
    'first_aid_treatment',
    'medication',
    'health_counselling',
    'bpi',
    'temperature_checking',
    'bp_tracking',
  ];

  /// [ids] sorted into [workflowOrder] order. Unknown ids come after the listed
  /// ones, still in the order they arrived in, so a purpose the clinic adds
  /// without this list noticing is not silently dropped.
  static List<String> inClinicalOrder(List<String> ids) {
    final order = _workflowOrder;
    final placed = <String>[];
    for (final o in order) {
      if (ids.contains(o)) placed.add(o);
    }
    final rest = [
      for (final id in ids)
        if (!order.contains(id)) id
    ];
    return [...placed, ...rest];
  }

  static ClinicPurpose? byId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final p in all) {
      if (p.id == id) return p;
    }
    return null;
  }

  static ClinicPurpose? byLabel(String? label) {
    if (label == null || label.isEmpty) return null;
    for (final p in all) {
      if (p.label.toLowerCase() == label.toLowerCase()) return p;
    }
    return null;
  }

  /// The single purpose a free-text reason belongs to, or null when it matches
  /// none. When several match, the LONGEST keyword wins, so "medical clearance"
  /// beats "clearance" and "medicine certificate" beats "medicine".
  static ClinicPurpose? match(String text) {
    final t = text.toLowerCase().trim();
    if (t.isEmpty) return null;
    ClinicPurpose? best;
    var bestLen = 0;
    for (final p in all) {
      for (final k in p.keywords) {
        if (k.length > bestLen && t.contains(k)) {
          best = p;
          bestLen = k.length;
        }
      }
    }
    return best;
  }

  /// Every purpose a free-text reason touches. A visit can come in for more
  /// than one thing ("BP tracking, wound dressing"), so this returns a list
  /// rather than the single best match.
  static List<ClinicPurpose> matchAll(String text) {
    final t = text.toLowerCase().trim();
    if (t.isEmpty) return const [];
    final found = <ClinicPurpose>[];
    for (final p in all) {
      if (p.keywords.any((k) => t.contains(k))) found.add(p);
    }
    return found;
  }

  /// Joins the labels the way they are stored in `visits.complaint`, e.g.
  /// "BP tracking, Wound dressing".
  static String joinLabels(Iterable<ClinicPurpose> purposes, {String? other}) {
    final parts = purposes.map((p) => p.label).toList();
    final extra = (other ?? '').trim();
    if (extra.isNotEmpty) parts.add(extra);
    return parts.join(', ');
  }
}
