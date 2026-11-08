import 'package:flutter/material.dart' show IconData, Icons;

import 'package:clinicmanagementsystem/features/visits/models/clinic_purposes.dart';
import 'package:clinicmanagementsystem/features/vitals/models/vital_classifier.dart';
import 'package:clinicmanagementsystem/features/vitals/models/vitals.dart';

enum ServiceFieldKind {
  text,
  multiline,
  number,
  dropdown,
  chips,
  multiselect,
  checkboxes,
  date,
  readOnly,
  sharedVitals,
  vitalsCard,
  medicationCard,
  staffName,
  inventoryPick,
  linkServiceCard,
  notice,
}

enum VitalField {
  systolic,
  diastolic,
  heartRate,
  respRate,
  temperature,
  o2Sat,
  heightCm,
  weightKg,
}

extension VitalFieldInfo on VitalField {
  String get column => switch (this) {
        VitalField.systolic => 'systolic',
        VitalField.diastolic => 'diastolic',
        VitalField.heartRate => 'heart_rate',
        VitalField.respRate => 'resp_rate',
        VitalField.temperature => 'temp_c',
        VitalField.o2Sat => 'o2_sat',
        VitalField.heightCm => 'height_cm',
        VitalField.weightKg => 'weight_kg',
      };

  String get interpretationKey => switch (this) {
        VitalField.systolic || VitalField.diastolic => 'blood_pressure',
        VitalField.heartRate => 'heart_rate',
        VitalField.respRate => 'resp_rate',
        VitalField.temperature => 'temperature',
        VitalField.o2Sat => 'o2_sat',
        VitalField.heightCm || VitalField.weightKg => 'bmi',
      };

  String get unit => switch (this) {
        VitalField.systolic || VitalField.diastolic => 'mmHg',
        VitalField.heartRate => 'bpm',
        VitalField.respRate => '/min',
        VitalField.temperature => '°C',
        VitalField.o2Sat => '%',
        VitalField.heightCm => 'cm',
        VitalField.weightKg => 'kg',
      };

  String get label => switch (this) {
        VitalField.systolic => 'Systolic',
        VitalField.diastolic => 'Diastolic',
        VitalField.heartRate => 'Pulse rate',
        VitalField.respRate => 'Respiratory rate',
        VitalField.temperature => 'Temperature',
        VitalField.o2Sat => 'Oxygen saturation',
        VitalField.heightCm => 'Height',
        VitalField.weightKg => 'Weight',
      };
}

class ServiceField {
  const ServiceField({
    required this.key,
    required this.label,
    this.kind = ServiceFieldKind.text,
    this.unit,
    this.hint,
    this.options = const [],
    this.optionsBuilder,
    this.required = false,
    this.vital,
    this.captureVitals = const [],
    this.maxChars = 500,
    this.width = FieldWidth.full,
    this.note,
    this.validate,
    this.shownWhenKey,
    this.shownWhenValues = const [],
    this.shownWhen = FieldCondition.isOneOf,
    this.shownWhenPredicate,
    this.requiredWhen,
    this.datePast = false,
    this.allowCustomEntries = false,
    this.opensService,
    this.buttonLabel,
    this.linkFromKey,
    this.otherOption = true,
    this.otherKey,
  });

  final String key;

  final String label;

  final ServiceFieldKind kind;

  final String? unit;

  final String? hint;

  final List<String> options;

  /// Picks the options from the answers so far, so a form only offers
  /// what fits the case. `options` is the full list (used as the fallback).
  final List<String> Function(Map<String, dynamic> data)? optionsBuilder;

  List<String> optionsIn(Map<String, dynamic> data) =>
      optionsBuilder?.call(data) ?? options;

  /// Suggested. The box is highlighted until it is filled, but nothing is
  /// blocked when it is left empty.
  final bool required;

  final VitalField? vital;

  final List<VitalField> captureVitals;

  final int maxChars;

  final FieldWidth width;

  final String? note;

  final ServiceFieldValidator? validate;

  final String? shownWhenKey;

  final List<String> shownWhenValues;

  final FieldCondition shownWhen;

  final bool Function(Map<String, dynamic> data)? shownWhenPredicate;

  final bool Function(Map<String, dynamic> data)? requiredWhen;

  final bool datePast;

  final bool allowCustomEntries;

  final String? opensService;

  final String? buttonLabel;

  final String? linkFromKey;

  /// Choice boxes (dropdown, chips, tick-boxes) get an "Other" choice at the
  /// end of the list. Picking it opens a box to type the answer. Set this to
  /// false for yes/no and fixed-scale answers where "Other" makes no sense.
  final bool otherOption;

  /// Where the typed "Other" answer is kept. Defaults to '<key>_other'.
  final String? otherKey;

  String get otherFieldKey => otherKey ?? '${key}_other';

  bool get isChoiceKind =>
      kind == ServiceFieldKind.dropdown ||
      kind == ServiceFieldKind.chips ||
      kind == ServiceFieldKind.multiselect ||
      kind == ServiceFieldKind.checkboxes;

  bool get hasOtherChoice => otherOption && isChoiceKind && options.isNotEmpty;

  bool isShownIn(Map<String, dynamic> data) {
    final predicate = shownWhenPredicate;
    if (predicate != null) return predicate(data);
    final gate = shownWhenKey;
    if (gate == null || shownWhenValues.isEmpty) return true;
    final raw = data[gate];
    if (raw == null) return shownWhen == FieldCondition.noneOf;
    final answers = raw is List ? raw.map((e) => '$e') : ['$raw'];
    return switch (shownWhen) {
      FieldCondition.isOneOf => shownWhenValues.any(answers.contains),
      FieldCondition.startsWith =>
        shownWhenValues.any((v) => answers.any((a) => a.startsWith(v))),
      FieldCondition.noneOf => !shownWhenValues.any(answers.contains),
    };
  }

  /// The box is suggested. It is highlighted green until it has an answer,
  /// but leaving it empty never stops the nurse.
  bool isSuggestedIn(Map<String, dynamic> data) =>
      required && isShownIn(data) && (requiredWhen?.call(data) ?? true);

  /// Blocks only when something was typed that is not allowed (for example
  /// a pain score of 15). An empty box never blocks.
  bool isRequiredIn(Map<String, dynamic> data) {
    if (!isShownIn(data)) return false;
    final v = data[key];
    final filled = v != null &&
        !(v is String && v.trim().isEmpty) &&
        !(v is List && v.isEmpty);
    return filled && validate?.call(v) != null;
  }
}

enum FieldCondition {
  isOneOf,
  startsWith,
  noneOf,
}

typedef ServiceFieldValidator = String? Function(Object? value);

enum FieldWidth { full, half }

class FieldGroup {
  const FieldGroup(this.keys, {this.title});

  final List<String> keys;

  final String? title;

  bool holds(String key) => keys.contains(key);
}

class ServiceSlide {
  const ServiceSlide({
    required this.title,
    this.fields = const [],
    this.custom,
    this.groups = const [],
    this.icon,
    this.subtitle,
  });

  final String title;

  final List<ServiceField> fields;

  final ServiceCustomSlide? custom;

  final List<FieldGroup> groups;

  /// Shown in the section header card.
  final IconData? icon;

  /// One short line under the section title.
  final String? subtitle;
}

class ServiceCustomSlide {
  const ServiceCustomSlide(this.id, {this.requiredKeys = const []});

  final String id;
  final List<String> requiredKeys;
}

enum ServiceFormKind { declarative, custom }

class ServiceFormSpec {
  const ServiceFormSpec({
    required this.serviceId,
    this.slides = const [],
    this.kind = ServiceFormKind.declarative,
    this.crossValidate,
    this.referralReasons,
    this.referralTitle,
    this.warnings,
    this.allowOther = true,
  });

  final String serviceId;
  final List<ServiceSlide> slides;
  final ServiceFormKind kind;

  final Map<String, String> Function(Map<String, dynamic> data)? crossValidate;

  final List<String> Function(Map<String, dynamic> data, VisitVitals vitals)?
      referralReasons;

  final String? referralTitle;

  final List<String> Function(Map<String, dynamic> data, VisitVitals vitals)?
      warnings;

  /// False for BMI and Vital Signs, which never get an "Other" choice.
  final bool allowOther;

  bool offersOther(ServiceField f) => allowOther && f.hasOtherChoice;

  /// The choices a box shows, with "Other" added at the end when it applies.
  List<String> optionsFor(ServiceField f, Map<String, dynamic> data) {
    final base = f.optionsIn(data);
    if (!offersOther(f) || base.contains(kOtherLabel)) return base;
    return [...base, kOtherLabel];
  }

  List<String> get requiredKeys => [
        for (final s in slides) ...[
          ...s.fields.where((f) => f.required).map((f) => f.key),
          ...?s.custom?.requiredKeys,
        ],
      ];

  /// Boxes that are highlighted green until they are filled. Never blocks.
  List<String> suggestedKeysIn(Map<String, dynamic> data) => [
        for (final s in slides) ...[
          ...s.fields.where((f) => f.isSuggestedIn(data)).map((f) => f.key),
          ...?s.custom?.requiredKeys,
        ],
      ];

  /// Boxes that block, and only because the typed answer is not allowed.
  /// An empty box is never in this list.
  List<String> requiredKeysIn(Map<String, dynamic> data) => [
        for (final s in slides)
          ...s.fields.where((f) => f.isRequiredIn(data)).map((f) => f.key),
        ...?crossValidate?.call(data).keys,
      ];

  /// Values the app fills in by itself. They never count as "something was
  /// recorded", otherwise an untouched form would look finished.
  static const Set<String> kSeededKeys = {
    'visitor_sex',
    'session_date',
    'counsellor',
  };

  /// A service counts as done when something was recorded and nothing typed
  /// is wrong. Empty suggested boxes do not stop it.
  bool isAnswered(Map<String, dynamic> data) {
    if (requiredKeysIn(data).isNotEmpty) return false;
    return data.entries.any((e) {
      if (kSeededKeys.contains(e.key)) return false;
      final v = e.value;
      if (v == null) return false;
      if (v is List) return v.isNotEmpty;
      return '$v'.trim().isNotEmpty;
    });
  }

  List<ServiceField> get fields => [
        for (final s in slides) ...s.fields,
      ];

  List<ServiceField> visibleFields(
          ServiceSlide slide, Map<String, dynamic> data) =>
      [
        for (final f in slide.fields)
          if (f.isShownIn(data)) f
      ];

  String? validate(String key, Object? value) {
    for (final f in fields) {
      if (f.key == key) return f.validate?.call(value);
    }
    return null;
  }

  String? validateInContext(String key, Map<String, dynamic> data) {
    final own = validate(key, data[key]);
    if (own != null) return own;
    return crossValidate?.call(data)[key];
  }
}

ServiceFieldValidator _vitalWhole(int min, int max) => (value) {
      final v = VitalClassifier.asWhole(value);
      if (value == null || '$value'.trim().isEmpty) return null;
      if (v == null || v < min || v > max) {
        return VitalClassifier.rangeError(min, max);
      }
      return null;
    };

ServiceFieldValidator _vitalDecimal(double min, double max) => (value) {
      if (value == null || '$value'.trim().isEmpty) return null;
      final v = VitalClassifier.asNumber(value);
      if (v == null || v < min || v > max) {
        return VitalClassifier.rangeError(min, max);
      }
      return null;
    };

Map<String, String> _vitalSignsCrossRules(Map<String, dynamic> data) {
  final s = VitalClassifier.asWhole(data['systolic']);
  final d = VitalClassifier.asWhole(data['diastolic']);
  if (s != null && d != null && s <= d) {
    return {vitalSystolicKey: VitalClassifier.systolicMustBeHigher};
  }
  return const {};
}

const String vitalSystolicKey = 'systolic';

ServiceFieldValidator _painWholeScore() => (value) {
      if (value == null || '$value'.trim().isEmpty) return null;
      final parsed = num.tryParse('$value'.trim());
      if (parsed == null ||
          parsed != parsed.roundToDouble() ||
          parsed < 0 ||
          parsed > 10) {
        return 'A pain score is a whole number from 0 to 10.';
      }
      return null;
    };

ServiceFieldValidator _cappedLength(int max, String what) => (value) {
      final s = value == null ? '' : '$value'.trim();
      if (s.length <= max) return null;
      return 'Keep $what to $max characters or fewer.';
    };

const List<String> kConsultationComplaints = [
  'Headache',
  'Fever',
  'Cough / Cold',
  'Abdominal Pain',
  'Dizziness',
  'Injury',
  'Menstrual Concern',
  'Skin Problem',
  'Eye Problem',
  'Toothache',
  'Sore Throat',
  'Nosebleed',
  'Allergy / Rash',
  'Stomach Upset',
];

