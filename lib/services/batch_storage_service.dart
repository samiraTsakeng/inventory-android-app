import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/batch.dart';
import '../models/scanned_item.dart';

class BatchStorageService {
  static const String _batchesKey = 'saved_batches';

  // Synced batches are already in the ERP; they're kept this long for the
  // list page, then dropped so the stored JSON doesn't grow forever.
  static const Duration _syncedRetention = Duration(days: 30);

  // countingSheetId -> barcodes present in saved batches. Built on first
  // use and reset on every write, so a scan doesn't decode every batch.
  static Map<int, Set<String>>? _barcodeIndex;

  static Future<void> saveBatch(Batch batch) async {
    final cutoff = DateTime.now().subtract(_syncedRetention);
    final batches = await getBatches();
    batches.removeWhere((b) => b.isSynced && b.createdAt.isBefore(cutoff));
    batches.add(batch);
    await _write(batches);
  }

  static Future<List<Batch>> getBatches() async {
    final prefs = await SharedPreferences.getInstance();
    final String? batchesJson = prefs.getString(_batchesKey);
    if (batchesJson == null) return [];
    final List<dynamic> decoded = jsonDecode(batchesJson);
    return decoded.map((e) => Batch.fromJson(e)).toList();
  }

  // Whether this barcode is already in a saved batch of the sheet.
  static Future<bool> isBarcodeInBatches(int countingSheetId, String barcode) async {
    if (_barcodeIndex == null) {
      final index = <int, Set<String>>{};
      for (final batch in await getBatches()) {
        index
            .putIfAbsent(batch.countingSheetId, () => <String>{})
            .addAll(batch.items.map((item) => item.barcode));
      }
      _barcodeIndex = index;
    }
    return _barcodeIndex![countingSheetId]?.contains(barcode) ?? false;
  }

  static Future<void> removeBatch(String batchId) async {
    final batches = await getBatches();
    batches.removeWhere((b) => b.id == batchId);
    await _write(batches);
  }

  static Future<void> removeBatches(List<String> batchIds) async {
    final batches = await getBatches();
    batches.removeWhere((b) => batchIds.contains(b.id));
    await _write(batches);
  }

  static Future<void> markBatchAsSynced(String batchId) async {
    final batches = await getBatches();
    final index = batches.indexWhere((b) => b.id == batchId);
    if (index != -1) {
      batches[index].isSynced = true;
      await _write(batches);
    }
  }

  // ✅ NEW: replace the items of a saved batch (used when editing
  // quantities/deleting items from the scanned-items list opened from a
  // saved batch).
  static Future<void> updateBatchItems(String batchId, List<ScannedItem> items) async {
    final batches = await getBatches();
    final index = batches.indexWhere((b) => b.id == batchId);
    if (index != -1) {
      batches[index].items
        ..clear()
        ..addAll(items);
      await _write(batches);
    }
  }

  static Future<void> clearAllBatches() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_batchesKey);
    _barcodeIndex = null;
  }

  static Future<void> _write(List<Batch> batches) async {
    final prefs = await SharedPreferences.getInstance();
    final batchesJson = batches.map((b) => b.toJson()).toList();
    await prefs.setString(_batchesKey, jsonEncode(batchesJson));
    _barcodeIndex = null;
  }
}
