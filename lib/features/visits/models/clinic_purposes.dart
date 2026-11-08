import 'package:flutter/material.dart';

class PurposeField {
  final String key;
  final String label;
  final String type;
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

  final String id;

  final String label;

  final String short;

  final IconData icon;

  final List<String> keywords;

  final List<String> procedures;

  final List<PurposeField> fields;

  final List<String> outcomes;

  String get records =>
      '${fields.map((f) => f.unit == null ? f.label : '${f.label} (${f.unit})').join(', ')} — then the result';

  final bool vitals;

  final bool medicine;

  final bool attachment;

  final String? attachmentNote;
}

const Set<String> kBlankFormServiceIds = {};

class ClinicPurposes {
  const ClinicPurposes._();

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
  ];

  static const List<ClinicPurpose> all = [
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
    ClinicPurpose(
      id: 'medicine_consultation',
      label: 'Medical consultation',
      short: 'Consultation',
      icon: Icons.medical_information_outlined,
      keywords: [
        'medical consultation',
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
    ClinicPurpose(
      id: 'medicine_certificate',
      label: 'Medical certificate',
      short: 'Certificate',
      icon: Icons.description_outlined,
      keywords: [
        'medical certificate',
        'medicine certificate',
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
        'blood pressure',
        'bp tracking',
        'bp monitoring',
        'bp reading',
        'hypertension',
        'high blood pressure',
        'bp',
        'temperature',
        'temp check',
        'fever',
        'temp',
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

  static const List<String> _workflowOrder = [
    'vital_signs',
    'medicine_consultation',
    'prenatal',
    'wound_dressing',
    'first_aid_treatment',
    'medication',
    'health_counselling',
    'bpi',
  ];

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

  static String joinLabels(Iterable<ClinicPurpose> purposes, {String? other}) {
    final parts = purposes.map((p) => p.label).toList();
    final extra = (other ?? '').trim();
    if (extra.isNotEmpty) parts.add(extra);
    return parts.join(', ');
  }
}