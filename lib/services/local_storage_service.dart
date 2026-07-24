import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/scanned_item.dart';

class LocalStorageService {
  static const String _scannedItemsKey = 'scanned_items_';
  static const String _sheetIdKey = 'current_sheet_id';
  static const String _productCacheKey = 'product_cache_';
  static const String _cachedBarcodesKey = 'cached_barcodes';

  // ✅ Save product to cache for offline use
  static Future<void> cacheProduct(String barcode, Map<String, dynamic> productData) async {
    final prefs = await SharedPreferences.getInstance();
    final productJson = jsonEncode(productData);
    await prefs.setString('${_productCacheKey}$barcode', productJson);

    // Track which barcodes are cached
    final cachedBarcodes = await _getCachedBarcodes();
    if (!cachedBarcodes.contains(barcode)) {
      cachedBarcodes.add(barcode);
      await prefs.setStringList(_cachedBarcodesKey, cachedBarcodes);
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

  // ✅ Get all cached barcodes
  static Future<List<String>> _getCachedBarcodes() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getStringList(_cachedBarcodesKey) ?? [];
  }

  // ✅ Get all cached products count
  static Future<int> getCachedProductsCount() async {
    final barcodes = await _getCachedBarcodes();
    return barcodes.length;
  }

  // ✅ Check if product exists in cache
  static Future<bool> isProductCached(String barcode) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey('${_productCacheKey}$barcode');
  }

  // ✅ Clear product cache
  static Future<void> clearProductCache() async {
    final prefs = await SharedPreferences.getInstance();
    final barcodes = await _getCachedBarcodes();
    for (final barcode in barcodes) {
      await prefs.remove('${_productCacheKey}$barcode');
    }
    await prefs.remove(_cachedBarcodesKey);
  }

  // Save scanned items for a specific counting sheet
  static Future<void> saveScannedItems(int sheetId, List<ScannedItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    final itemsJson = items.map((item) => jsonEncode({
      'barcode': item.barcode,
      'productName': item.productName,
      'productId': item.productId,
      'quantity': item.quantity,
      'lotNumber': item.lotNumber,
      'lotId': item.lotId,
      'tracking': item.tracking,
    })).toList();
    await prefs.setStringList('${_scannedItemsKey}$sheetId', itemsJson);
    await prefs.setInt(_sheetIdKey, sheetId);
  }

  // Load scanned items for a specific counting sheet
  static Future<List<ScannedItem>> loadScannedItems(int sheetId) async {
    final prefs = await SharedPreferences.getInstance();
    final itemsJson = prefs.getStringList('${_scannedItemsKey}$sheetId');
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
    await prefs.remove('${_scannedItemsKey}$sheetId');
  }

  // Get current sheet ID
  static Future<int?> getCurrentSheetId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_sheetIdKey);
  }
}