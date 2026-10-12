// ─────────────────────────────────────────────────────────────────────────────
//  visit_service_forms.dart
//  What step 3 asks for each service — as DATA.
//
//  WHY THIS IS A SEPARATE FILE WITH NO WIDGETS IN IT
//  Step 3 is one screen with twelve different forms on it. Writing them as
//  twelve bespoke `StatefulWidget`s would mean twelve places where "which
//  fields does a Prenatal visit need?" is answered, and the answer would drift
//  from the validation, the slide count and the saved record. So a form is
//  described here — its slides, its fields, which of them are required, which
//  of them ARE the visit's vitals — and one renderer in
//  lib/screen/visit/service_form_screens.dart turns any of these descriptions
//  into boxes.
//
//  The consequence that matters: adding a service is adding a description here,
//  and renaming a field is editing one line. Nothing in the UI has to change.
//
//  SPECIAL SERVICES
//  Three of the twelve cannot be a list of boxes — Medication needs a stock-aware
//  search, and Medical Certificate needs a document preview. Those are marked
//  with [ServiceFormKind.custom] and built in the renderer; the description
//  still declares their slides so validation, the footer step indicator and
//  Save & Continue all work exactly as they do for the declarative ones.
// ─────────────────────────────────────────────────────────────────────────────

import 'clinic_purposes.dart';
import 'vitals.dart';
import 'vitals_interpretation.dart';

/// How a field is entered.
enum ServiceFieldKind {
  /// A single line of free text.
  text,

  /// Several lines of free text. Only the last slide's `notes` field carries the
  /// 500-character counter; the rest are ordinary boxes.
  multiline,

  /// A number, optionally with a unit and an interpretation pill beside it.
  number,

  /// One of [ServiceField.options].
  dropdown,

  /// One of [ServiceField.options], as a row of chips. Used where the choice is
  /// short and there is no "none of these" to express — an arm, a position —
  /// and a dropdown would make the nurse open something to answer a question
  /// with two answers.
  chips,

  /// Any number of [ServiceField.options], as chips.
  multiselect,

  /// Any number of [ServiceField.options], as tick boxes.
  checkboxes,

  /// A calendar date, stored as yyyy-MM-dd.
  date,

  /// Worked out from other fields, never typed. Carries a small "auto" tag.
  readOnly,

  /// The visit's own vitals, shown read-only with a link to the service that
  /// owns them. This is how Blood Pressure in a Prenatal visit works.
  sharedVitals,

  /// The name of the person who did the work: the signed-in staff member by
  /// default, swappable to any other clinic account, and free to type for
  /// anyone without one.
  ///
  /// A dropdown alone would be wrong twice over. It would refuse the student who
  /// ran the session and cannot be recorded, and it would make a nurse retype
  /// the same name for every service on every visit — which is the reason the
  /// box was dropped from the counselling form in the first place.
  staffName,

  /// One or more items chosen from the clinic's own inventory, recorded by name.
  ///
  /// For what went onto a patient during a visit rather than what was
  /// prescribed: an antiseptic painted into a wound, a dressing taken off the
  /// shelf. It reads from the same shelf the Medication service prescribes from,
  /// so the record and the stock list cannot name two different bottles — but it
  /// spends nothing, because "was used on this patient" and "was dispensed to
  /// this patient" are different facts and only the second one is a
  /// prescription.
  ///
  /// Deliberately not a [MedicineDose]. A quantity here would be a number on a
  /// record that never adjusted a stock line, and the clinic would be left
  /// unable to tell a real discrepancy from a form that always says it.
  inventoryPick,
}

/// Which visit vital a number field owns, if any.
///
/// A field that owns one writes straight into the visit's single
/// [VisitVitals] record rather than into its own service data — which is what
/// makes "entered once, read-only everywhere else" true rather than a
/// convention.
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
  /// The column in `public.visit_vitals` this field fills.
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

  /// The key in `public.vitals_config` and in
  /// [VisitVitals.interpretations] that bands this reading.
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
}

/// One box on a service form.
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
    this.maxChars = 500,
    this.width = FieldWidth.full,
    this.note,
    this.validate,
    this.shownWhenKey,
    this.shownWhenValues = const [],
    this.shownWhen = FieldCondition.isOneOf,
  });

  /// Where the answer is stored, inside the service's own `data` jsonb.
  final String key;

  final String label;

  final ServiceFieldKind kind;

  /// Shown inside the box, after the number.
  final String? unit;

  /// Placeholder text. Written as what the nurse would type, not as a
  /// description of the field.
  final String? hint;

  /// The choices for a dropdown / chips / tick boxes.
  final List<String> options;

  /// Whether Save & Continue and Next refuse to move on without it.
  final bool required;

  /// Set on a number field that IS one of the visit's vitals.
  final VitalField? vital;

  /// The counter length for a multiline field.
  final int maxChars;

  /// Half a slide (with another field beside it) or the whole width.
  final FieldWidth width;

  /// A line under the box: the caveat, the unit reminder, why it is optional.
  final String? note;

  /// Extra rules on top of [required], for a field where "not empty" is not the
  /// same as "usable" — a blood pressure of 9999 is filled in, and it is still
  /// not a measurement.
  ///
  /// Returns the sentence to print under the box, or null when the value is
  /// fine. Deliberately optional: most fields have nothing to say beyond "not
  /// empty", and forcing every one of them to answer this would be noise.
  final ServiceFieldValidator? validate;

  // ── WHEN THIS BOX IS ON SCREEN AT ALL ──────────────────────────────────
  //
  //  A question that only makes sense after another one has been answered is
  //  not on the form until it does. "Why are you following this up?" asked
  //  before the nurse has said whether there IS a follow-up is a box they will
  //  fill in to get rid of it, and a box filled in to get rid of it is worse
  //  than no box. These three properties are what make that possible.

  /// The field whose answer decides whether this box is shown. Null means the
  /// box is always on the slide.
  final String? shownWhenKey;

  /// The answers to [shownWhenKey] that put this box on screen.
  final List<String> shownWhenValues;

  /// How [shownWhenValues] is read off the answer it depends on.
  final FieldCondition shownWhen;

  /// Whether this box belongs on the slide, given what has been answered.
  ///
  /// Always true for a field with no condition, so every form written before
  /// this existed behaves exactly as it did.
  ///
  /// Reads a dropdown's string, a chips row's one-element list and a tick-box
  /// list the same way, because the three are stored differently and a
  /// condition that only worked for one of them would be a trap.
  bool isShownIn(Map<String, dynamic> data) {
    final gate = shownWhenKey;
    if (gate == null || shownWhenValues.isEmpty) return true;
    final raw = data[gate];
    if (raw == null) return false;
    final answers = raw is List ? raw.map((e) => '$e') : ['$raw'];
    return switch (shownWhen) {
      // "Is" rather than "equals", because the gate is very often a tick-box
      // list: ticking "Wound Dressing" and "Bandaging" together should still
      // bring up the dressing material box, and a condition that insisted on an
      // exact match would hide it the moment a second box was ticked.
      FieldCondition.isOneOf => shownWhenValues.any(answers.contains),
      // For the family of answers that share a stem — every "Referred to …"
      // disposition — so the form names the stem once instead of listing each
      // place the clinic refers to.
      FieldCondition.startsWith =>
        shownWhenValues.any((v) => answers.any((a) => a.startsWith(v))),
    };
  }
}

/// How a field's [ServiceField.shownWhenValues] is matched against the answer it
/// depends on.
enum FieldCondition {
  /// The answer is one of the values, or a ticked list holding one of them.
  isOneOf,

  /// The answer begins with one of the values.
  startsWith,
}

/// What is wrong with a value, said in a sentence to print under its box. Null
/// means it is fine.
typedef ServiceFieldValidator = String? Function(Object? value);

enum FieldWidth { full, half }

/// One "page" of a service form. A slide holds at most six fields, arranged in
/// a two-column grid, so a form never needs the page itself to scroll.
/// A set of fields the renderer draws inside one bordered card, side by side.
///
/// For pairs and rows that only mean something together: what was cleaned and
/// what was put on it, a finding and the date it brings the patient back. Two
/// separate boxes make a nurse read them as two unrelated questions and put a
/// border between a number and how it was obtained.
///
/// Groups are layout only. The fields inside are still declared, still
/// validated, still counted as required and still printed on the review, so
/// nothing about the record changes because two boxes became one card.
class FieldGroup {
  const FieldGroup(this.keys);

