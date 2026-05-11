import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/scanned_item.dart';

class LocalStorageService {
  static const String _scannedItemsKey = 'scanned_items_';
  static const String _sheetIdKey = 'current_sheet_id';

  // Save scanned items for a specific counting sheet
  static Future<void> saveScannedItems(int sheetId, List<ScannedItem> items) async {
    final prefs = await SharedPreferences.getInstance();
    final itemsJson = items.map((item) => jsonEncode({
      'barcode': item.barcode,
      'productName': item.productName,
      'productId': item.productId,
      'quantity': item.quantity,
      'lotNumber': item.lotNumber,
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