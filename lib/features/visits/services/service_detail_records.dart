import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'package:clinicmanagementsystem/features/visits/models/clinic_purposes.dart';
import 'package:clinicmanagementsystem/features/vitals/models/vital_classifier.dart';
import 'package:clinicmanagementsystem/features/visits/models/visit_details.dart';
import 'package:clinicmanagementsystem/features/visits/models/visit_service_forms.dart';
import 'package:clinicmanagementsystem/features/vitals/models/vitals.dart';
import 'package:clinicmanagementsystem/core/config/supabase_config.dart';

String _tableFor(String dartServiceId) => switch (dartServiceId) {
      'bpi' => 'bmi_records',
      'wound_dressing' => 'wound_dressing_records',
      'first_aid_treatment' => 'first_aid_records',
      'health_counselling' => 'counselling_records',
      'prenatal' => 'prenatal_records',
      'medication' => 'medication_services',
      'medicine_consultation' => 'medical_consultations',
      'vital_signs' => 'vital_signs',
      _ => '',
    };

Future<void> saveServiceRecord({
  required String visitServiceId,
  required String visitId,
  required String dartServiceId,
  required ServiceDraft d,
  required VisitVitals vitals,
  String? recordedBy,
}) async {
  final table = _tableFor(dartServiceId);
  if (table.isEmpty) return;

  final row = buildServiceRecord(
    dartServiceId: dartServiceId,
    d: d,
    vitals: vitals,
    recordedBy: recordedBy,
  );
  if (row == null) return;

  if (table == 'medication_services') {
    try {
      final existing = await supabaseClient
          .from('medication_services')
          .select('medication_service_id')
          .eq('visit_service_id', visitServiceId)
          .maybeSingle();
      if (existing != null) {
        await supabaseClient.from('medication_services').update(row).eq(
            'medication_service_id', '${existing['medication_service_id']}');
      } else {
        await supabaseClient.from('medication_services').insert({
          'visit_service_id': visitServiceId,
          'visit_id': visitId,
          ...row,
        });
      }
    } catch (_) {}
    return;
  }

  String? oldParentId;
  if (dartServiceId == 'first_aid_treatment') {
    try {
      final old = await supabaseClient
          .from(table)
          .select('first_aid_id')
          .eq('visit_service_id', visitServiceId)
          .maybeSingle();
      oldParentId = '${old?['first_aid_id'] ?? ''}';
    } catch (_) {}
    if (oldParentId != null && oldParentId.isNotEmpty) {
      try {
        await supabaseClient
            .from('first_aid_conditions')
            .delete()
            .eq('first_aid_id', oldParentId);
      } catch (_) {}
      try {
        await supabaseClient
            .from('first_aid_treatments')
            .delete()
            .eq('first_aid_id', oldParentId);
      } catch (_) {}
    }
  }

  try {
    await supabaseClient
        .from(table)
        .delete()
        .eq('visit_service_id', visitServiceId);
  } catch (e) {
    debugPrint('service detail: $table clear failed: $e');
    return;
  }

  try {
    final inserted = await supabaseClient
        .from(table)
        .insert({'visit_service_id': visitServiceId, ...row})
        .select()
        .single();

    if (dartServiceId == 'first_aid_treatment') {
      final parentId = '${inserted['first_aid_id'] ?? ''}';
      if (parentId.isNotEmpty) {
        await _insertFirstAidChildren(parentId, d);
      }
    }
  } catch (e) {
    debugPrint('service detail: $table write failed: $e');
  }
}

Future<void> _insertFirstAidChildren(
  String firstAidId,
  ServiceDraft d,
) async {
  final conditions = _jsonList(d, 'findings');
  final treatments = _jsonList(d, 'treatment');
  if (conditions.isEmpty && treatments.isEmpty) return;

  try {
    if (conditions.isNotEmpty) {
      await supabaseClient.from('first_aid_conditions').insert([
        for (final c in conditions)
          {'first_aid_id': firstAidId, 'condition': c},
      ]);
    }
    if (treatments.isNotEmpty) {
      await supabaseClient.from('first_aid_treatments').insert([
        for (final t in treatments)
          {'first_aid_id': firstAidId, 'treatment_type': t},
      ]);
    }
  } catch (_) {}
}

Future<void> deleteServiceRecord({
  required String visitServiceId,
  required String dartServiceId,
}) async {
  final table = _tableFor(dartServiceId);
  if (table.isEmpty) return;

  if (dartServiceId == 'first_aid_treatment') {
    String parentId = '';
    try {
      final old = await supabaseClient
          .from(table)
          .select('first_aid_id')
          .eq('visit_service_id', visitServiceId)
          .maybeSingle();
      parentId = '${old?['first_aid_id'] ?? ''}';
    } catch (_) {}
    if (parentId.isNotEmpty) {
      try {
        await supabaseClient
            .from('first_aid_conditions')
            .delete()
            .eq('first_aid_id', parentId);
      } catch (_) {}
      try {
        await supabaseClient
            .from('first_aid_treatments')
            .delete()
            .eq('first_aid_id', parentId);
      } catch (_) {}
    }
  }

  if (table == 'medication_services') {
    String? headerId;
    try {
      final header = await supabaseClient
          .from('medication_services')
          .select('medication_service_id')
          .eq('visit_service_id', visitServiceId)
          .maybeSingle();
      if (header != null) headerId = '${header['medication_service_id']}';
    } catch (_) {}
    if (headerId != null) {
      try {
        await supabaseClient
            .from('medication_service_items')
            .delete()
            .eq('medication_service_id', headerId);
      } catch (_) {}
      try {
        await supabaseClient
            .from('medication_services')
            .delete()
            .eq('medication_service_id', headerId);
      } catch (_) {}
    }
    return;
  }

  try {
    await supabaseClient
        .from(table)
        .delete()
        .eq('visit_service_id', visitServiceId);
  } catch (e) {
    debugPrint('service detail: $table delete failed: $e');
  }
}