  final List<String> keys;

  bool holds(String key) => keys.contains(key);
}

class ServiceSlide {
  const ServiceSlide({
    required this.title,
    this.fields = const [],
    this.custom,
    this.groups = const [],
  });

  /// Shown at the top of the slide, and the step name in the card footer.
  final String title;

  final List<ServiceField> fields;

  /// Non-null for a slide the renderer builds itself (the medicine picker, the
  /// certificate preview). The description still owns the slide, so it still
  /// counts towards "1 / 3" and the validation still knows what it needs.
  final ServiceCustomSlide? custom;

  /// Fields drawn inside one card each, in the position the first of them holds
  /// on the slide. A field named here is not also drawn on its own.
  final List<FieldGroup> groups;
}

/// Marker for a slide the renderer builds itself. [id] is what the renderer
/// switches on; [requiredKeys] is what "is this slide answered?" checks.
class ServiceCustomSlide {
  const ServiceCustomSlide(this.id, {this.requiredKeys = const []});

  final String id;
  final List<String> requiredKeys;
}

/// Whether the renderer draws the declared fields or builds the slides itself.
enum ServiceFormKind { declarative, custom }

/// One service's whole form.
class ServiceFormSpec {
  const ServiceFormSpec({
    required this.serviceId,
    required this.slides,
    this.kind = ServiceFormKind.declarative,
  });

  final String serviceId;
  final List<ServiceSlide> slides;
  final ServiceFormKind kind;

  /// The keys that must be answered before the service counts as Complete.
  /// Collected from the slides so a form cannot declare a required field it
  /// never renders, or forget to declare one it does.
  List<String> get requiredKeys => [
        for (final s in slides) ...[
          ...s.fields.where((f) => f.required).map((f) => f.key),
          ...?s.custom?.requiredKeys,
        ],
      ];

  /// The required keys that are actually on screen for the answers in [data].
  ///
  /// A required field behind a condition that has not fired is not required, and
  /// this is the reason: "Follow-up Needed: No" would otherwise leave the form
  /// permanently unsaveable, blocked on a box asking why that is not on the
  /// screen to be filled in. Nothing is lost by dropping it — the moment the
  /// nurse answers "Yes" the box appears AND the requirement comes back with it.
  List<String> requiredKeysIn(Map<String, dynamic> data) => [
        for (final s in slides) ...[
          ...s.fields
              .where((f) => f.required && f.isShownIn(data))
              .map((f) => f.key),
          ...?s.custom?.requiredKeys,
        ],
      ];

  /// A service with nothing required still has to be a valid service, so
  /// "answered" is at least one field carrying a value.
  ///
  /// A required field is only answered when it is both filled in AND valid:
  /// otherwise a systolic of 9999 would satisfy [requiredKeys] and the nurse
  /// would walk out with a reading nobody checked.
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
      return validate(k, v) == null;
    });
  }

  /// Every declared field across every slide, in order.
  List<ServiceField> get fields => [
        for (final s in slides) ...s.fields,
      ];

  /// The fields of [slide] the answers in [data] actually put on screen, in the
  /// order they were declared. The renderer lays these out, so a box behind a
  /// condition that has not fired is not merely greyed out — it is not there,
  /// and its row is given to whatever else is.
  List<ServiceField> visibleFields(
          ServiceSlide slide, Map<String, dynamic> data) =>
      [
        for (final f in slide.fields)
          if (f.isShownIn(data)) f
      ];

  /// What is wrong with [key]'s answer, or null when it is fine. Every rule is
  /// declared in one place, so the validator, the red border and the disabled
  /// Next button cannot disagree about whether a value is acceptable.
  String? validate(String key, Object? value) {
    for (final f in fields) {
      if (f.key == key) return f.validate?.call(value);
    }
    return null;
  }

  /// The validators declared on one slide, so the renderer can show each error
  /// under its own box.
  Map<String, ServiceFieldValidator> validatorsFor(ServiceSlide slide) => {
        for (final f in slide.fields)
          if (f.validate != null) f.key: f.validate!,
      };
}

/// A validator that accepts a whole number inside [limit] and says so in the
/// field's own units when it does not.
///
/// Blank is not an error here: "required" already owns the empty box, and two
/// sentences under one field is a worse experience than one. This only speaks
/// up once there IS a number and it is the wrong one.
///
/// Reads a `double` as well as a string, because a reading mirrored out of
/// `visit_vitals` arrives as 120.0 rather than 120 — and `int.tryParse` on
/// "120.0" is null, which would have rejected every value the nurse had typed
/// correctly.
ServiceFieldValidator _bpNumber(VitalLimit limit) => (value) {
      if (value == null) return null;
      final num? parsed = switch (value) {
        final num n => n,
        _ => num.tryParse('$value'.trim()),
      };
      if (parsed == null) return limit.errorText;
      return limit.accepts(parsed.round()) ? null : limit.errorText;
    };

/// A validator for a 0–10 pain score.
///
/// Blank is not an error here — "required" already owns the empty box — so this
/// only speaks up once there IS a number and it is out of scale. Written as a
/// plain range rather than a slider because a nurse typing "6" with a keyboard
/// is faster than one dragging a handle, and a slider that is halfway between
/// 5 and 6 has recorded a pain score of neither.
ServiceFieldValidator _painScore() => (value) {
      if (value == null) return null;
      final num? parsed = switch (value) {
        final num n => n,
        _ => num.tryParse('$value'.trim()),
      };
      if (parsed == null || parsed < 0 || parsed > 10) {
        return 'A pain score is a whole number from 0 to 10.';
      }
      return null;
    };

/// How many repeat readings the form will hold. Two is the guideline minimum for
/// an initial assessment; the cap keeps the average meaningful rather than an
/// average of whatever the nurse felt like doing.
const int kMaxBpReadings = 3;

// ── REUSABLE CHOICE LISTS ────────────────────────────────────────────────────

/// The complaint a consultation was booked for, as tick boxes beside a box that
/// carries the complaint in the patient's own words. The list shortens the
/// common answers; the free text is what makes it a record rather than a
/// multiple-choice question, because "headache and dizziness for 2 days" is not
/// any one of these.
const List<String> kConsultationComplaints = [
  'Headache',
  'Fever',
  'Cough / Cold',
  'Abdominal Pain',
  'Dizziness',
  'Injury',
  'Menstrual Concern',
  'Skin Problem',
  'Other',
];

/// Relevant history worth flagging on a consultation. Optional by nature: most
/// of it is already in the complaint, and a box that is asked every time is a
/// box that gets the same answer every time.
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
  'Other',
];

/// What the clinician did about it. Deliberately not a diagnosis list, and
/// deliberately including "Medication" without a prescription behind it — the
/// record says a drug was part of the management, and the prescription itself
/// lives in Medication Service where stock is actually deducted.
const List<String> kConsultationTreatment = [
  'Advice / Health Education',
  'Medication',
  'Wound Care',
  'Rest / Observation',
  'Other',
];

/// Yes or No, in that order.
///
/// "No" first so it is the first chip under the thumb and so a form that is
/// scrolled away from still reads as a no rather than a yes: the default answer
/// on a referral question has to be the one that does not send anyone anywhere.
const List<String> kYesNo = ['No', 'Yes'];

/// Where a visit is being sent next. The clinic's own services by their names as
/// the nurse knows them, plus the two ways out of the building.
const List<String> kReferralServices = [
  'BP Taking',
  'Temperature Checking',
  'BMI',
  'Wound Dressing',
  'Medication Service',
  'Health Counselling',
  'Prenatal',
  'First Aid Treatment',
  'Medical Consultation',
  'Vital Signs',
  'External Healthcare Facility',
  'Other',
];

/// What was counselled about. Tick boxes rather than a dropdown because a session
/// on nutrition and exercise is one session, and a dropdown would have thrown the
/// second topic away.
const List<String> kCounsellingTopics = [
  'General Health',
  'Nutrition / Diet',
  'Personal Hygiene',
  'Mental/Emotional Well-being',
  'Reproductive Health',
  'Physical Activity / Exercise',
  'Disease Prevention',
  'Medication / Treatment Adherence',
  'Other',
];