const List<String> kConsultationDuration = [
  'Just now',
  'Today',
  '2-3 days',
  'More than 3 days',
];

/// Background conditions only. Today's symptoms are already in the
/// complaint ticks, so they are not repeated here.
const List<String> kConsultationHistory = [
  'Asthma',
  'Diabetes',
  'Hypertension / heart condition',
  'Seizure / epilepsy',
  'Taking medicine now',
  'Similar problem before',
];

const List<String> kConsultationTreatment = [
  'Advice / Health Education',
  'Medication',
  'Wound Care',
  'Rest / Observation',
];

const List<String> kConsultationRedFlags = [
  'None',
  'Difficulty breathing',
  'Chest pain',
  'Fainting / unresponsive',
  'Seizure',
  'Severe bleeding',
  'Severe abdominal pain',
  'Head injury with vomiting or confusion',
  'Signs of allergic reaction',
  'Suspected pregnancy complication',
];

const Set<String> kConsultationEmergencyFlags = {
  'Difficulty breathing',
  'Chest pain',
  'Seizure',
  'Fainting / unresponsive',
};

const List<String> kConsultationDispositions = [
  'Returned to Class',
  'Rested in Clinic then Returned to Class',
  'Sent Home',
  'Referred to Physician / Healthcare Facility',
  'Sent to Hospital (emergency)',
];

const List<String> kConsultationReferralDispositions = [
  'Referred to Physician / Healthcare Facility',
  'Sent to Hospital (emergency)',
];

const List<String> kConsultationReferralServices = [
  'Vital Signs',
  'BMI',
  'Wound Dressing',
  'Medication',
  'Health Counselling',
  'Prenatal',
  'First Aid Treatment',
  'Guidance Counselor (school)',
  'External Healthcare Facility',
  'Other',
];

const List<String> kConsultationNamedReferralTargets = [
  'Guidance Counselor (school)',
  'External Healthcare Facility',
];

const List<String> kYesNoUnknown = ['Unknown', 'No', 'Yes'];

const List<String> kYesNo = ['No', 'Yes'];

const List<String> kCounsellingTopics = [
  'General Health',
  'Nutrition / Diet',
  'Personal Hygiene',
  'Mental/Emotional Well-being',
  'Reproductive Health',
  'Physical Activity / Exercise',
  'Disease Prevention',
  'Medication / Treatment Adherence',
  'Bullying / Safety',
  'Substance Use (smoking, vaping, alcohol)',
  'Stress / Exam Anxiety',
  'Sleep',
];

const Set<String> kCounsellingSensitiveTopics = {
  'Mental/Emotional Well-being',
  'Reproductive Health',
  'Bullying / Safety',
  'Substance Use (smoking, vaping, alcohol)',
};

const List<String> kCounsellingReferralSource = [
  'Self-referred',
  'Referred by Teacher / Adviser',
  'Referred by Guardian',
  'Nurse-initiated / Follow-up',
  'Referred from another clinic service',
];

const List<String> kCounsellingSessionType = [
  'Individual',
  'Group',
];

const List<String> kCounsellingUnderstanding = [
  'Understood',
  'Needs more explanation',
  'Not receptive',
];

const List<String> kCounsellingConcernSigns = [
  'None',
  'Talked about hurting self',
  'Talked about hurting others',
  'Signs of abuse or neglect',
  'Being bullied',
  'Severe anxiety or sadness',
  'Substance use',
];

const List<String> kCounsellingGuardian = ['Yes', 'No', 'Not needed'];

const List<String> kCounsellingPrivacyLevels = ['Normal', 'Restricted'];

const List<String> kCounsellingRecommendedServices = [
  'Vital Signs',
  'BMI',
  'Wound Dressing',
  'Medication',
  'First Aid Treatment',
  'Prenatal',
  'Medical Consultation',
  'Guidance Counselor (school)',
  'External Healthcare Facility',
  'Other',
];

const Map<String, String> kRecommendedServiceAppIds = {
  'Vital Signs': 'vital_signs',
  'BMI': 'bpi',
  'Wound Dressing': 'wound_dressing',
  'Medication': 'medication',
  'Health Counselling': 'health_counselling',
  'First Aid Treatment': 'first_aid_treatment',
  'Prenatal': 'prenatal',
  'Medical Consultation': 'medicine_consultation',
};

String? appServiceIdForRecommended(String name) =>
    kRecommendedServiceAppIds[name.trim()];

const List<String> kFirstAidRecommendedServices = [
  'Vital Signs',
  'BMI',
  'Wound Dressing',
  'Medication',
  'Prenatal',
  'Medical Consultation',
  'Guidance Counselor (school)',
  'External Healthcare Facility',
  'Other',
];

const List<String> kCounsellingReferralSigns = [
  'Talked about hurting self',
  'Talked about hurting others',
  'Signs of abuse or neglect',
  'Being bullied',
  'Severe anxiety or sadness',
  'Substance use',
];

List<String> counsellingConcernSigns(Map<String, dynamic> data) {
  final raw = data['concern_signs'];
  if (raw is List) return [for (final e in raw) '$e'.trim()];
  final s = '${raw ?? ''}'.trim();
  return s.isEmpty ? const [] : [s];
}

List<String> counsellingReferralReasons(Map<String, dynamic> data) {
  final signs = counsellingConcernSigns(data);
  final other = _strOf(data['concern_signs_other']);
  return [
    for (final s in signs)
      if (kCounsellingReferralSigns.contains(s))
        s
      else if (s == kOtherLabel)
        (other.isEmpty ? 'Other warning sign' : other),
  ];
}

bool counsellingAutoRestricted(Map<String, dynamic> data) {
  if (counsellingReferralReasons(data).isNotEmpty) return true;
  final raw = data['topic'];
  final topics = raw is List
      ? [for (final e in raw) '$e'.trim()]
      : <String>['${raw ?? ''}'.trim()];
  return topics.any(kCounsellingSensitiveTopics.contains);
}

String counsellingPrivacyLevel(Map<String, dynamic> data) {
  if (counsellingAutoRestricted(data)) return 'Restricted';
  final raw = data['privacy_level'];
  final chosen = raw is List && raw.isNotEmpty ? '${raw.first}'.trim() : '';
  return chosen == 'Restricted' ? 'Restricted' : 'Normal';
}

/// True when the record is Restricted, either chosen or forced by the app.
bool _counsellingIsRestricted(Map<String, dynamic> d) =>
    counsellingPrivacyLevel(d) == 'Restricted';

List<String> consultationRedFlags(Map<String, dynamic> data) {
  final other = _strOf(data['red_flags_other']);
  return [
    for (final f in _strListOf(data['red_flags']))
      if (f != 'None')
        (f == kOtherLabel && other.isNotEmpty) ? other : f,
  ];
}

const Set<String> kConsultationDizzinessComplaints = {
  'Dizziness',
  'Fainting / unresponsive',
};

List<String> consultationReferralReasons(
    Map<String, dynamic> data, VisitVitals vitals) {
  final reasons = <String>[];

  final flags = consultationRedFlags(data);
  final emergency = flags.where(kConsultationEmergencyFlags.contains).toList();
  if (emergency.isNotEmpty) {
    reasons.add('Call emergency / clinic head now.');
  }
  reasons.addAll(flags);

  final temp = vitals.tempC;
  if (temp != null && temp >= 38.5) {
    reasons.add('Temperature ${_trimNum(temp)} °C is 38.5 or higher.');
  }
  final systolic = vitals.systolic;
  final diastolic = vitals.diastolic;
  if (systolic != null && systolic >= 140) {
    reasons.add('Systolic $systolic is 140 or higher.');
  }
  if (diastolic != null && diastolic >= 90) {
    reasons.add('Diastolic $diastolic is 90 or higher.');
  }
  final pulse = vitals.heartRate;
  if (pulse != null && (pulse > 120 || pulse < 50)) {
    reasons
        .add('Pulse $pulse is ${pulse > 120 ? 'above 120' : 'below 50'} bpm.');
  }

  final dizzy = _strListOf(data['symptoms'])
      .any(kConsultationDizzinessComplaints.contains);
  final anyAbnormal =
      VitalClassifier.classifyBp(systolic, diastolic)?.isAbnormal == true ||
          VitalClassifier.classifyPulse(pulse)?.isAbnormal == true ||
          VitalClassifier.classifyTemp(temp)?.isAbnormal == true;
  if (dizzy && anyAbnormal) {
    reasons.add('Dizziness / fainting with abnormal vitals.');
  }

  return reasons;
}

List<String> consultationWarnings(
    Map<String, dynamic> data, VisitVitals vitals) {
  final warnings = <String>[];

  if (consultationReferralReasons(data, vitals).isNotEmpty) {
    final disposition = _strOf(data['disposition']);
    const safe = {
      'Referred to Physician / Healthcare Facility',
      'Sent to Hospital (emergency)',
      'Sent Home',
    };
    if (!safe.contains(disposition)) {
      warnings.add(
          'This consultation raises a referral. Confirm the disposition on '
          'the Plan slide.');
    }
  }

  final guardian = _strOf(data['guardian_informed']);
  final disposition = _strOf(data['disposition']);
  if (guardian == 'No' &&
      (disposition == 'Sent Home' ||
          kConsultationReferralDispositions.contains(disposition))) {
    warnings
        .add('Parent / Guardian was not informed. The student may be a minor — '
            'confirm this is appropriate.');
  }

  return warnings;
}

String consultationComplaintDetails(Map<String, dynamic> data) {
  final parts = <String>[];
  final chief = _strOf(data['chief_complaint']);
  if (chief.isNotEmpty) parts.add(chief);
  final ticks = _strListOf(data['symptoms']);
  final other = _strOf(data['symptom_other']);
  if (ticks.isNotEmpty) {
    parts.add([
      for (final t in ticks)
        if (t != 'Other' || other.isEmpty) t else other,
    ].join(', '));
  }
  final duration = <String>[
    ..._strListOf(data['duration_onset_choice']),
    _strOf(data['duration_onset']),
  ].where((e) => e.isNotEmpty).join(', ');
  if (duration.isNotEmpty) parts.add('Duration / onset: $duration.');
  // Old records may still have this. New forms no longer ask for it.
  final additional = _strOf(data['additional_complaint']);
  if (additional.isNotEmpty) parts.add(additional);
  return parts.join('. ');
}

String consultationDiagnosis(Map<String, dynamic> data) {
  final impression = _strOf(data['clinical_impression']);
  final secondary = _strOf(data['secondary_diagnosis']);
  if (impression.isEmpty) return secondary;
  if (secondary.isEmpty) return impression;
  return '$impression; $secondary';
}

// ---- Medical Consultation: when a box is worth showing -------------------

/// Complaints where asking for a pain score makes sense.
const Set<String> kConsultationPainComplaints = {
  'Headache',
  'Abdominal Pain',
  'Toothache',
  'Sore Throat',
  'Injury',
  'Menstrual Concern',
};

bool consultationHasPain(Map<String, dynamic> d) =>
    _answersOf(d['symptoms']).any(kConsultationPainComplaints.contains) ||
    _strOf(d['chief_complaint']).toLowerCase().contains('pain');

bool consultationLongDuration(Map<String, dynamic> d) =>
    _answersOf(d['duration_onset_choice']).contains('More than 3 days');

/// Allergies only matter when medicine is going to be given.
bool consultationGivesMedicine(Map<String, dynamic> d) =>
    _answersOf(d['treatment']).contains('Medication');

/// LMP is asked only for a female visitor with a related complaint.
bool consultationAsksLmp(Map<String, dynamic> d) {
  if ('${d['visitor_sex'] ?? ''}'.trim().toLowerCase() != 'female') {
    return false;
  }
  return _answersOf(d['symptoms']).any(const [
    'Menstrual Concern',
    'Abdominal Pain',
    'Dizziness',
    'Stomach Upset',
  ].contains);
}

/// Excuse slip and guardian only matter when the visitor leaves the clinic.
bool consultationLeavesClinic(Map<String, dynamic> d) {
  final x = _strOf(d['disposition']);
  return x == 'Sent Home' || kConsultationReferralDispositions.contains(x);
}

ServiceFieldValidator _notPastDate(String what) => (value) {
      final s = value == null ? '' : '$value'.trim();
      if (s.isEmpty) return null;
      final picked = DateTime.tryParse(s);
      if (picked == null) return null;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      if (picked.isBefore(today)) return 'The $what cannot be in the past.';
      return null;
    };

ServiceFieldValidator _notFutureDate(String what) => (value) {
      final s = value == null ? '' : '$value'.trim();
      if (s.isEmpty) return null;
      final picked = DateTime.tryParse(s);
      if (picked == null) return null;
      final now = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);
      if (picked.isAfter(today)) return 'The $what cannot be in the future.';
      return null;
    };

