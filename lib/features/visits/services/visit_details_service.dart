import 'package:clinicmanagementsystem/features/certificates/models/certificate_engine.dart';
import 'package:clinicmanagementsystem/features/visits/models/visit_details.dart';
import 'package:clinicmanagementsystem/features/vitals/models/vitals.dart';
import 'package:flutter/foundation.dart';
import 'package:clinicmanagementsystem/core/services/data_tracker.dart';
import 'package:clinicmanagementsystem/features/visits/services/service_detail_records.dart';
import 'package:clinicmanagementsystem/core/config/supabase_config.dart';

const Map<String, String> _serviceCodeByDartId = {
  'bpi': 'BMI',
  'wound_dressing': 'WOUND_DRESSING',
  'first_aid_treatment': 'FIRST_AID',
  'health_counselling': 'COUNSELLING',
  'prenatal': 'PRENATAL',
  'medication': 'MEDICATION',
  'medicine_consultation': 'MED_CONSULT',
  'medicine_certificate': 'MED_CERT',
  'vital_signs': 'VITAL_SIGNS',
};

Map<String, String> dartIdByServiceTypeId(Iterable<dynamic> serviceTypes) {
  final idByCode = <String, String>{
    for (final t in serviceTypes)
      '${t['service_code'] ?? ''}': '${t['service_type_id'] ?? ''}',
  };
  final out = <String, String>{};
  for (final e in _serviceCodeByDartId.entries) {
    final id = idByCode[e.value];
    if (id != null) out[id] = e.key;
  }
  return out;
}

Future<Map<String, String>> _serviceTypeIds() async {
  try {
    final rows = await supabaseClient
        .from('service_types')
        .select('service_type_id, service_code');
    return {
      for (final r in rows)
        '${r['service_code'] ?? ''}': '${r['service_type_id'] ?? ''}',
    };
  } catch (_) {
    return const {};
  }
}

bool _deductsStock(String action) =>
    action == 'Given' || action == 'Partially Given';

class VisitDetailsService {
  VisitDetailsService._();

  static final Map<String, VisitDetailsController> _recentSaved = {};

  static VisitDetailsController _snapshotOf(VisitDetailsController src) {
    final copy = VisitDetailsController(
      serviceIds: [for (final d in src.drafts) d.serviceId],
    );
    copy.hydrate(
      serviceData: {
        for (final d in src.drafts)
          d.serviceId: Map<String, dynamic>.of(d.data),
      },
      restoredMedicines: [
        for (final m
            in src.draftFor('medication')?.medicines ?? const <MedicineDose>[])
          m.copy(),
      ],
      visitVitals: src.vitals,
    );

    for (final d in src.drafts) {
      final t = copy.draftFor(d.serviceId);
      if (t != null) t.status = d.status;
    }
    return copy;
  }

  static Map<String, VisitDetailsController> _withRecentSaved(
    Map<String, VisitDetailsController> out,
    List<String> visitIds,
  ) {
    if (_recentSaved.isEmpty) return out;
    for (final id in visitIds) {
      final cached = _recentSaved[id];
      if (cached == null) continue;
      if (out.containsKey(id)) {
        _recentSaved.remove(id);
      } else {
        out[id] = cached;
      }
    }
    return out;
  }

  static Map<String, VisitDetailsController> recentSavedFor(
      Iterable<String> visitIds) {
    if (_recentSaved.isEmpty) return const {};
    final out = <String, VisitDetailsController>{};
    for (final id in visitIds) {
      final cached = _recentSaved[id];
      if (cached != null) out[id] = cached;
    }
    return out;
  }

