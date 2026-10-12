// ============================================================================
//  service_detail_records.dart
//  The structured record behind one worked service.
//
//  `clinic_visit_services` holds the fact that a service was done on a visit and
//  how far it got; this file holds WHAT was recorded — the readings, the wound,
//  the prescription's outcome. Each service keeps one row in its own detail
//  table, keyed by `visit_service_id`, so step 3 writes the same record on
//  every save (delete the row, rebuild it from the draft) and reads it straight
//  back into the form that produced it.
//
//  Two shapes, one file:
//
//    * [buildServiceRecord] turns a draft into the row its table expects, using
//      the exact column spellings of the live database. The column names and the
//      form's field keys are deliberately free to differ — the BP form says
//      "pulse_bpm", its table says "pulse_rate" — because the record and the
//      on-screen form may name a number differently without disagreeing about it.
//
//    * [applyServiceRecordTo] turns a row back into the form's own field keys,
//      so the resumed form shows what was recorded (checkbox answers come back
//      as lists, single choices as strings, exactly the shape the boxes wrote).
//
//  A column that holds a list (ticks, checkboxes) stores JSON rather than a
//  comma-joined sentence, because an option can legitimately contain a comma.
// ============================================================================

import 'dart:convert';

import 'package:clinicmanagementsystem/core/visit_details.dart';
import 'package:clinicmanagementsystem/core/vitals.dart';
import 'package:clinicmanagementsystem/services/supabase_config.dart';

// ── WRITING ──────────────────────────────────────────────────────────────

