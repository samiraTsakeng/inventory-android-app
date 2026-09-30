import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/batch.dart';
import '../models/scanned_item.dart';

class BatchStorageService {
  static const String _batchesKey = 'saved_batches';

  static Future<void> saveBatch(Batch batch) async {
    final prefs = await SharedPreferences.getInstance();
    final batches = await getBatches();
    batches.add(batch);
    final batchesJson = batches.map((b) => b.toJson()).toList();
    await prefs.setString(_batchesKey, jsonEncode(batchesJson));
  }

  static Future<List<Batch>> getBatches() async {
    final prefs = await SharedPreferences.getInstance();
    final String? batchesJson = prefs.getString(_batchesKey);
    if (batchesJson == null) return [];
    final List<dynamic> decoded = jsonDecode(batchesJson);
    return decoded.map((e) => Batch.fromJson(e)).toList();
  }

  static Future<void> removeBatch(String batchId) async {
    final prefs = await SharedPreferences.getInstance();
    final batches = await getBatches();
    batches.removeWhere((b) => b.id == batchId);
    final batchesJson = batches.map((b) => b.toJson()).toList();
    await prefs.setString(_batchesKey, jsonEncode(batchesJson));
  }

  static Future<void> removeBatches(List<String> batchIds) async {
    final prefs = await SharedPreferences.getInstance();
    final batches = await getBatches();
    batches.removeWhere((b) => batchIds.contains(b.id));
    final batchesJson = batches.map((b) => b.toJson()).toList();
    await prefs.setString(_batchesKey, jsonEncode(batchesJson));
  }

  static Future<void> markBatchAsSynced(String batchId) async {
    final prefs = await SharedPreferences.getInstance();
    final batches = await getBatches();
    final index = batches.indexWhere((b) => b.id == batchId);
    if (index != -1) {
      batches[index].isSynced = true;
      final batchesJson = batches.map((b) => b.toJson()).toList();
      await prefs.setString(_batchesKey, jsonEncode(batchesJson));
    }
  }

  // ✅ NEW: replace the items of a saved batch (used when editing
  // quantities/deleting items from the scanned-items list opened from a
  // saved batch).
  static Future<void> updateBatchItems(String batchId, List<ScannedItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    final batches = await getBatches();
    final index = batches.indexWhere((b) => b.id == batchId);
    if (index != -1) {
      batches[index].items
        ..clear()
        ..addAll(items);
      final batchesJson = batches.map((b) => b.toJson()).toList();
      await prefs.setString(_batchesKey, jsonEncode(batchesJson));
    }
  }

  static Future<void> clearAllBatches() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_batchesKey);
  }
}