Map<String, dynamic>? buildServiceRecord({
  required String dartServiceId,
  required ServiceDraft d,
  required VisitVitals vitals,
  String? recordedBy,
}) {
  switch (dartServiceId) {
    case 'bpi':
      final bmiClass = _choice(d, 'bmi_class');
      return {
        'height_cm': _vitalNum(vitals.heightCm),
        'weight_kg': _vitalNum(vitals.weightKg),
        'bmi': _choice(d, 'bmi') ??
            vitals.bmiReading?.display ??
            _vitalNum(vitals.bmi),
        'classification': bmiClass ?? vitals.bmiReading?.category,
        'notes': _textOrNull(d, 'notes'),
      };
    case 'wound_dressing':
      final woundMeds = _medicinesOrNull(d);
      return {
        'injury_timing':
            _choiceWithOtherOrNull(d, 'injury_timing', kWoundInjuryTiming),
        'injury_cause': _textOrNull(d, 'injury_cause'),
        'wound_location': _choiceWithOtherOrNull(
            d, 'wound_location', ClinicPurposes.bodySites),
        'other_location_specify': _otherTextOrNull(d, 'wound_location'),
        'wound_type': _choiceWithOtherOrNull(d, 'wound_type', kWoundTypes),
        'other_type_specify': _otherTextOrNull(d, 'wound_type'),
        'burn_degree': _choiceWithOtherOrNull(d, 'burn_degree', kBurnDegrees),
        'wound_condition': _listWithOtherOrNull(d, 'wound_condition'),
        'bleeding': _choiceWithOtherOrNull(d, 'bleeding', kBleedingStatus),
        'tetanus_status': _choice(d, 'tetanus_status'),
        'wound_length_cm': _numOrNull(d, 'wound_length_cm'),
        'wound_width_cm': _numOrNull(d, 'wound_width_cm'),
        'temperature': _vitalNum(vitals.tempC),
        'systolic': _vitalNum(vitals.systolic),
        'diastolic': _vitalNum(vitals.diastolic),
        'cleaning_performed': _listWithOtherOrNull(d, 'cleaning_performed'),
        if (woundMeds != null) 'medications_used': woundMeds,
        'other_medication': _textOrNull(d, 'other_medication'),
        'dressing_material': _listWithOtherOrNull(d, 'dressing_applied'),
        'assessment_findings': _listWithOtherOrNull(d, 'assessment'),
        'action_taken': _listWithOtherOrNull(d, 'action_taken'),
        'referred_to': _textOrNull(d, 'referred_to'),
        'needs_referral':
            woundNeedsReferral(d.data, temperature: vitals.tempC) ? true : null,
        'no_further_dressing':
            _hasChosen(d, 'no_further_dressing', kWoundNoFurtherDressing)
                ? true
                : null,
        'next_dressing_date': _dateOrNull(d, 'next_dressing_date'),
        'notes': _textOrNull(d, 'notes'),
      };
    case 'first_aid_treatment':
      final disposition = _choice(d, 'disposition') ?? '';
      final referred = isReferralDisposition(disposition);
      final referredToWhere = _textOrNull(d, 'referred_to_where');
      final referralReason = _textOrNull(d, 'referral_reason');
      final observation = _numOrNull(d, 'observation_minutes');
      return {
        'incident_type':
            _choiceWithOtherOrNull(d, 'incident', kFirstAidIncidents),
        'incident_other': _otherTextOrNull(d, 'incident'),
        'incident_timing':
            _choiceWithOtherOrNull(d, 'incident_timing', kFirstAidTimings),
        'incident_place':
            _choiceWithOtherOrNull(d, 'incident_place', kFirstAidPlaces),
        'incident_cause': _textOrNull(d, 'incident_cause'),
        'known_allergies': _textOrNull(d, 'known_allergies'),
        'body_location':
            _choiceWithOtherOrNull(d, 'body_part', ClinicPurposes.bodySites),
        'pain_level': _textOrNull(d, 'pain_level'),
        'head_injury_signs': _listOrNull(d, 'head_injury_signs'),
        'consciousness': _choice(d, 'consciousness'),
        'dressing_material': _choiceWithOtherOrNull(
            d, 'dressing_material', kDressingMaterialsUsed),
        'dressing_other': _otherTextOrNull(d, 'dressing_material'),
        'medication_given': _textOrNull(d, 'medication_given'),
        'observation_minutes': observation?.round(),
        'condition_after_treatment': _textOrNull(d, 'condition_after'),
        'disposition': _choice(d, 'disposition'),
        'guardian_informed': _choice(d, 'guardian_informed'),
        'sent_to': referredToWhere ?? _textOrNull(d, 'sent_to'),
        'follow_up_date': _dateOrNull(d, 'follow_up_date'),
        'referral_reason': referralReason,
        'needs_referral': referred,
        'referral_reasons': referred
            ? jsonEncode([
                if (referralReason != null) referralReason,
                if (referredToWhere != null) referredToWhere,
              ])
            : null,
        'notes': _textOrNull(d, 'notes'),
      };
    case 'health_counselling':
      final counsellingReasons = counsellingReferralReasons(d.data);
      final referredTo = _textOrNull(d, 'referred_to');
      final serviceReason = _textOrNull(d, 'referral_reason');
      return {
        'topic': _listOrNull(d, 'topic'),
        'other_topic': _textOrNull(d, 'topic_other'),
        'reason_or_concern': _textOrNull(d, 'reason'),
        'counselling_provided': _listOrNull(d, 'provided'),
        'other_provided': _textOrNull(d, 'provided_other'),
        'counsellor_name': _textOrNull(d, 'counsellor'),
        'referral_source': _choice(d, 'referral_source'),
        'session_type': _choice(d, 'session_type'),
        'session_date': d.text('session_date').trim().isEmpty
            ? null
            : d.text('session_date').trim(),
        'duration_minutes': _numOrNull(d, 'duration_minutes')?.round(),
        'understanding': _choice(d, 'understanding'),
        'student_response': _textOrNull(d, 'student_response'),
        'concern_signs': _listOrNull(d, 'concern_signs'),
        'guardian_informed': _choice(d, 'guardian_informed'),
        'privacy_level': counsellingPrivacyLevel(d.data),
        'needs_referral': counsellingReasons.isNotEmpty,
        'referral_reasons':
            counsellingReasons.isEmpty ? null : jsonEncode(counsellingReasons),
        'follow_up_needed': _choice(d, 'follow_up_needed'),
        'follow_up_date': _dateOrNull(d, 'follow_up_date'),
        'follow_up_reason': _textOrNull(d, 'follow_up_reason'),
        'additional_service_needed': _choice(d, 'additional_service_needed'),
        'additional_service_name': _choiceWithOtherOrNull(
            d, 'referral_service', kCounsellingRecommendedServices),
        'additional_service_reason':
            _foldReferralPlace(serviceReason, referredTo),
        'notes': _textOrNull(d, 'notes'),
      };
    case 'prenatal':
      return {
        'gravida': _textOrNull(d, 'gravida'),
        'para': _textOrNull(d, 'para'),
        'lmp': _dateOrNull(d, 'lmp'),
        'lmp_unknown': _hasChosen(d, 'lmp_unknown', 'Unknown') ? true : null,
        'edd': _textOrNull(d, 'edd'),
        'gestational_age': _textOrNull(d, 'aog'),
        'fundal_height_cm': _numOrNull(d, 'fundal_height'),
        'fetal_heart_rate': _numOrNull(d, 'fetal_heart_tone'),
        'fetal_heart_not_done':
            _hasChosen(d, 'fetal_heart_not_done', 'Not done / no equipment')
                ? true
                : null,
        'fetal_movement': _textOrNull(d, 'fetal_movement'),
        'edema': _choice(d, 'edema'),
        'urine_protein': _choice(d, 'urine_protein'),
        'danger_signs': _listWithOtherOrNull(d, 'danger_signs'),
        'care_elsewhere': _textOrNull(d, 'care_elsewhere'),
        'care_elsewhere_place': _textOrNull(d, 'care_elsewhere_place'),
        'service_provided': _listOrNull(d, 'service_provided'),
        'other_service_specify': _textOrNull(d, 'other_service_specify'),
        'given_this_visit': _listWithOtherOrNull(d, 'given_this_visit'),
        'assessment': vitals.bloodPressure?.category,
        'action_taken': _listWithOtherOrNull(d, 'action_taken'),
        'referred_to': _textOrNull(d, 'referred_to'),
        'follow_up_date': _dateOrNull(d, 'follow_up_date'),
        'needs_referral': prenatalNeedsReferral(vitals) ? true : null,
        'notes': _textOrNull(d, 'notes'),
      };
    case 'medication':
      return {
        'reason': _listOrNull(d, 'reason_common'),
        'notes': _textOrNull(d, 'reason_other'),
      };
    case 'medicine_consultation':
      final reasons = consultationReferralReasons(d.data, vitals);
      final needsReferral = reasons.isNotEmpty;

      final durationParts = <String>[
        ...d.chosen('duration_onset_choice'),
        d.text('duration_onset').trim(),
      ].where((e) => e.isNotEmpty).toList();
      return {
        'chief_complaint': _textOrNull(d, 'chief_complaint'),
        'history_of_present_illness': _textOrNull(d, 'history_details'),
        'physical_examination': _textOrNull(d, 'physical_exam'),
        'assessment': _textOrNull(d, 'clinical_impression'),
        'treatment_management': _listOrNull(d, 'treatment'),
        'follow_up_needed': _choice(d, 'follow_up_needed'),
        'follow_up_date': _dateOrNull(d, 'follow_up_date'),
        'referral_needed': _choice(d, 'referral_needed'),
        'referral_reason': _textOrNull(d, 'referral_reason'),
        'attending': _textOrNull(d, 'attending'),
        'notes': _textOrNull(d, 'notes'),
        'common_complaints': _listOrNull(d, 'symptoms'),
        'other_complaint': _textOrNull(d, 'symptom_other'),
        'duration_onset':
            durationParts.isEmpty ? null : durationParts.join(', '),
        'additional_complaint': _textOrNull(d, 'additional_complaint'),
        'history_symptoms': _listOrNull(d, 'history'),
        'other_history': _otherTextOrNull(d, 'history'),
        'history_details': _textOrNull(d, 'history_details'),
        'secondary_diagnosis': _textOrNull(d, 'secondary_diagnosis'),
        'red_flags': _listOrNull(d, 'red_flags'),
        'treatment_provided': _listOrNull(d, 'treatment'),
        'other_treatment': _otherTextOrNull(d, 'treatment'),
        'treatment_details': _textOrNull(d, 'management_details'),
        'medication_service_required':
            (_choice(d, 'medication_service_needed') == 'Yes'),
        'medication_intended': _textOrNull(d, 'medication_summary'),
        'rest_minutes': _numOrNull(d, 'rest_minutes')?.toInt(),
        'disposition': _choice(d, 'disposition'),
        'sent_home_with': _textOrNull(d, 'sent_home_with'),
        'guardian_informed': _choice(d, 'guardian_informed'),
        'follow_up_instructions': _textOrNull(d, 'follow_up_instructions'),
        'excuse_slip_needed': (_choice(d, 'excuse_slip_needed') == 'Yes'),
        'excuse_days': _numOrNull(d, 'excuse_days')?.toInt(),
        'referral_service': _choice(d, 'referral_service'),
        'referred_to': _textOrNull(d, 'referred_to'),
        'needs_referral': needsReferral,
        'referral_reasons': reasons.isEmpty ? null : jsonEncode(reasons),
      };
        case 'vital_signs':
      // Only ticked vitals are saved; unticked ones go in as NULL.
      // Old visits (nothing ticked) keep every value they have.
      final vsPicked = d.chosen(kVitalsSelectedKey).toSet();
      bool vsOn(String choice) => vsPicked.isEmpty || vsPicked.contains(choice);

      final vsSys = vsOn('Blood Pressure') ? vitals.systolic : null;
      final vsDia = vsOn('Blood Pressure') ? vitals.diastolic : null;
      final vsTemp = vsOn('Temperature') ? vitals.tempC : null;
      final vsPulse = vsOn('Pulse') ? vitals.heartRate : null;
      final vsResp = vsOn('Respiratory Rate') ? vitals.respRate : null;
      final vsSpo2 = vsOn('O₂ Saturation') ? vitals.o2Sat : null;

      final vsBp = VitalClassifier.classifyBp(vsSys, vsDia);
      final vsTempClass = VitalClassifier.classifyTemp(vsTemp);
      final vsPulseClass = VitalClassifier.classifyPulse(vsPulse);
      final vsRespClass = VitalClassifier.classifyResp(vsResp);
      final vsSpo2Class = VitalClassifier.classifySpo2(vsSpo2);
       final vsAnyVital = vsSys != null ||
          vsDia != null ||
          vsTemp != null ||
          vsPulse != null ||
          vsResp != null ||
          vsSpo2 != null;
      return {
        'systolic': _vitalNum(vsSys),
        'diastolic': _vitalNum(vsDia),
        'pulse_rate': _vitalNum(vsPulse),
        'temperature': _vitalNum(vsTemp),
        'temp_method':
            vsOn('Temperature') ? _textOrNull(d, 'method') : null,
        'respiratory_rate': _vitalNum(vsResp),
        'spo2': _vitalNum(vsSpo2),
        'arm': vsOn('Blood Pressure') ? _listOrNull(d, 'arm_used') : null,
        'position': vsOn('Blood Pressure') ? _listOrNull(d, 'position') : null,
        'bp_classification': vsBp?.label,
        'bp_band': vsBp?.band.name,
        'temperature_classification': vsTempClass?.label,
        'temperature_band': vsTempClass?.band.name,
        'pulse_classification': vsPulseClass?.label,
        'pulse_band': vsPulseClass?.band.name,
        'respiratory_classification': vsRespClass?.label,
        'respiratory_band': vsRespClass?.band.name,
        'spo2_classification': vsSpo2Class?.label,
        'spo2_band': vsSpo2Class?.band.name,
        'measured_at':
            vsAnyVital ? vitals.measuredAt?.toIso8601String() : null,
        if (recordedBy != null && recordedBy.isNotEmpty)
          'recorded_by': recordedBy,
        'action_taken': _vitalActionsOrNull(d),
       'referral_reason': _textOrNull(d, 'referral_reason'),
        'referred_to': _textOrNull(d, 'referred_to'),
        'assessment': _textOrNull(d, 'assessment'),
      };
    default:
      return null;
  }
}

