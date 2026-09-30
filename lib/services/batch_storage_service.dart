import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/batch.dart';
import '../models/scanned_item.dart';

class BatchStorageService {
  static const String _batchesKey = 'saved_batches';

  // Save a batch
  static Future<void> saveBatch(Batch batch) async {
    final prefs = await SharedPreferences.getInstance();
    final batches = await getBatches();
    batches.add(batch);
    final batchesJson = batches.map((b) => b.toJson()).toList();
    await prefs.setString(_batchesKey, jsonEncode(batchesJson));
  }

  // Get all batches
  static Future<List<Batch>> getBatches() async {
    final prefs = await SharedPreferences.getInstance();
    final String? batchesJson = prefs.getString(_batchesKey);
    if (batchesJson == null) return [];
    final List<dynamic> decoded = jsonDecode(batchesJson);
    return decoded.map((e) => Batch.fromJson(e)).toList();
  }

  // Remove a batch
  static Future<void> removeBatch(String batchId) async {
    final prefs = await SharedPreferences.getInstance();
    final batches = await getBatches();
    batches.removeWhere((b) => b.id == batchId);
    final batchesJson = batches.map((b) => b.toJson()).toList();
    await prefs.setString(_batchesKey, jsonEncode(batchesJson));
  }

  // Remove multiple batches
  static Future<void> removeBatches(List<String> batchIds) async {
    final prefs = await SharedPreferences.getInstance();
    final batches = await getBatches();
    batches.removeWhere((b) => batchIds.contains(b.id));
    final batchesJson = batches.map((b) => b.toJson()).toList();
    await prefs.setString(_batchesKey, jsonEncode(batchesJson));
  }

  // Update batch sync status
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

  // ✅ Update the item list of an existing, already-saved batch (used when
  // deleting or editing an article from inside "Lots sauvegardés"). Without
  // this, changes only lived in memory and reverted the moment the page
  // was reopened, since it re-reads from storage via getBatches().
  static Future<void> updateBatchItems(String batchId, List<ScannedItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    final batches = await getBatches();
    final index = batches.indexWhere((b) => b.id == batchId);
    if (index != -1) {
      batches[index].items.clear();
      batches[index].items.addAll(items);
      final batchesJson = batches.map((b) => b.toJson()).toList();
      await prefs.setString(_batchesKey, jsonEncode(batchesJson));
    }
  }

  // Clear all batches
  static Future<void> clearAllBatches() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_batchesKey);
  }
}