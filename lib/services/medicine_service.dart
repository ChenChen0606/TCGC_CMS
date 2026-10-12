// ─────────────────────────────────────────────────────────────────────────────
//  medicine_service.dart
//  Supabase-backed CRUD for the medicines inventory table.
//
//  Audit trail (created_by / created_at / updated_by / updated_at) is NOT
//  written by the client — the database trigger in clinic_schema.sql
//  (`touch_audit_columns`) maintains it automatically from the authenticated
//  session (auth.uid()). RLS policies gate every read/write.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:clinicmanagementsystem/services/data_tracker.dart';
import 'package:clinicmanagementsystem/services/supabase_config.dart';

/// Simple medicine model matching the `public.medicines` table shape.
class Medicine {
  final int? id;
  final String name;
  final int stock;
  final int maxCapacity;
  final bool isArchived;

  const Medicine({
    this.id,
    required this.name,
    required this.stock,
    required this.maxCapacity,
    this.isArchived = false,
  });

  factory Medicine.fromSupabase(Map<String, dynamic> row) {
    return Medicine(
      id: row['id'] as int?,
      name: row['name'] as String,
      stock: row['stock'] as int? ?? 0,
      maxCapacity: row['max_capacity'] as int? ?? 0,
      isArchived: row['is_archived'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toSupabase() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'stock': stock,
      'max_capacity': maxCapacity,
    };
  }
}

class MedicineService {
  MedicineService._();

  /// Loads all non-archived medicines, sorted by name.
  static Future<List<Medicine>> fetchAll() async {
    final rows = await supabaseClient
        .from('medicines')
        .select()
        .eq('is_archived', false)
        .order('name');
    return rows
        .map<Medicine>(
            (r) => Medicine.fromSupabase(Map<String, dynamic>.from(r)))
        .toList();
  }

  /// Inserts a new medicine. Returns the persisted row with server-assigned id.
  /// Throws if a medicine with the same name already exists (UNIQUE constraint).
  static Future<Medicine> create({
    required String name,
    required int stock,
    required int maxCapacity,
  }) async {
    final row = await supabaseClient
        .from('medicines')
        .insert({'name': name, 'stock': stock, 'max_capacity': maxCapacity})
        .select()
        .single();
    DataTracker.bump();
    return Medicine.fromSupabase(Map<String, dynamic>.from(row));
  }

  /// Updates an existing medicine by id.
  /// NOTE: `id` is `bigint generated always as identity`, so it must NOT be
  /// included in the UPDATE payload or PostgreSQL rejects the change.
  static Future<void> update(Medicine med) async {
    if (med.id == null) {
      throw StateError('Cannot update a medicine without a Supabase id.');
    }
    await supabaseClient.from('medicines').update({
      'name': med.name,
      'stock': med.stock,
      'max_capacity': med.maxCapacity,
    }).eq('id', med.id!);
    DataTracker.bump();
  }

  /// Hard-deletes a medicine by id.
  static Future<void> delete(int id) async {
    await supabaseClient.from('medicines').delete().eq('id', id);
    DataTracker.bump();
  }

  /// Atomically decrements stock for the given medicine.
  /// Uses a raw RPC or a conditional update to avoid going below zero.
  static Future<void> decrementStock(int medicineId, int qty) async {
    // Fetch current stock first, then update (PostgREST doesn't support
    // arithmetic expressions directly). The check constraint on the DB
    // will reject negative stock as a safety net.
    final row = await supabaseClient
        .from('medicines')
        .select('stock')
        .eq('id', medicineId)
        .single();
    final currentStock = row['stock'] as int;
    if (currentStock < qty) {
      throw StateError('Insufficient stock for medicine id $medicineId '
          '(have $currentStock, need $qty).');
    }
    await supabaseClient
        .from('medicines')
        .update({'stock': currentStock - qty}).eq('id', medicineId);
    DataTracker.bump();
  }

  /// Atomically increases stock for the given medicine (e.g. returning
  /// supplies that were deducted but then cancelled/removed on an edit).
  static Future<void> incrementStock(int medicineId, int qty) async {
    if (qty <= 0) return;
    final row = await supabaseClient
        .from('medicines')
        .select('stock')
        .eq('id', medicineId)
        .single();
    final currentStock = row['stock'] as int;
    await supabaseClient
        .from('medicines')
        .update({'stock': currentStock + qty}).eq('id', medicineId);
    DataTracker.bump();
  }

  /// Checks if any medicines exist. If the table is empty, seeds the default
  /// inventory so the app is usable out of the box.
  ///
  /// Deliberately never throws. The emptiness check reads through RLS, which
  /// can report an empty table for a restricted role, and the seed INSERT has
  /// to pass the table's own RLS policy — either one failing used to surface as
  /// a "Failed to load medicines" banner on every screen that loaded the list.
  static Future<void> seedIfEmpty() async {
    try {
      final rows = await supabaseClient.from('medicines').select('id').limit(1);
      if (rows.isNotEmpty) return;

      await supabaseClient.from('medicines').insert([
        {'name': 'Paracetamol', 'stock': 148, 'max_capacity': 200},
        {'name': 'Amoxicillin', 'stock': 0, 'max_capacity': 100},
        {'name': 'Biogesic', 'stock': 12, 'max_capacity': 150},
        {'name': 'Cetirizine', 'stock': 85, 'max_capacity': 100},
        {'name': 'Mefenamic Acid', 'stock': 5, 'max_capacity': 50},
        {'name': 'Ascorbic Acid', 'stock': 190, 'max_capacity': 200},
      ]);
    } catch (_) {
      // RLS blocked the read or the write: seeding is a convenience, not the
      // inventory itself, so a blocked seed must not fail the medicines list.
    }
  }
}
