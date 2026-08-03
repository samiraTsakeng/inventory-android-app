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
  }

  // ✅ Get current session ID
  static Future<String> getSessionId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_sessionIdKey) ?? 'default';
  }

  // ✅ Clear all data for current session (on logout)
  static Future<void> clearSessionData() async {
    final prefs = await SharedPreferences.getInstance();
    final sessionId = await getSessionId();

    // Clear product cache for this session
    final barcodesKey = '${_cachedBarcodesKey}$sessionId';
    final barcodes = prefs.getStringList(barcodesKey) ?? [];
    for (final barcode in barcodes) {
      await prefs.remove('${_productCacheKey}$barcode');
    }
    await prefs.remove(barcodesKey);

    // Clear scanned items for this session
    // (We'll keep the sheet ID clearing separate)

    print("🗑️ Cleared session data for: $sessionId");
  }

  // ✅ Save product to cache for offline use
  static Future<void> cacheProduct(String barcode, Map<String, dynamic> productData) async {
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
  }

  // ✅ Get cached product
  static Future<Map<String, dynamic>?> getCachedProduct(String barcode) async {
    final prefs = await SharedPreferences.getInstance();
    final productJson = prefs.getString('${_productCacheKey}$barcode');
    if (productJson != null) {
      return jsonDecode(productJson);
    }
    return null;
  }

  // ✅ Get all cached barcodes for current session
  static Future<List<String>> getCachedBarcodes() async {
    final prefs = await SharedPreferences.getInstance();
    final sessionId = await getSessionId();
    final barcodesKey = '${_cachedBarcodesKey}$sessionId';
    return prefs.getStringList(barcodesKey) ?? [];
  }

  // ✅ Get cached products count for current session
  static Future<int> getCachedProductsCount() async {
    final barcodes = await getCachedBarcodes();
    return barcodes.length;
  }

  // ✅ Check if product exists in cache
  static Future<bool> isProductCached(String barcode) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey('${_productCacheKey}$barcode');
  }

  // ✅ Clear ALL product cache (for full reset)
  static Future<void> clearAllProductCache() async {
    final prefs = await SharedPreferences.getInstance();
    final sessionId = await getSessionId();
    final barcodesKey = '${_cachedBarcodesKey}$sessionId';
    final barcodes = prefs.getStringList(barcodesKey) ?? [];
    for (final barcode in barcodes) {
      await prefs.remove('${_productCacheKey}$barcode');
    }
    await prefs.remove(barcodesKey);
  }

  // Save scanned items for a specific counting sheet
  static Future<void> saveScannedItems(int sheetId, List<ScannedItem> items) async {
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
  }

  // Load scanned items for a specific counting sheet
  static Future<List<ScannedItem>> loadScannedItems(int sheetId) async {
    final prefs = await SharedPreferences.getInstance();
    final sessionId = await getSessionId();
    final key = '${_scannedItemsKey}${sessionId}_$sheetId';
    final itemsJson = prefs.getStringList(key);
    if (itemsJson == null) return [];
    return itemsJson.map((json) {
      final data = jsonDecode(json);
      return ScannedItem(
        barcode: data['barcode'],
        productName: data['productName'],
        productId: data['productId'],
        quantity: data['quantity'],
        lotNumber: data['lotNumber'],
        lotId: data['lotId'],
        tracking: data['tracking'] ?? 'none',
      );
    }).toList();
  }

  // Clear scanned items for a specific counting sheet
  static Future<void> clearScannedItems(int sheetId) async {
    final prefs = await SharedPreferences.getInstance();
    final sessionId = await getSessionId();
    final key = '${_scannedItemsKey}${sessionId}_$sheetId';
    await prefs.remove(key);
  }

  // Get current sheet ID
  static Future<int?> getCurrentSheetId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_sheetIdKey);
  }

  // ✅ Clear ALL session data (for logout with new credentials)
  static Future<void> clearAllSessionData() async {
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
  }
}