Future<Map<String, Map<String, dynamic>>> loadServiceRecords(
    List<String> visitServiceIds) async {
  final out = <String, Map<String, dynamic>>{};
  if (visitServiceIds.isEmpty) return out;

  const tables = [
    'bmi_records',
    'wound_dressing_records',
    'first_aid_records',
    'counselling_records',
    'prenatal_records',
    'medical_consultations',
    'medication_services',
    'vital_signs',
  ];
  for (final table in tables) {
    try {
      final rows = await supabaseClient
          .from(table)
          .select()
          .inFilter('visit_service_id', visitServiceIds);
      for (final r in rows) {
        final id = '${r['visit_service_id'] ?? ''}';
        if (id.isEmpty) continue;
        out.putIfAbsent(id, () => {}).addAll(r.cast<String, dynamic>());
      }
    } catch (_) {}
  }

  final firstAidParents = <String, String>{};
  for (final e in out.entries) {
    final pid = '${e.value['first_aid_id'] ?? ''}';
    if (pid.isNotEmpty) firstAidParents[pid] = e.key;
  }
  if (firstAidParents.isNotEmpty) {
    try {
      final conditions = await supabaseClient
          .from('first_aid_conditions')
          .select('first_aid_id, condition')
          .inFilter('first_aid_id', firstAidParents.keys.toList());
      for (final c in conditions) {
        final kid = firstAidParents['${c['first_aid_id'] ?? ''}'];
        if (kid == null) continue;
        out[kid]!.putIfAbsent('_conditions', () => []).add('${c['condition']}');
      }
    } catch (_) {}
    try {
      final treatments = await supabaseClient
          .from('first_aid_treatments')
          .select('first_aid_id, treatment_type')
          .inFilter('first_aid_id', firstAidParents.keys.toList());
      for (final t in treatments) {
        final kid = firstAidParents['${t['first_aid_id'] ?? ''}'];
        if (kid == null) continue;
        out[kid]!
            .putIfAbsent('_treatments', () => [])
            .add('${t['treatment_type']}');
      }
    } catch (_) {}
  }

  return out;
}