/// What the counsellor actually did, as distinct from what it was about.
///
/// This is the line the whole form turns on, and the reason a referral is a
/// separate slide rather than an option in here: "Advised on diet" is something
/// the clinic did, while "needs a BMI" is something that should happen next. Two
/// different claims, two different boxes, and a record that mixes them cannot be
/// read back to say whether the person was treated or sent away.
const List<String> kCounsellingProvided = [
  'Health Education',
  'Advice / Guidance',
  'Preventive Education',
  'Lifestyle / Behavior Advice',
  'Demonstration',
  'Medication-related Education',
  'Other',
];

const List<String> kClearancePurposes = [
  'Sports / Intramurals',
  'OJT / Practicum',
  'Enrollment',
  'Employment / Work',
  'Other',
];

const List<String> kAttendingStaff = [
  'Nurse',
  'Physician',
  'Nurse + Physician',
];

const List<String> kWoundTypes = [
  'Incised / Cut',
  'Abrasive',
  'Burn',
  'Puncture wound',
  'Laceration',
  'Other',
];

/// How the wound looks when the dressing comes off. A question with a small
/// fixed set of answers, so it is chips rather than a dropdown.
const List<String> kWoundConditions = [
  'Clean',
  'Infected',
  'Healing',
  'Requires suturing',
];

