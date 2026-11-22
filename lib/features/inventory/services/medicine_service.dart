import 'package:clinicmanagementsystem/core/services/data_tracker.dart';
import 'package:clinicmanagementsystem/core/config/supabase_config.dart';

const List<String> kMedicineCategories = [
  'Pain / Fever',
  'Antibiotic',
  'Allergy',
  'Cough / Cold',
  'Stomach / Antacid',
  'Vitamins',
  'Topical / Antiseptic',
  'First Aid Supply',
  'Other',
];

const List<String> kMedicineUnits = [
  'tablet',
  'capsule',
  'ml',
  'bottle',
  'sachet',
  'tube',
  'pcs',
];

/// Batches expiring within this many days are flagged "Expiring soon".
const int kExpiringSoonDays = 60;

/// Trim + collapse repeated spaces. Use before saving or comparing names.
String normalizeName(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');

String? _dateOnly(DateTime? d) => d == null
    ? null
    : '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')}';

int? _daysUntil(DateTime? d) {
  if (d == null) return null;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  return DateTime(d.year, d.month, d.day).difference(today).inDays;
}

class DuplicateMedicineException implements Exception {
  final String name;
  DuplicateMedicineException(this.name);
  @override
  String toString() =>
      '"$name" already exists in the inventory. Use Restock to add new stock.';
}

/// Thrown when a medicine that is already part of a clinic visit record is
/// asked to be deleted.
class MedicineInUseException implements Exception {
  final String name;
  MedicineInUseException(this.name);
  @override
  String toString() =>
      'Sorry, "$name" cannot be deleted because it has already been used in '
      'a clinic visit record.';
}

// =============================================================================
//  BATCH
// =============================================================================
class MedicineBatch {
  final int? id;
  final int medicineId;
  final String? batchNo;
  final int quantity;
  final DateTime? expiryDate;
  final DateTime? receivedAt;

  const MedicineBatch({
    this.id,
    required this.medicineId,
    this.batchNo,
    required this.quantity,
    this.expiryDate,
    this.receivedAt,
  });

  factory MedicineBatch.fromSupabase(Map<String, dynamic> row) {
    final exp = row['expiry_date'];
    final rec = row['received_at'];
    return MedicineBatch(
      id: (row['id'] as num?)?.toInt(),
      medicineId: (row['medicine_id'] as num).toInt(),
      batchNo: row['batch_no'] as String?,
      quantity: (row['quantity'] as num?)?.toInt() ?? 0,
      expiryDate: exp == null ? null : DateTime.tryParse(exp.toString()),
      receivedAt: rec == null ? null : DateTime.tryParse(rec.toString()),
    );
  }

  int? get daysToExpiry => _daysUntil(expiryDate);

  /// Expired = before today (still usable ON its expiry date).
  bool get isExpired => daysToExpiry != null && daysToExpiry! < 0;

  bool get isExpiringSoon =>
      daysToExpiry != null &&
      daysToExpiry! >= 0 &&
      daysToExpiry! <= kExpiringSoonDays;
}

// =============================================================================
//  MEDICINE
// =============================================================================
class Medicine {
  final int? id;
  final String name;

  /// Total on hand (all batches, INCLUDING expired). Kept in sync by the DB.
  final int stock;
  final int maxCapacity;
  final bool isArchived;
  final String category;
  final String unit;

  /// Batches that still have quantity > 0, earliest expiry first.
  final List<MedicineBatch> batches;

  const Medicine({
    this.id,
    required this.name,
    required this.stock,
    required this.maxCapacity,
    this.isArchived = false,
    this.category = 'Other',
    this.unit = 'pcs',
    this.batches = const [],
  });

  factory Medicine.fromSupabase(Map<String, dynamic> row) {
    final raw = row['medicine_batches'];
    final list = <MedicineBatch>[];
    if (raw is List) {
      for (final r in raw) {
        final b = MedicineBatch.fromSupabase(Map<String, dynamic>.from(r));
        if (b.quantity > 0) list.add(b);
      }
      list.sort((a, b) {
        if (a.expiryDate == null && b.expiryDate == null) {
          return (a.id ?? 0).compareTo(b.id ?? 0);
        }
        if (a.expiryDate == null) return 1;
        if (b.expiryDate == null) return -1;
        return a.expiryDate!.compareTo(b.expiryDate!);
      });
    }
    return Medicine(
      id: (row['id'] as num?)?.toInt(),
      name: row['name'] as String,
      stock: (row['stock'] as num?)?.toInt() ?? 0,
      maxCapacity: (row['max_capacity'] as num?)?.toInt() ?? 0,
      isArchived: row['is_archived'] as bool? ?? false,
      category: row['category'] as String? ?? 'Other',
      unit: row['unit'] as String? ?? 'pcs',
      batches: list,
    );
  }

  Map<String, dynamic> toSupabase() => {
        if (id != null) 'id': id,
        'name': name,
        'stock': stock,
        'max_capacity': maxCapacity,
        'category': category,
        'unit': unit,
      };

  // ---------------- usable vs expired ----------------
  bool get _hasBatchData => batches.isNotEmpty;