void applyServiceRecordTo({
  required String dartServiceId,
  required Map<String, dynamic> row,
  required Map<String, dynamic> data,
}) {
  switch (dartServiceId) {
    case 'bpi':

      _setStr(data, 'bmi', row['bmi']);
      _setStr(data, 'bmi_class', row['classification']);
      _setStr(data, 'notes', row['notes']);
    case 'wound_dressing':
      _readChoiceWithOther(
          data, 'injury_timing', row['injury_timing'], kWoundInjuryTiming,
          dropdown: true);
      _setStr(data, 'injury_cause', row['injury_cause']);
      _readChoiceWithOther(data, 'wound_location', row['wound_location'],
          ClinicPurposes.bodySites,
          legacyOther: row['other_location_specify'], dropdown: true);

      var type = '${row['wound_type'] ?? ''}'.trim();
      if (type == 'Abrasive') type = 'Abrasion';
      _readChoiceWithOther(data, 'wound_type', type, kWoundTypes,
          legacyOther: row['other_type_specify'], dropdown: true);
      _readChoiceWithOther(
          data, 'burn_degree', row['burn_degree'], kBurnDegrees);

      final storedRaw = _decodeList(row['wound_condition']);
      final needsSuturing =
          storedRaw.any((e) => e.trim() == 'Requires suturing');
      final conditions =
          storedRaw.where((e) => e.trim() != 'Requires suturing').toList();
      if (conditions.isNotEmpty) {
        _readListWithOther(
            data, 'wound_condition', conditions, kWoundConditions);
      }
      if (needsSuturing) data['wound_requires_suturing_legacy'] = true;
      _readChoiceWithOther(data, 'bleeding', row['bleeding'], kBleedingStatus);

      final tetanus = '${row['tetanus_status'] ?? ''}'.trim();
      if (tetanus.isNotEmpty) data['tetanus_status'] = <String>[tetanus];
      _setNum(data, 'wound_length_cm', row['wound_length_cm']);
      _setNum(data, 'wound_width_cm', row['wound_width_cm']);
      _readListWithOther(data, 'cleaning_performed', row['cleaning_performed'],
          kWoundCleaningPerformed);

      final storedMeds = row['medications_used'];
      if (storedMeds != null && '$storedMeds'.trim().isNotEmpty) {
        data['medications_used'] =
            storedMeds is String ? storedMeds : jsonEncode(storedMeds);
      } else {
        final legacyNames = [
          for (final e in _decodeList(row['antiseptic_used']))
            if (e.trim() != kWoundNoMedicationLabel) e,
        ];
        if (legacyNames.isNotEmpty) {
          data['medications_used'] = jsonEncode([
            for (final n in legacyNames) {'name': n},
          ]);
        }
      }
      _setStr(data, 'other_medication', row['other_medication']);
      _readListWithOther(data, 'dressing_applied', row['dressing_material'],
          kWoundDressingMaterials);
      _readListWithOther(
          data, 'assessment', row['assessment_findings'], kWoundFindings);
      _readListWithOther(
          data, 'action_taken', row['action_taken'], kWoundActions);
      _setStr(data, 'referred_to', row['referred_to']);

      if (row['no_further_dressing'] == true) {
        _readList(data, 'no_further_dressing', [kWoundNoFurtherDressing]);
      }
      _setStr(data, 'next_dressing_date', row['next_dressing_date']);
      _setStr(data, 'notes', row['notes']);
    case 'first_aid_treatment':
      _readChoiceWithOther(
          data, 'incident', row['incident_type'], kFirstAidIncidents,
          legacyOther: row['incident_other'], dropdown: true);
      _readChoiceWithOther(
          data, 'incident_timing', row['incident_timing'], kFirstAidTimings,
          dropdown: true);
      _readChoiceWithOther(
          data, 'incident_place', row['incident_place'], kFirstAidPlaces,
          dropdown: true);
      _setStr(data, 'incident_cause', row['incident_cause']);
      _setStr(data, 'known_allergies', row['known_allergies']);
      _readChoiceWithOther(
          data, 'body_part', row['body_location'], ClinicPurposes.bodySites,
          dropdown: true);
      _setStr(data, 'pain_level', row['pain_level']);
      _readList(data, 'head_injury_signs', row['head_injury_signs']);
      _readList(data, 'consciousness', row['consciousness']);
      _readChoiceWithOther(data, 'dressing_material', row['dressing_material'],
          kDressingMaterialsUsed,
          legacyOther: row['dressing_other'], dropdown: true);
      _setStr(data, 'medication_given', row['medication_given']);
      _setNum(data, 'observation_minutes', row['observation_minutes']);
      _setStr(data, 'condition_after', row['condition_after_treatment']);
      _readList(data, 'disposition', row['disposition']);
      _readList(data, 'guardian_informed', row['guardian_informed']);

      if (isReferralDisposition('${row['disposition'] ?? ''}'.trim())) {
        _setStr(data, 'referred_to_where', row['sent_to']);
      } else {
        _setStr(data, 'sent_to', row['sent_to']);
      }
      _setStr(data, 'follow_up_date', row['follow_up_date']);
      _setStr(data, 'referral_reason', row['referral_reason']);
      _readList(data, 'findings', row['_conditions']);
      _readList(data, 'treatment', row['_treatments']);
      _setStr(data, 'notes', row['notes']);
    case 'health_counselling':
      _readList(data, 'topic', row['topic']);
      _setStr(data, 'topic_other', row['other_topic']);
      _setStr(data, 'reason', row['reason_or_concern']);
      _readList(data, 'provided', row['counselling_provided']);
      _setStr(data, 'provided_other', row['other_provided']);
      _setStr(data, 'counsellor', row['counsellor_name']);

      _readList(data, 'referral_source', row['referral_source']);
      _readList(data, 'session_type', row['session_type']);
      _setStr(data, 'session_date', row['session_date']);
      _setNum(data, 'duration_minutes', row['duration_minutes']);
      _readList(data, 'understanding', row['understanding']);
      _setStr(data, 'student_response', row['student_response']);
      _readList(data, 'concern_signs', row['concern_signs']);
      _readList(data, 'guardian_informed', row['guardian_informed']);
      _readList(data, 'privacy_level', row['privacy_level']);
      _readList(data, 'follow_up_needed', row['follow_up_needed']);
      _setStr(data, 'follow_up_date', row['follow_up_date']);
      _setStr(data, 'follow_up_reason', row['follow_up_reason']);
      _readList(
          data, 'additional_service_needed', row['additional_service_needed']);

      _readChoiceWithOther(data, 'referral_service',
          row['additional_service_name'], kCounsellingRecommendedServices,
          dropdown: true);
      _unfoldReferralPlace(data, 'referral_reason', 'referred_to',
          row['additional_service_reason']);
      _setStr(data, 'notes', row['notes']);
    case 'prenatal':
      _setStr(data, 'gravida', row['gravida']);
      _setStr(data, 'para', row['para']);
      _setStr(data, 'lmp', row['lmp']);
      if (row['lmp_unknown'] == true) {
        _readList(data, 'lmp_unknown', ['Unknown']);
      }
      _setStr(data, 'edd', row['edd']);
      _setStr(data, 'aog', row['gestational_age']);
      _setStr(data, 'fundal_height', row['fundal_height_cm']);
      _setNum(data, 'fetal_heart_tone', row['fetal_heart_rate']);
      if (row['fetal_heart_not_done'] == true) {
        _readList(data, 'fetal_heart_not_done', ['Not done / no equipment']);
      }
      _setStr(data, 'fetal_movement', row['fetal_movement']);
      _readList(data, 'edema', row['edema']);
      _readList(data, 'urine_protein', row['urine_protein']);
      _readListWithOther(
          data, 'danger_signs', row['danger_signs'], kPrenatalDangerSigns);
      _setStr(data, 'care_elsewhere', row['care_elsewhere']);
      _setStr(data, 'care_elsewhere_place', row['care_elsewhere_place']);
      _readList(data, 'service_provided', row['service_provided']);
      _setStr(data, 'other_service_specify', row['other_service_specify']);
      _readListWithOther(
          data, 'given_this_visit', row['given_this_visit'], kPrenatalGiven);
      _setStr(data, 'bp_assessment', row['assessment']);
      _readListWithOther(
          data, 'action_taken', row['action_taken'], kPrenatalActions);
      _setStr(data, 'referred_to', row['referred_to']);
      _setStr(data, 'follow_up_date', row['follow_up_date']);
      _setStr(data, 'notes', row['notes']);
    case 'medication':
      _readList(data, 'reason_common', row['reason']);

      _setStr(data, 'reason_other', _medicationReasonOther(row['notes']));
    case 'medicine_consultation':
      _setStr(data, 'chief_complaint', row['chief_complaint']);

      _readList(data, 'symptoms', row['common_complaints']);
      _setStr(data, 'symptom_other', row['other_complaint']);

      final dur = row['duration_onset']?.toString() ?? '';
      if (dur.isNotEmpty) {
        final matched = kConsultationDuration.firstWhere(
            (o) =>
                dur == o || dur.startsWith(o + ',') || dur.contains(', ' + o),
            orElse: () => '');
        if (matched.isNotEmpty) {
          _readList(data, 'duration_onset_choice', [matched]);
          final rest = dur.startsWith(matched + ',')
              ? dur.substring(matched.length + 1).trim()
              : dur.endsWith(', ' + matched)
                  ? dur.substring(0, dur.length - (matched.length + 2)).trim()
                  : (dur.contains(matched)
                      ? dur
                          .replaceFirst(matched, '')
                          .trim()
                          .replaceFirst('^,', '')
                          .trim()
                      : dur);
          if (rest.isNotEmpty && rest != matched) {
            data['duration_onset'] = rest;
          }
        } else {
          data['duration_onset'] = dur;
        }
      }
      _setStr(data, 'additional_complaint', row['additional_complaint']);
      _readList(data, 'history', row['history_symptoms']);
      _setStr(data, 'history_other', row['other_history']);
      _setStr(data, 'history_details',
          row['history_details'] ?? row['history_of_present_illness']);
      _setStr(data, 'physical_exam', row['physical_examination']);
      _setStr(data, 'clinical_impression', row['assessment']);
      _setStr(data, 'secondary_diagnosis', row['secondary_diagnosis']);
      _readList(data, 'red_flags', row['red_flags']);
      _readList(data, 'treatment',
          row['treatment_provided'] ?? row['treatment_management']);
      _setStr(data, 'treatment_other', row['other_treatment']);
      _setStr(data, 'management_details', row['treatment_details']);
      if (row['medication_service_required'] == true) {
        _readList(data, 'medication_service_needed', ['Yes']);
      } else if (row['medication_service_required'] == false) {
        _readList(data, 'medication_service_needed', ['No']);
      }
      _setStr(data, 'medication_summary', row['medication_intended']);
      _setNum(data, 'rest_minutes', row['rest_minutes']);

      _readList(data, 'disposition', row['disposition']);
      _setStr(data, 'sent_home_with', row['sent_home_with']);
      _readList(data, 'guardian_informed', row['guardian_informed']);
      _readList(data, 'follow_up_needed', row['follow_up_needed']);
      _setStr(data, 'follow_up_date', row['follow_up_date']);
      _setStr(data, 'follow_up_instructions', row['follow_up_instructions']);
      if (row['excuse_slip_needed'] == true) {
        _readList(data, 'excuse_slip_needed', ['Yes']);
      } else if (row['excuse_slip_needed'] == false) {
        _readList(data, 'excuse_slip_needed', ['No']);
      }
      _setNum(data, 'excuse_days', row['excuse_days']);
      _readList(data, 'referral_needed', row['referral_needed']);
      _setStr(data, 'referral_service', row['referral_service']);
      _setStr(data, 'referred_to', row['referred_to']);
      _setStr(data, 'referral_reason', row['referral_reason']);
      _setStr(data, 'attending', row['attending']);
      _setStr(data, 'notes', row['notes']);
    case 'vital_signs':
      _setNum(data, 'systolic', row['systolic']);
      _setNum(data, 'diastolic', row['diastolic']);
      _setNum(data, 'pulse_bpm', row['pulse_rate']);
      _setNum(data, 'temp_c', row['temperature']);
      _setStr(data, 'method', row['temp_method']);
      _setNum(data, 'resp_rate', row['respiratory_rate']);
      _setNum(data, 'o2_sat', row['spo2']);
            _setNum(data, 'height_cm', row['height_cm']);
      _setNum(data, 'weight_kg', row['weight_kg']);

      // Rebuild the tick-boxes from whichever columns have a value.
      final vsTicked = <String>[
        if (row['systolic'] != null || row['diastolic'] != null)
          'Blood Pressure',
        if (row['temperature'] != null) 'Temperature',
        if (row['pulse_rate'] != null) 'Pulse',
        if (row['respiratory_rate'] != null) 'Respiratory Rate',
        
        if (row['spo2'] != null) 'O₂ Saturation',
      ];
      if (vsTicked.isNotEmpty) {
        data[kVitalsSelectedKey] = [
          if (vsTicked.length == kVitalChoices.length) kSelectAllLabel,
          ...vsTicked,
        ];
      }
      _readList(data, 'position', row['position']);
      _readList(data, 'arm_used', row['arm']);
      _applyVitalActions(data, row['action_taken']);
      _setStr(data, 'referral_reason', row['referral_reason']);
      _setStr(data, 'assessment', row['assessment']);
        _setStr(data, 'referred_to', row['referred_to']);
      
  }
}

