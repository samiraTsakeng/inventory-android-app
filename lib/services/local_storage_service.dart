import 'package:flutter/foundation.dart';
import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/scanned_item.dart';
import 'file_store.dart';
import 'sheet_cache_service.dart';

class LocalStorageService {
  static const String _scannedItemsKey = 'scanned_items_';
  static const String _sheetIdKey = 'current_sheet_id';
  static const String _productCacheKey = 'product_cache_';
  static const String _cachedBarcodesKey = 'cached_barcodes_';
  static const String _sessionIdKey = 'session_id';

  //  Save session ID (called on login)
  static Future<void> setSessionId(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionIdKey, sessionId);
    debugPrint(" Session ID saved: $sessionId");
  }

  //  Get current session ID
  static Future<String> getSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_sessionIdKey) ?? 'default';
  }

  //  Save scanned items with better error handling
  // local_storage_service.dart - Update saveScannedItems with better logging

  static Future<void> saveScannedItems(int sheetId, List<ScannedItem> items) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionId = await getSessionId();
      final key = '${_scannedItemsKey}${sessionId}_$sheetId';

      final itemsJson = items.map((item) => jsonEncode({
        'barcode': item.barcode,
        'productName': item.productName,
        'productId': item.productId,
        'quantity': item.quantity,
        'lotNumber': item.lotNumber,
        'lotId': item.lotId,
        'tracking': item.tracking,
      })).toList();

      // setStringList completes once the value is written to disk, so no
      // reload or read-back is needed.
      await prefs.setStringList(key, itemsJson);
      await prefs.setInt(_sheetIdKey, sheetId);
    } catch (e) {
      debugPrint("Error saving scanned items: $e");
    }
  }

  // Load scanned items with better error handling
  static Future<List<ScannedItem>> loadScannedItems(int sheetId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionId = await getSessionId();
      final key = '${_scannedItemsKey}${sessionId}_$sheetId';

      debugPrint("Loading items from key: $key");

      final itemsJson = prefs.getStringList(key);
      if (itemsJson == null) {
        debugPrint("No items found for key: $key");
        return [];
      }

      final items = <ScannedItem>[];
      for (final json in itemsJson) {
        try {
          final data = jsonDecode(json);
          items.add(ScannedItem(
            barcode: data['barcode'] ?? '',
            productName: data['productName'] ?? '',
            productId: data['productId'] ?? 0,
            quantity: data['quantity'] ?? 1,
            lotNumber: data['lotNumber'],
            lotId: data['lotId'],
            tracking: data['tracking'] ?? 'none',
          ));
        } catch (e) {
          debugPrint("Error parsing item: $e");
        }
      }

      debugPrint("Loaded ${items.length} items from key: $key");
      return items;
    } catch (e) {
      debugPrint("Error loading scanned items: $e");
      return [];
    }
  }

  // Clear scanned items for a specific counting sheet
  static Future<void> clearScannedItems(int sheetId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionId = await getSessionId();
      final key = '${_scannedItemsKey}${sessionId}_$sheetId';
      await prefs.remove(key);
      debugPrint("Cleared items for key: $key");
    } catch (e) {
      debugPrint("Error clearing scanned items: $e");
    }
  }

  // Get current sheet ID
  static Future<int?> getCurrentSheetId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_sheetIdKey);
    } catch (e) {
      debugPrint(" Error getting current sheet ID: $e");
      return null;
    }
  }

  // Clear ALL session data (for logout with new credentials)
  static Future<void> clearAllSessionData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionId = await getSessionId();

      // Scanned items not saved in a batch yet.
      final allKeys = prefs.getKeys();
      final scannedKeys = allKeys
          .where((key) => key.startsWith('${_scannedItemsKey}${sessionId}_'))
          .toList();
      for (final key in scannedKeys) {
        await prefs.remove(key);
      }

      // Offline copies: lists, the adjustments' numbers, what each sheet
      // sent and the numbers looked up (re-downloaded at the next login).
      // Batches and sheet actions not replayed yet are kept.
      await FileStore.removePrefixes([
        '$_responseCacheKey${sessionId}_',
        'adj_lots_${sessionId}_',
        'sheet_sent_${sessionId}_',
        '$_lookupsKey$sessionId',
      ]);
      _lookups = null;
      _lookupsSession = null;
      SheetCacheService.clearMemory();

      // Reset session ID for next login
      await prefs.remove(_sessionIdKey);
      await prefs.remove(_sheetIdKey);

      debugPrint("Cleared ALL session data for: $sessionId");
    } catch (e) {
      debugPrint("Error clearing session data: $e");
    }
  }

  // Last successful server answer for a list (adjustments, sheets), so the
  // app can still be navigated down to the scanning page offline.
  static const String _responseCacheKey = 'response_cache_';

  static Future<void> cacheResponse(String name, Object data) async {
    final sessionId = await getSessionId();
    await FileStore.write('$_responseCacheKey${sessionId}_$name', data);
  }

  static Future<dynamic> getCachedResponse(String name) async {
    final sessionId = await getSessionId();
    return FileStore.read('$_responseCacheKey${sessionId}_$name');
  }

  // Numbers looked up on the server (number -> product), so a rescan of a
  // number outside the offline copy needs no network. One file per
  // account, kept in memory and saved a moment after the last change.
  static const String _lookupsKey = 'lookups_';
  static Map<String, dynamic>? _lookups;
  static String? _lookupsSession;
  static Timer? _lookupsSave;

  static Future<Map<String, dynamic>> _loadLookups() async {
    final sessionId = await getSessionId();
    if (_lookups != null && _lookupsSession == sessionId) return _lookups!;
    final raw = await FileStore.read('$_lookupsKey$sessionId');
    _lookupsSession = sessionId;
    return _lookups = raw is Map ? Map<String, dynamic>.from(raw) : {};
  }

  // At most this many numbers: the oldest looked up are dropped first.
  static const int _lookupsMax = 2000;

  static Future<void> cacheProduct(String barcode, Map<String, dynamic> productData) async {
    final lookups = await _loadLookups();
    // Removed then added: the map keeps insertion order, newest last.
    lookups.remove(barcode);
    lookups[barcode] = productData;
    while (lookups.length > _lookupsMax) {
      lookups.remove(lookups.keys.first);
    }
    _scheduleLookupsSave(lookups);
  }

  // Forgets the numbers looked up (after a full offline preparation, which
  // brings fresh copies of every adjustment).
  static Future<void> clearLookups() async {
    final lookups = await _loadLookups();
    if (lookups.isEmpty) return;
    lookups.clear();
    _scheduleLookupsSave(lookups);
  }

  static void _scheduleLookupsSave(Map<String, dynamic> lookups) {
    final key = '$_lookupsKey$_lookupsSession';
    _lookupsSave?.cancel();
    _lookupsSave = Timer(const Duration(seconds: 2), () {
      FileStore.write(key, lookups);
    });
  }

  static Future<Map<String, dynamic>?> getCachedProduct(String barcode) async {
    final product = (await _loadLookups())[barcode];
    return product is Map ? Map<String, dynamic>.from(product) : null;
  }

  // Before this version, offline copies and every product of the catalog
  // were stored in SharedPreferences, which made each write (every scan)
  // rewrite megabytes. Runs once: the copies move to files, the catalog is
  // dropped. The other values are put back after a single clear() (one
  // removal per key would rewrite the big file thousands of times); they
  // are saved to a file first so a crash in between loses nothing.
  static const String _migratedKey = 'storage_files_v1';
  static const String _backupKey = 'prefs_backup';

  static Future<void> migrateLargeData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final backup = await FileStore.read(_backupKey);
      if (backup is Map) {
        // Interrupted last time: finish putting the values back.
        await _restore(prefs, backup);
        return;
      }
      if (prefs.getBool(_migratedKey) == true) return;

      bool isLarge(String key) =>
          key.startsWith(_productCacheKey) ||
          key.startsWith(_cachedBarcodesKey) ||
          key.startsWith(_responseCacheKey) ||
          key.startsWith('adj_lots_') ||
          key.startsWith('sheet_sent_');

      final keys = prefs.getKeys();
      for (final key in keys) {
        if (key.startsWith(_responseCacheKey) || key.startsWith('adj_lots_')) {
          final raw = prefs.getString(key);
          if (raw != null) {
            try {
              await FileStore.write(key, jsonDecode(raw));
            } catch (_) {}
          }
        } else if (key.startsWith('sheet_sent_')) {
          final list = prefs.getStringList(key);
          if (list != null) await FileStore.write(key, list);
        }
      }

      final kept = <String, Object?>{};
      for (final key in keys) {
        if (isLarge(key)) continue;
        final value = prefs.get(key);
        kept[key] = {
          'type': value is bool
              ? 'bool'
              : value is int
                  ? 'int'
                  : value is double
                      ? 'double'
                      : value is List
                          ? 'list'
                          : 'string',
          'value': value,
        };
      }
      if (kept.length == keys.length) {
        await prefs.setBool(_migratedKey, true);
        return;
      }
      await FileStore.write(_backupKey, kept);
      await _restore(prefs, kept);
    } catch (e) {
      debugPrint("Storage migration error: $e");
    }
  }

  static Future<void> _restore(SharedPreferences prefs, Map backup) async {
    await prefs.clear();
    for (final entry in backup.entries) {
      final key = entry.key as String;
      final item = entry.value;
      if (item is! Map) continue;
      final value = item['value'];
      switch (item['type']) {
        case 'bool':
          await prefs.setBool(key, value as bool);
        case 'int':
          await prefs.setInt(key, value as int);
        case 'double':
          await prefs.setDouble(key, (value as num).toDouble());
        case 'list':
          await prefs.setStringList(key, List<String>.from(value as List));
        default:
          await prefs.setString(key, value.toString());
      }
    }
    await prefs.setBool(_migratedKey, true);
    await FileStore.remove(_backupKey);
  }
}