  /// Stock that is safe to give out (expired batches excluded).
  int get usableStock => _hasBatchData
      ? batches.where((b) => !b.isExpired).fold(0, (s, b) => s + b.quantity)
      : stock;

  int get expiredStock =>
      batches.where((b) => b.isExpired).fold(0, (s, b) => s + b.quantity);

  bool get hasExpiredStock => expiredStock > 0;

  bool get isExpiringSoon => batches.any((b) => !b.isExpired && b.isExpiringSoon);

  /// Earliest expiry among batches still on hand (may already be past).
  DateTime? get nextExpiry {
    DateTime? best;
    for (final b in batches) {
      if (b.expiryDate == null) continue;
      if (best == null || b.expiryDate!.isBefore(best)) best = b.expiryDate;
    }
    return best;
  }

  MedicineBatch? get nextExpiryBatch {
    MedicineBatch? best;
    for (final b in batches) {
      if (b.expiryDate == null) continue;
      if (best == null || b.expiryDate!.isBefore(best.expiryDate!)) best = b;
    }
    return best;
  }

  // ---------------- stock level ----------------
  bool get isOutOfStock => usableStock <= 0;

  /// Low when usable stock is at or below 20% of capacity (10 if no capacity).
  int get lowThreshold =>
      maxCapacity > 0 ? (maxCapacity * 0.2).ceil() : 10;

  /// True when out of stock OR at/below the low-stock line.
  bool get isLowStock => usableStock <= 0 || usableStock <= lowThreshold;

  /// Use in the dispense screen: only usable (non-expired) stock counts.
  bool get canDispense => usableStock > 0;
}

// =============================================================================
//  SERVICE
// =============================================================================
class MedicineService {
  MedicineService._();

  static bool _isDuplicateError(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('23505') || s.contains('duplicate key');
  }

  static bool _isInUseError(Object e) {
    final s = e.toString().toLowerCase();
    return s.contains('23503') || s.contains('foreign key');
  }

  static Future<List<Medicine>> fetchAll() async {
    final rows = await supabaseClient
        .from('medicines')
        .select('*, medicine_batches(*)')
        .eq('is_archived', false)
        .order('name');
    return rows
        .map<Medicine>(
            (r) => Medicine.fromSupabase(Map<String, dynamic>.from(r)))
        .toList();
  }

  /// Creates a NEW medicine (+ its first batch if [initialQty] > 0).
  /// Throws [DuplicateMedicineException] if the name already exists.
  static Future<Medicine> create({
    required String name,
    required int maxCapacity,
    String category = 'Other',
    String unit = 'pcs',
    int initialQty = 0,
    DateTime? expiryDate,
    String? batchNo,
  }) async {
    final clean = normalizeName(name);
    Map<String, dynamic> row;
    try {
      row = Map<String, dynamic>.from(await supabaseClient
          .from('medicines')
          .insert({
            'name': clean,
            'stock': 0,
            'max_capacity': maxCapacity,
            'category': category,
            'unit': unit,
          })
          .select()
          .single());
    } catch (e) {
      if (_isDuplicateError(e)) throw DuplicateMedicineException(clean);
      rethrow;
    }

    final id = (row['id'] as num).toInt();
    if (initialQty > 0) {
      try {
        await supabaseClient.rpc('restock_medicine', params: {
          'p_medicine_id': id,
          'p_qty': initialQty,
          'p_expiry': _dateOnly(expiryDate),
          'p_batch_no': batchNo,
        });
      } catch (e) {
        // don't leave an empty orphan medicine behind
        await supabaseClient.from('medicines').delete().eq('id', id);
        rethrow;
      }
    }
    DataTracker.bump();
    return Medicine.fromSupabase(row);
  }

  /// Edits details only (name, category, unit, capacity).
  /// Stock and expiry are managed through batches.
  static Future<void> update(Medicine med) async {
    if (med.id == null) {
      throw StateError('Cannot update a medicine without a Supabase id.');
    }
    final clean = normalizeName(med.name);
    try {
      await supabaseClient.from('medicines').update({
        'name': clean,
        'max_capacity': med.maxCapacity,
        'category': med.category,
        'unit': med.unit,
      }).eq('id', med.id!);
    } catch (e) {
      if (_isDuplicateError(e)) throw DuplicateMedicineException(clean);
      rethrow;
    }
    DataTracker.bump();
  }

  /// Receive new stock. Adds a new batch, or tops up the same batch when the
  /// batch number AND expiry match one already on hand (no duplicate batches).
  static Future<void> restock({
    required Medicine med,
    required int quantity,
    DateTime? expiry,
    String? batchNo,
  }) async {
    if (med.id == null) {
      throw StateError('Cannot restock a medicine without a Supabase id.');
    }
    if (quantity <= 0) throw ArgumentError('Quantity must be greater than 0.');
    await supabaseClient.rpc('restock_medicine', params: {
      'p_medicine_id': med.id,
      'p_qty': quantity,
      'p_expiry': _dateOnly(expiry),
      'p_batch_no': batchNo,
    });
    DataTracker.bump();
  }