void liftVitalsFromRows(
    Iterable<Map<String, dynamic>> rows, VisitVitals vitals) {
  for (final r in rows) {
    if (r['systolic'] != null && r['diastolic'] != null) {
      vitals.systolic = (r['systolic'] as num).toInt();
      vitals.diastolic = (r['diastolic'] as num).toInt();
    }
    if (r['pulse_rate'] != null) {
      vitals.heartRate = (r['pulse_rate'] as num).toInt();
    }
    if (r['temperature'] != null) {
      vitals.tempC = (r['temperature'] as num).toDouble();
    }
    if (r['respiratory_rate'] != null) {
      vitals.respRate = (r['respiratory_rate'] as num).toInt();
    }
    if (r['spo2'] != null) {
      vitals.o2Sat = (r['spo2'] as num).toInt();
    }
    if (r['height_cm'] != null) {
      vitals.heightCm = (r['height_cm'] as num).toDouble();
    }
    if (r['weight_kg'] != null) {
      vitals.weightKg = (r['weight_kg'] as num).toDouble();
    }
    final measured = r['measured_at'];
    if (measured != null) {
      final stamp = DateTime.tryParse('$measured');
      if (stamp != null) vitals.measuredAt = stamp;
    }
  }
  vitals.interpretations.clear();
  for (final v in vitals.readings) {
    vitals.interpretations[v.key] = v.category ?? v.band.label;
  }
}