  static Future<void> hydrate({
    required String visitId,
    required VisitDetailsController controller,
  }) async {
    final serviceData = <String, Map<String, dynamic>>{};
    final slideIndexes = <String, int>{};
    final visitServiceByDart = <String, String>{};

    Map<String, String> byType = const {};
    try {
      final types = await supabaseClient
          .from('service_types')
          .select('service_type_id, service_code');
      byType = dartIdByServiceTypeId(types);
    } catch (_) {}

    try {
      final rows = await supabaseClient
          .from('clinic_visit_services')
          .select('visit_service_id, service_type_id, status')
          .eq('visit_id', visitId);
      for (final row in rows) {
        final dartId = byType['${row['service_type_id'] ?? ''}'];
        if (dartId == null) continue;
        serviceData[dartId] = {};
        visitServiceByDart[dartId] = '${row['visit_service_id'] ?? ''}';

        if ('${row['status']}' == ServiceDraftStatus.completed.label) {
          slideIndexes[dartId] = 0;
        }
      }
    } catch (_) {}

    final medicines =
        (await _medicinesForVisits([visitId]))[visitId] ?? const [];

    final visitVitals = await _detailsInto(serviceData, visitServiceByDart);

    if (serviceData.isEmpty && medicines.isEmpty) return;

    controller.hydrate(
      serviceData: serviceData,
      slideIndexes: slideIndexes,
      visitVitals: visitVitals,
      restoredMedicines: medicines,
    );
  }

  static Future<VisitVitals?> _detailsInto(
    Map<String, Map<String, dynamic>> serviceData,
    Map<String, String> visitServiceByDart,
  ) async {
    if (visitServiceByDart.isEmpty) return null;
    final rows = await loadServiceRecords(visitServiceByDart.values.toList());
    VisitVitals? vitals;
    for (final e in visitServiceByDart.entries) {
      final row = rows[e.value];
      if (row == null) continue;
      applyServiceRecordTo(
          dartServiceId: e.key, row: row, data: serviceData[e.key]!);

      if (e.key != 'prenatal') {
        liftVitalsFromRows([row], vitals ??= VisitVitals());
      }
    }
    return vitals;
  }

  static Future<Map<String, VisitDetailsController>> readVisits(
      List<String> visitIds) async {
    if (visitIds.isEmpty) return const {};

    Map<String, String> byType;
    try {
      final types = await supabaseClient
          .from('service_types')
          .select('service_type_id, service_code');
      byType = dartIdByServiceTypeId(types);
    } catch (_) {
      return _withRecentSaved({}, visitIds);
    }

    List<dynamic> serviceRows;
    try {
      serviceRows = await supabaseClient
          .from('clinic_visit_services')
          .select(
              'visit_id, visit_service_id, service_type_id, status, created_at')
          .inFilter('visit_id', visitIds)
          .order('created_at');
    } catch (_) {
      return _withRecentSaved({}, visitIds);
    }

    final medicinesByVisit = await _medicinesForVisits(visitIds);

    final byVisit = <String, List<Map<String, dynamic>>>{};
    for (final r in serviceRows) {
      final visitId = r['visit_id'] as String?;
      if (visitId == null || visitId.isEmpty) continue;
      byVisit.putIfAbsent(visitId, () => []).add(r.cast<String, dynamic>());
    }

    final out = <String, VisitDetailsController>{};
    for (final entry in byVisit.entries) {
      final serviceIds = <String>[];
      final visitServiceByDart = <String, String>{};
      for (final s in entry.value) {
        final dartId = byType['${s['service_type_id'] ?? ''}'];
        if (dartId == null || serviceIds.contains(dartId)) continue;
        serviceIds.add(dartId);
        visitServiceByDart[dartId] = '${s['visit_service_id'] ?? ''}';
      }
      if (serviceIds.isEmpty) continue;

      final controller = VisitDetailsController(serviceIds: serviceIds);

      final serviceData = <String, Map<String, dynamic>>{
        for (final id in serviceIds) id: <String, dynamic>{},
      };
      final visitVitals = await _detailsInto(serviceData, visitServiceByDart);

      controller.hydrate(
        serviceData: serviceData,
        visitVitals: visitVitals,
        restoredMedicines: medicinesByVisit[entry.key],
      );

      for (final s in entry.value) {
        final draft =
            controller.draftFor(byType['${s['service_type_id'] ?? ''}'] ?? '');
        if (draft == null) continue;
        final stored = _statusByLabel('${s['status'] ?? ''}');
        if (stored != null) draft.status = stored;
      }

      out[entry.key] = controller;
    }
    return _withRecentSaved(out, visitIds);
  }

