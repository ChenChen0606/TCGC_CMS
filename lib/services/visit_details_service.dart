// ============================================================================
//  visit_details_service.dart
//  Reading and writing what step 3 collects.
//
//  Persistence is against the live schema that the clinic actually selves on:
//  every worked service gets one row on `clinic_visit_services` (keyed to a
//  `service_types` row by `service_type_id`), and the prescription is written
//  to `medication_services` + `medication_service_items`. Stock is deducted
//  from `medicines` only for the lines that were actually administered.
//
//  The tables this app used to write (`visit_services`, `visit_vitals`,
//  `visit_medications`, `vitals_config`, `templates`, `documents`) no longer
//  exist in the database, so nothing in this file targets them any more. The
//  certificate flow that depended on `templates`/`documents` is gone with them.
//
//  A read that fails returns an empty result rather than throwing. Step 3 is a
//  form, not a report: a network blip must cost the nurse the data she has
//  already typed into the form in front of her, never the whole step.
// ============================================================================

import 'package:clinicmanagementsystem/core/certificate_engine.dart';
import 'package:clinicmanagementsystem/core/visit_details.dart';
import 'package:clinicmanagementsystem/core/vitals.dart';
import 'package:clinicmanagementsystem/services/data_tracker.dart';
import 'package:clinicmanagementsystem/services/service_detail_records.dart';
import 'package:clinicmanagementsystem/services/supabase_config.dart';

/// The service that `.from('clinic_visit_services')` calls in the Dart client
/// map to their `service_types.service_code` counterparts. Every one of these
/// codes exists as a seeded row in `service_types`.
const Map<String, String> _serviceCodeByDartId = {
  'bp_tracking': 'BP_TAKING',
  'temperature_checking': 'TEMP_CHECKING',
  'bpi': 'BMI',
  'wound_dressing': 'WOUND_DRESSING',
  'first_aid_treatment': 'FIRST_AID',
  'health_counselling': 'COUNSELLING',
  'prenatal': 'PRENATAL',
  'medication': 'MEDICATION',
  'medicine_consultation': 'MED_CONSULT',
  'medicine_certificate': 'MED_CERT',
  'medical_clearance': 'MED_CLEAR',
  'vital_signs': 'VITAL_SIGNS',
};

/// The reverse: a `service_types.service_type_id` back to the Dart service id,
/// used when a saved visit is read back.
Map<String, String> _dartIdByServiceType(Map<String, String> codeById) {
  final out = <String, String>{};
  for (final e in _serviceCodeByDartId.entries) {
    final id = codeById[e.value];
    if (id != null) out[id] = e.key;
  }
  return out;
}

/// A `service_types` lookup as code -> service_type_id.
///
/// Read once and reused for the whole save/read cycle. When it cannot be read,
/// an empty map means "no service rows can be written", which is honest.
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

/// Which medication `action`s pull stock at save time. Anything else was
/// prescribed but not administered, and must not deduct.
bool _deductsStock(String action) =>
    action == 'Given' || action == 'Partially Given';

class VisitDetailsService {
  VisitDetailsService._();

  // ── LOADING A VISIT BACK ────────────────────────────────────────────────