ServiceFieldValidator _minutesWhole() => (value) {
      if (value == null || '$value'.trim().isEmpty) return null;
      final n = num.tryParse('$value'.trim());
      if (n == null || n != n.roundToDouble() || n < 1 || n > 480) {
        return 'Enter a whole number of minutes from 1 to 480.';
      }
      return null;
    };

ServiceFieldValidator _excuseDaysWhole() => (value) {
      if (value == null || '$value'.trim().isEmpty) return null;
      final n = num.tryParse('$value'.trim());
      if (n == null || n != n.roundToDouble() || n < 1 || n > 7) {
        return 'Enter a whole number of days from 1 to 7.';
      }
      return null;
    };

const List<String> kCounsellingProvided = [
  'Health Education',
  'Advice / Guidance',
  'Preventive Education',
  'Lifestyle / Behavior Advice',
  'Demonstration',
  'Medication-related Education',
];

const List<String> kAttendingStaff = [
  'Nurse',
  'Physician',
  'Nurse + Physician',
];

const List<String> kWoundTypes = [
  'Incised / Cut',
  'Abrasion',
  'Laceration',
  'Puncture',
  'Burn',
  'Animal bite',
  'Blister',
];

const List<String> kWoundConditions = [
  'Clean',
  'Contaminated / Dirty',
  'Infected',
  'Healing',
];

const List<String> kWoundCleaningPerformed = [
  'Running water',
  'Normal Saline',
  'Povidone-Iodine',
  'Chlorhexidine',
  'Hydrogen Peroxide',
  'Tap water',
];

const List<String> kWoundDressingMaterials = [
  'Sterile Gauze',
  'Gauze Pad',
  'Bandage / Roller',
  'Crepe Bandage',
  'Adhesive Plaster',
  'Cotton / Cotton Ball',
];

const List<String> kDressingMaterialsUsed = [
  'Sterile Gauze',
  'Gauze Pad',
  'Bandage / Roller',
  'Crepe Bandage',
  'Adhesive Plaster',
  'Cotton / Cotton Ball',
  'Eye Pad',
  'Sling / Arm Sling',
];

const List<String> kWoundFindings = [
  'Wound edges clean',
  'No signs of infection',
  'Redness present',
  'Swelling present',
  'Pus / discharge present',
  'Bleeding controlled',
  'Edges approximated / sutured',
];

const List<String> kWoundInjuryTiming = [
  'Just now (under 1 hour)',
  'Within 6 hours',
  '6 to 24 hours',
  'More than 24 hours',
];

const List<String> kBurnDegrees = [
  '1st degree',
  '2nd degree',
  '3rd degree',
];

const List<String> kBleedingStatus = [
  'None',
  'Controlled',
  'Still bleeding',
];

const List<String> kTetanusStatus = [
  'Yes',
  'No',
  'Unknown',
];

const List<String> kWoundActions = [
  'Wound cleaned and dressed',
  'Advice given (keep dry, signs of infection)',
  'Referred to Hospital/RHU',
  'Parents / Guardian informed',
  'Sent home',
  'Returned to class',
  'Follow-up scheduled',
];

const String kWoundNoFurtherDressing = 'No further dressing needed';

const String kWoundNoMedicationLabel = 'None applied';

const List<String> kWoundHeadSites = ['Head', 'Face', 'Neck'];

const List<String> kWoundTetanusTypes = ['Puncture', 'Animal bite'];

const List<String> kWoundTetanusConditions = [
  'Contaminated / Dirty',
  'Infected'
];

const List<String> kWoundOpenTypes = ['Incised / Cut', 'Laceration'];

const double kWoundReferralLengthCm = 2.5;

const double kWoundReferralTempC = 38;

bool prenatalNeedsReferral(VisitVitals vitals) {
  final bp = vitals.bloodPressure;
  if (bp == null) return false;
  return bp.band == VitalBand.high || bp.band == VitalBand.critical;
}

List<String> woundReferralReasons(
  Map<String, dynamic> data, {
  num? temperature,
}) {
  final type = _strOf(data['wound_type']);
  final condition = _strListOf(data['wound_condition']);
  final location = _strOf(data['wound_location']);
  final bleeding = _strOf(data['bleeding']);
  final burn = _strOf(data['burn_degree']);
  final timing = _strOf(data['injury_timing']);
  final findings = _strListOf(data['assessment']);

  final reasons = <String>[];
  if (kWoundTetanusTypes.contains(type)) {
    reasons.add(type == 'Animal bite' ? 'Animal bite' : 'Puncture wound');
  }
  if (burn == '2nd degree' || burn == '3rd degree') {
    reasons.add('$burn burn');
  }
  if (bleeding == 'Still bleeding') {
    reasons.add('Still bleeding');
  }
  if (kWoundOpenTypes.contains(type) && kWoundHeadSites.contains(location)) {
    reasons.add('$type on the ${location.toLowerCase()}');
  }
  if (condition.contains('Infected') &&
      temperature != null &&
      temperature >= kWoundReferralTempC) {
    reasons.add('Infected with a temperature of ${_trimNum(temperature)} °C');
  }
  if (findings.contains('Pus / discharge present')) {
    reasons.add('Pus / discharge present');
  }
  if (timing == 'More than 24 hours' && !condition.contains('Clean')) {
    reasons.add('Injury more than 24 hours old and not clean');
  }
  if (data['wound_requires_suturing_legacy'] == true) {
    reasons.add('Requires suturing (recorded before this form changed)');
  }
  return reasons;
}

bool woundNeedsReferral(Map<String, dynamic> data, {num? temperature}) =>
    woundReferralReasons(data, temperature: temperature).isNotEmpty;

/// Wounds where it is worth asking about tetanus: puncture, animal bite,
/// laceration, a 2nd or 3rd degree burn, or any dirty or infected wound.
/// A clean scrape, clean cut or blister does not ask.
bool woundNeedsTetanusCheck(Map<String, dynamic> data) {
  final type = _answersOf(data['wound_type']);
  final cond = _answersOf(data['wound_condition']);
  final burn = _answersOf(data['burn_degree']);
  if (type.any(const ['Puncture', 'Animal bite', 'Laceration'].contains)) {
    return true;
  }
  if (type.contains('Burn') &&
      burn.any(const ['2nd degree', '3rd degree'].contains)) {
    return true;
  }
  return cond.any(kWoundTetanusConditions.contains);
}

/// Temperature / blood pressure matter for an infected wound or a deeper burn.
bool woundNeedsVitals(Map<String, dynamic> data) {
  final cond = _answersOf(data['wound_condition']);
  final type = _answersOf(data['wound_type']);
  final burn = _answersOf(data['burn_degree']);
  return cond.contains('Infected') ||
      (type.contains('Burn') &&
          burn.any(const ['2nd degree', '3rd degree'].contains));
}

/// A next dressing date is asked only when one is likely.
bool woundNeedsNextDressing(Map<String, dynamic> data) {
  final conds = _answersOf(data['wound_condition']);
  final acts = _answersOf(data['action_taken']);
  return conds.contains('Infected') ||
      conds.contains('Healing') ||
      acts.contains('Follow-up scheduled');
}

List<String> woundCleaningFor(Map<String, dynamic> data) {
  final type = _answersOf(data['wound_type']);
  if (type.contains('Burn')) {
    return const ['Running water', 'Normal Saline', 'Tap water'];
  }
  return kWoundCleaningPerformed;
}

List<String> woundFindingsFor(Map<String, dynamic> data) {
  final type = _answersOf(data['wound_type']);
  final canBeClosed = type.any(kWoundOpenTypes.contains);
  return [
    for (final f in kWoundFindings)
      if (canBeClosed || f != 'Edges approximated / sutured') f,
  ];
}

/// What First Aid offers depends on the kind of incident.
enum FirstAidGroup { wound, injury, nosebleed, allergy, illness, other }

FirstAidGroup firstAidGroupOf(String incident) => switch (incident) {
      'Wound' || 'Bleeding' || 'Burn' => FirstAidGroup.wound,
      'Minor Injury' ||
      'Fall' ||
      'Sprain / Strain' ||
      'Bruise' ||
      'Head Injury' ||
      'Eye Injury' =>
        FirstAidGroup.injury,
      'Nosebleed' => FirstAidGroup.nosebleed,
      'Insect Bite / Allergic Reaction' => FirstAidGroup.allergy,
      'Headache' ||
      'Dizziness' ||
      'Fainting' ||
      'Stomach Pain / Nausea' ||
      'Menstrual Cramps' =>
        FirstAidGroup.illness,
      _ => FirstAidGroup.other,
    };

const Map<FirstAidGroup, List<String>> _kFirstAidFindingsByGroup = {
  FirstAidGroup.wound: [
    'Pain',
    'Swelling',
    'Bleeding',
    'Redness',
    'Wound / Open Skin',
    'Burn',
  ],
  FirstAidGroup.injury: [
    'Pain',
    'Swelling',
    'Bruising',
    'Redness',
    'Limited Movement',
    'Bleeding',
    'Wound / Open Skin',
  ],
  FirstAidGroup.nosebleed: ['Bleeding', 'Nausea / Vomiting'],
  FirstAidGroup.allergy: [
    'Pain',
    'Swelling',
    'Redness',
    'Allergic Reaction / Hives',
    'Difficulty Breathing',
  ],
  FirstAidGroup.illness: ['Pain', 'Nausea / Vomiting', 'Difficulty Breathing'],
};

const Map<FirstAidGroup, List<String>> _kFirstAidTreatmentsByGroup = {
  FirstAidGroup.wound: [
    'Bleeding Control',
    'Cold Compress',
    'Rest / Observation',
    'Basic Medication Given',
  ],
  FirstAidGroup.injury: [
    'Bleeding Control',
    'Cold Compress',
    'Warm Compress',
    'Immobilization',
    'Bandaging',
    'Rest / Observation',
    'Basic Medication Given',
  ],
  FirstAidGroup.nosebleed: [
    'Bleeding Control',
    'Cold Compress',
    'Rest / Observation',
  ],
  FirstAidGroup.allergy: [
    'Cold Compress',
    'Rest / Observation',
    'Basic Medication Given',
  ],
  FirstAidGroup.illness: [
    'Rest / Observation',
    'Cold Compress',
    'Warm Compress',
    'Basic Medication Given',
  ],
};

List<String> firstAidFindingsFor(Map<String, dynamic> data) =>
    _kFirstAidFindingsByGroup[firstAidGroupOf(_strOf(data['incident']))] ??
    kFirstAidFindings;

List<String> firstAidTreatmentsFor(Map<String, dynamic> data) =>
    _kFirstAidTreatmentsByGroup[firstAidGroupOf(_strOf(data['incident']))] ??
    kFirstAidTreatments;

bool firstAidIsIllness(Map<String, dynamic> data) =>
    firstAidGroupOf(_strOf(data['incident'])) == FirstAidGroup.illness;

bool firstAidIsHeadCase(Map<String, dynamic> data) {
  final incident = _strOf(data['incident']);
  if (incident == 'Head Injury') return true;
  final site = _strOf(data['body_part']);
  return incident == 'Fall' && (site == 'Head' || site == 'Face');
}

bool firstAidNeedsVitals(Map<String, dynamic> data) {
  final incident = _strOf(data['incident']);
  const needs = [
    'Head Injury',
    'Fainting',
    'Dizziness',
    'Headache',
    'Stomach Pain / Nausea',
    'Menstrual Cramps',
    'Insect Bite / Allergic Reaction',
  ];
  return needs.contains(incident) ||
      firstAidIsHeadCase(data) ||
      _strListOf(data['findings']).contains('Difficulty Breathing');
}

bool firstAidSuggestsWoundCare(Map<String, dynamic> data) {
  final incident = _strOf(data['incident']);
  if (incident == 'Wound' || incident == 'Bleeding' || incident == 'Burn') {
    return true;
  }
  final findings = _strListOf(data['findings']);
  return findings.contains('Wound / Open Skin') || findings.contains('Burn');
}

bool firstAidSuggestsConsultation(Map<String, dynamic> data) {
  final signs =
      _strListOf(data['head_injury_signs']).where((s) => s != 'None of these');
  return signs.isNotEmpty ||
      _strOf(data['condition_after']) == 'Requires Further Treatment' ||
      _strListOf(data['findings']).contains('Difficulty Breathing');
}

/// True when blood pressure, pulse or temperature on the Vital Signs form is
/// outside the normal range. (Respiratory rate and oxygen are not part of
/// this check.)
bool vitalReadingsAbnormal(Map<String, dynamic> data) {
  final bp = VitalClassifier.classifyBp(
    VitalClassifier.asWhole(data['systolic']),
    VitalClassifier.asWhole(data['diastolic']),
  );
  final pulse =
      VitalClassifier.classifyPulse(VitalClassifier.asWhole(data['pulse_bpm']));
  final temp = VitalClassifier.classifyTemp(
      VitalClassifier.asNumber(data['temp_c'])?.toDouble());
  return bp?.isAbnormal == true ||
      pulse?.isAbnormal == true ||
      temp?.isAbnormal == true;
}