  static Future<Map<String, List<MedicineDose>>> _medicinesForVisits(
      List<String> visitIds) async {
    final out = <String, List<MedicineDose>>{};
    if (visitIds.isEmpty) return out;

    List<dynamic> services;
    try {
      services = await supabaseClient
          .from('medication_services')
          .select('medication_service_id, visit_id')
          .inFilter('visit_id', visitIds);
    } catch (_) {
      return out;
    }
    if (services.isEmpty) return out;

    final serviceVisit = <String, String>{};
    final serviceIds = <String>[];
    for (final s in services) {
      final id = '${s['medication_service_id'] ?? ''}';
      final visitId = '${s['visit_id'] ?? ''}';
      if (id.isEmpty || visitId.isEmpty) continue;
      serviceVisit[id] = visitId;
      serviceIds.add(id);
      out.putIfAbsent(visitId, () => []);
    }

    List<dynamic> items;
    try {
      items = await supabaseClient
          .from('medication_service_items')
          .select('medication_service_id, medicine_id, quantity, '
              'frequency, action, response, notes')
          .inFilter('medication_service_id', serviceIds);
    } catch (_) {
      return out;
    }

    final medicineIds = <int>{
      for (final it in items)
        if ((it['medicine_id'] as num?)?.toInt() case final int id) id,
    };
    final names = <int, String>{};
    if (medicineIds.isNotEmpty) {
      try {
        final meds = await supabaseClient
            .from('medicines')
            .select('id, name')
            .inFilter('id', medicineIds.toList());
        for (final m in meds) {
          names[(m['id'] as num?)?.toInt() ?? 0] = '${m['name'] ?? ''}';
        }
      } catch (_) {}
    }

    for (final it in items) {
      final visitId = serviceVisit['${it['medication_service_id'] ?? ''}'];
      if (visitId == null) continue;
      final medicineId = (it['medicine_id'] as num?)?.toInt();
      out[visitId]!.add(MedicineDose(
        medicineId: medicineId,
        name: names[medicineId] ?? '',
        quantity: (it['quantity'] as num?)?.toInt(),
        frequency: '${it['frequency'] ?? ''}',
        action: '${it['action'] ?? ''}',
        response: '${it['response'] ?? ''}',
        notes: '${it['notes'] ?? ''}',
      ));
    }
    return out;
  }

  static ServiceDraftStatus? _statusByLabel(String label) {
    for (final s in ServiceDraftStatus.values) {
      if (s.label == label) return s;
    }
    return null;
  }

  static Future<void> saveAll({
    required String visitId,
    required VisitDetailsController controller,
    String userName = '',
  }) async {
    final drafts = controller.drafts;
    if (drafts.isEmpty) return;

    final touched = drafts
        .where((d) =>
            d.status != ServiceDraftStatus.notStarted ||
            d.data.isNotEmpty ||
            d.medicines.isNotEmpty)
        .toList();
    if (touched.isEmpty) return;

    final typeIds = await _serviceTypeIds();
    if (typeIds.isEmpty) return;

    final performedBy = supabaseClient.auth.currentUser?.id ?? '';

    String? medicationServiceId;
    final visitServiceByDart = <String, String>{};
    for (final d in touched) {
      final code = _serviceCodeByDartId[d.serviceId];
      final typeId = code == null ? null : typeIds[code];
      if (typeId == null) continue;

      d.refreshStatus();
      final completedAt =
          d.isComplete ? DateTime.now().toUtc().toIso8601String() : null;

      Map<String, dynamic>? existing;
      try {
        existing = await supabaseClient
            .from('clinic_visit_services')
            .select('visit_service_id')
            .eq('visit_id', visitId)
            .eq('service_type_id', typeId)
            .maybeSingle();
      } catch (_) {}

      if (existing != null) {
        final id = '${existing['visit_service_id']}';
        await supabaseClient.from('clinic_visit_services').update({
          'status': d.status.label,
          'performed_by': performedBy,
          if (completedAt != null) 'completed_at': completedAt,
        }).eq('visit_service_id', id);
        visitServiceByDart[d.serviceId] = id;
        if (d.serviceId == 'medication') medicationServiceId = id;
      } else {
        final inserted = await supabaseClient
            .from('clinic_visit_services')
            .insert({
              'visit_id': visitId,
              'service_type_id': typeId,
              'status': d.status.label,
              'performed_by': performedBy,
              if (completedAt != null) 'completed_at': completedAt,
            })
            .select('visit_service_id')
            .single();
        final id = '${inserted['visit_service_id']}';
        visitServiceByDart[d.serviceId] = id;
        if (d.serviceId == 'medication') medicationServiceId = id;
      }
    }

    for (final entry in visitServiceByDart.entries) {
      final draft = controller.draftFor(entry.key);
      if (draft == null) continue;
      await saveServiceRecord(
        visitServiceId: entry.value,
        visitId: visitId,
        dartServiceId: entry.key,
        d: draft,
        vitals: controller.vitals,
        recordedBy: performedBy,
      );
    }

    await _saveMedications(visitId, controller, medicationServiceId);

    try {
      _recentSaved[visitId] = _snapshotOf(controller);

      while (_recentSaved.length > 100) {
        _recentSaved.remove(_recentSaved.keys.first);
      }
    } catch (_) {}
    DataTracker.bump();
  }