/// What was used to clean it. "Tick all that apply" because a wound is often
/// rinsed with saline and then wiped with povidone-iodine, and the record is
/// more useful with both on it than with whichever was tapped last.
///
/// "Other" is on both of these lists, and it is the reason for the text box
/// behind it: a clinic with its own prep on the shelf would otherwise have to
/// write it in the notes, where it is not a tick anybody can count.
const List<String> kWoundCleaningPerformed = [
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

/// The same materials plus the two that belong to first aid rather than to a
/// dressing clinic: an eye pad, and the limb sling.
///
/// Wound Dressing keeps its own shorter list because that form is a dressing
/// appointment and a sling would be a different service. Here, where the
/// treatment box above already says "Wound Dressing" or "Bandaging", the sling
/// is the thing actually put on the patient and leaving it out makes the list
/// wrong for the case it was written for.
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

/// What the nurse saw. Deliberately observations and outcomes, not a diagnosis —
/// the same line the whole step 3 holds: it records what was found, and a
/// diagnosis is a separate service with a clinician's name on it.
const List<String> kWoundFindings = [
  'Wound edges clean',
  'No signs of infection',
  'Redness present',
  'Swelling present',
  'Pus / discharge present',
  'Bleeding controlled',
  'Edges approximated / sutured',
];

/// What the medicine was wanted for. Tick boxes beside a box that takes the
/// complaint in the patient's own words — "headache since last night, worse in
/// the evening" is the record, and this list is only there to save typing it.
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

/// What happened to the medicine. Required, and the only genuinely important
/// question on the whole form: "Medication Service" does not mean anybody was
/// given anything, and a record that cannot tell those apart is worse than no
/// record at all.
const List<String> kMedicationActions = [
  'Administered',
  'Dispensed / Given to Individual',
  'Not Given',
  'Medication Unavailable',
  'Referred',
];

/// The three of [kMedicationActions] that are a "no". Each is a reason the
/// person left without the medicine, so each has to be followed by what the
/// reason actually was — and that is why they are named as a list here rather
/// than written out three times in the form.
const List<String> kMedicationNotGiven = [
  'Not Given',
  'Medication Unavailable',
  'Referred',
];

/// How the person was afterwards. Optional throughout: a nurse who hands out
/// paracetamol and never sees the patient again has genuinely not observed an
/// outcome, and a form that forced a guess would be filled in with "Improved".
const List<String> kMedicationResponses = [
  'Improved',
  'No Change',
  'Worsened',
  'Not Observed',
];

/// Why the person is being seen for first aid: what happened to them, rather
/// than how it happened.
///
/// One question, not two. "Fall / Slip" and "Accidental cut" were previously
/// separate boxes for the incident and the cause, which made a nurse tick both
/// to describe a fall that cut someone, and left a record where the cause was on
/// the form and the injury was not.
const List<String> kFirstAidIncidents = [
  'Minor Injury',
  'Wound',
  'Bleeding',
  'Burn',
  'Sprain / Strain',
  'Bruise',
  'Fall',
  'Headache',
  'Dizziness',
  'Fainting',
  'Other',
];

/// What the nurse found on examination. Tick boxes, because an injury arrives
/// with several findings at once and a single answer can only keep one of them.
///
/// Observations, not conclusions: "Bleeding" is something you can see, "shock"
/// is a diagnosis and belongs to the consultation.
const List<String> kFirstAidFindings = [
  'Pain',
  'Swelling',
  'Bleeding',
  'Bruising',
  'Redness',
  'Wound / Open Skin',
  'Limited Movement',
  'Burn',
  'Other',
];

/// The first aid actually carried out. At least one has to be ticked, because
/// "First Aid Treatment" with nothing on it is a form that recorded an
/// attendance and not a treatment.
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

/// The person afterwards, in the four words a nurse would use. Not a scale and
/// not a diagnosis — it is the handover line, and "requires further treatment" is
/// a perfectly good answer.
const List<String> kConditionAfterTreatment = [
  'Improved',
  'Stable',
  'Requires Further Observation',
  'Requires Further Treatment',
];

/// What happened to them next. "Referred" comes last and the two referral
/// options share a stem on purpose, so the follow-up date and referral reason
/// behind them are declared once rather than four times over.
const List<String> kFirstAidDispositions = [
  'Treated and Released',
  'Advised to Monitor',
  'Follow-up Recommended',
  'Referred to Clinic Head / Nurse',
  'Referred to Physician / Healthcare Facility',
];

const List<String> kFetalPresentations = [
  'Cephalic',
  'Breech',
  'Transverse / Oblique',
  'Not determined',
];

/// Fetal movement over the last day. A required question on a prenatal form
/// because "the baby is moving" is one of the few things a mother can report on
/// the mother, and its absence is a finding.
const List<String> kFetalMovements = [
  'Active',
  'Normal',
  'Reduced',
  'Absent',
  'Not applicable',
];

/// What the visit was for. At least one has to be ticked, or a prenatal form
/// records a full set of measurements and no reason for them.
const List<String> kPrenatalServices = [
  'Routine Prenatal Visit',
  'Initial ANC Booking',
  'High-Risk Pregnancy Follow-up',
  'Pre-Eclampsia Monitoring',
  'Antenatal Ultrasound Request',
  'Iron / Folic Acid Supplementation',
  'Referral to Obstetrician',
  'Other',
];

/// What was done about it, kept separate from the service itself so the record
/// says both what the mother came for and what she left with.
const List<String> kPrenatalActions = [
  'Vital Signs Taken',
  'Fetal Heart Tone Monitored',
  'Advice Given',
  'Medication Prescribed',
  'Referred for Further Testing',
  'Follow-up Scheduled',
];

/// Where the swelling is, asked in the order that matters rather than the order
/// that sounds mildest. Ankles at the end of a long day are not the finding;
/// hands and face are.
const List<String> kPrenatalEdema = [
  'None',
  'Feet / Ankles only',
  'Legs',
  'Hands / Face',
];

/// The other half of the same screen. "Not tested" is offered on purpose: a form
/// that cannot record the check not being done produces a positive answer by
/// omission, which is worse than no form.
const List<String> kPrenatalUrineProtein = [
  'Not tested',
  'Negative',
  'Trace / 1+',
  '2+ or more',
];

/// What she went home with. Distinct from [kPrenatalServices], which says why she
/// came: iron and folic acid are routine enough to be a reason for the visit and
/// rare enough to be a separate question about the shelf.
const List<String> kPrenatalGiven = [
  'Iron / Folic Acid',
  'Tetanus Toxoid (TT)',
  'Calcium',
  'Anti-malarial',
];

// ── THE CHOICES THE FOUR VITAL SIGNS FORMS SHARE ────────────────────────────

/// Where the arm was held. Two answers, so it is a chip and not a dropdown the
/// nurse has to open to close again.
const List<String> kBpArms = ['Left', 'Right'];

/// The position the reading was taken in. It is required because the same 130/85
/// means different things sitting and standing, and a reading with no position
/// on it cannot be read against a guideline at all.
const List<String> kBpPositions = ['Sitting', 'Standing', 'Lying'];

/// What was done about the reading, rather than what the reading was. Optional,
/// because plenty of readings need nothing done beyond recording them.
const List<String> kBpActions = [
  'Rechecked after rest',
  'Advised to rest and recheck',
  'Advised on salt intake',
  'Advised on medication',
  'Medication started / adjusted',
  'Referred to physician',
  'Follow-up scheduled',
  'Other',
];

/// Where a thermometer goes. The site's name is written out in full because
/// "Axillary" alone is a word new staff meet in a textbook and not on a
/// thermometer, and the reading means something different depending on it.
const List<String> kTemperatureMethods = [
  'Oral',
  'Axillary (underarm)',
  'Tympanic (ear)',
  'Forehead / Temporal',
];

/// The thirteen rows of the paper form's PHYSICAL EXAMINATION table, in the
/// order the paper prints them. The key is what the template's
/// `exam.*` placeholder is filled from, so the printed form and the on-screen
/// form can never disagree about which row is which.
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

// ── THE FORM REGISTRY ────────────────────────────────────────────────────────

/// The description of every service on step 2, keyed by its `ClinicPurposes`
/// id. The `other` sentinel from the wizard has an entry too, so the step-3
/// list is driven by the same ids the step-2 checklist writes.
class VisitServiceForms {
  const VisitServiceForms._();

  static const String otherServiceId = 'other';

  /// Convenience for the notes field every form ends on. Declared once so all
  /// twelve forms carry the same 500-character limit and the same key.
  static ServiceField notes({String hint = 'Optional'}) => ServiceField(
        key: 'notes',
        label: 'Notes / Remarks',
        kind: ServiceFieldKind.multiline,
        maxChars: 500,
        hint: hint,
      );

  /// The read-only sheet every service ends on: the whole form printed back
  /// for the nurse to check before pressing Done. The renderer builds it from
  /// the spec (`form_review`), so a service needs no sheet of its own — the
  /// boxes the nurse answered decide what is on it. BP Taking carries its own
  /// printed form instead; the certificate services end on their own preview.
  static const ServiceSlide reviewSlide = ServiceSlide(
    title: 'Review',
    custom: ServiceCustomSlide('form_review'),
  );

  /// The twelve descriptions, keyed by their `ClinicPurposes` id. The
  /// `other` sentinel from the wizard has an entry too, so the step-3 list is
  /// driven by the same ids the step-2 checklist writes.
  ///
  /// Not const, because [notes] is a method — a map literal calling it has to be
  /// built on first use rather than at compile time, which costs nothing here
  /// and is only read while a form is being built.
  static final Map<String, ServiceFormSpec> _specs = {
    // ── 1. BP TAKING ───────────────────────────────────────────────────────
    //  FOUR slides, the first of them built by the renderer rather than declared,
    //  because the joint systolic/diastolic box, the live result card and the
    //  guide are all pieces of UI a field list cannot express. The declaration is
    //  still worth having: it is what says what "Complete" means and what Save
    //  refuses to pass.
    //
    //  The READING is on one screen on purpose. A nurse taking a blood pressure
    //  wants to see the number, its verdict, the pulse and their note together —
    //  splitting them put the reading and its meaning on different screens, and
    //  made the form taller than a 1366x768 laptop could show without scrolling.
    //
    //  The detail behind the reading, and the printed form at the end, are separate
    //  slides for the same reason in reverse: they are read once, after the
    //  number, and adding them to the reading slide would have pushed the note off
    //  the bottom of the screen.
    'bp_tracking': ServiceFormSpec(
      serviceId: 'bp_tracking',
      kind: ServiceFormKind.custom,
      slides: [
        ServiceSlide(
          title: 'Vital Signs',
          // The three required keys live on the fields below rather than in
          // `custom.requiredKeys`, because that is where the limits they have to
          // respect are declared. Naming them twice would make Next check each
          // one twice and complain about the same box twice.
          custom: const ServiceCustomSlide('bp_reading'),
          fields: [
            ServiceField(
              key: 'systolic',
              label: 'Blood Pressure (mmHg)',
              kind: ServiceFieldKind.number,
              unit: 'mmHg',
              vital: VitalField.systolic,
              required: true,
              width: FieldWidth.half,
              validate: _bpNumber(BpLimits.systolic),
            ),
            ServiceField(
              key: 'diastolic',
              label: 'Blood Pressure (mmHg)',
              kind: ServiceFieldKind.number,
              unit: 'mmHg',
              vital: VitalField.diastolic,
              required: true,
              width: FieldWidth.half,
              validate: _bpNumber(BpLimits.diastolic),
            ),
            // `pulse_bpm`, not `heart_rate`. The form's own data is read by
            // people auditing a visit, and "pulse_bpm" says what the number is;
            // the shared visit vital it also writes is still `heart_rate`,
            // because that is the column every other service reads.
            ServiceField(
              key: 'pulse_bpm',
              label: 'Pulse Rate (beats per minute)',
              kind: ServiceFieldKind.number,
              unit: 'bpm',
              required: true,
              width: FieldWidth.half,
              validate: _bpNumber(BpLimits.pulse),
            ),
            ServiceField(
              key: 'notes',
              label: 'Notes / Remarks',
              kind: ServiceFieldKind.multiline,
              maxChars: 500,
            ),
          ],
        ),
        ServiceSlide(
          title: 'Measurement Details',
          // The finding comes first, worked out as the boxes were typed, so the
          // verdict is on the page rather than hidden in a result panel above.
          fields: [
            ServiceField(
              key: 'bp_assessment',
              label: 'BP Classification',
              kind: ServiceFieldKind.readOnly,
              width: FieldWidth.full,
              note: 'Worked out from the reading above — Normal, High-Normal, '
                  'Grade 1, Grade 2 or Severe.',
            ),
            // The position and the arm are required together, and the pair is what
            // makes a reading comparable: 130/85 sitting and 130/85 standing are
            // different findings, and a record holding only the first number is a
            // record that cannot be read back.
            ServiceField(
              key: 'position',
              label: 'Position',
              kind: ServiceFieldKind.chips,
              options: kBpPositions,
              required: true,
              width: FieldWidth.half,
            ),
            ServiceField(
              key: 'arm_used',
              label: 'Arm Used',
              kind: ServiceFieldKind.chips,
              options: kBpArms,
              required: true,
              width: FieldWidth.half,
            ),
            // The rest of the vitals. Optional on purpose: a clinic that does
            // not take a respiratory rate at every BP should not be made to type
            // one, but one that does should have it on the same reading. They
            // write into the visit's vitals, so whichever service asks first
            // owns them and the rest read them read-only.
            //
            // No temperature here on purpose. Temperature Checking owns the
            // visit's temperature, and a vital can only have one owner: a second
            // box for it on this form would accept the number and then write it
            // into the BP service's data, leaving Temperature Checking's required
            // box permanently empty and the visit impossible to finish. The same
            // reason keeps the pulse on the reading slide, where the BP widget
            // writes it, instead of being repeated here.
            ServiceField(
              key: 'resp_rate',
              label: 'Respiratory Rate',
              kind: ServiceFieldKind.number,
              unit: '/min',
              vital: VitalField.respRate,
              width: FieldWidth.half,
              hint: 'Optional',
              validate: _bpNumber(BpLimits.respRate),
            ),
            ServiceField(
              key: 'o2_sat',
              label: 'Oxygen Saturation (SpO2)',
              kind: ServiceFieldKind.number,
              unit: '%',
              vital: VitalField.o2Sat,
              width: FieldWidth.half,
              hint: 'Optional',
              validate: _bpNumber(BpLimits.spo2),
            ),
          ],
        ),
        ServiceSlide(
          title: 'Action Provided',
          fields: [
            ServiceField(
              key: 'action_taken',
              label: 'Action / Advice',
              kind: ServiceFieldKind.checkboxes,
              options: kBpActions,
              note: 'Tick anything done or advised for this reading.',
            ),
            ServiceField(
              key: 'action_other',
              label: 'Other Action',
              kind: ServiceFieldKind.text,
              width: FieldWidth.half,
              note: 'Fill in only when "Other" is ticked.',
            ),
          ],
        ),
        ServiceSlide(
          title: 'BP Taking Form',
          // The printed form, held back until the reading exists so there is
          // something to print. This is the last slide on purpose: Done only
          // means "I have finished with this service" once the nurse can see the
          // whole form in front of them.
          custom: const ServiceCustomSlide('bp_form'),
        ),
      ],
    ),

    // ── 2. TEMPERATURE CHECKING ────────────────────────────────────────────
    // The method is required, not optional. A temperature without one is a number
    // that could have come off a forehead scanner in a corridor or a glass
    // thermometer under the tongue, and the two differ by enough to change the
    // assessment sitting in the strip above it.
    //
    // The assessment itself is NOT a field. It is worked out from the reading and
    // shown in the result strip and the pill beside the box, so there is no way to
    // type an assessment that disagrees with the number it came from.
    'temperature_checking': ServiceFormSpec(
      serviceId: 'temperature_checking',
      slides: [
        ServiceSlide(
          title: 'Reading',
          // The number and how it was taken share one card. A temperature
          // without a method is a reading from an unknown instrument, and two
          // separate boxes with a border between them invite exactly that: the
          // method is the box that gets left behind when the number is already
          // typed. The note sits under the card, where a note belongs.
          groups: [
            FieldGroup(['temp_c', 'method'])
          ],
          fields: [
            ServiceField(
              key: 'temp_c',
              label: 'Temperature',
              kind: ServiceFieldKind.number,
              unit: '°C',
              vital: VitalField.temperature,
              required: true,
              width: FieldWidth.half,
              hint: '36.8',
            ),
            ServiceField(
              key: 'method',
              label: 'Method / Site',
              kind: ServiceFieldKind.dropdown,
              options: kTemperatureMethods,
              required: true,
              width: FieldWidth.half,
            ),
            ServiceField(
              key: 'temp_assessment',
              label: 'Classification / Findings',
              kind: ServiceFieldKind.readOnly,
              width: FieldWidth.full,
              note: 'Worked out from the temperature above — Low, Normal, '
                  'Low-grade fever, Fever or High fever.',
            ),
            notes(),
          ],
        ),
        VisitServiceForms.reviewSlide,
      ],
    ),

    // ── 3. BMI ─────────────────────────────────────────────────────────────
    // Deliberately no BMI box and no classification box that can be typed: a
    // typed BMI can disagree with the height and weight beside it, so both are
    // worked out and shown read-only.
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

    // ── 4. HEALTH COUNSELLING ─────────────────────────────────────────────
    // Three slides, and the split between the second and the third is the whole
    // point of the form.
    //
    // "Counselling Provided" is what the clinic DID. "Additional Service Needed"
    // is what should happen NEXT. They are not one list: a session where the
    // nurse ticked "Advice / Guidance" and then sent the person for a BMI
    // recorded two separate facts, and one that offered "Referral Recommended" as
    // a fourth tick on the first list could not say which of the two had
    // happened.
    //
    // A topic never opens another service on its own. Nutrition counselling
    // might or might not need a BMI behind it, and the nurse who knows which is
    // the one answering on the last slide.
    //
    // What was dropped: the "Concerns Discussed" / "Advice Given" pair, which
    // said the same thing twice — once as a topic list and once as free text,
    // with nothing to say which of the two was the record.
    'health_counselling': ServiceFormSpec(
      serviceId: 'health_counselling',
      slides: [
        ServiceSlide(
          title: 'Counselling Information',
          fields: [
            // Back, deliberately, after being dropped as redundant. It was
            // redundant only because it was a blank box asking a nurse to type
            // the name of the person already signed in and shown on the strip
            // above. Seeded with that name it is no work at all, and it earns
            // its place back for the two cases that are real: a nurse covering
            // for a colleague, and a session run by someone with no account of
            // their own - a student, an interpreter - who can only be typed.
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
            ServiceField(
              key: 'reason',
              label: 'Reason / Concern',
              kind: ServiceFieldKind.multiline,
              required: true,
              note: 'Why this person needed counselling, in their own words. '
                  'The topic says what was discussed; this says why.',
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
              label: 'Other Provided',
              kind: ServiceFieldKind.text,
              required: true,
              shownWhenKey: 'provided',
              shownWhenValues: ['Other'],
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
                  'Optional — leave blank when the follow-up has no date yet.',
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
              label: 'Recommended / Related Service',
              kind: ServiceFieldKind.dropdown,
              options: kReferralServices,
              required: true,
              width: FieldWidth.half,
              shownWhenKey: 'additional_service_needed',
              shownWhenValues: ['Yes'],
            ),
            ServiceField(
              key: 'referral_reason',
              label: 'Reason for Referral / Additional Service',
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

    // ── 5. PRENATAL ────────────────────────────────────────────────────────
    // The blood pressure and the weight are the VISIT's, not this form's, so they
    // stay the read-only strip with a link back to whichever service took them.
    // They are deliberately NOT second required boxes here: a second copy of a
    // weight, typed on a different slide, is a weight that can disagree with the
    // one every other service and the BMI were worked out from — and only one of
    // the two would ever be the one on the record. What the prenatal form owns
    // and requires is the pregnancy itself.
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
              width: FieldWidth.half,
              note: 'The date the age of gestation and the due date are '
                  'worked out from.',
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
              // The two words every clinic form uses and almost none of them
              // explains. A count, not a stage: total pregnancies ever, this one
              // included. Stated on the box because getting it wrong silently
              // changes what the rest of the record means.
              note: 'Total pregnancies ever, this one included.',
            ),
            ServiceField(
              key: 'para',
              label: 'Para',
              kind: ServiceFieldKind.number,
              required: true,
              width: FieldWidth.half,
              // A count of live/sterilised births, not of pregnancy outcomes:
              // para and gravida differ by the pregnancies that did not reach a
              // birth, which is exactly the difference nobody should be guessing
              // at from the label alone.
              note: 'Pregnancies that reached a birth, not including this one.',
            ),
          ],
        ),
        ServiceSlide(
          title: 'Examination',
          fields: [
            ServiceField(
              key: 'shared_vitals',
              label: 'Visit Vitals (Blood Pressure / Weight)',
              kind: ServiceFieldKind.sharedVitals,
              width: FieldWidth.full,
            ),
            // Named one vital per box rather than left to the result strip
            // alone, because on this form the BP verdict is the single most
            // consequential line on it, and a headline about several readings at
            // once is not the same thing as the BP's own category.
            ServiceField(
              key: 'bp_assessment',
              label: 'Blood Pressure Assessment',
              kind: ServiceFieldKind.readOnly,
              width: FieldWidth.half,
              note: 'Worked out from the visit\'s blood pressure.',
            ),
            ServiceField(
              key: 'bmi',
              label: 'BMI',
              kind: ServiceFieldKind.readOnly,
              width: FieldWidth.half,
              note: 'Worked out from the visit\'s height and weight.',
            ),
            ServiceField(
              key: 'fundal_height',
              label: 'Fundal Height',
              kind: ServiceFieldKind.number,
              unit: 'cm',
              required: true,
              width: FieldWidth.half,
            ),
            ServiceField(
              key: 'fetal_heart_tone',
              label: 'Fetal Heart Tone',
              kind: ServiceFieldKind.number,
              unit: 'bpm',
              required: true,
              width: FieldWidth.half,
            ),
            ServiceField(
              key: 'fetal_movement',
              label: 'Fetal Movement',
              kind: ServiceFieldKind.dropdown,
              options: kFetalMovements,
              required: true,
              width: FieldWidth.full,
            ),
          ],
        ),
        ServiceSlide(
          title: 'Maternal Checks',
          fields: [
            // The two halves of the pre-eclampsia screen, and they are here as
            // fields rather than left to the BP because the BP alone is not the
            // warning: swelling of the face or the hands, and protein in the
            // urine, are what turn a raised reading into a referral, and this
            // form was measuring neither.
            ServiceField(
              key: 'edema',
              label: 'Oedema / Swelling',
              kind: ServiceFieldKind.chips,
              options: kPrenatalEdema,
              required: true,
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
              required: true,
              width: FieldWidth.half,
              note: '"Not tested" is a real answer here, and is not a failure '
                  'state — the other half of the screen is on the box beside it.',
            ),
          ],
        ),
        ServiceSlide(
          title: 'Care Plan',
          fields: [
            ServiceField(
              key: 'service_provided',
              label: 'Service / Care Provided',
              kind: ServiceFieldKind.checkboxes,
              options: kPrenatalServices,
              required: true,
              note: 'Tick at least one. The reason for the visit has to be on '
                  'the record, or a full set of measurements says nothing about '
                  'why they were taken.',
            ),
            ServiceField(
              key: 'action_taken',
              label: 'Action / Advice',
              kind: ServiceFieldKind.checkboxes,
              options: kPrenatalActions,
              required: true,
              note: 'Tick at least one.',
            ),
            // What she actually left with, which is a different fact from what
            // the visit was for: a mother can come for iron and go home without
            // any, and only one of those two is on the record above.
            ServiceField(
              key: 'given_this_visit',
              label: 'Given This Visit',
              kind: ServiceFieldKind.checkboxes,
              options: kPrenatalGiven,
              note: 'What she went home with. Leave blank when nothing was '
                  'handed over.',
            ),
            ServiceField(
              key: 'presentation',
              label: 'Presentation',
              kind: ServiceFieldKind.dropdown,
              options: kFetalPresentations,
              width: FieldWidth.full,
            ),
            notes(),
          ],
        ),
        VisitServiceForms.reviewSlide,
      ],
    ),

    // ── 6. MEDICATION ─────────────────────────────────────────────────────
    // The two middle slides are the picker's, not the field list's: stock-aware
    // search, one row per medicine with its own dosage, and a live warning when
    // the prescription is deeper than the shelf. Stock is NOT deducted here: that
    // happens when the visit is completed.
    //
    // The first and last slides are declared like everything else, and the last
    // one carries the question the service exists to answer — did the person
    // actually get it? A "Medication Service" record that cannot tell
    // "administered" from "the shelf was empty" is the record that gets audited
    // and cannot be defended.
    //
    // Strength is not a column of its own because the inventory item carries it
    // in its name ("Paracetamol 500 mg") and the dosage row prints that name. A
    // second strength box would be a second place for one answer to live and
    // disagree with itself.
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
          custom: ServiceCustomSlide('medicine_picker'),
        ),
        ServiceSlide(
          title: 'Dosage',
          custom: ServiceCustomSlide(
            'medicine_dosage',
            requiredKeys: ['medicine_name'],
          ),
        ),
        ServiceSlide(
          title: 'Outcome',
          fields: [
            ServiceField(
              key: 'medication_action',
              label: 'Medication Action',
              kind: ServiceFieldKind.chips,
              options: kMedicationActions,
              required: true,
              note: 'What actually happened. Required, because this service '
                  'being on the visit does not mean anybody was given anything.',
            ),
            ServiceField(
              key: 'action_reason',
              label: 'Reason',
              kind: ServiceFieldKind.text,
              required: true,
              shownWhenKey: 'medication_action',
              shownWhenValues: kMedicationNotGiven,
              note: 'Required for the three answers that leave the person '
                  'without the medicine.',
            ),
            ServiceField(
              key: 'response',
              label: 'Response After Medication',
              kind: ServiceFieldKind.chips,
              options: kMedicationResponses,
              note: 'Optional — only if you saw them afterwards.',
            ),
            notes(),
          ],
        ),
        ServiceSlide(
          title: 'Additional Service',
          fields: [
            ServiceField(
              key: 'additional_service_needed',
              label: 'Additional Service Needed?',
              kind: ServiceFieldKind.chips,
              options: kYesNo,
              required: true,
              width: FieldWidth.half,
              note: 'Records it. It does not open that service.',
            ),
            ServiceField(
              key: 'referral_service',
              label: 'Recommended / Related Service',
              kind: ServiceFieldKind.dropdown,
              options: kReferralServices,
              required: true,
              width: FieldWidth.half,
              shownWhenKey: 'additional_service_needed',
              shownWhenValues: ['Yes'],
            ),
            ServiceField(
              key: 'referral_reason',
              label: 'Reason for Referral / Additional Service',
              kind: ServiceFieldKind.text,
              shownWhenKey: 'additional_service_needed',
              shownWhenValues: ['Yes'],
            ),
          ],
        ),
        VisitServiceForms.reviewSlide,
      ],
    ),

    // ── 7. FIRST AID TREATMENT ────────────────────────────────────────────
    // Four slides, and the conditional boxes are the reason it is not two.
    //
    // A pain score is asked for only when "Pain" is among the findings, because
    // asking a person with a clean sprain how much it hurts invites them to
    // invent a number, and an invented 0 and a real 0 look the same on the record
    // forever after.
    //
    // "Wound Dressing" and "Basic Medication Given" each bring up their own
    // detail, and nothing else does. This is the form refusing to grow: every
    // extra question is one more box to get wrong on a person who is in front of
    // you, so a box appears only when an answer has earned it.
    //
    // The body location list is the clinic's own, which is side-specific — "Left
    // Knee" rather than "Knee". An injury record that cannot say which knee is
    // half a record.
    //
    // What was dropped: "Materials Used" as a free-standing list. It is now a
    // consequence of the treatment rather than a separate question, so a dressing
    // cannot be recorded with no material and a material cannot be recorded with
    // no dressing.
    'first_aid_treatment': ServiceFormSpec(
      serviceId: 'first_aid_treatment',
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
              key: 'body_part',
              label: 'Body Location',
              kind: ServiceFieldKind.dropdown,
              options: ClinicPurposes.bodySites,
              required: true,
              width: FieldWidth.half,
            ),
            ServiceField(
              key: 'findings',
              label: 'Observed Condition',
              kind: ServiceFieldKind.checkboxes,
              options: kFirstAidFindings,
              required: true,
              note: 'Tick at least one. What you can see, not what it means.',
            ),
            ServiceField(
              key: 'findings_other',
              label: 'Other Finding',
              kind: ServiceFieldKind.text,
              required: true,
              width: FieldWidth.half,
              shownWhenKey: 'findings',
              shownWhenValues: ['Other'],
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
              validate: _painScore(),
            ),
          ],
        ),
        ServiceSlide(
          title: 'First Aid Provided',
          fields: [
            ServiceField(
              key: 'treatment',
              label: 'Treatment / First Aid Performed',
              kind: ServiceFieldKind.checkboxes,
              options: kFirstAidTreatments,
              required: true,
              note:
                  'Tick at least one. "First Aid Treatment" with nothing on it '
                  'is an attendance, not a treatment.',
            ),
            ServiceField(
              key: 'treatment_other',
              label: 'Other Treatment',
              kind: ServiceFieldKind.text,
              required: true,
              width: FieldWidth.half,
              shownWhenKey: 'treatment',
              shownWhenValues: ['Other'],
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
              note: 'Stock is only deducted when the visit is completed.',
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
                  'Name and dose. To take this off the shelf, open Medication '
                  'Service — this box records what was given, it does not '
                  'prescribe it.',
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
              key: 'follow_up_date',
              label: 'Follow-up Date',
              kind: ServiceFieldKind.date,
              width: FieldWidth.half,
              shownWhenKey: 'disposition',
              shownWhenValues: ['Follow-up'],
              // The stem, not the whole option: a date is needed by anything that
              // is a follow-up, and the disposition is free to grow more of them.
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
        ServiceSlide(
          title: 'Additional Service',
          fields: [
            ServiceField(
              key: 'additional_service_needed',
              label: 'Additional Service Needed?',
              kind: ServiceFieldKind.chips,
              options: kYesNo,
              required: true,
              width: FieldWidth.half,
              note: 'Records it. It does not open that service.',
            ),
            ServiceField(
              key: 'referral_service',
              label: 'Recommended / Related Service',
              kind: ServiceFieldKind.dropdown,
              options: kReferralServices,
              required: true,
              width: FieldWidth.half,
              shownWhenKey: 'additional_service_needed',
              shownWhenValues: ['Yes'],
            ),
            ServiceField(
              key: 'referral_reason_additional',
              label: 'Reason for Additional Service',
              kind: ServiceFieldKind.text,
              shownWhenKey: 'additional_service_needed',
              shownWhenValues: ['Yes'],
            ),
          ],
        ),
        VisitServiceForms.reviewSlide,
      ],
    ),

    // ── 8. WOUND DRESSING ─────────────────────────────────────────────────
    // What was done to the wound and what was put on it are both required, as
    // tick boxes rather than a free-text list: "the wound was cleaned and
    // dressed" is the minimum a dressing visit can record, and a record that can
    // say only "dressed" cannot be audited.
    //
    // Two slides and a summary, rather than three slides and a summary.
    //
    // The second one is laid out in rows on purpose. Dressing a wound is done in
    // an order — clean it, put something on it, look at it, book the next visit —
    // and the old split put what went on the wound on one slide and what was
    // found on another, so the nurse read the work and the observations as two
    // records of two different visits. Two cards and a note underneath hold the
    // whole of it on one screen of the clinic's laptop, and the slide after it
    // reads all of it back.
    'wound_dressing': ServiceFormSpec(
      serviceId: 'wound_dressing',
      slides: [
        ServiceSlide(
          title: 'The Wound',
          fields: [
            ServiceField(
              key: 'wound_location',
              label: 'Location of the Wound',
              kind: ServiceFieldKind.dropdown,
              options: ClinicPurposes.bodySites,
              required: true,
              width: FieldWidth.half,
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
              key: 'wound_condition',
              label: 'Wound Condition',
              kind: ServiceFieldKind.chips,
              options: kWoundConditions,
              required: true,
              width: FieldWidth.half,
            ),
            // Two boxes, not one. "3 x 1.5" in a text box is a string nobody can
            // sort or compare: the question a dressing visit is asked on the next
            // day is whether the wound is bigger, and that is arithmetic on two
            // numbers rather than a reading of a sentence.
            ServiceField(
              key: 'wound_length_cm',
              label: 'Length (cm)',
              kind: ServiceFieldKind.number,
              unit: 'cm',
              width: FieldWidth.half,
              hint: 'e.g. 3',
            ),
            ServiceField(
              key: 'wound_width_cm',
              label: 'Width (cm)',
              kind: ServiceFieldKind.number,
              unit: 'cm',
              width: FieldWidth.half,
              hint: 'e.g. 1.5',
            ),
          ],
        ),
        ServiceSlide(
          title: 'Cleaning & Dressing',
          groups: [
            // Row one: what it was cleaned with, and what went on. Beside each
            // other because the second choice means nothing without knowing the
            // first, and because a nurse who has cleaned with saline and reached
            // for the antiseptic should see both in one look.
            FieldGroup(['cleaning_performed', 'medication_applied']),
            // Row two: what it looks like now, and when it is seen again.
            FieldGroup(['assessment', 'next_dressing_date']),
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
              key: 'cleaning_other',
              label: 'Other Cleaning Used',
              kind: ServiceFieldKind.text,
              width: FieldWidth.half,
              shownWhenKey: 'cleaning_performed',
              shownWhenValues: ['Other'],
              note: 'The clinic\'s own prep, by name.',
            ),
            // Reads the inventory rather than being typed. An antiseptic written
            // into a free-text box can be spelled four ways and match nothing on
            // the shelf; one picked off the shelf is the bottle that was actually
            // in the clinic. Nothing is spent here - see
            // [ServiceFieldKind.inventoryPick].
            ServiceField(
              key: 'medication_applied',
              label: 'Medication / Antiseptic Used',
              kind: ServiceFieldKind.inventoryPick,
              required: true,
              note: 'Picked from the shelf. This form does not spend stock - a '
                  'prescription is the Medication service.',
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
              key: 'dressing_other',
              label: 'Other Dressing Used',
              kind: ServiceFieldKind.text,
              width: FieldWidth.half,
              shownWhenKey: 'dressing_applied',
              shownWhenValues: ['Other'],
              note: 'The clinic\'s own material, by name.',
            ),
            // Deliberately observations and outcomes, not a diagnosis - the same
            // line the whole step 3 holds: it records what was found, and a
            // diagnosis is a separate service with a clinician\'s name on it.
            ServiceField(
              key: 'assessment',
              label: 'Assessment / Findings',
              kind: ServiceFieldKind.checkboxes,
              options: kWoundFindings,
              note: 'Optional. Observations only - a diagnosis is a separate '
                  'service.',
            ),
            ServiceField(
              key: 'next_dressing_date',
              label: 'Next Dressing Date',
              kind: ServiceFieldKind.date,
              width: FieldWidth.half,
              note: 'Optional.',
            ),
            notes(),
          ],
        ),
        VisitServiceForms.reviewSlide,
      ],
    ),

    // ── 9. MEDICAL CONSULTATION ───────────────────────────────────────────
    // Six slides, because this is the one form here that is genuinely a clinical
    // document rather than a set of observations.
    //
    // The vitals are the READ-ONLY strip and stay that way. A consultation does
    // get a blood pressure, but it does not own the number: BP Taking owns it,
    // Temperature Checking owns the temperature, and a second box for either here
    // would be a second reading of the same visit that can disagree with the
    // first — and, worse, would leave the owning service's own required box
    // unfillable, because two services cannot both be the one that recorded it.
    // Whoever wants the vitals taken adds that service on step 2; the strip then
    // shows them here, read-only, with a link back.
    //
    // The clinical impression is REQUIRED and it is typed by a person. Nothing on
    // this form is allowed to work it out: a BP verdict is a screening aid and
    // belongs to the reading, and a diagnosis written by the same rules that
    // colour a pill orange is not a diagnosis.
    //
    // Naming a drug in "Medication" does not prescribe it. The one box that
    // appears after it asks whether a Medication Service record is wanted, and
    // the prescription itself — dose, quantity, route, stock — is made there,
    // because that is the form that can deduct from the shelf.
    'medicine_consultation': ServiceFormSpec(
      serviceId: 'medicine_consultation',
      slides: [
        ServiceSlide(
          title: 'Complaint',
          fields: [
            ServiceField(
              key: 'chief_complaint',
              label: 'Chief Complaint',
              kind: ServiceFieldKind.text,
              required: true,
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
              label: 'Other Complaint',
              kind: ServiceFieldKind.text,
              required: true,
              width: FieldWidth.half,
              shownWhenKey: 'symptoms',
              shownWhenValues: ['Other'],
            ),
            ServiceField(
              key: 'duration_onset',
              label: 'Duration / Onset',
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
              key: 'shared_vitals',
              label: 'Visit Vitals',
              kind: ServiceFieldKind.sharedVitals,
              note: 'Taken by the service that owns them, shown here '
                  'read-only.',
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
              label: 'Other History',
              kind: ServiceFieldKind.text,
              shownWhenKey: 'history',
              shownWhenValues: ['Other'],
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
              label: 'Other Treatment',
              kind: ServiceFieldKind.text,
              required: true,
              width: FieldWidth.half,
              shownWhenKey: 'treatment',
              shownWhenValues: ['Other'],
            ),
            ServiceField(
              key: 'management_details',
              label: 'Treatment Details',
              kind: ServiceFieldKind.multiline,
              note: 'What was actually done, in the patient\'s own words for '
                  'them to take away.',
            ),
            ServiceField(
              key: 'medication_service_needed',
              label: 'Medication Service Required?',
              kind: ServiceFieldKind.chips,
              options: kYesNo,
              required: true,
              width: FieldWidth.half,
              shownWhenKey: 'treatment',
              shownWhenValues: ['Medication'],
            ),
            ServiceField(
              key: 'medication_summary',
              label: 'Medication Intended',
              kind: ServiceFieldKind.text,
              required: true,
              width: FieldWidth.half,
              shownWhenKey: 'medication_service_needed',
              shownWhenValues: ['Yes'],
              note: 'Name and dose. Open Medication Service to prescribe it — '
                  'that is the form that takes it off the shelf.',
            ),
          ],
        ),
        ServiceSlide(
          title: 'Plan',
          fields: [
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
              key: 'attending',
              label: 'Attending',
              kind: ServiceFieldKind.dropdown,
              options: kAttendingStaff,
              width: FieldWidth.half,
              note: 'Who examined them. The strip above already says who is '
                  'signed in.',
            ),
            notes(),
          ],
        ),
        ServiceSlide(
          title: 'Referral',
          fields: [
            ServiceField(
              key: 'referral_needed',
              label: 'Referral / Additional Service Needed?',
              kind: ServiceFieldKind.chips,
              options: kYesNo,
              required: true,
              width: FieldWidth.half,
              note: 'Records it. It does not open that service and does not '
                  'send anyone anywhere.',
            ),
            ServiceField(
              key: 'referral_service',
              label: 'Service / Referral',
              kind: ServiceFieldKind.dropdown,
              options: kReferralServices,
              required: true,
              width: FieldWidth.half,
              shownWhenKey: 'referral_needed',
              shownWhenValues: ['Yes'],
            ),
            ServiceField(
              key: 'referral_reason',
              label: 'Reason',
              kind: ServiceFieldKind.text,
              required: true,
              shownWhenKey: 'referral_needed',
              shownWhenValues: ['Yes'],
            ),
          ],
        ),
        VisitServiceForms.reviewSlide,
      ],
    ),

    // ── 10. MEDICAL CLEARANCE ─────────────────────────────────────────────
    'medical_clearance': ServiceFormSpec(
      serviceId: 'medical_clearance',
      slides: [
        ServiceSlide(
          title: 'Request',
          fields: [
            ServiceField(
              key: 'purpose',
              label: 'Purpose',
              kind: ServiceFieldKind.dropdown,
              options: kClearancePurposes,
              required: true,
              width: FieldWidth.half,
            ),
            ServiceField(
              key: 'status',
              label: 'Status',
              kind: ServiceFieldKind.dropdown,
              options: ['Cleared', 'Not cleared'],
              required: true,
              width: FieldWidth.half,
            ),
            ServiceField(
              key: 'not_cleared_for',
              label: 'Not Cleared For',
              kind: ServiceFieldKind.text,
              width: FieldWidth.full,
              note: 'Fill in only when the status is "Not cleared".',
            ),
          ],
        ),
        ServiceSlide(
          title: 'Recommendations',
          fields: [
            ServiceField(
              key: 'recommendations',
              label: 'Recommendations',
              kind: ServiceFieldKind.multiline,
              required: true,
              note: 'Printed on the clearance document.',
            ),
            ServiceField(
              key: 'validity_date',
              label: 'Validity Date',
              kind: ServiceFieldKind.date,
              width: FieldWidth.half,
              note: 'Optional.',
            ),
            notes(),
          ],
        ),
      ],
    ),

    // ── 11. MEDICAL CERTIFICATE ───────────────────────────────────────────
    // Four slides for a Medical Certificate, three for a Certification — the
    // renderer drops the physical-examination slide for the excuse letter. The
    // document itself is produced by the certificate engine.
    'medicine_certificate': ServiceFormSpec(
      serviceId: 'medicine_certificate',
      kind: ServiceFormKind.custom,
      slides: [
        ServiceSlide(
          title: 'Document',
          custom: ServiceCustomSlide('certificate_type',
              requiredKeys: ['doc_type']),
        ),
        ServiceSlide(
          title: 'Visitor Details',
          // The three boxes the certificate is actually built around live on this
          // slide, so this is where they are required. Asking for them on the
          // first slide would refuse to advance past boxes the nurse cannot yet
          // see.
          custom: ServiceCustomSlide('certificate_details', requiredKeys: [
            'clearance_status',
            'purpose',
            'reason',
            'issue_date',
          ]),
        ),
        ServiceSlide(
          title: 'Examination',
          custom: ServiceCustomSlide('certificate_exam'),
        ),
        ServiceSlide(
          title: 'Preview',
          custom: ServiceCustomSlide('certificate_preview'),
        ),
      ],
    ),

    // ── 12. VITAL SIGNS ────────────────────────────────────────────────────
    // The whole set on one form. As with every other service the readings are
    // the VISIT's, not this form's: whichever earlier service declared a vital
    // owns the box, this form reads the same number back, and the two boxes
    // never disagree. The respiratory rate and oxygen saturation have no other
    // home on the visit, so this form is where they live — both optional, so a
    // clinic that does not take them is not blocked from finishing the check.
    'vital_signs': ServiceFormSpec(
      serviceId: 'vital_signs',
      slides: [
        ServiceSlide(
          title: 'Readings',
          groups: [
            // Row one: the blood pressure as a pair. Row two: the temperature
            // and how it was taken, beside each other because a number without
            // a method is a reading from an unknown instrument.
            FieldGroup(['systolic', 'diastolic']),
            FieldGroup(['temp_c', 'method']),
          ],
          fields: [
            ServiceField(
              key: 'systolic',
              label: 'Blood Pressure (mmHg)',
              kind: ServiceFieldKind.number,
              unit: 'mmHg',
              vital: VitalField.systolic,
              required: true,
              width: FieldWidth.half,
              validate: _bpNumber(BpLimits.systolic),
            ),
            ServiceField(
              key: 'diastolic',
              label: 'Blood Pressure (mmHg)',
              kind: ServiceFieldKind.number,
              unit: 'mmHg',
              vital: VitalField.diastolic,
              required: true,
              width: FieldWidth.half,
              validate: _bpNumber(BpLimits.diastolic),
            ),
            ServiceField(
              key: 'pulse_bpm',
              label: 'Pulse Rate (beats per minute)',
              kind: ServiceFieldKind.number,
              unit: 'bpm',
              vital: VitalField.heartRate,
              required: true,
              width: FieldWidth.half,
              validate: _bpNumber(BpLimits.pulse),
            ),
            ServiceField(
              key: 'temp_c',
              label: 'Temperature',
              kind: ServiceFieldKind.number,
              unit: '°C',
              vital: VitalField.temperature,
              required: true,
              width: FieldWidth.half,
              hint: '36.8',
            ),
            ServiceField(
              key: 'method',
              label: 'Method / Site',
              kind: ServiceFieldKind.dropdown,
              options: kTemperatureMethods,
              required: true,
              width: FieldWidth.half,
            ),
            ServiceField(
              key: 'resp_rate',
              label: 'Respiratory Rate',
              kind: ServiceFieldKind.number,
              unit: '/min',
              vital: VitalField.respRate,
              width: FieldWidth.half,
              hint: 'Optional',
              validate: _bpNumber(BpLimits.respRate),
            ),
            ServiceField(
              key: 'o2_sat',
              label: 'Oxygen Saturation (SpO2)',
              kind: ServiceFieldKind.number,
              unit: '%',
              vital: VitalField.o2Sat,
              width: FieldWidth.half,
              hint: 'Optional',
              validate: _bpNumber(BpLimits.spo2),
            ),
            ServiceField(
              key: 'bp_assessment',
              label: 'Blood Pressure Classification',
              kind: ServiceFieldKind.readOnly,
              width: FieldWidth.half,
              note: 'Worked out from the blood pressure entered on this form.',
            ),
          ],
        ),
        ServiceSlide(
          title: 'Symptoms & Remarks',
          fields: [
            ServiceField(
              key: 'symptoms',
              label: 'Symptoms / Complaints',
              kind: ServiceFieldKind.multiline,
              note: 'What the person reports alongside the readings.',
            ),
            ServiceField(
              key: 'assessment',
              label: 'Assessment / Observations',
              kind: ServiceFieldKind.multiline,
              note:
                  'Notes against the readings — what stands out on this check.',
            ),
            ServiceField(
              key: 'follow_up',
              label: 'Follow-up / Recommendation',
              kind: ServiceFieldKind.multiline,
              note: 'What happens next, if anything.',
            ),
            notes(),
          ],
        ),
        VisitServiceForms.reviewSlide,
      ],
    ),

    // ── 12. OTHER ─────────────────────────────────────────────────────────
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

  /// The description for [serviceId]. A service added to the catalog without a
  /// form here gets a single-slide fallback rather than a crash, so the
  /// checklist and the details step cannot disagree by accident.
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

  /// The ids this file describes. `test/visit_service_forms_test.dart` walks
  /// `ClinicPurposes.all` and fails if one is missing — the same seam that keeps
  /// the step-2 checklist columns honest.
  static Iterable<String> get describedIds => _specs.keys;

  /// How many days a pregnancy is measured in. 280 days = 40 weeks, and the
  /// expected due date is the LMP plus this.
  static const int pregnancyDays = 280;
}