/// The detail table one service writes to.
String _tableFor(String dartServiceId) => switch (dartServiceId) {
      'bp_tracking' => 'bp_readings',
      'temperature_checking' => 'temperature_records',
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

/// Whether [dartServiceId] keeps a detail row at all.
bool hasServiceRecord(String dartServiceId) =>
    _tableFor(dartServiceId).isNotEmpty;

/// Writes (or rewrites) the detail rows for one service on a save.
///
/// A delete-then-insert keyed on `visit_service_id`, not an upsert: the rows are
/// one-per-service, small, and replacing them is what makes a second save agree
/// with a form that has been edited since the first. First-aid's two child
/// lists are rewritten with the parent, from the parent's fresh id.
Future<void> saveServiceRecord({
  required String visitServiceId,
  required String visitId,
  required String dartServiceId,
  required ServiceDraft d,
  required VisitVitals vitals,
}) async {
  final table = _tableFor(dartServiceId);
  if (table.isEmpty) return;

  final row =
      buildServiceRecord(dartServiceId: dartServiceId, d: d, vitals: vitals);
  if (row == null) return;

  // The medication row is also the header the prescription's lines hang off
  // (`medication_service_items` references it), so it is updated in place,
  // never deleted and rebuilt.
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

  // First-aid's children are keyed to the parent row. Find the parent id before
  // the parent is replaced, so the stale children can go with it.
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

  // Drop the old row (and anything cascading off it), then write the fresh one
  // so the whole read-back reflects what is on the form right now.
  try {
    await supabaseClient
        .from(table)
        .delete()
        .eq('visit_service_id', visitServiceId);
  } catch (_) {
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
  } catch (_) {
    // The row stays in memory; the visit itself is saved by the caller.
  }
}

/// Inserts the condition/treatment child rows under a fresh first-aid parent.
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

// ── THE RECORD, COLUMN FOR COLUMN ────────────────────────────────────────

/// The row [d]'s service writes, in its table's own column spellings, or null
/// when there is nothing worth recording yet.
Map<String, dynamic>? buildServiceRecord({
  required String dartServiceId,
  required ServiceDraft d,
  required VisitVitals vitals,
}) {
  switch (dartServiceId) {
    case 'bp_tracking':
      return {
        'systolic': _vitalNum(vitals.systolic),
        'diastolic': _vitalNum(vitals.diastolic),
        'pulse_rate': _vitalNum(vitals.heartRate),
        'position': _listOrNull(d, 'position'),
        'arm': _listOrNull(d, 'arm_used'),
        'assessment': _bpVerdict(vitals),
        'notes': _textOrNull(d, 'notes'),
      };
    case 'temperature_checking':
      return {
        'temperature': _vitalNum(vitals.tempC),
        'unit': 'C',
        'method': _textOrNull(d, 'method'),
        'assessment': vitals.tempReading?.category,
        'notes': _textOrNull(d, 'notes'),
      };
    case 'bpi':
      return {
        'height_cm': _vitalNum(vitals.heightCm),
        'weight_kg': _vitalNum(vitals.weightKg),
        'bmi': vitals.bmiReading?.display,
        'classification': vitals.bmiReading?.category,
        'notes': _textOrNull(d, 'notes'),
      };
    case 'wound_dressing':
      return {
        'wound_location': _textOrNull(d, 'wound_location'),
        'wound_type': _textOrNull(d, 'wound_type'),
        'wound_condition': _listOrNull(d, 'wound_condition'),
        'cleaning_performed': _listOrNull(d, 'cleaning_performed'),
        'antiseptic_used': _listOrNull(d, 'medication_applied'),
        'dressing_material': _listOrNull(d, 'dressing_applied'),
        'assessment_findings': _listOrNull(d, 'assessment'),
        'next_dressing_date': _dateOrNull(d, 'next_dressing_date'),
        'wound_length_cm': _numOrNull(d, 'wound_length_cm'),
        'wound_width_cm': _numOrNull(d, 'wound_width_cm'),
        'notes': _textOrNull(d, 'notes'),
      };
    case 'first_aid_treatment':
      return {
        'incident_type': _textOrNull(d, 'incident'),
        'body_location': _textOrNull(d, 'body_part'),
        'pain_level': _textOrNull(d, 'pain_level'),
        'condition_after_treatment': _textOrNull(d, 'condition_after'),
        'disposition': _choice(d, 'disposition'),
        'referral_reason': _textOrNull(d, 'referral_reason'),
        'notes': _textOrNull(d, 'notes'),
      };
    case 'health_counselling':
      return {
        'topic': _listOrNull(d, 'topic'),
        'other_topic': _textOrNull(d, 'topic_other'),
        'reason_or_concern': _textOrNull(d, 'reason'),
        'counselling_provided': _listOrNull(d, 'provided'),
        'counsellor_name': _textOrNull(d, 'counsellor'),
        'follow_up_needed': _choice(d, 'follow_up_needed'),
        'follow_up_date': _dateOrNull(d, 'follow_up_date'),
        'follow_up_reason': _textOrNull(d, 'follow_up_reason'),
        'additional_service_needed': _choice(d, 'additional_service_needed'),
        'additional_service_name': _textOrNull(d, 'referral_service'),
        'additional_service_reason': _textOrNull(d, 'referral_reason'),
        'notes': _textOrNull(d, 'notes'),
      };
    case 'prenatal':
      return {
        'gravida': _textOrNull(d, 'gravida'),
        'para': _textOrNull(d, 'para'),
        'lmp': _dateOrNull(d, 'lmp'),
        'edd': _textOrNull(d, 'edd'),
        'gestational_age': _textOrNull(d, 'aog'),
        'blood_pressure': _bpString(vitals),
        'weight_kg': _vitalNum(vitals.weightKg),
        'fundal_height_cm': _numOrNull(d, 'fundal_height'),
        'fetal_heart_rate': _numOrNull(d, 'fetal_heart_tone'),
        'fetal_movement': _textOrNull(d, 'fetal_movement'),
        'temperature': _vitalNum(vitals.tempC),
        'pulse_rate': _vitalNum(vitals.heartRate),
        'edema': _choice(d, 'edema'),
        'urine_protein': _choice(d, 'urine_protein'),
        'service_provided': _listOrNull(d, 'service_provided'),
        'given_this_visit': _listOrNull(d, 'given_this_visit'),
        'presentation': _textOrNull(d, 'presentation'),
        'assessment': d.text('bp_assessment'),
        'action_taken': _listOrNull(d, 'action_taken'),
        'follow_up_date': _dateOrNull(d, 'follow_up_date'),
        'notes': _textOrNull(d, 'notes'),
      };
    case 'medication':
      return {
        'reason': _listOrNull(d, 'reason_common'),
        'action': _choice(d, 'medication_action'),
        'action_reason': _textOrNull(d, 'action_reason'),
        'response': _choice(d, 'response'),
        'additional_service_needed': _choice(d, 'additional_service_needed'),
        'referral_service': _textOrNull(d, 'referral_service'),
        'referral_reason': _textOrNull(d, 'referral_reason'),
        'notes': _textOrNull(d, 'notes'),
      };
    case 'medicine_consultation':
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
      };
    case 'vital_signs':
      return {
        'systolic': _vitalNum(vitals.systolic),
        'diastolic': _vitalNum(vitals.diastolic),
        'pulse_rate': _vitalNum(vitals.heartRate),
        'temperature': _vitalNum(vitals.tempC),
        'temp_method': _textOrNull(d, 'method'),
        'respiratory_rate': _vitalNum(vitals.respRate),
        'spo2': _vitalNum(vitals.o2Sat),
        'bp_classification': _bpVerdict(vitals),
        'symptoms': _textOrNull(d, 'symptoms'),
        'assessment': _textOrNull(d, 'assessment'),
        'follow_up': _textOrNull(d, 'follow_up'),
        'notes': _textOrNull(d, 'notes'),
      };
    default:
      return null;
  }
}