/// Details that are the same in Wound Dressing and First Aid. When both
/// services are in one visit, typing it in one fills the other. If only one
/// of the two is in the visit, that form just has its own boxes.
/// Each pair is (Wound Dressing key, First Aid key).
const List<(String, String)> kWoundFirstAidSharedKeys = [
  ('wound_location', 'body_part'),
  ('injury_cause', 'incident_cause'),
];

bool isReferralDisposition(String disposition) =>
    disposition.startsWith('Referred to');

String _strOf(Object? v) {
  if (v == null) return '';
  if (v is List) return v.isEmpty ? '' : '${v.first}'.trim();
  return '$v'.trim();
}

List<String> _answersOf(Object? v) {
  if (v == null) return const [];
  if (v is List) {
    return [
      for (final e in v)
        if ('$e'.trim().isNotEmpty) '$e'.trim(),
    ];
  }
  final s = '$v'.trim();
  return s.isEmpty ? const [] : [s];
}

List<String> _strListOf(Object? v) => _answersOf(v);

String _trimNum(num n) {
  if (n == n.roundToDouble()) return n.toInt().toString();
  return n
      .toString()
      .replaceAll(RegExp(r'0+$'), '')
      .replaceAll(RegExp(r'\.$'), '');
}

const List<String> kMedicationReasons = [
  'Headache',
  'Fever',
  'Cough / Cold',
  'Stomachache',
  'Menstrual Pain',
  'Allergies',
  'Body Ache',
  'Diarrhea',
];

const List<String> kFirstAidIncidents = [
  'Minor Injury',
  'Wound',
  'Bleeding',
  'Burn',
  'Sprain / Strain',
  'Bruise',
  'Fall',
  'Head Injury',
  'Nosebleed',
  'Insect Bite / Allergic Reaction',
  'Eye Injury',
  'Headache',
  'Dizziness',
  'Fainting',
  'Stomach Pain / Nausea',
  'Menstrual Cramps',
];

const List<String> kFirstAidFindings = [
  'Pain',
  'Swelling',
  'Bleeding',
  'Bruising',
  'Redness',
  'Wound / Open Skin',
  'Limited Movement',
  'Burn',
  'Allergic Reaction / Hives',
  'Difficulty Breathing',
  'Nausea / Vomiting',
];

const List<String> kFirstAidTreatments = [
  'Wound Cleaning',
  'Wound Dressing',
  'Bleeding Control',
  'Bandaging',
  'Cold Compress',
  'Warm Compress',
  'Immobilization',
  'Rest / Observation',
  'Basic Medication Given',
];

const List<String> kConditionAfterTreatment = [
  'Improved',
  'Stable',
  'Requires Further Observation',
  'Requires Further Treatment',
];

const List<String> kFirstAidDispositions = [
  'Returned to Class',
  'Rested in Clinic',
  'Treated and Released',
  'Sent Home',
  'Advised to Monitor',
  'Follow-up Recommended',
  'Referred to Doctor',
  'Referred to Hospital',
];

const List<String> kFirstAidTimings = [
  'Just now (under 1 hour)',
  'Within the hour',
  'Today',
  'Earlier this week',
  'Unknown',
];

const List<String> kFirstAidPlaces = [
  'Classroom',
  'Corridor',
  'Laboratory',
  'Library',
  'Gym / Sports Area',
  'Canteen',
  'Clinic (already here)',
  'Outside School Grounds',
  'At Home',
];

const List<String> kFirstAidHeadSigns = [
  'None of these',
  'Loss of consciousness',
  'Repeated vomiting',
  'Confusion / does not remember',
  'Seizure',
  'Clear fluid or blood from nose or ears',
  'Unequal pupils',
  'Weakness / numbness in limbs',
  'Worsening headache',
];

const List<String> kFirstAidConsciousness = [
  'Alert',
  'Drowsy',
  'Confused',
  'Unresponsive',
];

const List<String> kFirstAidGuardian = ['Yes', 'No', 'Not needed'];

const List<String> kFetalMovements = [
  'Active',
  'Normal',
  'Reduced',
  'Absent',
  'Not yet expected (early pregnancy)',
  'Not assessed',
];

const List<String> kPrenatalServices = [
  'Routine Prenatal Check',
  'Initial Booking',
  'High-Risk Follow-up',
  'Pre-Eclampsia Monitoring',
  'Iron / Folic Acid',
  'Referral to Doctor/OB',
];

const List<String> kPrenatalActions = [
  'Vital Signs Taken',
  'Fetal Heart Tone Checked',
  'Advice Given',
  'Referred for Further Testing',
  'Referred to Hospital/RHU',
  'Parents/Guardian Informed (if student)',
  'Follow-up Scheduled',
];

const List<String> kPrenatalEdema = [
  'None',
  'Feet / Ankles only',
  'Legs',
  'Hands / Face',
];

const List<String> kPrenatalUrineProtein = [
  'Not tested',
  'Negative',
  'Trace / 1+',
  '2+ or more',
];

const List<String> kPrenatalDangerSigns = [
  'None',
  'Severe headache',
  'Blurred vision',
  'Abdominal pain',
  'Vaginal bleeding',
  'Leaking fluid',
  'Fever',
  'Convulsions',
  'Decreased baby movement',
];

const List<String> kPrenatalGiven = [
  'Iron / Folic Acid',
  'Tetanus Toxoid (TT)',
  'Calcium',
];

const List<String> kBpArms = ['Left', 'Right'];

const List<String> kBpPositions = ['Sitting', 'Standing', 'Lying'];

const List<String> kTemperatureMethods = [
  'Oral',
  'Axillary (underarm)',
  'Tympanic (ear)',
  'Forehead / Temporal',
];

const List<String> kVitalActions = [
  'No intervention needed',
  'Rest advised',
  'Rested in clinic',
  'Recheck vital signs later',
  'Referred to hospital / emergency care',
  'Guardian / companion informed',
  'Sent home',
  'Cleared to return to class / work',
];

const List<String> kReferralActions = ['Referred to hospital / emergency care'];

const String kVitalsSelectedKey = 'vitals_selected';
const String kSelectAllLabel = 'Select All';

const List<String> kVitalChoices = [
  'Blood Pressure',
  'Temperature',
  'Pulse',
  'Respiratory Rate',
  'O₂ Saturation',
];

const Map<String, List<String>> kVitalChoiceKeys = {
  'Blood Pressure': [
    'systolic',
    'diastolic',
    'position',
    'arm_used',
    'bp_assessment'
  ],
  'Temperature': ['temp_c', 'method', 'temp_assessment'],
  'Pulse': ['pulse_bpm', 'pulse_assessment'],
  'Respiratory Rate': ['resp_rate', 'resp_assessment'],
  'O₂ Saturation': ['o2_sat', 'spo2_assessment'],
};

const Map<String, List<VitalField>> kVitalChoiceFields = {
  'Blood Pressure': [VitalField.systolic, VitalField.diastolic],
  'Temperature': [VitalField.temperature],
  'Pulse': [VitalField.heartRate],
  'Respiratory Rate': [VitalField.respRate],
  'O₂ Saturation': [VitalField.o2Sat],
};

const List<({String key, String label})> kPhysicalExamRows = [
  (key: 'general_appearance', label: 'General Appearance'),
  (key: 'orientation', label: 'Orientation'),
  (key: 'skin', label: 'Skin'),
  (key: 'heent', label: 'HEENT (Eyes, Ears, Nose, Throat)'),
  (key: 'lungs', label: 'Lungs'),
  (key: 'abdomen', label: 'Abdomen'),
  (key: 'hernia', label: 'Hernia'),
  (key: 'neurological', label: 'Neurological'),
  (key: 'genito_urinary', label: 'Genito-urinary'),
  (key: 'endocrine', label: 'Endocrine'),
  (key: 'joints', label: 'Joints'),
  (key: 'backs', label: 'Backs'),
  (key: 'immunization', label: 'Immunization'),
];

const String kOtherLabel = 'Other';

/// Simple wording shown on screen. Only the DISPLAY changes: the value that is
/// saved and checked by the rules stays exactly as before, so old records and
/// referral rules keep working.
const Map<String, String> kOptionLabels = {
  // Wound Dressing
  'Incised / Cut': 'Incision (clean cut)',
  'Abrasion': 'Abrasion (scrape)',
  'Laceration': 'Laceration (jagged cut)',
  'Puncture': 'Puncture (deep hole)',
  'Contaminated / Dirty': 'Dirty',
  'Normal Saline': 'Saline',
  'Povidone-Iodine': 'Povidone-iodine',
  'Sterile Gauze': 'Gauze',
  'Gauze Pad': 'Gauze pad',
  'Bandage / Roller': 'Roller bandage',
  'Crepe Bandage': 'Elastic bandage',
  'Adhesive Plaster': 'Adhesive tape',
  'Cotton / Cotton Ball': 'Cotton',
  'Eye Pad': 'Eye pad',
  'Sling / Arm Sling': 'Arm sling',
  'Wound edges clean': 'Clean edges',
  'No signs of infection': 'No infection signs',
  'Redness present': 'Redness',
  'Swelling present': 'Swelling',
  'Pus / discharge present': 'Pus / discharge',
  'Bleeding controlled': 'Bleeding stopped',
  'Edges approximated / sutured': 'Edges closed / stitched',
  '1st degree': '1st degree (red skin)',
  '2nd degree': '2nd degree (blisters)',
  '3rd degree': '3rd degree (deep)',
  'Controlled': 'Stopped',
  'Advice given (keep dry, signs of infection)': 'Advice given',
  'Referred to Hospital/RHU': 'Referred to hospital / RHU',
  'Parents / Guardian informed': 'Guardian informed',
  'Follow-up scheduled': 'Follow-up set',
  // First Aid
  'Insect Bite / Allergic Reaction': 'Insect bite / allergy',
  'Wound / Open Skin': 'Open wound',
  'Allergic Reaction / Hives': 'Allergy / hives',
  'Limited Movement': 'Hard to move',
  'Bleeding Control': 'Stop bleeding',
  'Rest / Observation': 'Rest and watch',
  'Basic Medication Given': 'Medicine given',
  'Immobilization': 'Immobilize (splint / sling)',
  'Requires Further Observation': 'Needs more monitoring',
  'Requires Further Treatment': 'Needs more treatment',
  'Advised to Monitor': 'Advised to watch',
  'Follow-up Recommended': 'Follow-up advised',
  'Clinic (already here)': 'In the clinic',
  'Outside School Grounds': 'Outside school',
  'Confusion / does not remember': 'Confused / memory loss',
  'Clear fluid or blood from nose or ears': 'Fluid or blood from nose / ear',
  'Weakness / numbness in limbs': 'Weak / numb arms or legs',
  // Medical Consultation
  'Allergy to medicine': 'Drug allergy',
  'Asthma / known condition': 'Asthma / long-term illness',
  'Taking medicine now': 'On medicine now',
  'Advice / Health Education': 'Advice given',
  'Signs of allergic reaction': 'Allergic reaction signs',
  'Head injury with vomiting or confusion': 'Head injury + vomiting / confusion',
  'Rested in Clinic then Returned to Class': 'Rested, then back to class',
  'Referred to Physician / Healthcare Facility': 'Referred to doctor / hospital',
  'Physician': 'Doctor',
  'Nurse + Physician': 'Nurse + doctor',
  'Hypertension / heart condition': 'High BP / heart condition',
  'Seizure / epilepsy': 'Seizures / epilepsy',
  // Health Counselling
  'Mental/Emotional Well-being': 'Mental health',
  'Medication / Treatment Adherence': 'Following treatment',
  'Physical Activity / Exercise': 'Exercise',
  'Substance Use (smoking, vaping, alcohol)': 'Smoking / vaping / alcohol',
  'Self-referred': 'Came on their own',
  'Referred by Teacher / Adviser': 'Teacher / adviser',
  'Referred by Guardian': 'Guardian',
  'Nurse-initiated / Follow-up': 'Nurse follow-up',
  'Referred from another clinic service': 'Other clinic service',
  'Advice / Guidance': 'Advice',
  'Preventive Education': 'Prevention tips',
  'Lifestyle / Behavior Advice': 'Lifestyle advice',
  'Medication-related Education': 'Medicine advice',
  // Prenatal
  'Not yet expected (early pregnancy)': 'Too early to feel',
  'High-Risk Follow-up': 'High-risk follow-up',
  'Pre-Eclampsia Monitoring': 'Pre-eclampsia check',
  'Referral to Doctor/OB': 'Referral to doctor / OB',
  'Referred for Further Testing': 'Referred for tests',
  'Parents/Guardian Informed (if student)': 'Guardian informed (if student)',
};

