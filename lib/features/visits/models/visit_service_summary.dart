import 'package:clinicmanagementsystem/features/visits/models/visit_details.dart';
import 'package:clinicmanagementsystem/features/visits/models/visit_service_forms.dart';
import 'package:clinicmanagementsystem/features/vitals/models/vitals.dart';

class SummaryRow {
  const SummaryRow(this.label, this.value);

  final String label;
  final String value;
}

class SummarySection {
  const SummarySection(this.title, this.rows);

  final String title;
  final List<SummaryRow> rows;
}

List<SummarySection> serviceSummary(ServiceDraft draft, VisitVitals vitals,
    {bool canSeeRestricted = true}) {
  final sections = <SummarySection>[];

  final hideRestricted = !canSeeRestricted &&
      draft.serviceId == 'health_counselling' &&
      counsellingPrivacyLevel(draft.data) == 'Restricted';
  const restrictedKeys = {
    'reason',
    'student_response',
    'action_plan',
    'concern_signs',
    'notes',
  };

  for (final slide in draft.spec.slides) {
    if (slide.custom?.id == 'form_review') continue;
    final rows = <SummaryRow>[];
    for (final f in slide.fields) {
      if (f.key == kVitalsSelectedKey) continue;
      if (f.kind == ServiceFieldKind.sharedVitals ||
          f.kind == ServiceFieldKind.vitalsCard ||
          f.kind == ServiceFieldKind.linkServiceCard ||
          f.kind == ServiceFieldKind.notice) {
        continue;
      }
      // A box that is not shown for this case must not appear in the review.
      if (!f.isShownIn(draft.data)) continue;

      if (_foldedOtherKeys(draft).contains(f.key)) continue;
      if (hideRestricted && restrictedKeys.contains(f.key)) continue;
      var value = summaryValue(draft, f);
      if (f.kind == ServiceFieldKind.readOnly) {
        value = _autoSummary(f.key, vitals) ?? value;
      }
      if (value.trim().isEmpty) continue;
      rows.add(SummaryRow(f.label, value));
    }
    if (rows.isNotEmpty) sections.add(SummarySection(slide.title, rows));
  }

  if (draft.serviceId == 'health_counselling') {
    final reasons = counsellingReferralReasons(draft.data);
    if (reasons.isNotEmpty) {
      sections.add(SummarySection('Referral', [
        SummaryRow(
          'Referral advised',
          draft.spec.referralTitle ?? 'Refer to doctor / hospital.',
        ),
        SummaryRow('Reason', reasons.join(' · ')),
      ]));
    }
  }

  if (draft.serviceId == 'wound_dressing') {
    final reasons = woundReferralReasons(draft.data, temperature: vitals.tempC);
    if (reasons.isNotEmpty) {
      sections.add(SummarySection('Referral', [
        const SummaryRow(
          'Referral advised',
          'Refer to doctor / RHU / hospital. May need suturing, tetanus or '
              'further treatment.',
        ),
        SummaryRow('Reason', reasons.join(' · ')),
      ]));
    }
  }

  if (draft.serviceId == 'medicine_consultation') {
    final reasons = consultationReferralReasons(draft.data, vitals);
    if (reasons.isNotEmpty) {
      sections.add(SummarySection('Referral', [
        const SummaryRow(
          'Referral advised',
          'Referral / additional service needed. Check disposition, guardian, '
              'and referral service.',
        ),
        SummaryRow('Reason', reasons.join(' · ')),
      ]));
    }
  }

  if (draft.medicines.isNotEmpty) {
    sections.add(SummarySection('Medicines', [
      for (final m in draft.medicines)
        SummaryRow(m.name, m.detail.isEmpty ? '—' : m.detail),
    ]));
  }

  final wantsVitals = draft.serviceId != 'bpi' &&
      draft.spec.slides.any((s) => s.fields.any((f) =>
          f.kind == ServiceFieldKind.sharedVitals ||
          f.kind == ServiceFieldKind.vitalsCard ||
          f.vital != null));
  if (wantsVitals) {
    final readings = <SummaryRow>[
      for (final r in [
        vitals.bloodPressure,
        vitals.heartRateReading,
        vitals.respRateReading,
        vitals.tempReading,
        vitals.o2Reading,
        if (draft.serviceId != 'vital_signs') vitals.bmiReading,
      ])
        if (r != null) SummaryRow(r.label, r.display),
    ];
    if (readings.isNotEmpty) {
      sections.add(SummarySection('Visit Vitals', readings));
    }
  }

  return sections;
}

String summaryValue(ServiceDraft draft, ServiceField field) {
  switch (field.kind) {
    case ServiceFieldKind.checkboxes:
    case ServiceFieldKind.chips:
    case ServiceFieldKind.multiselect:
    case ServiceFieldKind.inventoryPick:
      return _joinedChoices(draft, field);
    case ServiceFieldKind.number:
      final v = draft.text(field.key).trim();
      if (v.isEmpty) return '';
      final unit = field.unit?.trim() ?? '';
      return unit.isEmpty ? v : '$v $unit';
    default:
      final raw = draft.text(field.key).trim();

      if (raw == kOtherLabel && _foldsOther(draft, field)) {
        final other = draft.text(field.otherFieldKey).trim();
        if (other.isNotEmpty) return other;
      }
      return field.kind == ServiceFieldKind.dropdown ? optionLabel(raw) : raw;
  }
}

bool _foldsOther(ServiceDraft draft, ServiceField field) =>
    draft.spec.offersOther(field) ||
    _foldedOtherKeys(draft).contains(field.otherFieldKey);

String _joinedChoices(ServiceDraft draft, ServiceField field) {
  final chosen = draft.chosen(field.key);
  final other = _foldsOther(draft, field)
      ? draft.text(field.otherFieldKey).trim()
      : '';
  return [
    for (final c in chosen)
      if (c == kOtherLabel && other.isNotEmpty) other else optionLabel(c),
  ].join(' · ');
}

Set<String> _foldedOtherKeys(ServiceDraft draft) {
  const folded = <String, List<String>>{
    'vital_signs': ['action_taken'],
    'prenatal': ['danger_signs', 'action_taken', 'given_this_visit'],
    'wound_dressing': [
      'cleaning_performed',
      'dressing_applied',
      'wound_condition',
      'assessment',
      'action_taken',
      'injury_timing',
      'wound_location',
      'wound_type',
      'burn_degree',
      'bleeding',
    ],
    'first_aid_treatment': [
      'incident',
      'incident_place',
      'body_part',
      'dressing_material',
      'recommended_service',
    ],
    'health_counselling': ['referral_service'],
  };
  final lists = folded[draft.serviceId] ?? const <String>[];
  return {for (final k in lists) '${k}_other'};
}

String? _autoSummary(String key, VisitVitals v) => switch (key) {
      'bmi' => v.bmi?.toStringAsFixed(1),
      'bmi_class' => v.bmiReading?.category,
      'bp_assessment' => v.bloodPressure?.category,
      'temp_assessment' => v.tempReading?.category,
      'pulse_assessment' => v.heartRateReading?.category,
      'resp_assessment' => v.respRateReading?.category,
      'spo2_assessment' => v.o2Reading?.category,
      _ => null,
    };