  /// Give out stock. Takes from the batch that expires first and never from
  /// expired batches. Throws if there isn't enough usable stock.
  static Future<void> dispense({
    required int medicineId,
    required int quantity,
  }) async {
    await supabaseClient.rpc('dispense_medicine', params: {
      'p_medicine_id': medicineId,
      'p_qty': quantity,
    });
    DataTracker.bump();
  }

  /// Correct a batch (count mistake, wrong expiry, batch number).
  static Future<void> updateBatch(MedicineBatch b) async {
    if (b.id == null) throw StateError('Batch has no id.');
    await supabaseClient.from('medicine_batches').update({
      'quantity': b.quantity,
      'expiry_date': _dateOnly(b.expiryDate),
      'batch_no': (b.batchNo ?? '').trim().isEmpty ? null : b.batchNo!.trim(),
    }).eq('id', b.id!);
    DataTracker.bump();
  }

  /// Remove a batch entirely (expired / damaged / recalled).
  static Future<void> deleteBatch(int batchId) async {
    await supabaseClient.from('medicine_batches').delete().eq('id', batchId);
    DataTracker.bump();
  }

  /// True when this medicine is already part of a clinic visit record (it was
  /// given to a visitor), so it must stay in the database.
  static Future<bool> isUsed(int medicineId) async {
    final items = await supabaseClient
        .from('medication_service_items')
        .select('medication_item_id')
        .eq('medicine_id', medicineId)
        .limit(1);
    if (items.isNotEmpty) return true;

    // Which batch each visit took from. Missing on an old database: ignore.
    try {
      final log = await supabaseClient
          .from('medicine_dispense_log')
          .select('log_id')
          .eq('medicine_id', medicineId)
          .limit(1);
      if (log.isNotEmpty) return true;
    } catch (_) {}
    return false;
  }

  /// Deletes a medicine that was never used in a clinic visit.
  /// Throws [MedicineInUseException] when it has been used (nothing is
  /// deleted). The database enforces the same rule as a second safety net.
  static Future<void> deleteUnused(int medicineId, String name) async {
    if (await isUsed(medicineId)) throw MedicineInUseException(name);
    try {
      await supabaseClient.from('medicines').delete().eq('id', medicineId);
    } catch (e) {
      if (_isInUseError(e)) throw MedicineInUseException(name);
      rethrow;
    }
    DataTracker.bump();
  }

  /// Plain delete with no usage check. Prefer [deleteUnused].
  static Future<void> delete(int id) async {
    await supabaseClient.from('medicines').delete().eq('id', id);
    DataTracker.bump();
  }

  static Future<void> seedIfEmpty() async {
    try {
      final rows = await supabaseClient.from('medicines').select('id').limit(1);
      if (rows.isNotEmpty) return;

      final now = DateTime.now();
      DateTime inMonths(int m) => DateTime(now.year, now.month + m, now.day);

      final seed = <Map<String, dynamic>>[
        {
          'name': 'Paracetamol 500mg', 'max': 300,
          'category': 'Pain / Fever', 'unit': 'tablet',
          'batches': [
            [48, inMonths(2), 'PC-A'],
            [100, inMonths(14), 'PC-B'],
          ],
        },
        {
          'name': 'Amoxicillin 500mg', 'max': 100,
          'category': 'Antibiotic', 'unit': 'capsule',
          'batches': <List<dynamic>>[],
        },
        {
          'name': 'Cetirizine 10mg', 'max': 100,
          'category': 'Allergy', 'unit': 'tablet',
          'batches': [
            [85, inMonths(1), 'CT-01'],
          ],
        },
        {
          'name': 'Mefenamic Acid 500mg', 'max': 50,
          'category': 'Pain / Fever', 'unit': 'capsule',
          'batches': [
            [5, inMonths(7), 'MA-01'],
          ],
        },
        {
          'name': 'Ascorbic Acid 500mg', 'max': 200,
          'category': 'Vitamins', 'unit': 'tablet',
          'batches': [
            [190, inMonths(18), 'AA-01'],
          ],
        },
        {
          'name': 'Adhesive Bandage', 'max': 200,
          'category': 'First Aid Supply', 'unit': 'pcs',
          'batches': [
            [120, null, null],
          ],
        },
      ];

      final inserted = await supabaseClient
          .from('medicines')
          .insert(seed
              .map((s) => {
                    'name': s['name'],
                    'stock': 0,
                    'max_capacity': s['max'],
                    'category': s['category'],
                    'unit': s['unit'],
                  })
              .toList())
          .select('id,name');

      final idByName = {
        for (final r in inserted) r['name'] as String: (r['id'] as num).toInt()
      };

      final batchRows = <Map<String, dynamic>>[];
      for (final s in seed) {
        for (final b in (s['batches'] as List)) {
          batchRows.add({
            'medicine_id': idByName[s['name']],
            'quantity': b[0],
            'expiry_date': _dateOnly(b[1] as DateTime?),
            'batch_no': b[2],
          });
        }
      }
      if (batchRows.isNotEmpty) {
        await supabaseClient.from('medicine_batches').insert(batchRows);
      }
    } catch (_) {}
  }
}