  static Future<void> _saveMedications(
    String visitId,
    VisitDetailsController controller,
    String? medicationServiceId,
  ) async {
    final med = controller.draftFor('medication');
    if (med == null || medicationServiceId == null) return;

    final rows = med.medicines.where((m) => m.medicineId != null).toList();

    String? headerId;
    try {
      final existing = await supabaseClient
          .from('medication_services')
          .select('medication_service_id')
          .eq('visit_service_id', medicationServiceId)
          .maybeSingle();
      if (existing != null) {
        headerId = '${existing['medication_service_id']}';
      } else {
        final inserted = await supabaseClient
            .from('medication_services')
            .insert({
              'visit_service_id': medicationServiceId,
              'visit_id': visitId,
            })
            .select('medication_service_id')
            .single();
        headerId = '${inserted['medication_service_id']}';
      }
    } catch (_) {
      return;
    }

    final previously = <int, int>{};
    try {
      final oldItems = await supabaseClient
          .from('medication_service_items')
          .select('medicine_id, quantity, action')
          .eq('medication_service_id', headerId);
      for (final o in oldItems) {
        final id = (o['medicine_id'] as num?)?.toInt();
        if (id == null || !_deductsStock('${o['action'] ?? ''}')) continue;
        previously[id] =
            (previously[id] ?? 0) + ((o['quantity'] as num?)?.toInt() ?? 0);
      }
    } catch (_) {}

    final now = <int, int>{};
    for (final m in rows) {
      if (!_deductsStock(m.action)) continue;
      now[m.medicineId!] = (now[m.medicineId!] ?? 0) + (m.quantity ?? 0);
    }

    try {
      await supabaseClient
          .from('medication_service_items')
          .delete()
          .eq('medication_service_id', headerId);
      if (rows.isNotEmpty) {
        await supabaseClient.from('medication_service_items').insert([
          for (final m in rows)
            {
              'medication_service_id': headerId,
              'medicine_id': m.medicineId,
              'quantity': m.quantity ?? 0,
              'frequency':
                  m.frequency.trim().isEmpty ? null : m.frequency.trim(),
              'action': m.action.trim().isEmpty ? null : m.action.trim(),
              'response': m.response.trim().isEmpty ? null : m.response.trim(),
              'notes': m.notes.trim().isEmpty ? null : m.notes.trim(),
            },
        ]);
      }
    } catch (_) {}

    for (final id in {...previously.keys, ...now.keys}) {
      final delta = (now[id] ?? 0) - (previously[id] ?? 0);
      if (delta == 0) continue;
      try {
        final row = await supabaseClient
            .from('medicines')
            .select('id, stock')
            .eq('id', id)
            .maybeSingle();
        if (row == null) continue;
        final current = (row['stock'] as num?)?.toInt() ?? 0;
        final target = current - delta < 0 ? 0 : current - delta;
        await supabaseClient
            .from('medicines')
            .update({'stock': target}).eq('id', id);
      } catch (_) {}
    }
  }