  /// Fills [controller] with what is already on the server for [visitId], so a
  /// visit that is being resumed shows what was recorded rather than blanks.
  ///
  /// Each table is read on its own and a failure of one is logged and skipped:
  /// a missing `medication_services` row must not cost the nurse the service
  /// statuses that are there.
  static Future<void> hydrate({
    required String visitId,
    required VisitDetailsController controller,
  }) async {
    final serviceData = <String, Map<String, dynamic>>{};
    final slideIndexes = <String, int>{};
    final visitServiceByDart = <String, String>{};
    final codesById = <String, String>{};

    try {
      final types = await supabaseClient
          .from('service_types')
          .select('service_type_id, service_code');
      for (final t in types) {
        codesById['${t['service_type_id'] ?? ''}'] =
            '${t['service_code'] ?? ''}';
      }
    } catch (_) {
      // No service types means nothing below has a name; leave the drafts empty.
    }

    try {
      final rows = await supabaseClient
          .from('clinic_visit_services')
          .select('visit_service_id, service_type_id, status')
          .eq('visit_id', visitId);
      final byType = _dartIdByServiceType(codesById);
      for (final row in rows) {
        final dartId = byType['${row['service_type_id'] ?? ''}'];
        if (dartId == null) continue;
        serviceData[dartId] = {};
        visitServiceByDart[dartId] = '${row['visit_service_id'] ?? ''}';
        // A service that is already complete is a resume, not a new start, so
        // the nurse is put on the first slide that still needs something.
        if ('${row['status']}' == ServiceDraftStatus.completed.label) {
          slideIndexes[dartId] = 0;
        }
      }
    } catch (_) {
      // Leave the drafts empty; the form is still fully usable.
    }

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

  /// Merges a visit's detail-table rows into [serviceData] (the form field
  /// maps the drafts will load) and lifts whatever vitals they hold into one
  /// [VisitVitals].
  ///
  /// Detail rows are the only record of what a service actually collected —
  /// `clinic_visit_services` says a service was done, not what it found — and
  /// the shared readings (BP, pulse, temperature, height, weight) live in those
  /// rows rather than a `visit_vitals` table, so a resumed visit rebuilds them
  /// from whatever BP / temperature / BMI / vital-signs rows it has. Null when
  /// nothing was measured.
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
      liftVitalsFromRows([row], vitals ??= VisitVitals());
    }
    return vitals;
  }

  /// Reads a set of saved visits back as [VisitDetailsController]s — the same
  /// object the Clinic Visit wizard holds while it is writing step 3, and
  /// therefore the same object step 4 renders.
  ///
  /// Keyed by visit id. Two reads for the whole page, not two per row: the
  /// Records Booklet needs a service list and a status on every row it draws.
  ///
  /// A visit with nothing on `clinic_visit_services` is absent from the map
  /// rather than mapped to an empty controller. "No services were recorded" and
  /// "this row is not a visit" are different facts, and the booklet says the
  /// first out loud.
  static Future<Map<String, VisitDetailsController>> readVisits(
      List<String> visitIds) async {
    if (visitIds.isEmpty) return const {};

    Map<String, String> codesById;
    try {
      final types = await supabaseClient
          .from('service_types')
          .select('service_type_id, service_code');
      codesById = {
        for (final t in types)
          '${t['service_type_id'] ?? ''}': '${t['service_code'] ?? ''}',
      };
    } catch (_) {
      return const {};
    }
    final byType = _dartIdByServiceType(codesById);

    List<dynamic> serviceRows;
    try {
      serviceRows = await supabaseClient
          .from('clinic_visit_services')
          .select(
              'visit_id, visit_service_id, service_type_id, status, created_at')
          .inFilter('visit_id', visitIds)
          .order('created_at');
    } catch (_) {
      return const {};
    }
    if (serviceRows.isEmpty) return const {};

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

      // `hydrate` re-derives every status from the answers it can see. What the
      // nurse actually left the form in is the stored column, and that is the
      // truth about a saved record.
      for (final s in entry.value) {
        final draft =
            controller.draftFor(byType['${s['service_type_id'] ?? ''}'] ?? '');
        if (draft == null) continue;
        final stored = _statusByLabel('${s['status'] ?? ''}');
        if (stored != null) draft.status = stored;
      }

      out[entry.key] = controller;
    }
    return out;
  }

  /// The prescription lines of a set of visits, keyed by visit id.
  ///
  /// `medication_services` links a visit to its lines (`visit_id` holds the
  /// visit, `visit_service_id` ties the prescription to the Medication service
  /// row it belongs to). Medicine names are resolved from `medicines` so a
  /// resumed form prints real names rather than blank rows.
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
          .select('medication_service_id, medicine_id, dose, quantity, unit, '
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
      } catch (_) {
        // Names are cosmetic; the lines still restore.
      }
    }

    for (final it in items) {
      final visitId = serviceVisit['${it['medication_service_id'] ?? ''}'];
      if (visitId == null) continue;
      final medicineId = (it['medicine_id'] as num?)?.toInt();
      out[visitId]!.add(MedicineDose(
        medicineId: medicineId,
        name: names[medicineId] ?? '',
        unit: '${it['unit'] ?? ''}',
        quantity: (it['quantity'] as num?)?.toInt(),
        dose: '${it['dose'] ?? ''}',
        frequency: '${it['frequency'] ?? ''}',
        action: '${it['action'] ?? ''}',
        response: '${it['response'] ?? ''}',
        notes: '${it['notes'] ?? ''}',
      ));
    }
    return out;
  }

  /// The stored state, by the label it was stored under, or null when the label
  /// is not one this build knows — in which case the re-derived status stands
  /// rather than the service being shown as nothing at all.
  static ServiceDraftStatus? _statusByLabel(String label) {
    for (final s in ServiceDraftStatus.values) {
      if (s.label == label) return s;
    }
    return null;
  }

  // ── SAVING ──────────────────────────────────────────────────────────────

  /// Writes the whole of step 3 for [visitId].
  ///
  /// Every touched service is written on every save rather than only the one
  /// that changed. A visit has at most a dozen services and a nurse makes a
  /// handful of saves, so the simplicity is worth more than the write count —
  /// and it means a service can never be left holding answers that only exist
  /// in memory if the save is interrupted.
  ///
  /// Each worked service becomes a `clinic_visit_services` row. The Dart
  /// service id ("medication", "bp_tracking", …) maps to `service_types`
  /// through the code map above, so the row links the visit to the right type.
  /// Services that have no type ("Other") are left without a row: the database
  /// requires a `service_type_id` and there is no honest value to invent.
  static Future<void> saveAll({
    required String visitId,
    required VisitDetailsController controller,
    String userName = '',
  }) async {
    final drafts = controller.drafts;
    if (drafts.isEmpty) return;

    // A service with nothing in it gets no row. `clinic_visit_services` is a
    // record of services that were actually worked on, and a row saying "Not
    // Started" for all twelve services would be a worse record than none.
    final touched = drafts
        .where((d) =>
            d.status != ServiceDraftStatus.notStarted ||
            d.data.isNotEmpty ||
            d.medicines.isNotEmpty)
        .toList();
    if (touched.isEmpty) return;

    final typeIds = await _serviceTypeIds();
    if (typeIds.isEmpty) return;

    // `clinic_visit_services.performed_by` is NOT NULL with no default, so it
    // has to carry the signed-in user's id (auth == useraccount.user_id), the
    // same stamp the visit header uses for `created_by`.
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

      // `clinic_visit_services` has no natural upsert key — `visit_service_id`
      // is a server-generated uuid — so the row is found by (visit, type) and
      // updated, or inserted when a visit is saved before the row exists.
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

    // Each worked service also records WHAT it collected, in its own detail
    // table. One row per service, keyed by the row just written above.
    for (final entry in visitServiceByDart.entries) {
      final draft = controller.draftFor(entry.key);
      if (draft == null) continue;
      await saveServiceRecord(
        visitServiceId: entry.value,
        visitId: visitId,
        dartServiceId: entry.key,
        d: draft,
        vitals: controller.vitals,
      );
    }

    await _saveMedications(visitId, controller, medicationServiceId);
    DataTracker.bump();
  }

  /// Replaces the visit's prescription wholesale and moves the stock to match.
  ///
  /// The medication lines live in `medication_services` (one row per visit,
  /// tied to the visit and to its Medication service) and
  /// `medication_service_items` (one row per medicine). Delete-then-insert
  /// rather than a diff: the list is a handful of rows, it is the only list on
  /// the visit, and a diff is the kind of code that quietly loses a line when
  /// two rows are edited in the same session.
  ///
  /// Stock is adjusted by the NET movement only for lines that were actually
  /// administered (Given / Partially Given), and only for +delta between the
  /// previous prescription on this visit and the new one — so saving the same
  /// visit twice with the same medicine moves nothing, and removing a line
  /// hands the stock back. `quantity` is clamped at 0; a shortfall is visible
  /// in the inventory rather than failing the save.
  static Future<void> _saveMedications(
    String visitId,
    VisitDetailsController controller,
    String? medicationServiceId,
  ) async {
    final med = controller.draftFor('medication');
    if (med == null || medicationServiceId == null) return;

    final rows = med.medicines.where((m) => m.medicineId != null).toList();

    // Find (or create) the `medication_services` header for this visit's
    // Medication service row.
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

    // The quantities this visit already deducted, so the net movement is the
    // difference between the two prescriptions rather than a fresh deduction
    // every time.
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
    } catch (_) {
      // Unknown previous state; the new prescription still saves.
    }

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
              'dose': m.dose.trim().isEmpty ? null : m.dose.trim(),
              'quantity': m.quantity ?? 0,
              'unit': m.unit.trim().isEmpty ? null : m.unit.trim(),
              'frequency':
                  m.frequency.trim().isEmpty ? null : m.frequency.trim(),
              'action': m.action.trim().isEmpty ? null : m.action.trim(),
              'response': m.response.trim().isEmpty ? null : m.response.trim(),
              'notes': m.notes.trim().isEmpty ? null : m.notes.trim(),
            },
        ]);
      }
    } catch (_) {
      // The prescription stays in memory if the write fails; the visit is saved.
    }

    for (final id in {...previously.keys, ...now.keys}) {
      final delta = (previously[id] ?? 0) - (now[id] ?? 0);
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
      } catch (_) {
        // One bad line must not stop the rest of the prescription saving.
      }
    }
  }

  // ── THE DRAWER ──────────────────────────────────────────────────────────

  /// The person's visit history, for the drawer. Each row is the date, what
  /// they came in with, and what was done — the three columns the Individual
  /// Clients Record prints.
  ///
  /// Read through `clinic_visit_services` rather than off `clinic_visits`,
  /// because `clinic_visits.reason_for_visit` is the complaint the nurse typed,
  /// not what was actually done to the visitor, and the record is meant to say
  /// the second. Service display names come from `service_types`.
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
  /// `''` to a dash, so an empty list joined to nothing reads as "nothing
  /// recorded" rather than as a blank cell in a record.
  String ifEmpty(String fallback) => trim().isEmpty ? fallback : this;
}