String? _textOrNull(ServiceDraft d, String key) {
  final v = d.text(key).trim();
  return v.isEmpty ? null : v;
}

String? _choice(ServiceDraft d, String key) {
  final one = _chosenOne(d, key);
  return one.isEmpty ? null : one;
}

String _chosenOne(ServiceDraft d, String key) {
  final raw = d.data[key];
  if (raw is List) return raw.isEmpty ? '' : '${raw.first}'.trim();
  return '${raw ?? ''}'.trim();
}

String? _choiceWithOtherOrNull(
    ServiceDraft d, String key, List<String> options) {
  final first = _chosenOne(d, key);
  if (first.isEmpty) return null;
  if (first == 'Other') {
    final other = d.text('${key}_other').trim();
    return other.isEmpty ? 'Other' : other;
  }
  return first;
}

String? _foldReferralPlace(String? reason, String? place) {
  final r = reason?.trim();
  final p = place?.trim();
  if (p == null || p.isEmpty) return (r == null || r.isEmpty) ? null : r;
  if (r == null || r.isEmpty) return p;
  return '$r\n$p';
}

void _unfoldReferralPlace(Map<String, dynamic> data, String reasonKey,
    String placeKey, Object? cell) {
  final s = '${cell ?? ''}'.trim();
  if (s.isEmpty) return;
  final i = s.lastIndexOf('\n');
  if (i < 0) {
    data[reasonKey] = s;
    return;
  }
  final head = s.substring(0, i).trim();
  final tail = s.substring(i + 1).trim();
  if (head.isNotEmpty) data[reasonKey] = head;
  if (tail.isNotEmpty) data[placeKey] = tail;
}

