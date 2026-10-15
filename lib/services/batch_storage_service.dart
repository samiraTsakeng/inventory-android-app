import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/batch.dart';
import '../models/scanned_item.dart';
import 'local_storage_service.dart';
import 'sync_service.dart';

class BatchStorageService {
  // Batches are stored per account (same session id as the scanned items),
  // so another user on the same phone neither sees nor sends them.
  static const String _batchesKey = 'saved_batches';

  // countingSheetId -> barcodes present in saved batches. Built on first
  // use and reset on every write, so a scan doesn't decode every batch.
  static Map<int, Set<String>>? _barcodeIndex;
  // Storage key the index was built from (it changes with the account).
  static String? _indexKey;

  static Future<String> _key() async {
    final sessionId = await LocalStorageService.getSessionId();
    return '${_batchesKey}_$sessionId';
  }

  // Before batches were per account they lived under one shared key. The
  // first account to open the batches after the update takes them over, so
  // no saved (possibly unsynced) batch is lost.
  static Future<void> _migrateLegacy(SharedPreferences prefs, String key) async {
    final legacy = prefs.getString(_batchesKey);
    if (legacy == null) return;
    if (!prefs.containsKey(key)) {
      await prefs.setString(key, legacy);
    }
    await prefs.remove(_batchesKey);
  }

  static Future<void> saveBatch(Batch batch) async {
    final batches = await getBatches();
    batches.add(batch);
    await _write(batches);
  }

  // Batches kept as "synced" by earlier versions of the app: their data is
  // in the ERP, so they are dropped (called at startup).
  static Future<void> purgeSent() async {
    final batches = await getBatches();
    final before = batches.length;
    batches.removeWhere((b) => b.isSynced);
    if (batches.length != before) await _write(batches);
  }

  static Future<List<Batch>> getBatches() async {
    final prefs = await SharedPreferences.getInstance();
    final key = await _key();
    await _migrateLegacy(prefs, key);
    final String? batchesJson = prefs.getString(key);
    if (batchesJson == null) return [];
    final List<dynamic> decoded = jsonDecode(batchesJson);
    return decoded.map((e) => Batch.fromJson(e)).toList();
  }

  // Whether this barcode is already in a saved batch of the sheet.
  static Future<bool> isBarcodeInBatches(int countingSheetId, String barcode) async {
    final key = await _key();
    if (_barcodeIndex == null || _indexKey != key) {
      final index = <int, Set<String>>{};
      for (final batch in await getBatches()) {
        index
            .putIfAbsent(batch.countingSheetId, () => <String>{})
            .addAll(batch.items.map((item) => item.barcode));
      }
      _barcodeIndex = index;
      _indexKey = key;
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

  // Called once the ERP accepted the batch: its data is deleted from the
  // phone, so it can't be sent twice and doesn't pile up. A rescan of its
  // numbers is still flagged "déjà envoyé" (SheetCacheService.markSent).
  static Future<void> deleteSentBatch(String batchId) => removeBatch(batchId);

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
    await prefs.remove(await _key());
    _barcodeIndex = null;
    SyncService.pendingBatches.value = 0;
  }

  static Future<void> _write(List<Batch> batches) async {
    final prefs = await SharedPreferences.getInstance();
    final batchesJson = batches.map((b) => b.toJson()).toList();
    await prefs.setString(await _key(), jsonEncode(batchesJson));
    _barcodeIndex = null;
    SyncService.pendingBatches.value = batches.where((b) => !b.isSynced).length;
  }
}