  static Future<void> removeServices({
    required String visitId,
    required List<String> serviceIds,
  }) async {
    if (serviceIds.isEmpty) return;

    final typeIds = await _serviceTypeIds();
    if (typeIds.isEmpty) return;

    for (final serviceId in serviceIds) {
      final code = _serviceCodeByDartId[serviceId];
      final typeId = code == null ? null : typeIds[code];
      if (typeId == null) continue;

      String? visitServiceId;
      try {
        final row = await supabaseClient
            .from('clinic_visit_services')
            .select('visit_service_id')
            .eq('visit_id', visitId)
            .eq('service_type_id', typeId)
            .maybeSingle();
        if (row == null) continue;
        visitServiceId = '${row['visit_service_id']}';
      } catch (_) {
        continue;
      }

      if (serviceId == 'medication') {
        await _returnMedicationStock(visitServiceId);
      }
      await deleteServiceRecord(
        visitServiceId: visitServiceId,
        dartServiceId: serviceId,
      );
      try {
        await supabaseClient
            .from('clinic_visit_services')
            .delete()
            .eq('visit_service_id', visitServiceId);
      } catch (e) {
        debugPrint('visit service: remove $serviceId failed: $e');
      }
    }
    DataTracker.bump();
  }

  static Future<void> _returnMedicationStock(String visitServiceId) async {
    String? headerId;
    try {
      final header = await supabaseClient
          .from('medication_services')
          .select('medication_service_id')
          .eq('visit_service_id', visitServiceId)
          .maybeSingle();
      if (header == null) return;
      headerId = '${header['medication_service_id']}';
    } catch (_) {
      return;
    }

    final taken = <int, int>{};
    try {
      final items = await supabaseClient
          .from('medication_service_items')
          .select('medicine_id, quantity, action')
          .eq('medication_service_id', headerId);
      for (final it in items) {
        if (!_deductsStock('${it['action'] ?? ''}')) continue;
        final id = (it['medicine_id'] as num?)?.toInt();
        if (id == null) continue;
        taken[id] = (taken[id] ?? 0) + ((it['quantity'] as num?)?.toInt() ?? 0);
      }
    } catch (_) {
      return;
    }

    for (final e in taken.entries) {
      if (e.value <= 0) continue;
      try {
        final row = await supabaseClient
            .from('medicines')
            .select('id, stock')
            .eq('id', e.key)
            .maybeSingle();
        if (row == null) continue;
        final current = (row['stock'] as num?)?.toInt() ?? 0;
        await supabaseClient
            .from('medicines')
            .update({'stock': current + e.value}).eq('id', e.key);
      } catch (_) {}
    }
  }

  static Future<List<HistoryRow>> historyFor(String visitorRecordNo) async {
    try {
      final visits = await supabaseClient
          .from('clinic_visits')
          .select('visit_id, visit_date, reason_for_visit')
          .eq('person_id', visitorRecordNo)
          .order('visit_date', ascending: false)
          .limit(20);
      if (visits.isEmpty) return const [];

      final serviceNames = <String, String>{};
      try {
        final types = await supabaseClient
            .from('service_types')
            .select('service_type_id, service_name');
        for (final t in types) {
          serviceNames['${t['service_type_id'] ?? ''}'] =
              '${t['service_name'] ?? ''}';
        }
      } catch (_) {}

      final byVisit = <String, List<String>>{};
      final ids = [for (final v in visits) '${v['visit_id'] ?? ''}'.trim()]
          .where((id) => id.isNotEmpty)
          .toList();
      if (ids.isNotEmpty) {
        final services = await supabaseClient
            .from('clinic_visit_services')
            .select('visit_id, service_type_id, status')
            .inFilter('visit_id', ids);
        for (final s in services) {
          final id = '${s['visit_id'] ?? ''}'.trim();
          if (id.isEmpty) continue;
          final name = serviceNames['${s['service_type_id'] ?? ''}'];
          if (name == null || name.isEmpty) continue;
          byVisit.putIfAbsent(id, () => []).add(
                name +
                    ('${s['status']}' == ServiceDraftStatus.completed.label
                        ? ''
                        : ' (incomplete)'),
              );
        }
      }

      return [
        for (final v in visits)
          HistoryRow(
            date: _pretty('${v['visit_date'] ?? ''}'),
            chiefComplaint: '${v['reason_for_visit'] ?? '—'}',
            treatment: (byVisit['${v['visit_id']}'] ?? const [])
                .join(', ')
                .ifEmpty('—'),
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  static String _pretty(String iso) {
    final d = DateTime.tryParse(iso);
    if (d == null) return iso;
    return '${d.month.toString().padLeft(2, '0')}/${d.day.toString().padLeft(2, '0')}/${d.year}';
  }
}

extension on String {
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}