String? _otherTextOrNull(ServiceDraft d, String key) {
  if (_chosenOne(d, key) != 'Other') return null;
  final other = d.text('${key}_other').trim();
  return other.isEmpty ? null : other;
}

String? _medicinesOrNull(ServiceDraft d) {
  if (d.medicines.isEmpty) return null;
  return jsonEncode([
    for (final m in d.medicines)
      {...m.toJson(), 'stock_at_pick': m.stockAtPick},
  ]);
}

bool _hasChosen(ServiceDraft d, String key, String value) {
  return d.chosen(key).contains(value);
}

String? _listOrNull(ServiceDraft d, String key) {
  final v = d.data[key];
  if (v is List && v.isNotEmpty) return jsonEncode(v);
  return null;
}

String? _listWithOtherOrNull(ServiceDraft d, String key) {
  final v = d.data[key];
  if (v is! List || v.isEmpty) return null;
  final other = d.text('${key}_other').trim();
  final out = <String>[
    for (final e in v)
      if ('$e' == 'Other' && other.isNotEmpty) other else '$e',
  ];
  return jsonEncode(out);
}

String? _medicationReasonOther(Object? value) {
  if (value == null) return null;
  if (value is Map) {
    final other = value['reason_other'];
    return other == null ? null : '$other';
  }
  final s = '$value'.trim();
  if (s.isEmpty) return null;
  if (s.startsWith('{')) {
    try {
      final decoded = jsonDecode(s);
      if (decoded is Map) {
        final other = decoded['reason_other'];
        return other == null ? null : '$other';
      }
    } catch (_) {}
  }
  return s;
}

