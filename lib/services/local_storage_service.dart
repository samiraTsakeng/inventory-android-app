import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/scanned_item.dart';

class LocalStorageService {
  static const String _scannedItemsKey = 'scanned_items_';
  static const String _sheetIdKey = 'current_sheet_id';
  static const String _productCacheKey = 'product_cache_';
  static const String _cachedBarcodesKey = 'cached_barcodes_';
  static const String _sessionIdKey = 'session_id';

  // ✅ Get session-specific cache key
  static Future<String> _getSessionKey(String baseKey) async {
    final prefs = await SharedPreferences.getInstance();
    final sessionId = prefs.getString(_sessionIdKey) ?? 'default';
    return '${baseKey}_$sessionId';
  }

  // ✅ Save session ID (called on login)
  static Future<void> setSessionId(String sessionId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionIdKey, sessionId);
    print("✅ Session ID saved: $sessionId");
  }

  // ✅ Get current session ID
  static Future<String> getSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    final sessionId = prefs.getString(_sessionIdKey) ?? 'default';
    print("📱 Current session ID: $sessionId");
    return sessionId;
  }

  // ✅ Save scanned items with better error handling
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

      await prefs.setStringList(key, itemsJson);
      await prefs.setInt(_sheetIdKey, sheetId);

      // ✅ Force save to disk
      await prefs.reload();

      print("💾 Saved ${items.length} items to key: $key");
      print("💾 Session ID: $sessionId, Sheet ID: $sheetId");

      // ✅ Verify save
      final verify = prefs.getStringList(key);
      print("💾 Verification: ${verify?.length ?? 0} items saved");
    } catch (e) {
      print("❌ Error saving scanned items: $e");
    }
  }

  // ✅ Load scanned items with better error handling
  static Future<List<ScannedItem>> loadScannedItems(int sheetId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionId = await getSessionId();
      final key = '${_scannedItemsKey}${sessionId}_$sheetId';

      print("📱 Loading items from key: $key");

      final itemsJson = prefs.getStringList(key);
      if (itemsJson == null) {
        print("📭 No items found for key: $key");
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
          print("❌ Error parsing item: $e");
        }
      }

      print("📱 Loaded ${items.length} items from key: $key");
      return items;
    } catch (e) {
      print("❌ Error loading scanned items: $e");
      return [];
    }
  }

  // ✅ Clear scanned items for a specific counting sheet
  static Future<void> clearScannedItems(int sheetId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionId = await getSessionId();
      final key = '${_scannedItemsKey}${sessionId}_$sheetId';
      await prefs.remove(key);
      print("🗑️ Cleared items for key: $key");
    } catch (e) {
      print("❌ Error clearing scanned items: $e");
    }
  }

  // ✅ Get current sheet ID
  static Future<int?> getCurrentSheetId() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getInt(_sheetIdKey);
    } catch (e) {
      print("❌ Error getting current sheet ID: $e");
      return null;
    }
  }

  // ✅ Clear ALL session data (for logout with new credentials)
  static Future<void> clearAllSessionData() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionId = await getSessionId();

      // Clear all product cache for this session
      final barcodesKey = '${_cachedBarcodesKey}$sessionId';
      final barcodes = prefs.getStringList(barcodesKey) ?? [];
      for (final barcode in barcodes) {
        await prefs.remove('${_productCacheKey}$barcode');
      }
      await prefs.remove(barcodesKey);

      // Clear all scanned items for this session
      final allKeys = prefs.getKeys();
      final scannedKeys = allKeys.where((key) => key.startsWith('${_scannedItemsKey}${sessionId}_'));
      for (final key in scannedKeys) {
        await prefs.remove(key);
      }

      // Reset session ID for next login
      await prefs.remove(_sessionIdKey);
      await prefs.remove(_sheetIdKey);

      print("🗑️ Cleared ALL session data for: $sessionId");
    } catch (e) {
      print("❌ Error clearing session data: $e");
    }
  }

  // ✅ Save product to cache for offline use
  static Future<void> cacheProduct(String barcode, Map<String, dynamic> productData) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionId = await getSessionId();
      final productJson = jsonEncode(productData);
      await prefs.setString('${_productCacheKey}$barcode', productJson);

      // Track which barcodes are cached for this session
      final barcodesKey = '${_cachedBarcodesKey}$sessionId';
      final cachedBarcodes = prefs.getStringList(barcodesKey) ?? [];
      if (!cachedBarcodes.contains(barcode)) {
        cachedBarcodes.add(barcode);
        await prefs.setStringList(barcodesKey, cachedBarcodes);
      }
    } catch (e) {
      print("❌ Error caching product: $e");
    }
  }

  // ✅ Get cached product
  static Future<Map<String, dynamic>?> getCachedProduct(String barcode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final productJson = prefs.getString('${_productCacheKey}$barcode');
      if (productJson != null) {
        return jsonDecode(productJson);
      }
      return null;
    } catch (e) {
      print("❌ Error getting cached product: $e");
      return null;
    }
  }

  // ✅ Get all cached barcodes for current session
  static Future<List<String>> getCachedBarcodes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionId = await getSessionId();
      final barcodesKey = '${_cachedBarcodesKey}$sessionId';
      return prefs.getStringList(barcodesKey) ?? [];
    } catch (e) {
      print("❌ Error getting cached barcodes: $e");
      return [];
    }
  }

  // ✅ Get cached products count for current session
  static Future<int> getCachedProductsCount() async {
    try {
      final barcodes = await getCachedBarcodes();
      return barcodes.length;
    } catch (e) {
      print("❌ Error getting cached products count: $e");
      return 0;
    }
  }

  // ✅ Check if product exists in cache
  static Future<bool> isProductCached(String barcode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.containsKey('${_productCacheKey}$barcode');
    } catch (e) {
      print("❌ Error checking product cache: $e");
      return false;
    }
  }

  // ✅ Clear ALL product cache (for full reset)
  static Future<void> clearAllProductCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final sessionId = await getSessionId();
      final barcodesKey = '${_cachedBarcodesKey}$sessionId';
      final barcodes = prefs.getStringList(barcodesKey) ?? [];
      for (final barcode in barcodes) {
        await prefs.remove('${_productCacheKey}$barcode');
      }
      await prefs.remove(barcodesKey);
      print("Cleared all product cache");
    } catch (e) {
      print("Error clearing product cache: $e");
    }
  }
}