/// The simple wording for a saved choice. Anything not listed shows as is.
String optionLabel(String option) => kOptionLabels[option] ?? option;

class VisitServiceForms {
  const VisitServiceForms._();

  static const String otherServiceId = 'other';

  static ServiceField notes({String hint = 'Optional'}) => ServiceField(
        key: 'notes',
        label: 'Notes / Remarks',
        kind: ServiceFieldKind.multiline,
        maxChars: 500,
        hint: hint,
      );

  static const ServiceSlide reviewSlide = ServiceSlide(
    title: 'Review',
    custom: ServiceCustomSlide('form_review'),
  );

  static final Map<String, ServiceFormSpec> _specs = {
    'bpi': ServiceFormSpec(
      serviceId: 'bpi',
      allowOther: false,
      slides: [
        ServiceSlide(
          title: 'Measurement',
          fields: [
            ServiceField(
              key: 'height_cm',
              label: 'Height',
              kind: ServiceFieldKind.number,
              unit: 'cm',
              vital: VitalField.heightCm,
              validate: _vitalDecimal(90, 250),
              required: true,
              width: FieldWidth.half,
            ),
            ServiceField(
              key: 'weight_kg',
              label: 'Weight',
              kind: ServiceFieldKind.number,
              unit: 'kg',
              vital: VitalField.weightKg,
              validate: _vitalDecimal(10, 300),
              required: true,
              width: FieldWidth.half,
            ),
            ServiceField(
              key: 'bmi',
              label: 'BMI',
              kind: ServiceFieldKind.readOnly,
              width: FieldWidth.half,
              note: 'Calculated from height and weight.',
            ),
            ServiceField(
              key: 'bmi_class',
              label: 'BMI Classification',
              kind: ServiceFieldKind.readOnly,
              width: FieldWidth.half,
              note: 'Weight category for this BMI.',
            ),
            notes(),
          ],
        ),
        VisitServiceForms.reviewSlide,
      ],
    ),

    // =====================================================================
    // HEALTH COUNSELLING
    // Only boxes that fit the session are shown:
    //  - group size: only for a Group session
    //  - "what happened": only when understanding was not "Understood"
    //  - privacy chips: only when the app is not already forcing Restricted
    //  - referral boxes: only when a warning sign was ticked
    //  - follow-up boxes: only when follow-up is Yes
    // =====================================================================
    'health_counselling': ServiceFormSpec(
      serviceId: 'health_counselling',
      referralTitle:
          'Refer to the Guidance Counselor or Clinic Head today. Do not leave '
          'the person alone if there is a risk of self-harm.',
      referralReasons: (data, _) => counsellingReferralReasons(data),
      slides: [
        ServiceSlide(
          title: 'Session',
          icon: Icons.event_note_outlined,
          subtitle: 'Who, why and what was discussed',
          fields: [
            ServiceField(
              key: 'counsellor',
              label: 'Counsellor',
              kind: ServiceFieldKind.staffName,
              required: true,
              width: FieldWidth.half,
              note: 'Staff who ran the session.',
            ),
            ServiceField(
              key: 'session_date',
              label: 'Date / Time',
              kind: ServiceFieldKind.readOnly,
              width: FieldWidth.half,
              note: 'Taken from the visit.',
            ),
            ServiceField(
              key: 'referral_source',
              label: 'Why did they come?',
              kind: ServiceFieldKind.chips,
              options: kCounsellingReferralSource,
              required: true,
              note: 'Who sent them. Pick one.',
            ),
            ServiceField(
              key: 'session_type',
              otherOption: false,
              label: 'Session type',
              kind: ServiceFieldKind.chips,
              options: kCounsellingSessionType,
              required: true,
              width: FieldWidth.half,
            ),
            ServiceField(
              key: 'group_size',
              label: 'How many in the group?',
              kind: ServiceFieldKind.number,
              width: FieldWidth.half,
              validate: _vitalWhole(2, 100),
              shownWhenKey: 'session_type',
              shownWhenValues: ['Group'],
            ),
            ServiceField(
              key: 'topic',
              label: 'Counselling topic',
              kind: ServiceFieldKind.checkboxes,
              options: kCounsellingTopics,
              required: true,
              note: 'Tick all that were discussed.',
            ),
            ServiceField(
              key: 'reason',
              label: 'Reason / Concern',
              kind: ServiceFieldKind.multiline,
              maxChars: 300,
              validate: _cappedLength(300, 'the reason'),
              note: 'Why counselling was needed.',
            ),
            ServiceField(
              key: 'concern_signs',
              label: 'Warning signs check',
              kind: ServiceFieldKind.checkboxes,
              options: kCounsellingConcernSigns,
              required: true,
              note: 'Tick None if no concern. Any sign means refer today and '
                  'the record becomes Restricted.',
            ),
            ServiceField(
              key: 'privacy_level',
              otherOption: false,
              label: 'Privacy level',
              kind: ServiceFieldKind.chips,
              options: kCounsellingPrivacyLevels,
              shownWhenPredicate: (d) => !counsellingAutoRestricted(d),
              note: 'Sensitive topics or a warning sign set it to Restricted '
                  'automatically.',
            ),
            const ServiceField(
              key: 'privacy_notice',
              label: '',
              kind: ServiceFieldKind.notice,
              shownWhenPredicate: _counsellingIsRestricted,
            ),
          ],
        ),
        ServiceSlide(
          title: 'Counselling Given',
          icon: Icons.record_voice_over_outlined,
          subtitle: 'What was done and how it went',
          fields: [
            ServiceField(
              key: 'provided',
              label: 'Counselling provided',
              kind: ServiceFieldKind.checkboxes,
              options: kCounsellingProvided,
              required: true,
              note: 'Tick what was done.',
            ),
            ServiceField(
              key: 'understanding',
              otherOption: false,
              label: 'Understanding',
              kind: ServiceFieldKind.chips,
              options: kCounsellingUnderstanding,
              required: true,
            ),
            ServiceField(
              key: 'student_response',
              label: 'What happened?',
              kind: ServiceFieldKind.text,
              maxChars: 200,
              validate: _cappedLength(200, 'the response'),
              note: 'In one line: what they said or did.',
              shownWhenKey: 'understanding',
              shownWhenValues: ['Needs more explanation', 'Not receptive'],
            ),
            ServiceField(
              key: 'action_plan',
              label: 'What they agreed to do',
              kind: ServiceFieldKind.text,
              maxChars: 200,
              validate: _cappedLength(200, 'the plan'),
              hint: 'e.g. sleep before 10 PM, talk to adviser',
              note: 'The next step they agreed on. Optional.',
            ),
            ServiceField(
              key: 'duration_minutes',
              label: 'Duration in minutes',
              kind: ServiceFieldKind.number,
              unit: 'min',
              width: FieldWidth.half,
              validate: _vitalWhole(1, 180),
            ),
          ],
        ),
        ServiceSlide(
          title: 'Next Steps',
          icon: Icons.flag_outlined,
          subtitle: 'Referral and follow-up',
          fields: [
            ServiceField(
              key: 'guardian_informed',
              otherOption: false,
              label: 'Guardian informed',
              kind: ServiceFieldKind.chips,
              options: kCounsellingGuardian,
              required: true,
              width: FieldWidth.half,
              shownWhenPredicate: (d) =>
                  counsellingReferralReasons(d).isNotEmpty,
            ),
            ServiceField(
              key: 'referred_to',
              label: 'Referred to (name or place)',
              kind: ServiceFieldKind.text,
              required: true,
              shownWhenPredicate: (d) =>
                  counsellingReferralReasons(d).isNotEmpty,
              note: 'e.g. Guidance Counselor or hospital.',
            ),
            ServiceField(
              key: 'referral_reason',
              label: 'Reason for referral',
              kind: ServiceFieldKind.text,
              shownWhenPredicate: (d) =>
                  counsellingReferralReasons(d).isNotEmpty,
            ),
            ServiceField(
              key: 'follow_up_needed',
              otherOption: false,
              label: 'Follow-up needed?',
              kind: ServiceFieldKind.chips,
              options: kYesNo,
              required: true,
              width: FieldWidth.half,
            ),
            ServiceField(
              key: 'follow_up_date',
              label: 'Follow-up date',
              kind: ServiceFieldKind.date,
              width: FieldWidth.half,
              validate: _notPastDate('follow-up date'),
              shownWhenKey: 'follow_up_needed',
              shownWhenValues: ['Yes'],
              note: 'Today or later only.',
            ),
            ServiceField(
              key: 'follow_up_reason',
              label: 'Reason for follow-up',
              kind: ServiceFieldKind.text,
              required: true,
              shownWhenKey: 'follow_up_needed',
              shownWhenValues: ['Yes'],
            ),
            ServiceField(
              key: 'bmi_link',
              label: 'BMI',
              kind: ServiceFieldKind.linkServiceCard,
              opensService: 'bpi',
              buttonLabel: 'Open BMI',
              shownWhenKey: 'topic',
              shownWhenValues: [
                'Nutrition / Diet',
                'Physical Activity / Exercise'
              ],
              note: 'Height and weight may help. Optional.',
            ),
            ServiceField(
              key: 'consult_link',
              label: 'Medical Consultation',
              kind: ServiceFieldKind.linkServiceCard,
              opensService: 'medicine_consultation',
              buttonLabel: 'Open Medical Consultation',
              shownWhenKey: 'topic',
              shownWhenValues: ['Medication / Treatment Adherence', 'Sleep'],
              note: 'A doctor may need to check. Optional.',
            ),
            notes(),
          ],
        ),
        VisitServiceForms.reviewSlide,
      ],
    ),
    'prenatal': ServiceFormSpec(
      serviceId: 'prenatal',
      slides: [
        ServiceSlide(
          title: 'Pregnancy',
          fields: [
            ServiceField(
              key: 'lmp',
              label: 'Last Menstrual Period (LMP)',
              kind: ServiceFieldKind.date,
              required: true,
              datePast: true,
              width: FieldWidth.half,
              note: 'First day of her last period. Tick Unknown if not sure.',
            ),
            ServiceField(
              key: 'lmp_unknown',
              otherOption: false,
              label: 'LMP not sure / unknown',
              kind: ServiceFieldKind.checkboxes,
              options: const ['Unknown'],
              required: false,
              width: FieldWidth.half,
            ),
            ServiceField(
              key: 'aog',
              label: 'Age of Gestation',
              kind: ServiceFieldKind.readOnly,
              width: FieldWidth.half,
              note: 'Weeks of pregnancy so far.',
            ),
            ServiceField(
              key: 'edd',
              label: 'Expected Due Date',
              kind: ServiceFieldKind.readOnly,
              width: FieldWidth.half,
              note: 'Estimated delivery date.',
            ),
            ServiceField(
              key: 'gravida',
              label: 'Gravida',
              kind: ServiceFieldKind.number,
              required: true,
              width: FieldWidth.half,
              note: 'Total pregnancies, including this one.',
            ),
            ServiceField(
              key: 'para',
              label: 'Para',
              kind: ServiceFieldKind.number,
              required: true,
              width: FieldWidth.half,
              note: 'Births so far, not counting this pregnancy.',
            ),
          ],
        ),
        ServiceSlide(
          title: 'Examination',
          fields: [
            ServiceField(
              key: 'vitals_card',
              label: 'Vital Signs',
              kind: ServiceFieldKind.vitalsCard,
              width: FieldWidth.full,
              note: 'Taken in Vital Signs. Read only here.',
            ),
            ServiceField(
              key: 'bp_assessment',
              label: 'BP Classification',
              kind: ServiceFieldKind.readOnly,
              width: FieldWidth.half,
              note: 'From the visit\'s blood pressure.',
            ),
            ServiceField(
              key: 'fundal_height',
              label: 'Fundal Height',
              kind: ServiceFieldKind.number,
              unit: 'cm',
              required: false,
              width: FieldWidth.half,
              note: 'Top of the womb to pubic bone. From 20 weeks only.',
            ),
            ServiceField(
              key: 'fetal_heart_tone',
              label: 'Fetal Heart Tone',
              kind: ServiceFieldKind.number,
              unit: 'bpm',
              required: false,
              width: FieldWidth.half,
              note: 'Baby\'s heartbeat per minute.',
            ),
            ServiceField(
              key: 'fetal_heart_not_done',
              otherOption: false,
              label: '',
              kind: ServiceFieldKind.checkboxes,
              options: const ['Not done / no equipment'],
              required: false,
              width: FieldWidth.half,
            ),
            ServiceField(
              key: 'fetal_movement',
              otherOption: false,
              label: 'Fetal Movement',
              kind: ServiceFieldKind.dropdown,
              options: kFetalMovements,
              required: false,
              width: FieldWidth.full,
            ),
          ],
        ),
        ServiceSlide(
          title: 'Maternal Checks',
          fields: [
            ServiceField(
              key: 'edema',
              label: 'Swelling (edema)',
              kind: ServiceFieldKind.chips,
              options: kPrenatalEdema,
              required: false,
              width: FieldWidth.half,
              note: 'Swelling of the face or hands is more serious than feet.',
            ),
            ServiceField(
              key: 'urine_protein',
              otherOption: false,
              label: 'Urine Protein',
              kind: ServiceFieldKind.chips,
              options: kPrenatalUrineProtein,
              required: false,
              width: FieldWidth.half,
              note: 'Protein in urine can be a sign of pre-eclampsia.',
            ),
            ServiceField(
              key: 'danger_signs',
              label: 'Danger signs',
              kind: ServiceFieldKind.checkboxes,
              options: kPrenatalDangerSigns,
              required: false,
              width: FieldWidth.full,
            ),
          ],
        ),
        ServiceSlide(
          title: 'Care Plan',
          fields: [
            ServiceField(
              key: 'care_elsewhere',
              otherOption: false,
              label: 'Prenatal care elsewhere?',
              kind: ServiceFieldKind.dropdown,
              options: const ['Yes', 'No', 'Unknown'],
              required: false,
              width: FieldWidth.full,
            ),
            ServiceField(
              key: 'care_elsewhere_place',
              label: 'Where (RHU / hospital / OB name)',
              kind: ServiceFieldKind.text,
              required: false,
              width: FieldWidth.full,
              shownWhenKey: 'care_elsewhere',
              shownWhenValues: const ['Yes'],
            ),
            ServiceField(
              key: 'service_provided',
              otherKey: 'other_service_specify',
              label: 'Service / Care Provided',
              kind: ServiceFieldKind.checkboxes,
              options: kPrenatalServices,
              required: true,
              note: 'Tick at least one.',
            ),
            ServiceField(
              key: 'action_taken',
              label: 'Action / Advice',
              kind: ServiceFieldKind.checkboxes,
              options: kPrenatalActions,
              required: true,
              note: 'Tick at least one.',
            ),
            ServiceField(
              key: 'given_this_visit',
              label: 'Given This Visit',
              kind: ServiceFieldKind.checkboxes,
              options: kPrenatalGiven,
              note: 'Items handed to her today.',
            ),
            ServiceField(
              key: 'referred_to',
              label: 'Referred to',
              kind: ServiceFieldKind.text,
              required: false,
              width: FieldWidth.full,
              shownWhenKey: 'action_taken',
              shownWhenValues: const [
                'Referred for Further Testing',
                'Referred to Hospital/RHU'
              ],
              shownWhen: FieldCondition.startsWith,
            ),
            ServiceField(
              key: 'consult_link',
              label: 'Doctor-level check',
              kind: ServiceFieldKind.linkServiceCard,
              opensService: 'medicine_consultation',
              buttonLabel: 'Open Medical Consultation',
              shownWhenPredicate: (data) {
                final signs = _strListOf(data['danger_signs'])
                    .where((s) => s != 'None');
                return signs.isNotEmpty ||
                    _strOf(data['edema']) == 'Hands / Face' ||
                    _strOf(data['urine_protein']) == '2+ or more';
              },
              note: 'A doctor should check these signs. Optional.',
            ),
            ServiceField(
              key: 'follow_up_date',
              label: 'Follow-up Date',
              kind: ServiceFieldKind.date,
              required: false,
              width: FieldWidth.full,
              note: 'Today or later only.',
            ),
            notes(),
          ],
        ),
        VisitServiceForms.reviewSlide,
      ],
    ),
    'medication': ServiceFormSpec(
      serviceId: 'medication',
      kind: ServiceFormKind.custom,
      slides: [
        ServiceSlide(
          title: 'Reason',
          fields: [
            ServiceField(
              key: 'reason_common',
              otherKey: 'reason_other',
              label: 'Reason/Complaints',
              kind: ServiceFieldKind.checkboxes,
              options: kMedicationReasons,
              note: 'Why the medicine is given.',
            ),
          ],
        ),
        ServiceSlide(
          title: 'Medicines',
          custom: ServiceCustomSlide(
            'medicine_picker',
            requiredKeys: ['medicine_name'],
          ),
        ),
        VisitServiceForms.reviewSlide,
      ],
    ),
    'first_aid_treatment': ServiceFormSpec(
      serviceId: 'first_aid_treatment',
      crossValidate: (data) {
        final condition = _strOf(data['condition_after']);
        final disposition = _strOf(data['disposition']);
        if (condition == 'Requires Further Treatment' &&
            (disposition == 'Returned to Class' ||
                disposition == 'Advised to Monitor')) {
          return {
            'disposition':
                'The condition after first aid says more treatment is needed, '
                    'so "$disposition" does not fit.',
          };
        }
        return const {};
      },
      slides: [
        ServiceSlide(
          title: 'Incident',
          fields: [
            ServiceField(
              key: 'incident',
              label: 'What happened (Incident)',
              kind: ServiceFieldKind.dropdown,
              options: kFirstAidIncidents,
              required: true,
              width: FieldWidth.half,
            ),
            ServiceField(
              key: 'incident_timing',
              label: 'When did it happen?',
              kind: ServiceFieldKind.dropdown,
              options: kFirstAidTimings,
              required: true,
              width: FieldWidth.half,
            ),
            ServiceField(
              key: 'incident_place',
              label: 'Where did it happen?',
              kind: ServiceFieldKind.dropdown,
              options: kFirstAidPlaces,
              width: FieldWidth.half,
            ),
            ServiceField(
              key: 'incident_cause',
              label: 'How did it happen?',
              kind: ServiceFieldKind.text,
              width: FieldWidth.half,
              maxChars: 100,
              validate: _cappedLength(100, 'this note'),
              hint: 'e.g. fell during PE',
              shownWhenPredicate: (data) => !firstAidIsIllness(data),
            ),
            ServiceField(
              key: 'body_part',
              label: 'Body part (Location)',
              kind: ServiceFieldKind.dropdown,
              options: ClinicPurposes.bodySites,
              required: true,
              width: FieldWidth.half,
              shownWhenPredicate: (data) => !firstAidIsIllness(data),
            ),
            ServiceField(
              key: 'findings',
              label: 'What you see (Findings)',
              kind: ServiceFieldKind.checkboxes,
              options: kFirstAidFindings,
              optionsBuilder: firstAidFindingsFor,
              required: true,
              note: 'Tick what you see.',
            ),
            ServiceField(
              key: 'pain_level',
              label: 'Pain level (0 = none, 10 = worst)',
              kind: ServiceFieldKind.number,
              unit: '/10',
              required: true,
              width: FieldWidth.half,
              shownWhenKey: 'findings',
              shownWhenValues: ['Pain'],
              validate: _painWholeScore(),
            ),
            ServiceField(
              key: 'head_injury_signs',
              label: 'Head injury check',
              kind: ServiceFieldKind.checkboxes,
              options: kFirstAidHeadSigns,
              required: true,
              shownWhenPredicate: firstAidIsHeadCase,
              note: 'Any sign needs a doctor.',
            ),
            ServiceField(
              key: 'consciousness',
              otherOption: false,
              label: 'Level of consciousness',
              kind: ServiceFieldKind.chips,
              options: kFirstAidConsciousness,
              required: true,
              width: FieldWidth.half,
              shownWhenPredicate: (data) {
                final incident = _strOf(data['incident']);
                return incident == 'Fainting' || firstAidIsHeadCase(data);
              },
            ),
          ],
        ),
        ServiceSlide(
          title: 'First Aid Provided',
          fields: [
            ServiceField(
              key: 'vitals_card',
              label: 'Visit Vitals',
              kind: ServiceFieldKind.vitalsCard,
              shownWhenPredicate: firstAidNeedsVitals,
              note: 'Needed for this kind of incident.',
            ),
            ServiceField(
              key: 'treatment',
              label: 'First aid given',
              kind: ServiceFieldKind.checkboxes,
              options: kFirstAidTreatments,
              optionsBuilder: firstAidTreatmentsFor,
              required: true,
              note: 'Tick what was done. Wound care goes in Wound Dressing.',
            ),
            ServiceField(
              key: 'known_allergies',
              otherOption: false,
              label: 'Known allergies',
              kind: ServiceFieldKind.text,
              width: FieldWidth.half,
              shownWhenKey: 'treatment',
              shownWhenValues: ['Basic Medication Given'],
              note: 'Ask before giving medicine.',
            ),
            ServiceField(
              key: 'medication_given',
              label: 'Medicine given (name and dose)',
              kind: ServiceFieldKind.text,
              width: FieldWidth.half,
              shownWhenKey: 'treatment',
              shownWhenValues: ['Basic Medication Given'],
            ),
            ServiceField(
              key: 'medication_card',
              label: 'Medication from clinic stock',
              kind: ServiceFieldKind.medicationCard,
              shownWhenKey: 'treatment',
              shownWhenValues: ['Basic Medication Given'],
              note: 'Optional. Deducts from clinic stock.',
            ),
            ServiceField(
              key: 'observation_minutes',
              label: 'Minutes rested',
              kind: ServiceFieldKind.number,
              unit: 'min',
              width: FieldWidth.half,
              shownWhenKey: 'treatment',
              shownWhenValues: ['Rest / Observation'],
              validate: _vitalWhole(0, 600),
            ),
            ServiceField(
              key: 'wound_hint',
              label: 'Wound care',
              kind: ServiceFieldKind.linkServiceCard,
              opensService: 'wound_dressing',
              buttonLabel: 'Open Wound Dressing',
              shownWhenPredicate: firstAidSuggestsWoundCare,
              note: 'Matching answers are filled in for you. Optional.',
            ),
          ],
        ),
        ServiceSlide(
          title: 'Condition & Disposition',
          fields: [
            ServiceField(
              key: 'condition_after',
              otherOption: false,
              label: 'Condition after first aid',
              kind: ServiceFieldKind.dropdown,
              options: kConditionAfterTreatment,
              required: true,
              width: FieldWidth.half,
            ),
            ServiceField(
              key: 'disposition',
              label: 'What happens next',
              kind: ServiceFieldKind.chips,
              options: kFirstAidDispositions,
              required: true,
              note: 'Pick one.',
            ),
            ServiceField(
              key: 'guardian_informed',
              otherOption: false,
              label: 'Parent / Guardian informed?',
              kind: ServiceFieldKind.chips,
              options: kFirstAidGuardian,
              required: true,
              width: FieldWidth.half,
              shownWhenPredicate: (data) {
                final disposition = _strOf(data['disposition']);
                return disposition == 'Sent Home' ||
                    isReferralDisposition(disposition);
              },
            ),
            ServiceField(
              key: 'referred_to_where',
              label: 'Which hospital / clinic?',
              kind: ServiceFieldKind.text,
              required: true,
              shownWhenPredicate: (data) =>
                  isReferralDisposition(_strOf(data['disposition'])),
            ),
            ServiceField(
              key: 'referral_reason',
              label: 'Reason for referral',
              kind: ServiceFieldKind.text,
              shownWhenPredicate: (data) =>
                  isReferralDisposition(_strOf(data['disposition'])),
            ),
            ServiceField(
              key: 'sent_to',
              label: 'Sent home with',
              kind: ServiceFieldKind.text,
              required: true,
              shownWhenKey: 'disposition',
              shownWhenValues: ['Sent Home'],
              note: 'Who took the student home.',
            ),
            ServiceField(
              key: 'follow_up_date',
              label: 'Follow-up date',
              kind: ServiceFieldKind.date,
              width: FieldWidth.half,
              shownWhenKey: 'disposition',
              shownWhenValues: ['Follow-up'],
              shownWhen: FieldCondition.startsWith,
            ),
            ServiceField(
              key: 'consult_link',
              label: 'Doctor-level check',
              kind: ServiceFieldKind.linkServiceCard,
              opensService: 'medicine_consultation',
              buttonLabel: 'Open Medical Consultation',
              shownWhenPredicate: firstAidSuggestsConsultation,
              note: 'For a doctor-level check. Optional.',
            ),
            notes(),
          ],
        ),
        VisitServiceForms.reviewSlide,
      ],
    ),
    'wound_dressing': ServiceFormSpec(
      serviceId: 'wound_dressing',
      slides: [
        ServiceSlide(
          title: 'The Wound',
          fields: [
            ServiceField(
              key: 'injury_timing',
              label: 'When did it happen?',
              kind: ServiceFieldKind.dropdown,
              options: kWoundInjuryTiming,
              required: true,
              width: FieldWidth.half,
            ),
            ServiceField(
              key: 'injury_cause',
              label: 'How did it happen?',
              kind: ServiceFieldKind.text,
              width: FieldWidth.half,
              hint: 'e.g. Fell on the court',
              validate: _cappedLength(100, 'this note'),
            ),
            ServiceField(
              key: 'wound_location',
              label: 'Where on the body? (Location)',
              kind: ServiceFieldKind.dropdown,
              options: ClinicPurposes.bodySites,
              required: true,
              width: FieldWidth.half,
            ),
            ServiceField(
              key: 'wound_type',
              label: 'Wound type',
              kind: ServiceFieldKind.dropdown,
              options: kWoundTypes,
              required: true,
              width: FieldWidth.half,
            ),
            ServiceField(
              key: 'burn_degree',
              otherOption: false,
              label: 'Burn degree',
              kind: ServiceFieldKind.chips,
              options: kBurnDegrees,
              required: true,
              width: FieldWidth.half,
              shownWhenKey: 'wound_type',
              shownWhenValues: ['Burn'],
            ),
            ServiceField(
              key: 'wound_condition',
              label: 'Wound condition',
              kind: ServiceFieldKind.chips,
              options: kWoundConditions,
              required: true,
              width: FieldWidth.half,
            ),
            ServiceField(
              key: 'bleeding',
              otherOption: false,
              label: 'Bleeding',
              kind: ServiceFieldKind.chips,
              options: kBleedingStatus,
              required: true,
              width: FieldWidth.half,
              shownWhenKey: 'wound_type',
              shownWhenValues: ['Burn', 'Blister'],
              shownWhen: FieldCondition.noneOf,
            ),
            ServiceField(
              key: 'vitals_card',
              label: 'Visit Vitals (Temperature / Blood Pressure)',
              kind: ServiceFieldKind.vitalsCard,
              width: FieldWidth.full,
              shownWhenPredicate: woundNeedsVitals,
              note: 'For infected wounds or deep burns.',
            ),
            ServiceField(
              key: 'tetanus_status',
              otherOption: false,
              label: 'Tetanus shot up to date?',
              kind: ServiceFieldKind.chips,
              options: kTetanusStatus,
              width: FieldWidth.half,
              shownWhenPredicate: woundNeedsTetanusCheck,
              note: 'This wound type can cause tetanus.',
            ),
          ],
        ),
        ServiceSlide(
          title: 'Cleaning & Dressing',
          fields: [
            ServiceField(
              key: 'cleaning_performed',
              label: 'How the wound was cleaned',
              kind: ServiceFieldKind.checkboxes,
              options: kWoundCleaningPerformed,
              optionsBuilder: woundCleaningFor,
              required: true,
            ),
            ServiceField(
              key: 'dressing_applied',
              label: 'Dressing used',
              kind: ServiceFieldKind.checkboxes,
              options: kWoundDressingMaterials,
              required: true,
            ),
            ServiceField(
              key: 'assessment',
              label: 'What you see (Findings)',
              kind: ServiceFieldKind.checkboxes,
              options: kWoundFindings,
              optionsBuilder: woundFindingsFor,
              required: true,
              note: 'Only what you see. No diagnosis.',
            ),
            ServiceField(
              key: 'action_taken',
              label: 'What was done (Action taken)',
              kind: ServiceFieldKind.checkboxes,
              options: kWoundActions,
              required: true,
              note: 'Tick Follow-up set to add a next dressing date.',
            ),
            ServiceField(
              key: 'referred_to',
              label: 'Referred to (where)',
              kind: ServiceFieldKind.text,
              required: true,
              width: FieldWidth.half,
              shownWhenKey: 'action_taken',
              shownWhenValues: ['Referred to Hospital/RHU'],
            ),
            ServiceField(
              key: 'no_further_dressing',
              otherOption: false,
              label: 'Dressing plan',
              kind: ServiceFieldKind.chips,
              options: const [kWoundNoFurtherDressing],
              width: FieldWidth.half,
              shownWhenPredicate: (data) => !woundNeedsNextDressing(data),
              note: 'Tick if no more dressing is needed.',
            ),
            ServiceField(
              key: 'next_dressing_date',
              label: 'Next dressing date',
              kind: ServiceFieldKind.date,
              width: FieldWidth.half,
              required: true,
              shownWhenPredicate: woundNeedsNextDressing,
              note: 'Today or later.',
            ),
            ServiceField(
              key: 'medication_card',
              label: 'Medicine given (optional)',
              kind: ServiceFieldKind.medicationCard,
              width: FieldWidth.full,
              note: 'Only medicine from clinic stock, e.g. ointment.',
            ),
            notes(),
          ],
        ),
        VisitServiceForms.reviewSlide,
      ],
    ),

    // =====================================================================
    // MEDICAL CONSULTATION
    // Only boxes that fit the case are shown:
    //  - pain level: only for painful complaints
    //  - "since when": only when the problem is more than 3 days old
    //  - history details: only after a known condition is ticked
    //  - LMP: only for a female visitor with a related complaint
    //  - allergies: only when "Medication" is ticked in Treatment
    //  - medication card: only when "Medication" is ticked
    //  - "other condition": only after an impression is typed
    //  - guardian / excuse slip: only when sent home or referred
    //  - referral boxes: only when referred
    //  - follow-up boxes: only when follow-up is Yes
    // =====================================================================
    'medicine_consultation': ServiceFormSpec(
      serviceId: 'medicine_consultation',
      referralReasons: (data, vitals) =>
          consultationReferralReasons(data, vitals),
      warnings: (data, vitals) => consultationWarnings(data, vitals),
      slides: [
        ServiceSlide(
          title: 'Complaint',
          icon: Icons.chat_bubble_outline_rounded,
          subtitle: 'Why the patient came and any danger signs',
          fields: [
            ServiceField(
              key: 'chief_complaint',
              label: 'Chief complaint',
              kind: ServiceFieldKind.text,
              required: true,
              validate: _cappedLength(150, 'the complaint'),
              note: 'Main problem, in the patient\'s words.',
            ),
            ServiceField(
              key: 'symptoms',
              otherKey: 'symptom_other',
              label: 'Complaint category (tick any)',
              kind: ServiceFieldKind.checkboxes,
              options: kConsultationComplaints,
              note: 'Quick pick. Helps clinic reports.',
            ),
            ServiceField(
              key: 'duration_onset_choice',
              otherOption: false,
              label: 'How long?',
              kind: ServiceFieldKind.chips,
              options: kConsultationDuration,
            ),
            ServiceField(
              key: 'duration_onset',
              label: 'Since when / how many days?',
              kind: ServiceFieldKind.text,
              hint: 'e.g. 5 days',
              width: FieldWidth.half,
              shownWhenPredicate: consultationLongDuration,
            ),
            ServiceField(
              key: 'pain_level',
              label: 'Pain level (0 = none, 10 = worst)',
              kind: ServiceFieldKind.number,
              unit: '/10',
              width: FieldWidth.half,
              validate: _painWholeScore(),
              shownWhenPredicate: consultationHasPain,
            ),
            ServiceField(
              key: 'red_flags',
              label: 'Danger signs check',
              kind: ServiceFieldKind.checkboxes,
              options: kConsultationRedFlags,
              required: true,
              note:
                  'Tick None if there are no danger signs. Any sign means referral.',
            ),
          ],
        ),
        ServiceSlide(
          title: 'Vitals & History',
          icon: Icons.monitor_heart_outlined,
          subtitle: 'Today\'s readings and background conditions',
          fields: [
            ServiceField(
              key: 'vitals_card',
              label: 'Visit Vitals',
              kind: ServiceFieldKind.vitalsCard,
              note: 'Taken in Vital Signs. Read only here.',
            ),
            ServiceField(
              key: 'history',
              label: 'Known conditions (tick if any)',
              kind: ServiceFieldKind.checkboxes,
              options: kConsultationHistory,
            ),
            ServiceField(
              key: 'history_details',
              label: 'Details of the condition / medicine taken',
              kind: ServiceFieldKind.multiline,
              maxChars: 300,
              validate: _cappedLength(300, 'the details'),
              shownWhenPredicate: (d) => _answersOf(d['history']).isNotEmpty,
            ),
            ServiceField(
              key: 'lmp_date',
              label: 'Last menstrual period (LMP)',
              kind: ServiceFieldKind.date,
              width: FieldWidth.half,
              validate: _notFutureDate('LMP date'),
              shownWhenPredicate: consultationAsksLmp,
              note: 'Asked because of the complaint. Optional.',
            ),
          ],
        ),
        ServiceSlide(
          title: 'Assessment',
          icon: Icons.fact_check_outlined,
          subtitle: 'What was found and by whom',
          fields: [
            ServiceField(
              key: 'physical_exam',
              label: 'Examination findings',
              kind: ServiceFieldKind.multiline,
              maxChars: 500,
              note: 'Only what was actually checked. Optional.',
            ),
            ServiceField(
              key: 'clinical_impression',
              label: 'Assessment / impression',
              kind: ServiceFieldKind.multiline,
              required: true,
              note: 'Working impression. Not a final diagnosis.',
            ),
            ServiceField(
              key: 'secondary_diagnosis',
              label: 'Other condition found',
              kind: ServiceFieldKind.text,
              shownWhenPredicate: (d) =>
                  _strOf(d['clinical_impression']).isNotEmpty,
            ),
            ServiceField(
              key: 'attending',
              otherOption: false,
              label: 'Examined by',
              kind: ServiceFieldKind.chips,
              options: kAttendingStaff,
            ),
          ],
        ),
        ServiceSlide(
          title: 'Treatment',
          icon: Icons.healing_outlined,
          subtitle: 'What was done in the clinic',
          fields: [
            ServiceField(
              key: 'treatment',
              label: 'Treatment given',
              kind: ServiceFieldKind.checkboxes,
              options: kConsultationTreatment,
              required: true,
            ),
            ServiceField(
              key: 'known_allergies',
              otherOption: false,
              label: 'Any known allergy? (check before giving medicine)',
              kind: ServiceFieldKind.chips,
              options: kYesNoUnknown,
              required: true,
              width: FieldWidth.half,
              shownWhenPredicate: consultationGivesMedicine,
            ),
            ServiceField(
              key: 'allergy_specify',
              label: 'Allergic to what?',
              kind: ServiceFieldKind.text,
              required: true,
              width: FieldWidth.half,
              shownWhenPredicate: (d) =>
                  consultationGivesMedicine(d) &&
                  _strOf(d['known_allergies']) == 'Yes',
            ),
            ServiceField(
              key: 'medication_card',
              label: 'Medication',
              kind: ServiceFieldKind.medicationCard,
              shownWhenPredicate: consultationGivesMedicine,
              note: 'Record it in Medication to deduct stock.',
            ),
            ServiceField(
              key: 'wound_link',
              label: 'Wound Dressing',
              kind: ServiceFieldKind.linkServiceCard,
              opensService: 'wound_dressing',
              buttonLabel: 'Open Wound Dressing',
              shownWhenKey: 'treatment',
              shownWhenValues: ['Wound Care'],
              note: 'For a full wound record. Optional.',
            ),
            ServiceField(
              key: 'first_aid_link',
              label: 'First Aid',
              kind: ServiceFieldKind.linkServiceCard,
              opensService: 'first_aid_treatment',
              buttonLabel: 'Open First Aid Treatment',
              shownWhenKey: 'symptoms',
              shownWhenValues: ['Injury', 'Nosebleed'],
              note: 'Records on-the-spot care. Optional.',
            ),
            ServiceField(
              key: 'rest_minutes',
              label: 'Minutes rested',
              kind: ServiceFieldKind.number,
              unit: 'min',
              width: FieldWidth.half,
              hint: 'e.g. 30',
              validate: _minutesWhole(),
              shownWhenPredicate: (d) =>
                  _answersOf(d['treatment']).contains('Rest / Observation') ||
                  _strOf(d['disposition']).startsWith('Rested'),
            ),
            ServiceField(
              key: 'management_details',
              label: 'Treatment notes',
              kind: ServiceFieldKind.multiline,
              maxChars: 300,
              validate: _cappedLength(300, 'the notes'),
              note: 'Anything not covered above. Optional.',
            ),
          ],
        ),
        ServiceSlide(
          title: 'Plan & Disposition',
          icon: Icons.alt_route_rounded,
          subtitle: 'What happens next',
          fields: [
            ServiceField(
              key: 'disposition',
              label: 'What happens next',
              kind: ServiceFieldKind.chips,
              options: kConsultationDispositions,
              required: true,
              note: 'Pick one.',
            ),
            ServiceField(
              key: 'sent_home_with',
              label: 'Sent home with',
              kind: ServiceFieldKind.text,
              width: FieldWidth.half,
              shownWhenKey: 'disposition',
              shownWhenValues: ['Sent Home'],
            ),
            ServiceField(
              key: 'guardian_informed',
              otherOption: false,
              label: 'Parent / Guardian informed?',
              kind: ServiceFieldKind.chips,
              options: kYesNo,
              required: true,
              width: FieldWidth.half,
              shownWhenPredicate: consultationLeavesClinic,
            ),
            ServiceField(
              key: 'referred_to',
              label: 'Which hospital / clinic / doctor?',
              kind: ServiceFieldKind.text,
              required: true,
              shownWhenPredicate: (d) => kConsultationReferralDispositions
                  .contains(_strOf(d['disposition'])),
            ),
            ServiceField(
              key: 'referral_reason',
              label: 'Reason for referral',
              kind: ServiceFieldKind.text,
              shownWhenPredicate: (d) => kConsultationReferralDispositions
                  .contains(_strOf(d['disposition'])),
            ),
            ServiceField(
              key: 'excuse_slip_needed',
              otherOption: false,
              label: 'Excuse slip needed?',
              kind: ServiceFieldKind.chips,
              options: kYesNo,
              width: FieldWidth.half,
              shownWhenPredicate: consultationLeavesClinic,
              note: 'Printed in Medical Certificate.',
            ),
            ServiceField(
              key: 'excuse_days',
              label: 'Days excused',
              kind: ServiceFieldKind.number,
              unit: 'days',
              width: FieldWidth.half,
              hint: 'e.g. 2',
              validate: _excuseDaysWhole(),
              shownWhenPredicate: (d) =>
                  consultationLeavesClinic(d) &&
                  _strOf(d['excuse_slip_needed']) == 'Yes',
            ),
            ServiceField(
              key: 'follow_up_needed',
              otherOption: false,
              label: 'Follow-up needed?',
              kind: ServiceFieldKind.chips,
              options: kYesNo,
              required: true,
              width: FieldWidth.half,
            ),
            ServiceField(
              key: 'follow_up_date',
              label: 'Follow-up date',
              kind: ServiceFieldKind.date,
              width: FieldWidth.half,
              shownWhenKey: 'follow_up_needed',
              shownWhenValues: ['Yes'],
              validate: _notPastDate('follow-up date'),
            ),
            ServiceField(
              key: 'follow_up_instructions',
              label: 'Follow-up instructions',
              kind: ServiceFieldKind.text,
              shownWhenKey: 'follow_up_needed',
              shownWhenValues: ['Yes'],
            ),
            ServiceField(
              key: 'counselling_link',
              label: 'Health Counselling',
              kind: ServiceFieldKind.linkServiceCard,
              opensService: 'health_counselling',
              buttonLabel: 'Consider Health Counselling',
              shownWhenPredicate: (data) {
                final words =
                    '${data['chief_complaint'] ?? ''} ${data['history_details'] ?? ''}'
                        .toLowerCase();
                return const [
                  'stress',
                  'anxious',
                  'anxiety',
                  'sad',
                  'hopeless',
                  'depress',
                  'bully',
                  'self-harm',
                  'suicid',
                ].any(words.contains);
              },
              note: 'Counselling may help. Optional.',
            ),
            notes(),
          ],
        ),
        VisitServiceForms.reviewSlide,
      ],
    ),
    'medicine_certificate': ServiceFormSpec(
      serviceId: 'medicine_certificate',
      kind: ServiceFormKind.custom,
      slides: [
        ServiceSlide(
          title: 'Certificate',
          custom: ServiceCustomSlide('certificate_sheet'),
        ),
      ],
    ),
    'vital_signs': ServiceFormSpec(
      serviceId: 'vital_signs',
      allowOther: false,
      crossValidate: _vitalSignsCrossRules,
      slides: [
        ServiceSlide(
          title: 'Readings',
          groups: [
            FieldGroup(kVitalChoiceKeys['Blood Pressure']!,
                title: 'Blood Pressure'),
            FieldGroup(kVitalChoiceKeys['Temperature']!, title: 'Temperature'),
            FieldGroup(kVitalChoiceKeys['Pulse']!, title: 'Pulse'),
            FieldGroup(kVitalChoiceKeys['Respiratory Rate']!,
                title: 'Respiratory Rate'),
            FieldGroup(kVitalChoiceKeys['O₂ Saturation']!,
                title: 'Oxygen Saturation'),
          ],
          fields: [
            ServiceField(
              key: kVitalsSelectedKey,
              label: 'Vital signs to take',
              kind: ServiceFieldKind.checkboxes,
              options: const [kSelectAllLabel, ...kVitalChoices],
              required: true,
              note: 'Tick the vitals to take. Unticked ones are saved empty.',
            ),
            // ---- Blood pressure ----
            ServiceField(
              key: 'systolic',
              label: 'Systolic',
              kind: ServiceFieldKind.number,
              unit: 'mmHg',
              vital: VitalField.systolic,
              required: true,
              width: FieldWidth.half,
              shownWhenKey: kVitalsSelectedKey,
              shownWhenValues: const ['Blood Pressure'],
              validate: _vitalWhole(
                  VitalClassifier.systolicMin, VitalClassifier.systolicMax),
            ),
            ServiceField(
              key: 'diastolic',
              label: 'Diastolic',
              kind: ServiceFieldKind.number,
              unit: 'mmHg',
              vital: VitalField.diastolic,
              required: true,
              width: FieldWidth.half,
              shownWhenKey: kVitalsSelectedKey,
              shownWhenValues: const ['Blood Pressure'],
              validate: _vitalWhole(
                  VitalClassifier.diastolicMin, VitalClassifier.diastolicMax),
            ),
            ServiceField(
              key: 'position',
              label: 'Position',
              kind: ServiceFieldKind.chips,
              options: kBpPositions,
              required: true,
              width: FieldWidth.half,
              shownWhenKey: kVitalsSelectedKey,
              shownWhenValues: const ['Blood Pressure'],
            ),
            ServiceField(
              key: 'arm_used',
              label: 'Arm Used',
              kind: ServiceFieldKind.chips,
              options: kBpArms,
              required: true,
              width: FieldWidth.half,
              shownWhenKey: kVitalsSelectedKey,
              shownWhenValues: const ['Blood Pressure'],
            ),
            ServiceField(
              key: 'bp_assessment',
              label: 'Blood Pressure Classification',
              kind: ServiceFieldKind.readOnly,
              width: FieldWidth.half,
              shownWhenKey: kVitalsSelectedKey,
              shownWhenValues: const ['Blood Pressure'],
              note: 'One reading is a screening, not a diagnosis.',
            ),
            // ---- Temperature ----
            ServiceField(
              key: 'temp_c',
              label: 'Temperature',
              kind: ServiceFieldKind.number,
              unit: '°C',
              vital: VitalField.temperature,
              required: true,
              width: FieldWidth.half,
              hint: '36.8',
              shownWhenKey: kVitalsSelectedKey,
              shownWhenValues: const ['Temperature'],
              validate: _vitalDecimal(VitalClassifier.temperatureMin,
                  VitalClassifier.temperatureMax),
            ),
            ServiceField(
              key: 'method',
              label: 'Method / Site',
              kind: ServiceFieldKind.dropdown,
              options: kTemperatureMethods,
              required: true,
              width: FieldWidth.half,
              shownWhenKey: kVitalsSelectedKey,
              shownWhenValues: const ['Temperature'],
              note: 'Underarm reads about 0.3–0.5 °C lower than oral.',
            ),
            ServiceField(
              key: 'temp_assessment',
              label: 'Temperature Classification',
              kind: ServiceFieldKind.readOnly,
              width: FieldWidth.half,
              shownWhenKey: kVitalsSelectedKey,
              shownWhenValues: const ['Temperature'],
              note: 'Calculated from the temperature.',
            ),
            // ---- Pulse ----
            ServiceField(
              key: 'pulse_bpm',
              label: 'Pulse Rate (beats per minute)',
              kind: ServiceFieldKind.number,
              unit: 'bpm',
              vital: VitalField.heartRate,
              required: true,
              width: FieldWidth.half,
              shownWhenKey: kVitalsSelectedKey,
              shownWhenValues: const ['Pulse'],
              note: 'Beats per minute '
                  '(${VitalClassifier.pulseMin}–${VitalClassifier.pulseMax}).',
              validate: _vitalWhole(
                  VitalClassifier.pulseMin, VitalClassifier.pulseMax),
            ),
            ServiceField(
              key: 'pulse_assessment',
              label: 'Pulse Classification',
              kind: ServiceFieldKind.readOnly,
              width: FieldWidth.half,
              shownWhenKey: kVitalsSelectedKey,
              shownWhenValues: const ['Pulse'],
              note: 'Calculated from the pulse.',
            ),
            // ---- Respiratory rate ----
            ServiceField(
              key: 'resp_rate',
              label: 'Respiratory Rate',
              kind: ServiceFieldKind.number,
              unit: '/min',
              vital: VitalField.respRate,
              required: true,
              width: FieldWidth.half,
              shownWhenKey: kVitalsSelectedKey,
              shownWhenValues: const ['Respiratory Rate'],
              validate:
                  _vitalWhole(VitalClassifier.respMin, VitalClassifier.respMax),
            ),
            ServiceField(
              key: 'resp_assessment',
              label: 'Respiratory Classification',
              kind: ServiceFieldKind.readOnly,
              width: FieldWidth.half,
              shownWhenKey: kVitalsSelectedKey,
              shownWhenValues: const ['Respiratory Rate'],
              note: 'Calculated from the breathing rate.',
            ),
            // ---- Oxygen saturation ----
            ServiceField(
              key: 'o2_sat',
              label: 'Oxygen Saturation (SpO2)',
              kind: ServiceFieldKind.number,
              unit: '%',
              vital: VitalField.o2Sat,
              required: true,
              width: FieldWidth.half,
              shownWhenKey: kVitalsSelectedKey,
              shownWhenValues: const ['O₂ Saturation'],
              validate:
                  _vitalWhole(VitalClassifier.spo2Min, VitalClassifier.spo2Max),
            ),
            ServiceField(
              key: 'spo2_assessment',
              label: 'Oxygen Saturation Classification',
              kind: ServiceFieldKind.readOnly,
              width: FieldWidth.half,
              shownWhenKey: kVitalsSelectedKey,
              shownWhenValues: const ['O₂ Saturation'],
              note: 'Calculated from the oxygen level.',
            ),
          ],
        ),
        ServiceSlide(
          title: 'Action & Referral',
          fields: [
            ServiceField(
              key: 'action_taken',
              label: 'Action Taken',
              kind: ServiceFieldKind.checkboxes,
              options: kVitalActions,
              note: 'Tick all that apply.',
            ),
            ServiceField(
              key: 'consult_link',
              label: 'Doctor-level check',
              kind: ServiceFieldKind.linkServiceCard,
              opensService: 'medicine_consultation',
              buttonLabel: 'Open Medical Consultation',
              shownWhenPredicate: vitalReadingsAbnormal,
              note: 'A reading is abnormal. Optional.',
            ),
            ServiceField(
              key: 'referral_reason',
              label: 'Reason for Referral',
              kind: ServiceFieldKind.multiline,
              required: true,
              maxChars: 300,
              note: 'Why the person is being referred.',
              shownWhenKey: 'action_taken',
              shownWhenValues: kReferralActions,
            ),
            ServiceField(
              key: 'referred_to',
              label: 'Referred to (where)',
              kind: ServiceFieldKind.text,
              required: true,
              hint: 'e.g. Tangub City District Hospital',
              shownWhenKey: 'action_taken',
              shownWhenValues: kReferralActions,
            ),
          ],
        ),
        VisitServiceForms.reviewSlide,
      ],
    ),
    otherServiceId: ServiceFormSpec(
      serviceId: otherServiceId,
      slides: [
        ServiceSlide(
          title: 'Service',
          fields: [
            ServiceField(
              key: 'service_name',
              label: 'Service Name',
              kind: ServiceFieldKind.readOnly,
              width: FieldWidth.full,
              note: 'The name typed against "Other" on step 2.',
            ),
            ServiceField(
              key: 'description',
              label: 'Description',
              kind: ServiceFieldKind.multiline,
              required: true,
            ),
            ServiceField(
              key: 'action_taken',
              label: 'Action Taken',
              kind: ServiceFieldKind.multiline,
              required: true,
            ),
            notes(),
          ],
        ),
        VisitServiceForms.reviewSlide,
      ],
    ),
  };

  static ServiceFormSpec forId(String serviceId) =>
      _specs[serviceId] ??
      ServiceFormSpec(
        serviceId: serviceId,
        slides: [
          ServiceSlide(
            title: 'Details',
            fields: [
              ServiceField(
                key: 'description',
                label: 'Description',
                kind: ServiceFieldKind.multiline,
                required: true,
              ),
              notes(),
            ],
          ),
        ],
      );

  static const int pregnancyDays = 280;
}