String? _dateOrNull(ServiceDraft d, String key) {
  final v = d.text(key).trim();
  if (v.isEmpty) return null;
  return v.length >= 10 ? v.substring(0, 10) : v;
}

num? _numOrNull(ServiceDraft d, String key) {
  final v = d.data[key];
  if (v is num) return v;
  if (v == null) return null;
  return double.tryParse('$v'.trim());
}

num? _vitalNum(num? n) {
  final v = n;
  if (v == null) return null;
  return v.roundToDouble() == v ? v.toInt() : v;
}

List<String> _jsonList(ServiceDraft d, String key) {
  final v = d.data[key];
  if (v is List) {
    return [for (final e in v) '$e'.trim()].where((e) => e.isNotEmpty).toList();
  }
  return const [];
}

String? _vitalActionsOrNull(ServiceDraft d) {
  final chosen = _jsonList(d, 'action_taken');
  if (chosen.isEmpty) return null;
  final other = d.text('action_taken_other').trim();
  final out = <String>[
    for (final a in chosen)
      if (a != 'Other' || other.isEmpty) a else other,
  ];
  return out.isEmpty ? null : jsonEncode(out);
}

void _applyVitalActions(Map<String, dynamic> data, Object? value) {
  final stored = _decodeList(value);
  if (stored.isEmpty) return;
  final ticks = <String>[];
  final custom = <String>[];
  for (final e in stored) {
    final a = e.trim();
    if (a.isEmpty) continue;
    if (kVitalActions.contains(a)) {
      ticks.add(a);
    } else {
      custom.add(a);
    }
  }
  if (custom.isNotEmpty) {
    ticks.add('Other');
    data['action_taken_other'] = custom.join(', ');
  }
  data['action_taken'] = ticks;
}

List<String> _decodeList(Object? value) {
  if (value == null) return const [];
  if (value is List) return [for (final e in value) '$e'];
  final s = '$value'.trim();
  if (s.isEmpty) return const [];
  try {
    final decoded = jsonDecode(s);
    if (decoded is List) return [for (final e in decoded) '$e'];
  } catch (_) {}
  return [s];
}

void _setStr(Map<String, dynamic> data, String key, Object? value) {
  final s = value == null ? '' : '$value'.trim();
  if (s.isNotEmpty) data[key] = s;
}

void _setNum(Map<String, dynamic> data, String key, Object? value) {
  if (value is num) {
    data[key] =
        value.roundToDouble() == value ? value.toInt() : value.toDouble();
  } else if (value is String && value.trim().isNotEmpty) {
    final n = num.tryParse(value.trim());
    if (n != null) data[key] = n;
  }
}

void _readList(Map<String, dynamic> data, String key, Object? value) {
  if (value == null) return;
  if (value is List) {
    data[key] = [for (final e in value) '$e'];
    return;
  }
  final s = '$value'.trim();
  if (s.isEmpty) return;
  try {
    final decoded = jsonDecode(s);
    if (decoded is List) {
      data[key] = [for (final e in decoded) '$e'];
      return;
    }
  } catch (_) {}
  data[key] = [s];
}

void _readListWithOther(
  Map<String, dynamic> data,
  String key,
  Object? value,
  List<String> options,
) {
  final stored = _decodeList(value);
  if (stored.isEmpty) return;
  final ticks = <String>[];
  final custom = <String>[];
  for (final e in stored) {
    final a = e.trim();
    if (a.isEmpty) continue;
    if (options.contains(a)) {
      ticks.add(a);
    } else {
      custom.add(a);
    }
  }
  if (custom.isNotEmpty) {
    ticks.add('Other');
    data['${key}_other'] = custom.join(', ');
  }
  data[key] = ticks;
}

void _readChoiceWithOther(
  Map<String, dynamic> data,
  String key,
  Object? value,
  List<String> options, {
  Object? legacyOther,
  bool dropdown = false,
}) {
  final s = value == null ? '' : '$value'.trim();
  if (s.isEmpty) return;
  if (s != 'Other' && options.contains(s)) {
    data[key] = dropdown ? s : <String>[s];
    return;
  }
  var typed = s == 'Other' ? '${legacyOther ?? ''}'.trim() : s;
  if (typed == 'Other') typed = '';
  data[key] = dropdown ? 'Other' : const <String>['Other'];
  if (typed.isNotEmpty) data['${key}_other'] = typed;
}