// ── READING BACK ─────────────────────────────────────────────────────────

/// The detail rows of a set of services, keyed by `visit_service_id`, from
/// whichever of the detail tables holds them. One query per table, so a whole
/// booklet page is two round trips instead of one per row.
Future<Map<String, Map<String, dynamic>>> loadServiceRecords(
    List<String> visitServiceIds) async {
  final out = <String, Map<String, dynamic>>{};
  if (visitServiceIds.isEmpty) return out;

  const tables = [
    'bp_readings',
    'temperature_records',
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
    } catch (_) {
      // A table that does not exist yet is not a reason to lose the rest.
    }
  }

  // First-aid's conditions and treatments belong to the parent row, not to the
  // visit service, so they are fetched through it.
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

/// Fills [data] (a service's in-memory field map) with what the row recorded,
/// back in the form's own key spellings and shapes.
void applyServiceRecordTo({
  required String dartServiceId,
  required Map<String, dynamic> row,
  required Map<String, dynamic> data,
}) {
  switch (dartServiceId) {
    case 'bp_tracking':
      _setNum(data, 'systolic', row['systolic']);
      _setNum(data, 'diastolic', row['diastolic']);
      if (row.containsKey('bp_readings') == false &&
          (row['systolic'] != null ||
              row['diastolic'] != null ||
              row['pulse_rate'] != null)) {
        data['bp_readings'] = [
          {
            if (row['systolic'] != null)
              'systolic': (row['systolic'] as num).toInt(),
            if (row['diastolic'] != null)
              'diastolic': (row['diastolic'] as num).toInt(),
            if (row['pulse_rate'] != null)
              'pulse_rate': (row['pulse_rate'] as num).toInt(),
          },
        ];
      }
      _readList(data, 'position', row['position']);
      _readList(data, 'arm_used', row['arm']);
      _setStr(data, 'notes', row['notes']);
    case 'temperature_checking':
      _setNum(data, 'temp_c', row['temperature']);
      _setStr(data, 'method', row['method']);
      _setStr(data, 'notes', row['notes']);
    case 'bpi':
      _setNum(data, 'height_cm', row['height_cm']);
      _setNum(data, 'weight_kg', row['weight_kg']);
      _setStr(data, 'notes', row['notes']);
    case 'wound_dressing':
      _setStr(data, 'wound_location', row['wound_location']);
      _setStr(data, 'wound_type', row['wound_type']);
      _readList(data, 'wound_condition', row['wound_condition']);
      _readList(data, 'cleaning_performed', row['cleaning_performed']);
      _readList(data, 'medication_applied', row['antiseptic_used']);
      _readList(data, 'dressing_applied', row['dressing_material']);
      _readList(data, 'assessment', row['assessment_findings']);
      _setStr(data, 'next_dressing_date', row['next_dressing_date']);
      _setNum(data, 'wound_length_cm', row['wound_length_cm']);
      _setNum(data, 'wound_width_cm', row['wound_width_cm']);
      _setStr(data, 'notes', row['notes']);
    case 'first_aid_treatment':
      _setStr(data, 'incident', row['incident_type']);
      _setStr(data, 'body_part', row['body_location']);
      _setStr(data, 'pain_level', row['pain_level']);
      _setStr(data, 'condition_after', row['condition_after_treatment']);
      _readList(data, 'disposition', row['disposition']);
      _setStr(data, 'referral_reason', row['referral_reason']);
      _readList(data, 'findings', row['_conditions']);
      _readList(data, 'treatment', row['_treatments']);
      _setStr(data, 'notes', row['notes']);
    case 'health_counselling':
      _readList(data, 'topic', row['topic']);
      _setStr(data, 'topic_other', row['other_topic']);
      _setStr(data, 'reason', row['reason_or_concern']);
      _readList(data, 'provided', row['counselling_provided']);
      _setStr(data, 'counsellor', row['counsellor_name']);
      _readList(data, 'follow_up_needed', row['follow_up_needed']);
      _setStr(data, 'follow_up_date', row['follow_up_date']);
      _setStr(data, 'follow_up_reason', row['follow_up_reason']);
      _readList(
          data, 'additional_service_needed', row['additional_service_needed']);
      _setStr(data, 'referral_service', row['additional_service_name']);
      _setStr(data, 'referral_reason', row['additional_service_reason']);
      _setStr(data, 'notes', row['notes']);
    case 'prenatal':
      _setStr(data, 'gravida', row['gravida']);
      _setStr(data, 'para', row['para']);
      _setStr(data, 'lmp', row['lmp']);
      _setStr(data, 'edd', row['edd']);
      _setStr(data, 'aog', row['gestational_age']);
      _setStr(data, 'fundal_height', row['fundal_height_cm']);
      _setNum(data, 'fetal_heart_tone', row['fetal_heart_rate']);
      _setStr(data, 'fetal_movement', row['fetal_movement']);
      _readList(data, 'edema', row['edema']);
      _readList(data, 'urine_protein', row['urine_protein']);
      _readList(data, 'service_provided', row['service_provided']);
      _readList(data, 'given_this_visit', row['given_this_visit']);
      _setStr(data, 'presentation', row['presentation']);
      _setStr(data, 'bp_assessment', row['assessment']);
      _readList(data, 'action_taken', row['action_taken']);
      _setStr(data, 'follow_up_date', row['follow_up_date']);
      _setStr(data, 'notes', row['notes']);
    case 'medication':
      _readList(data, 'reason_common', row['reason']);
      _readList(data, 'medication_action', row['action']);
      _setStr(data, 'action_reason', row['action_reason']);
      _readList(data, 'response', row['response']);
      _readList(
          data, 'additional_service_needed', row['additional_service_needed']);
      _setStr(data, 'referral_service', row['referral_service']);
      _setStr(data, 'referral_reason', row['referral_reason']);
      _setStr(data, 'notes', row['notes']);
    case 'medicine_consultation':
      _setStr(data, 'chief_complaint', row['chief_complaint']);
      _setStr(data, 'history_details', row['history_of_present_illness']);
      _setStr(data, 'physical_exam', row['physical_examination']);
      _setStr(data, 'clinical_impression', row['assessment']);
      _readList(data, 'treatment', row['treatment_management']);
      _readList(data, 'follow_up_needed', row['follow_up_needed']);
      _setStr(data, 'follow_up_date', row['follow_up_date']);
      _readList(data, 'referral_needed', row['referral_needed']);
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
      _setStr(data, 'symptoms', row['symptoms']);
      _setStr(data, 'assessment', row['assessment']);
      _setStr(data, 'follow_up', row['follow_up']);
      _setStr(data, 'notes', row['notes']);
  }
}

