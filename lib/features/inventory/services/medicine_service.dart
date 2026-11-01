import 'package:clinicmanagementsystem/core/services/data_tracker.dart';
import 'package:clinicmanagementsystem/core/config/supabase_config.dart';

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

  bool get isOutOfStock => stock <= 0;

  bool get isLowStock {
    if (stock <= 0) return true;
    if (maxCapacity > 0) return stock <= (maxCapacity * 0.2).ceil();
    return stock <= 10;
  }
}

class MedicineService {
  MedicineService._();

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

  static Future<void> delete(int id) async {
    await supabaseClient.from('medicines').delete().eq('id', id);
    DataTracker.bump();
  }

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
    } catch (_) {}
  }
}
