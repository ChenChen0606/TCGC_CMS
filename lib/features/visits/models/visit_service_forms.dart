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
  });

  final String key;

  final String label;

  final ServiceFieldKind kind;

  final String? unit;

  final String? hint;

  final List<String> options;

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

  bool isRequiredIn(Map<String, dynamic> data) =>
      required && isShownIn(data) && (requiredWhen?.call(data) ?? true);
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
  });

  final String title;

  final List<ServiceField> fields;

  final ServiceCustomSlide? custom;

  final List<FieldGroup> groups;
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

  List<String> get requiredKeys => [
        for (final s in slides) ...[
          ...s.fields.where((f) => f.required).map((f) => f.key),
          ...?s.custom?.requiredKeys,
        ],
      ];

  List<String> requiredKeysIn(Map<String, dynamic> data) => [
        for (final s in slides) ...[
          ...s.fields.where((f) => f.isRequiredIn(data)).map((f) => f.key),
          ...?s.custom?.requiredKeys,
        ],
      ];

  bool isAnswered(Map<String, dynamic> data) {
    final needed = requiredKeysIn(data);
    if (needed.isEmpty) {
      return data.entries.any((e) => '${e.value}'.trim().isNotEmpty);
    }
    return needed.every((k) {
      final v = data[k];
      final empty = v == null ||
          (v is String && v.trim().isEmpty) ||
          (v is List && v.isEmpty);
      if (empty) return false;
      return validateInContext(k, data) == null;
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

ServiceFieldValidator _woundMeasurement() => (value) {
      if (value == null || '$value'.trim().isEmpty) return null;
      final n = num.tryParse('$value'.trim());
      if (n == null || n <= 0) return 'Enter a size greater than 0 cm.';
      if (n > 100) return 'Enter a size of 100 cm or less.';
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
  'Other',
];

const List<String> kConsultationDuration = [
  'Just now',
  'Today',
  '2-3 days',
  'More than 3 days',
];

const List<String> kConsultationHistory = [
  'Fever',
  'Headache',
  'Cough',
  'Difficulty Breathing',
  'Nausea',
  'Vomiting',
  'Diarrhea',
  'Dizziness',
  'Pain',
  'Allergy to medicine',
  'Asthma / known condition',
  'Taking medicine now',
  'Other',
];

const List<String> kConsultationTreatment = [
  'Advice / Health Education',
  'Medication',
  'Wound Care',
  'Rest / Observation',
  'Other',
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
  'Other',
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
  return [
    for (final s in signs)
      if (kCounsellingReferralSigns.contains(s)) s
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

List<String> consultationRedFlags(Map<String, dynamic> data) => [
      for (final f in _strListOf(data['red_flags']))
        if (f != 'None') f,
    ];

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
  'Other',
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
  'Other',
];

const List<String> kWoundConditions = [
  'Clean',
  'Contaminated / Dirty',
  'Infected',
  'Healing',
  'Other',
];

const List<String> kWoundCleaningPerformed = [
  'Running water',
  'Normal Saline',
  'Povidone-Iodine',
  'Chlorhexidine',
  'Hydrogen Peroxide',
  'Tap water',
  'Other',
];

const List<String> kWoundDressingMaterials = [
  'Sterile Gauze',
  'Gauze Pad',
  'Bandage / Roller',
  'Crepe Bandage',
  'Adhesive Plaster',
  'Cotton / Cotton Ball',
  'Other',
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
  'Other',
];

const List<String> kWoundFindings = [
  'Wound edges clean',
  'No signs of infection',
  'Redness present',
  'Swelling present',
  'Pus / discharge present',
  'Bleeding controlled',
  'Edges approximated / sutured',
  'Other',
];

const List<String> kWoundInjuryTiming = [
  'Just now (under 1 hour)',
  'Within 6 hours',
  '6 to 24 hours',
  'More than 24 hours',
  'Other',
];

const List<String> kBurnDegrees = [
  '1st degree',
  '2nd degree',
  '3rd degree',
  'Other',
];

const List<String> kBleedingStatus = [
  'None',
  'Controlled',
  'Still bleeding',
  'Other',
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
  'Other',
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
  final length = _numOf(data['wound_length_cm']);

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
  if (length != null && length >= kWoundReferralLengthCm) {
    reasons.add('Wound ${_trimNum(length)} cm across');
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

bool isReferralDisposition(String disposition) =>
    disposition.startsWith('Referred to');

String _strOf(Object? v) => v == null ? '' : '$v'.trim();

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

num? _numOf(Object? v) {
  if (v is num) return v;
  if (v == null) return null;
  return num.tryParse('$v'.trim());
}

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
  'Other',
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
  'Other',
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
  'Other',
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
  'Other',
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
  'Other',
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
  'Other',
];

const List<String> kPrenatalActions = [
  'Vital Signs Taken',
  'Fetal Heart Tone Checked',
  'Advice Given',
  'Referred for Further Testing',
  'Referred to Hospital/RHU',
  'Parents/Guardian Informed (if student)',
  'Follow-up Scheduled',
  'Other',
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
  'Other',
];

const List<String> kPrenatalGiven = [
  'Iron / Folic Acid',
  'Tetanus Toxoid (TT)',
  'Calcium',
  'Other',
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
  'Other',
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
  'Blood Pressure': ['systolic', 'diastolic', 'position', 'arm_used', 'bp_assessment'],
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
              required: true,
              width: FieldWidth.half,
            ),
            ServiceField(
              key: 'weight_kg',
              label: 'Weight',
              kind: ServiceFieldKind.number,
              unit: 'kg',
              vital: VitalField.weightKg,
              required: true,
              width: FieldWidth.half,
            ),
            ServiceField(
              key: 'bmi',
              label: 'BMI',
              kind: ServiceFieldKind.readOnly,
              width: FieldWidth.half,
              note: 'Worked out from the height and weight above.',
            ),
            ServiceField(
              key: 'bmi_class',
              label: 'BMI Classification',
              kind: ServiceFieldKind.readOnly,
              width: FieldWidth.half,
              note: 'The adult band this BMI falls in.',
            ),
            notes(),
          ],
        ),
        VisitServiceForms.reviewSlide,
      ],
    ),
    'health_counselling': ServiceFormSpec(
      serviceId: 'health_counselling',
      referralTitle:
          'Refer to Guidance Counselor / Clinic Head today. Do not leave the '
          'student alone if there is a risk of self-harm.',
      referralReasons: (data, _) => counsellingReferralReasons(data),
      warnings: (data, _) {
        if (counsellingReferralReasons(data).isEmpty) return const [];
        final answer = '${data['additional_service_needed'] ?? ''}'.trim();
        if (answer == 'Yes') return const [];
        return const [
          'This session raises a referral. Confirm the additional service or '
              'referral on the last slide.',
        ];
      },
      slides: [
        ServiceSlide(
          title: 'Counselling Information',
          fields: [
            ServiceField(
              key: 'counsellor',
              label: 'Counsellor',
              kind: ServiceFieldKind.staffName,
              required: true,
              width: FieldWidth.half,
              note: 'Yours by default. Change it to another clinic account, or '
                  'type a name if the session was run by someone without one.',
            ),
            ServiceField(
              key: 'session_date',
              label: 'Date / Time',
              kind: ServiceFieldKind.readOnly,
              width: FieldWidth.half,
              note: 'From the visit. Not typed.',
            ),
            ServiceField(
              key: 'referral_source',
              label: 'Why did the student come?',
              kind: ServiceFieldKind.chips,
              options: kCounsellingReferralSource,
              required: true,
              note: 'How the session started. One.',
            ),
            ServiceField(
              key: 'session_type',
              label: 'Session Type',
              kind: ServiceFieldKind.chips,
              options: kCounsellingSessionType,
              required: true,
              width: FieldWidth.half,
            ),
            ServiceField(
              key: 'privacy_level',
              label: 'Privacy level',
              kind: ServiceFieldKind.chips,
              options: kCounsellingPrivacyLevels,
              required: true,
              width: FieldWidth.half,
              note: 'Set to Restricted automatically for sensitive topics or a '
                  'referral. You can raise it, but not lower it once set.',
            ),
            ServiceField(
              key: 'topic',
              label: 'Counselling Topic',
              kind: ServiceFieldKind.checkboxes,
              options: kCounsellingTopics,
              required: true,
              note: 'Tick at least one. One session can cover two.',
            ),
            ServiceField(
              key: 'topic_other',
              label: 'Other Topic',
              kind: ServiceFieldKind.text,
              required: true,
              shownWhenKey: 'topic',
              shownWhenValues: ['Other'],
            ),
            const ServiceField(
              key: 'privacy_notice',
              label: '',
              kind: ServiceFieldKind.notice,
              width: FieldWidth.full,
            ),
            ServiceField(
              key: 'reason',
              label: 'Reason / Concern',
              kind: ServiceFieldKind.multiline,
              required: false,
              maxChars: 300,
              validate: _cappedLength(300, 'the reason'),
              note: 'Optional. Why this person needed counselling. The topic '
                  'says what was discussed; this says why.',
            ),
          ],
        ),
        ServiceSlide(
          title: 'Counselling Provided',
          fields: [
            ServiceField(
              key: 'provided',
              label: 'Counselling Provided',
              kind: ServiceFieldKind.checkboxes,
              options: kCounsellingProvided,
              required: true,
              note: 'Tick at least one. What the clinic did, not what happens '
                  'next.',
            ),
            ServiceField(
              key: 'provided_other',
              label: 'Other (specify)',
              kind: ServiceFieldKind.text,
              required: true,
              shownWhenKey: 'provided',
              shownWhenValues: ['Other'],
            ),
            ServiceField(
              key: 'understanding',
              label: 'Student understanding',
              kind: ServiceFieldKind.chips,
              options: kCounsellingUnderstanding,
              required: true,
              note: 'How well they took it in. Not a grade.',
            ),
            ServiceField(
              key: 'student_response',
              label: 'Student response',
              kind: ServiceFieldKind.text,
              required: false,
              maxChars: 200,
              validate: _cappedLength(200, 'the response'),
              note: 'Optional. What they said or did, in a line.',
            ),
            ServiceField(
              key: 'duration_minutes',
              label: 'Duration in minutes',
              kind: ServiceFieldKind.number,
              unit: 'min',
              required: false,
              width: FieldWidth.half,
              validate: _vitalWhole(1, 180),
              note: 'Optional. Whole minutes, 1–180.',
            ),
            ServiceField(
              key: 'concern_signs',
              label: 'Concern signs check',
              kind: ServiceFieldKind.checkboxes,
              options: kCounsellingConcernSigns,
              required: false,
              note: 'Optional. Any sign other than "None" refers today and '
                  'locks the record to Restricted.',
            ),
            ServiceField(
              key: 'guardian_informed',
              label: 'Guardian informed',
              kind: ServiceFieldKind.chips,
              options: kCounsellingGuardian,
              required: true,
              requiredWhen: (data) =>
                  counsellingReferralReasons(data).isNotEmpty,
              width: FieldWidth.half,
              note: 'Required once a concern sign is ticked.',
            ),
            ServiceField(
              key: 'follow_up_needed',
              label: 'Follow-up Needed?',
              kind: ServiceFieldKind.chips,
              options: kYesNo,
              required: true,
              width: FieldWidth.half,
            ),
            ServiceField(
              key: 'follow_up_reason',
              label: 'Reason for Follow-up',
              kind: ServiceFieldKind.text,
              required: true,
              shownWhenKey: 'follow_up_needed',
              shownWhenValues: ['Yes'],
            ),
            ServiceField(
              key: 'follow_up_date',
              label: 'Follow-up Date',
              kind: ServiceFieldKind.date,
              width: FieldWidth.half,
              shownWhenKey: 'follow_up_needed',
              shownWhenValues: ['Yes'],
              note:
                  'Optional — today or later only. Blank when it has no date yet.',
            ),
          ],
        ),
        ServiceSlide(
          title: 'Additional Service / Referral',
          fields: [
            ServiceField(
              key: 'additional_service_needed',
              label: 'Additional Service Needed?',
              kind: ServiceFieldKind.chips,
              options: kYesNo,
              required: true,
              width: FieldWidth.half,
              note: 'Does this person need another clinic service because of '
                  'what was discussed? Nothing is sent anywhere by answering '
                  'this — it is a note on the record for whoever sees them next.',
            ),
            ServiceField(
              key: 'referral_service',
              label: 'Recommended Service',
              kind: ServiceFieldKind.dropdown,
              options: kCounsellingRecommendedServices,
              required: true,
              width: FieldWidth.half,
              shownWhenKey: 'additional_service_needed',
              shownWhenValues: ['Yes'],
              note:
                  'Only services this clinic actually runs, plus the two ways '
                  'out of the building. Health Counselling itself is not listed.',
            ),
            ServiceField(
              key: 'referral_service_other',
              label: 'Other (specify)',
              kind: ServiceFieldKind.text,
              required: true,
              width: FieldWidth.half,
              shownWhenKey: 'referral_service',
              shownWhenValues: ['Other'],
            ),
            ServiceField(
              key: 'referred_to',
              label: 'Referred to (name or place)',
              kind: ServiceFieldKind.text,
              required: true,
              shownWhenKey: 'referral_service',
              shownWhenValues: const [
                'Guidance Counselor (school)',
                'External Healthcare Facility',
              ],
              note: 'Who or where, by name.',
            ),
            ServiceField(
              key: 'referral_link',
              label: 'Add this service to the visit',
              kind: ServiceFieldKind.linkServiceCard,
              linkFromKey: 'referral_service',
              buttonLabel: 'Add this service to the visit',
              shownWhenKey: 'additional_service_needed',
              shownWhenValues: ['Yes'],
              note: 'Ticks the service into this visit and opens its form. '
                  'Everything typed here is kept.',
            ),
            ServiceField(
              key: 'referral_reason',
              label: 'Reason for Referral',
              kind: ServiceFieldKind.text,
              required: true,
              shownWhenKey: 'additional_service_needed',
              shownWhenValues: ['Yes'],
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
              label: 'Last Menstrual Period',
              kind: ServiceFieldKind.date,
              required: true,
              datePast: true,
              width: FieldWidth.half,
              note: 'If unknown, tick "LMP not sure / unknown".',
            ),
            ServiceField(
              key: 'lmp_unknown',
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
              note: 'Weeks and days since the LMP.',
            ),
            ServiceField(
              key: 'edd',
              label: 'Expected Due Date',
              kind: ServiceFieldKind.readOnly,
              width: FieldWidth.half,
              note: 'LMP + 280 days.',
            ),
            ServiceField(
              key: 'gravida',
              label: 'Gravida',
              kind: ServiceFieldKind.number,
              required: true,
              width: FieldWidth.half,
              note: 'Total pregnancies ever, this one included.',
            ),
            ServiceField(
              key: 'para',
              label: 'Para',
              kind: ServiceFieldKind.number,
              required: true,
              width: FieldWidth.half,
              note: 'Pregnancies that reached a birth, not including this one.',
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
              note: 'BP, pulse and temperature are recorded once for the visit '
                  'on the Vital Signs service, then shown read-only here.',
            ),
            ServiceField(
              key: 'bp_assessment',
              label: 'BP Classification',
              kind: ServiceFieldKind.readOnly,
              width: FieldWidth.half,
              note: 'Worked out from the visit\'s blood pressure.',
            ),
            ServiceField(
              key: 'fundal_height',
              label: 'Fundal Height',
              kind: ServiceFieldKind.number,
              unit: 'cm',
              required: false,
              width: FieldWidth.half,
              note: 'Only applicable when AOG >= 20 weeks.',
            ),
            ServiceField(
              key: 'fetal_heart_tone',
              label: 'Fetal Heart Tone',
              kind: ServiceFieldKind.number,
              unit: 'bpm',
              required: false,
              width: FieldWidth.half,
            ),
            ServiceField(
              key: 'fetal_heart_not_done',
              label: '',
              kind: ServiceFieldKind.checkboxes,
              options: const ['Not done / no equipment'],
              required: false,
              width: FieldWidth.half,
            ),
            ServiceField(
              key: 'fetal_movement',
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
              label: 'Oedema / Swelling',
              kind: ServiceFieldKind.chips,
              options: kPrenatalEdema,
              required: false,
              width: FieldWidth.half,
              note:
                  'Face or hands matters more than feet: sudden swelling there '
                  'with a raised blood pressure is a clinician, not a note.',
            ),
            ServiceField(
              key: 'urine_protein',
              label: 'Urine Protein',
              kind: ServiceFieldKind.chips,
              options: kPrenatalUrineProtein,
              required: false,
              width: FieldWidth.half,
              note: '"Not tested" is a real answer here.',
            ),
            ServiceField(
              key: 'danger_signs',
              label: 'Danger signs',
              kind: ServiceFieldKind.checkboxes,
              options: kPrenatalDangerSigns,
              required: false,
              width: FieldWidth.full,
            ),
            ServiceField(
              key: 'danger_signs_other',
              label: 'Other Danger Sign',
              kind: ServiceFieldKind.text,
              required: true,
              width: FieldWidth.full,
              note:
                  'The sign itself, in your own words. This is what the record '
                  'keeps, not the word "Other".',
              shownWhenKey: 'danger_signs',
              shownWhenValues: const ['Other'],
            ),
          ],
        ),
        ServiceSlide(
          title: 'Care Plan',
          fields: [
            ServiceField(
              key: 'care_elsewhere',
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
              label: 'Service / Care Provided',
              kind: ServiceFieldKind.checkboxes,
              options: kPrenatalServices,
              required: true,
              note: 'Tick at least one.',
            ),
            ServiceField(
              key: 'other_service_specify',
              label: 'Other (specify)',
              kind: ServiceFieldKind.text,
              required: false,
              width: FieldWidth.full,
              shownWhenKey: 'service_provided',
              shownWhenValues: const ['Other'],
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
              key: 'action_taken_other',
              label: 'Other Action / Advice',
              kind: ServiceFieldKind.text,
              required: true,
              width: FieldWidth.full,
              note: 'The action itself, in your own words. This is what the '
                  'record keeps, not the word "Other".',
              shownWhenKey: 'action_taken',
              shownWhenValues: const ['Other'],
            ),
            ServiceField(
              key: 'given_this_visit',
              label: 'Given This Visit',
              kind: ServiceFieldKind.checkboxes,
              options: kPrenatalGiven,
              note:
                  'What she went home with. Leave blank when nothing was handed over.',
            ),
            ServiceField(
              key: 'given_this_visit_other',
              label: 'Other Given This Visit',
              kind: ServiceFieldKind.text,
              required: true,
              width: FieldWidth.full,
              note:
                  'The item itself, in your own words. This is what the record '
                  'keeps, not the word "Other".',
              shownWhenKey: 'given_this_visit',
              shownWhenValues: const ['Other'],
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
        ServiceSlide(
          title: 'Additional Service',
          fields: [
            ServiceField(
              key: 'recommended_service',
              label: 'Recommended Service',
              kind: ServiceFieldKind.dropdown,
              options: kFirstAidRecommendedServices,
              required: false,
              width: FieldWidth.half,
              note: 'Optional. A service this person should have next, if any.',
            ),
            ServiceField(
              key: 'recommended_service_other',
              label: 'Other (specify)',
              kind: ServiceFieldKind.text,
              required: false,
              width: FieldWidth.half,
              shownWhenKey: 'recommended_service',
              shownWhenValues: ['Other'],
            ),
            ServiceField(
              key: 'referred_to',
              label: 'Referred to (name or place)',
              kind: ServiceFieldKind.text,
              required: true,
              shownWhenKey: 'recommended_service',
              shownWhenValues: const [
                'Guidance Counselor (school)',
                'External Healthcare Facility',
              ],
            ),
            ServiceField(
              key: 'recommended_service_link',
              label: 'Add this service to the visit',
              kind: ServiceFieldKind.linkServiceCard,
              linkFromKey: 'recommended_service',
              buttonLabel: 'Add this service to the visit',
              shownWhenKey: 'recommended_service',
              shownWhenValues: kFirstAidRecommendedServices,
              shownWhen: FieldCondition.isOneOf,
              note: 'Ticks the service into this visit and opens its form.',
            ),
            ServiceField(
              key: 'counselling_hint',
              label: 'Consider Health Counselling',
              kind: ServiceFieldKind.linkServiceCard,
              opensService: 'health_counselling',
              buttonLabel: 'Add Health Counselling',
              shownWhenPredicate: (data) {
                final incident = _strOf(data['incident']);
                return incident == 'Fainting' ||
                    incident == 'Dizziness' ||
                    incident == 'Headache' ||
                    incident == 'Stomach Pain / Nausea' ||
                    incident == 'Menstrual Cramps';
              },
              note: 'For these incidents a counselling session is often as '
                  'useful as a physical check. A suggestion only — the choice '
                  'is yours.',
            ),
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
              label: 'Reason/Complaints',
              kind: ServiceFieldKind.checkboxes,
              options: kMedicationReasons,
              note: 'Tick the reason(s) the medicine is for.',
            ),
            ServiceField(
              key: 'reason_other',
              label: 'Other Reason',
              kind: ServiceFieldKind.text,
              required: true,
              shownWhenKey: 'reason_common',
              shownWhenValues: ['Other'],
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
                'Condition After Treatment says further treatment is needed — '
                    '"$disposition" cannot follow from it.',
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
              label: 'Reason / Incident',
              kind: ServiceFieldKind.dropdown,
              options: kFirstAidIncidents,
              required: true,
              width: FieldWidth.half,
            ),
            ServiceField(
              key: 'incident_other',
              label: 'Other Incident',
              kind: ServiceFieldKind.text,
              required: true,
              width: FieldWidth.half,
              shownWhenKey: 'incident',
              shownWhenValues: ['Other'],
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
              key: 'incident_place_other',
              label: 'Other Place',
              kind: ServiceFieldKind.text,
              width: FieldWidth.half,
              shownWhenKey: 'incident_place',
              shownWhenValues: ['Other'],
            ),
            ServiceField(
              key: 'incident_cause',
              label: 'Cause / Circumstances',
              kind: ServiceFieldKind.text,
              width: FieldWidth.half,
              maxChars: 100,
              validate: _cappedLength(100, 'the cause'),
              hint: 'e.g. fell during PE',
            ),
            ServiceField(
              key: 'known_allergies',
              label: 'Known allergies',
              kind: ServiceFieldKind.text,
              width: FieldWidth.half,
              note: 'Optional — anything that changes what you may give.',
            ),
            ServiceField(
              key: 'body_part',
              label: 'Body Location',
              kind: ServiceFieldKind.dropdown,
              options: ClinicPurposes.bodySites,
              required: true,
              width: FieldWidth.half,
            ),
            ServiceField(
              key: 'body_part_other',
              label: 'Other Location',
              kind: ServiceFieldKind.text,
              width: FieldWidth.half,
              shownWhenKey: 'body_part',
              shownWhenValues: ['Other'],
              note: "The clinic's own words, by name.",
            ),
            ServiceField(
              key: 'findings',
              label: 'Observed Condition',
              kind: ServiceFieldKind.checkboxes,
              options: kFirstAidFindings,
              required: true,
              allowCustomEntries: true,
              note: 'Tick what you can see. Tick "Other" to type your own.',
            ),
            ServiceField(
              key: 'pain_level',
              label: 'Pain Level',
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
              label: 'Head Injury Check',
              kind: ServiceFieldKind.checkboxes,
              options: kFirstAidHeadSigns,
              required: true,
              shownWhenPredicate: (data) {
                final incident = _strOf(data['incident']);
                if (incident == 'Head Injury') return true;
                final site = _strOf(data['body_part']);
                return incident == 'Fall' && (site == 'Head' || site == 'Face');
              },
              note: 'Ask, look, and tick. Any sign other than "None of these" '
                  'refers.',
            ),
            ServiceField(
              key: 'consciousness',
              label: 'Consciousness',
              kind: ServiceFieldKind.chips,
              options: kFirstAidConsciousness,
              required: true,
              width: FieldWidth.half,
              shownWhenPredicate: (data) {
                final incident = _strOf(data['incident']);
                if (incident == 'Head Injury' || incident == 'Fainting') {
                  return true;
                }
                final site = _strOf(data['body_part']);
                return incident == 'Fall' && (site == 'Head' || site == 'Face');
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
            ),
            ServiceField(
              key: 'treatment',
              label: 'Treatment / First Aid Performed',
              kind: ServiceFieldKind.checkboxes,
              options: kFirstAidTreatments,
              required: true,
              allowCustomEntries: true,
              note: 'Tick at least one. Tick "Other" to type what you did. '
                  '"First Aid Treatment" with nothing on it is an attendance, '
                  'not a treatment.',
            ),
            ServiceField(
              key: 'dressing_material',
              label: 'Dressing Material',
              kind: ServiceFieldKind.dropdown,
              options: kDressingMaterialsUsed,
              required: true,
              width: FieldWidth.half,
              shownWhenKey: 'treatment',
              shownWhenValues: ['Wound Dressing'],
            ),
            ServiceField(
              key: 'dressing_material_other',
              label: 'Other Dressing Material',
              kind: ServiceFieldKind.text,
              required: true,
              width: FieldWidth.half,
              shownWhenKey: 'dressing_material',
              shownWhenValues: ['Other'],
              note: "The clinic's own material, by name.",
            ),
            ServiceField(
              key: 'medication_given',
              label: 'Medication Given',
              kind: ServiceFieldKind.text,
              required: true,
              shownWhenKey: 'treatment',
              shownWhenValues: ['Basic Medication Given'],
              note:
                  'Name and dose — a record of what was given. To take it off '
                  'the shelf, use the card below; stock is deducted there.',
            ),
            ServiceField(
              key: 'medication_card',
              label: 'Medication',
              kind: ServiceFieldKind.medicationCard,
            ),
            ServiceField(
              key: 'observation_minutes',
              label: 'Observation Time',
              kind: ServiceFieldKind.number,
              unit: 'min',
              width: FieldWidth.half,
              shownWhenKey: 'treatment',
              shownWhenValues: ['Rest / Observation'],
              validate: _vitalWhole(0, 600),
              note: 'Optional — how long they rested here.',
            ),
            ServiceField(
              key: 'wound_hint',
              label: 'This looks like a dressing-room case',
              kind: ServiceFieldKind.linkServiceCard,
              opensService: 'wound_dressing',
              buttonLabel: 'Open Wound Dressing',
              shownWhenPredicate: (data) {
                final incident = _strOf(data['incident']);
                if (incident == 'Wound' ||
                    incident == 'Bleeding' ||
                    incident == 'Burn') {
                  return true;
                }
                final findings = _strListOf(data['findings']);
                return findings.contains('Wound / Open Skin') ||
                    findings.contains('Burn');
              },
              note: 'The wound form records the wound itself — type, size, '
                  'cleaning and dressing — and this form only the first aid '
                  'around it.',
            ),
          ],
        ),
        ServiceSlide(
          title: 'Condition & Disposition',
          fields: [
            ServiceField(
              key: 'condition_after',
              label: 'Condition After Treatment',
              kind: ServiceFieldKind.dropdown,
              options: kConditionAfterTreatment,
              required: true,
              width: FieldWidth.half,
              note: 'How they were afterwards. Not a diagnosis.',
            ),
            ServiceField(
              key: 'disposition',
              label: 'Disposition / Next Action',
              kind: ServiceFieldKind.chips,
              options: kFirstAidDispositions,
              required: true,
              note: 'One. This is the handover line the next person reads.',
            ),
            ServiceField(
              key: 'guardian_informed',
              label: 'Parent / Guardian informed?',
              kind: ServiceFieldKind.chips,
              options: kFirstAidGuardian,
              required: true,
              width: FieldWidth.half,
              requiredWhen: (data) {
                final disposition = _strOf(data['disposition']);
                return disposition == 'Sent Home' ||
                    isReferralDisposition(disposition);
              },
              note: 'Owed when someone is sent home or referred.',
            ),
            ServiceField(
              key: 'referred_to_where',
              label: 'Which hospital / clinic?',
              kind: ServiceFieldKind.text,
              required: true,
              shownWhenPredicate: (data) =>
                  isReferralDisposition(_strOf(data['disposition'])),
              note: 'Where they were referred, and to whom.',
            ),
            ServiceField(
              key: 'sent_to',
              label: 'Sent Home With',
              kind: ServiceFieldKind.text,
              required: true,
              shownWhenKey: 'disposition',
              shownWhenValues: ['Sent Home'],
              note: 'Who took them home.',
            ),
            ServiceField(
              key: 'follow_up_date',
              label: 'Follow-up Date',
              kind: ServiceFieldKind.date,
              width: FieldWidth.half,
              shownWhenKey: 'disposition',
              shownWhenValues: ['Follow-up'],
              shownWhen: FieldCondition.startsWith,
              note:
                  'Optional — leave blank when the follow-up has no date yet.',
            ),
            ServiceField(
              key: 'referral_reason',
              label: 'Referral Reason',
              kind: ServiceFieldKind.text,
              shownWhenKey: 'disposition',
              shownWhenValues: ['Referred to'],
              shownWhen: FieldCondition.startsWith,
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
              label: 'When Did It Happen?',
              kind: ServiceFieldKind.dropdown,
              options: kWoundInjuryTiming,
              required: true,
              width: FieldWidth.half,
            ),
            ServiceField(
              key: 'injury_timing_other',
              label: 'Other Timing (specify)',
              kind: ServiceFieldKind.text,
              required: true,
              width: FieldWidth.half,
              shownWhenKey: 'injury_timing',
              shownWhenValues: ['Other'],
              note: 'When it happened, in your own words.',
            ),
            ServiceField(
              key: 'injury_cause',
              label: 'How It Happened',
              kind: ServiceFieldKind.text,
              width: FieldWidth.half,
              hint: 'e.g. Fell on the court',
              validate: _cappedLength(100, 'this note'),
              note: 'Optional. In your own words.',
            ),
            ServiceField(
              key: 'wound_location',
              label: 'Location of the Wound',
              kind: ServiceFieldKind.dropdown,
              options: ClinicPurposes.bodySites,
              required: true,
              width: FieldWidth.half,
            ),
            ServiceField(
              key: 'wound_location_other',
              label: 'Other Location (specify)',
              kind: ServiceFieldKind.text,
              required: true,
              width: FieldWidth.half,
              shownWhenKey: 'wound_location',
              shownWhenValues: ['Other'],
              note: 'Where the wound is, in your own words. This is what the '
                  'record keeps, not the word "Other".',
            ),
            ServiceField(
              key: 'wound_type',
              label: 'Wound Type',
              kind: ServiceFieldKind.dropdown,
              options: kWoundTypes,
              required: true,
              width: FieldWidth.half,
            ),
            ServiceField(
              key: 'wound_type_other',
              label: 'Other Wound Type (specify)',
              kind: ServiceFieldKind.text,
              required: true,
              width: FieldWidth.half,
              shownWhenKey: 'wound_type',
              shownWhenValues: ['Other'],
              note: 'The type of wound, in your own words. This is what the '
                  'record keeps, not the word "Other".',
            ),
            ServiceField(
              key: 'burn_degree',
              label: 'Burn Degree',
              kind: ServiceFieldKind.chips,
              options: kBurnDegrees,
              required: true,
              width: FieldWidth.half,
              shownWhenKey: 'wound_type',
              shownWhenValues: ['Burn'],
            ),
            ServiceField(
              key: 'burn_degree_other',
              label: 'Other Burn Degree (specify)',
              kind: ServiceFieldKind.text,
              required: true,
              width: FieldWidth.half,
              shownWhenKey: 'burn_degree',
              shownWhenValues: ['Other'],
              note: 'The degree, in your own words.',
            ),
            ServiceField(
              key: 'wound_condition',
              label: 'Wound Condition',
              kind: ServiceFieldKind.chips,
              options: kWoundConditions,
              required: true,
              width: FieldWidth.half,
            ),
            ServiceField(
              key: 'wound_condition_other',
              label: 'Other Condition (specify)',
              kind: ServiceFieldKind.text,
              required: true,
              width: FieldWidth.half,
              shownWhenKey: 'wound_condition',
              shownWhenValues: ['Other'],
              note: 'The condition, in your own words.',
            ),
            ServiceField(
              key: 'bleeding',
              label: 'Bleeding',
              kind: ServiceFieldKind.chips,
              options: kBleedingStatus,
              required: true,
              width: FieldWidth.half,
            ),
            ServiceField(
              key: 'bleeding_other',
              label: 'Other Bleeding (specify)',
              kind: ServiceFieldKind.text,
              required: true,
              width: FieldWidth.half,
              shownWhenKey: 'bleeding',
              shownWhenValues: ['Other'],
              note: 'Describe the bleeding, in your own words.',
            ),
            ServiceField(
              key: 'wound_length_cm',
              label: 'Length (cm)',
              kind: ServiceFieldKind.number,
              unit: 'cm',
              width: FieldWidth.half,
              hint: 'e.g. 3',
              validate: _woundMeasurement(),
            ),
            ServiceField(
              key: 'wound_width_cm',
              label: 'Width (cm)',
              kind: ServiceFieldKind.number,
              unit: 'cm',
              width: FieldWidth.half,
              hint: 'e.g. 1.5',
              validate: _woundMeasurement(),
            ),
            ServiceField(
              key: 'vitals_card',
              label: 'Visit Vitals (Temperature / Blood Pressure)',
              kind: ServiceFieldKind.vitalsCard,
              width: FieldWidth.full,
              note: 'Taken once for the visit on the Vital Signs service — '
                  'read-only here.',
            ),
            ServiceField(
              key: 'tetanus_status',
              label: 'Tetanus Shot Up to Date?',
              kind: ServiceFieldKind.chips,
              options: kTetanusStatus,
              width: FieldWidth.half,
              shownWhenPredicate: (data) {
                final types = _answersOf(data['wound_type']);
                final conds = _answersOf(data['wound_condition']);
                return types.any(kWoundTetanusTypes.contains) ||
                    conds.any(kWoundTetanusConditions.contains);
              },
              note:
                  'Optional. Asked because these wounds carry a tetanus risk.',
            ),
          ],
        ),
        ServiceSlide(
          title: 'Cleaning & Dressing',
          groups: [
            FieldGroup(['cleaning_performed', 'cleaning_performed_other']),
            FieldGroup(['dressing_applied', 'dressing_applied_other']),
            FieldGroup(['assessment', 'assessment_other']),
            FieldGroup(['action_taken', 'action_taken_other']),
          ],
          fields: [
            ServiceField(
              key: 'cleaning_performed',
              label: 'Cleaning Performed',
              kind: ServiceFieldKind.checkboxes,
              options: kWoundCleaningPerformed,
              required: true,
              note: 'Tick at least one.',
            ),
            ServiceField(
              key: 'cleaning_performed_other',
              label: 'Other Cleaning Used',
              kind: ServiceFieldKind.text,
              required: true,
              width: FieldWidth.half,
              shownWhenKey: 'cleaning_performed',
              shownWhenValues: ['Other'],
              note: 'The clinic\'s own prep, by name.',
            ),
            ServiceField(
              key: 'dressing_applied',
              label: 'Dressing Applied',
              kind: ServiceFieldKind.checkboxes,
              options: kWoundDressingMaterials,
              required: true,
              note: 'Tick at least one.',
            ),
            ServiceField(
              key: 'dressing_applied_other',
              label: 'Other Dressing Used',
              kind: ServiceFieldKind.text,
              required: true,
              width: FieldWidth.half,
              shownWhenKey: 'dressing_applied',
              shownWhenValues: ['Other'],
              note: 'The clinic\'s own material, by name.',
            ),
            ServiceField(
              key: 'assessment',
              label: 'Assessment / Findings',
              kind: ServiceFieldKind.checkboxes,
              options: kWoundFindings,
              required: true,
              note: 'Tick at least one. Observations only - a diagnosis is a '
                  'separate service.',
            ),
            ServiceField(
              key: 'assessment_other',
              label: 'Other Finding (specify)',
              kind: ServiceFieldKind.text,
              required: true,
              width: FieldWidth.half,
              shownWhenKey: 'assessment',
              shownWhenValues: ['Other'],
              note: 'The finding, in your own words.',
            ),
            ServiceField(
              key: 'action_taken',
              label: 'Action Taken',
              kind: ServiceFieldKind.checkboxes,
              options: kWoundActions,
              required: true,
              note: 'Tick at least one.',
            ),
            ServiceField(
              key: 'action_taken_other',
              label: 'Other Action (specify)',
              kind: ServiceFieldKind.text,
              required: true,
              width: FieldWidth.half,
              shownWhenKey: 'action_taken',
              shownWhenValues: ['Other'],
              note: 'What was done, in your own words.',
            ),
            ServiceField(
              key: 'referred_to',
              label: 'Referred to (where)',
              kind: ServiceFieldKind.text,
              required: true,
              width: FieldWidth.half,
              shownWhenKey: 'action_taken',
              shownWhenValues: ['Referred to Hospital/RHU'],
              note: 'Required when a referral is recorded above.',
            ),
            ServiceField(
              key: 'no_further_dressing',
              label: 'Dressing Plan',
              kind: ServiceFieldKind.chips,
              options: const [kWoundNoFurtherDressing],
              width: FieldWidth.half,
              note: 'Tick when this wound needs no further dressing.',
            ),
            ServiceField(
              key: 'next_dressing_date',
              label: 'Next Dressing Date',
              kind: ServiceFieldKind.date,
              width: FieldWidth.half,
              required: true,
              shownWhenKey: 'no_further_dressing',
              shownWhenValues: const [kWoundNoFurtherDressing],
              shownWhen: FieldCondition.noneOf,
              requiredWhen: (data) {
                final conds = _answersOf(data['wound_condition']);
                final acts = _answersOf(data['action_taken']);
                return conds.contains('Infected') ||
                    conds.contains('Healing') ||
                    acts.contains('Follow-up scheduled');
              },
              note: 'Required for an infected or healing wound, or a booked '
                  'follow-up. Today or later only.',
            ),
            ServiceField(
              key: 'other_medication',
              label: 'Other Medication / Antiseptic',
              kind: ServiceFieldKind.text,
              width: FieldWidth.half,
              hint: 'e.g. Betadine swab',
              note: 'Optional. Anything applied that is not a prescription and '
                  'not named on the Medication service.',
            ),
            ServiceField(
              key: 'medication_card',
              label: 'Medication / Antiseptic Given',
              kind: ServiceFieldKind.medicationCard,
              width: FieldWidth.full,
              note: 'Recorded once for the visit on the Medication service — '
                  'read-only here.',
            ),
            notes(),
          ],
        ),
        VisitServiceForms.reviewSlide,
      ],
    ),
    'medicine_consultation': ServiceFormSpec(
      serviceId: 'medicine_consultation',
      referralReasons: (data, vitals) =>
          consultationReferralReasons(data, vitals),
      warnings: (data, vitals) => consultationWarnings(data, vitals),
      slides: [
        ServiceSlide(
          title: 'Complaint',
          fields: [
            ServiceField(
              key: 'chief_complaint',
              label: 'Chief Complaint',
              kind: ServiceFieldKind.text,
              required: true,
              validate: _cappedLength(150, 'the complaint'),
              note:
                  'In the patient\'s own words. "Headache and dizziness for 2 '
                  'days" is the complaint; none of the boxes below is.',
            ),
            ServiceField(
              key: 'symptoms',
              label: 'Common Complaints',
              kind: ServiceFieldKind.checkboxes,
              options: kConsultationComplaints,
              note: 'Optional. A shortcut for the box above.',
            ),
            ServiceField(
              key: 'symptom_other',
              label: 'Other Complaint (specify)',
              kind: ServiceFieldKind.text,
              required: true,
              width: FieldWidth.half,
              shownWhenKey: 'symptoms',
              shownWhenValues: ['Other'],
            ),
            ServiceField(
              key: 'duration_onset_choice',
              label: 'Duration / Onset',
              kind: ServiceFieldKind.chips,
              options: kConsultationDuration,
              width: FieldWidth.half,
              note: 'Optional. The box beside it takes the exact words.',
            ),
            ServiceField(
              key: 'duration_onset',
              label: 'Duration / Onset (exact)',
              kind: ServiceFieldKind.text,
              hint: 'e.g. started 2 days ago',
              width: FieldWidth.half,
            ),
            ServiceField(
              key: 'additional_complaint',
              label: 'Additional Complaint / Description',
              kind: ServiceFieldKind.text,
            ),
          ],
        ),
        ServiceSlide(
          title: 'History',
          fields: [
            ServiceField(
              key: 'vitals_card',
              label: 'Visit Vitals',
              kind: ServiceFieldKind.vitalsCard,
              note: 'Taken once for the visit on the Vital Signs service — '
                  'read-only here.',
            ),
            ServiceField(
              key: 'history',
              label: 'Relevant History / Symptoms',
              kind: ServiceFieldKind.checkboxes,
              options: kConsultationHistory,
              note: 'Optional.',
            ),
            ServiceField(
              key: 'history_other',
              label: 'Other History (specify)',
              kind: ServiceFieldKind.text,
              shownWhenKey: 'history',
              shownWhenValues: ['Other'],
            ),
            ServiceField(
              key: 'lmp_concern',
              label: 'Menstrual Concern',
              kind: ServiceFieldKind.checkboxes,
              options: const ['LMP / menstruation concern'],
              shownWhenPredicate: (data) =>
                  '${data['visitor_sex'] ?? ''}'.trim().toLowerCase() ==
                  'female',
              note: 'Optional. Shown for female students only.',
            ),
            ServiceField(
              key: 'known_allergies',
              label: 'Known allergies?',
              kind: ServiceFieldKind.chips,
              options: kYesNoUnknown,
              width: FieldWidth.half,
            ),
            ServiceField(
              key: 'allergy_specify',
              label: 'Allergy (specify)',
              kind: ServiceFieldKind.text,
              required: true,
              width: FieldWidth.half,
              shownWhenKey: 'known_allergies',
              shownWhenValues: ['Yes'],
            ),
            ServiceField(
              key: 'history_details',
              label: 'History Details',
              kind: ServiceFieldKind.multiline,
              note: 'Medications, allergies, past illnesses, pregnancy.',
            ),
          ],
        ),
        ServiceSlide(
          title: 'Examination & Assessment',
          fields: [
            ServiceField(
              key: 'physical_exam',
              label: 'Physical Examination / Findings',
              kind: ServiceFieldKind.multiline,
              required: true,
            ),
            ServiceField(
              key: 'clinical_impression',
              label: 'Clinical Impression',
              kind: ServiceFieldKind.multiline,
              required: true,
              note: 'Entered by the clinician. Nothing on this form works this '
                  'out for you.',
            ),
            ServiceField(
              key: 'secondary_diagnosis',
              label: 'Secondary Diagnosis / Condition',
              kind: ServiceFieldKind.text,
              note: 'Optional.',
            ),
            ServiceField(
              key: 'red_flags',
              label: 'Red-flag Check',
              kind: ServiceFieldKind.checkboxes,
              options: kConsultationRedFlags,
              required: true,
              note: 'Tick every sign present — or "None". Each flag except '
                  '"None" raises a referral.',
            ),
          ],
        ),
        ServiceSlide(
          title: 'Treatment',
          fields: [
            ServiceField(
              key: 'treatment',
              label: 'Treatment / Management Provided',
              kind: ServiceFieldKind.checkboxes,
              options: kConsultationTreatment,
              required: true,
              note: 'Tick at least one.',
            ),
            ServiceField(
              key: 'treatment_other',
              label: 'Other Treatment (specify)',
              kind: ServiceFieldKind.text,
              required: true,
              width: FieldWidth.half,
              shownWhenKey: 'treatment',
              shownWhenValues: ['Other'],
            ),
            ServiceField(
              key: 'medication_card',
              label: 'Medication Service',
              kind: ServiceFieldKind.medicationCard,
              shownWhenKey: 'treatment',
              shownWhenValues: ['Medication'],
              note: 'Naming a drug here does not prescribe it. Open Medication '
                  'to prescribe — that is the form that takes it off the '
                  'shelf.',
            ),
            ServiceField(
              key: 'medication_summary',
              label: 'Medication Intended',
              kind: ServiceFieldKind.text,
              width: FieldWidth.half,
              shownWhenKey: 'treatment',
              shownWhenValues: ['Medication'],
              note: 'Optional, record only. Name and dose — what you intend to '
                  'prescribe.',
            ),
            ServiceField(
              key: 'wound_link',
              label: 'Wound Dressing',
              kind: ServiceFieldKind.linkServiceCard,
              opensService: 'wound_dressing',
              buttonLabel: 'Open Wound Dressing',
              shownWhenKey: 'treatment',
              shownWhenValues: ['Wound Care'],
              note: 'For a detailed wound record, use Wound Dressing.',
            ),
            ServiceField(
              key: 'rest_minutes',
              label: 'Minutes rested',
              kind: ServiceFieldKind.number,
              unit: 'min',
              width: FieldWidth.half,
              hint: 'e.g. 30',
              validate: _minutesWhole(),
              shownWhenKey: 'treatment',
              shownWhenValues: ['Rest / Observation'],
            ),
            ServiceField(
              key: 'management_details',
              label: 'Treatment Details',
              kind: ServiceFieldKind.multiline,
              note: 'What was actually done.',
            ),
          ],
        ),
        ServiceSlide(
          title: 'Plan & Disposition',
          fields: [
            ServiceField(
              key: 'disposition',
              label: 'Disposition',
              kind: ServiceFieldKind.chips,
              options: kConsultationDispositions,
              required: true,
              note: 'One. This is the handover line the next person reads.',
            ),
            ServiceField(
              key: 'sent_home_with',
              label: 'Accompanied by',
              kind: ServiceFieldKind.text,
              width: FieldWidth.half,
              shownWhenKey: 'disposition',
              shownWhenValues: ['Sent Home'],
              note: 'Optional. Who took them home.',
            ),
            ServiceField(
              key: 'guardian_informed',
              label: 'Parent / Guardian informed?',
              kind: ServiceFieldKind.chips,
              options: kYesNo,
              required: true,
              width: FieldWidth.half,
              requiredWhen: (data) {
                final disposition = _strOf(data['disposition']);
                return disposition == 'Sent Home' ||
                    kConsultationReferralDispositions.contains(disposition);
              },
              note: 'Owed when someone is sent home or referred.',
            ),
            ServiceField(
              key: 'follow_up_needed',
              label: 'Follow-up Needed?',
              kind: ServiceFieldKind.chips,
              options: kYesNo,
              required: true,
              width: FieldWidth.half,
            ),
            ServiceField(
              key: 'follow_up_date',
              label: 'Follow-up Date',
              kind: ServiceFieldKind.date,
              width: FieldWidth.half,
              shownWhenKey: 'follow_up_needed',
              shownWhenValues: ['Yes'],
              validate: _notPastDate('follow-up date'),
              note:
                  'Optional — leave blank when the follow-up has no date yet.',
            ),
            ServiceField(
              key: 'follow_up_instructions',
              label: 'Follow-up Instructions',
              kind: ServiceFieldKind.text,
              shownWhenKey: 'follow_up_needed',
              shownWhenValues: ['Yes'],
            ),
            ServiceField(
              key: 'excuse_slip_needed',
              label: 'Excuse slip needed?',
              kind: ServiceFieldKind.chips,
              options: kYesNo,
              width: FieldWidth.half,
              note: 'Optional. Stored with the record; the certificate form '
                  'prints the document.',
            ),
            ServiceField(
              key: 'excuse_days',
              label: 'Days excused',
              kind: ServiceFieldKind.number,
              unit: 'days',
              width: FieldWidth.half,
              hint: 'e.g. 2',
              validate: _excuseDaysWhole(),
              shownWhenKey: 'excuse_slip_needed',
              shownWhenValues: ['Yes'],
            ),
            ServiceField(
              key: 'attending',
              label: 'Attending',
              kind: ServiceFieldKind.dropdown,
              options: kAttendingStaff,
              width: FieldWidth.half,
              note: 'Who examined them.',
            ),
            notes(),
          ],
        ),
        ServiceSlide(
          title: 'Referral / Additional Service',
          fields: [
            ServiceField(
              key: 'referral_needed',
              label: 'Referral / Additional Service Needed?',
              kind: ServiceFieldKind.chips,
              options: kYesNo,
              required: true,
              width: FieldWidth.half,
              note: 'Records it and offers the button below. It does not send '
                  'anyone anywhere by itself.',
            ),
            ServiceField(
              key: 'referral_service',
              label: 'Service / Referral',
              kind: ServiceFieldKind.dropdown,
              options: kConsultationReferralServices,
              required: true,
              width: FieldWidth.half,
              shownWhenKey: 'referral_needed',
              shownWhenValues: ['Yes'],
            ),
            ServiceField(
              key: 'referral_link',
              label: 'Add this service to the visit',
              kind: ServiceFieldKind.linkServiceCard,
              linkFromKey: 'referral_service',
              buttonLabel: 'Add this service to the visit',
              shownWhenKey: 'referral_needed',
              shownWhenValues: ['Yes'],
              note: 'Ticks the service onto the visit and opens its form.',
            ),
            ServiceField(
              key: 'referred_to',
              label: 'Referred to (name or place)',
              kind: ServiceFieldKind.text,
              required: true,
              shownWhenPredicate: (data) =>
                  _strListOf(data['referral_needed']).contains('Yes') &&
                  kConsultationNamedReferralTargets
                      .contains(_strOf(data['referral_service'])),
            ),
            ServiceField(
              key: 'referral_reason',
              label: 'Reason',
              kind: ServiceFieldKind.text,
              required: true,
              shownWhenKey: 'referral_needed',
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
                    '${data['chief_complaint'] ?? ''} ${data['additional_complaint'] ?? ''}'
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
              note: 'The complaint suggests a counselling session may help. '
                  'Suggestion only.',
            ),
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
              note: 'Tick what you are taking. Only ticked items are asked '
                  'for and saved; the rest are saved empty.',
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
              note: 'Single reading is a screening result, not a diagnosis.',
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
              note: 'Readings vary by method; axillary reads ~0.3–0.5 °C '
                  'lower than oral.',
            ),
            ServiceField(
              key: 'temp_assessment',
              label: 'Temperature Classification',
              kind: ServiceFieldKind.readOnly,
              width: FieldWidth.half,
              shownWhenKey: kVitalsSelectedKey,
              shownWhenValues: const ['Temperature'],
              note: 'Worked out from the temperature entered above.',
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
              note: 'Whole beats per minute, '
                  '${VitalClassifier.pulseMin}–${VitalClassifier.pulseMax}. '
                  'The classification fills in from the number.',
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
              note: 'Worked out from the pulse rate entered above.',
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
              note: 'Worked out from the respiratory rate entered above.',
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
              note: 'Worked out from the oxygen saturation entered above.',
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
              note: 'Tick everything that applies to this check.',
            ),
            ServiceField(
              key: 'action_taken_other',
              label: 'Other Action',
              kind: ServiceFieldKind.text,
              required: true,
              note: 'The action itself, in your own words. This is what the '
                  'record keeps, not the word "Other".',
              shownWhenKey: 'action_taken',
              shownWhenValues: ['Other'],
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