/// The numbers in [rows] lifted into the visit's shared vitals, so a resumed
/// visit shows its readings on every strip and every read-only box, not just on
/// the form that recorded them.
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
  }
  vitals.interpretations.clear();
  for (final v in vitals.readings) {
    vitals.interpretations[v.key] = v.category ?? v.band.label;
  }
}

// ── SHARED HELPERS ───────────────────────────────────────────────────────

String? _textOrNull(ServiceDraft d, String key) {
  final v = d.text(key).trim();
  return v.isEmpty ? null : v;
}

/// A single-answer chips field (Yes/No, one-of-N marks) as the cell value. The
/// box stores a list even when it only allows one tick, so the first answer is
/// the value — a plain, readable string.
String? _choice(ServiceDraft d, String key) {
  final picked = d.chosen(key);
  return picked.isEmpty ? null : picked.first.trim();
}

String? _listOrNull(ServiceDraft d, String key) {
  final v = d.data[key];
  if (v is List && v.isNotEmpty) return jsonEncode(v);
  return null;
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

String? _bpVerdict(VisitVitals v) {
  final bp = v.bloodPressure;
  return bp?.category;
}

String? _bpString(VisitVitals v) {
  if (v.systolic == null && v.diastolic == null) return null;
  return '${v.systolic} / ${v.diastolic}';
}

List<String> _jsonList(ServiceDraft d, String key) {
  final v = d.data[key];
  if (v is List) {
    return [for (final e in v) '$e'.trim()].where((e) => e.isNotEmpty).toList();
  }
  return const [];
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

/// A stored list column (JSON) back into the form's `List<String>` shape. A
/// plain string is treated as a single-answer list so a column written before a
/// field became a checkbox still restores.
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
