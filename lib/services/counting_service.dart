import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import '../models/scanned_item.dart';
import 'local_storage_service.dart';

class CountingService {
  // OFFLINE-FIRST: Check cache, then API
  static Future<Map<String, dynamic>?> lookupProduct(String barcode) async {
    try {
      final cachedProduct = await LocalStorageService.getCachedProduct(barcode);
      if (cachedProduct != null) {
        print("Product found in OFFLINE cache: ${cachedProduct['name']}");
        return cachedProduct;
      }

      print("Looking up product ONLINE: $barcode");
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/counting/lookup-product'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({'barcode': barcode}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['product'] != null) {
          final product = data['product'];
          await LocalStorageService.cacheProduct(barcode, product);
          return product;
        }
      }
      return null;
    } catch (e) {
      print("Product lookup error: $e");
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getSheetState(int sheetId) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/counting/sheet-state/$sheetId'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['sheet'];
      }
      return null;
    } catch (e) {
      print("Get sheet state error: $e");
      return null;
    }
  }

  static Future<bool> startSheet(int sheetId) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/counting/start-sheet'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({'sheet_id': sheetId}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      print("Start sheet error: $e");
      return false;
    }
  }

  static Future<bool> validateSheet(int sheetId) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/counting/validate-sheet'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({'sheet_id': sheetId}),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      print("Validate sheet error: $e");
      return false;
    }
  }

  static Future<bool> submitScannedItems({
    required int countingSheetId,
    required int adjustmentId,
    required List<ScannedItem> items,
  }) async {
    try {
      if (items.isEmpty) return false;

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/counting/submit-scans'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          'counting_sheet_id': countingSheetId,
          'adjustment_id': adjustmentId,
          'items': items.map((e) => e.toJson()).toList(),
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      print("Submit error: $e");
      return false;
    }
  }

  static Future<int> getCachedProductsCount() async {
    return await LocalStorageService.getCachedProductsCount();
  }


  // SHARED LIVE SESSION (two phones, same sheet)


  static Future<List<Map<String, dynamic>>> getLiveItems(int countingSheetId) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/counting/live-items/$countingSheetId'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['items'] is List) {
          return List<Map<String, dynamic>>.from(data['items']);
        }
      }
      return [];
    } catch (e) {
      print("Get live items error: $e");
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>?> pushLiveScan({
    required int countingSheetId,
    required Map<String, dynamic> item,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/counting/live-scan'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          'counting_sheet_id': countingSheetId,
          ...item,
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['items'] is List) {
          return List<Map<String, dynamic>>.from(data['items']);
        }
      }
      return null;
    } catch (e) {
      print("Push live scan error: $e");
      return null;
    }
  }

  static Future<bool> clearLiveItems(int countingSheetId) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/counting/live-items/$countingSheetId/clear'),
      );
      return response.statusCode == 200;
    } catch (e) {
      print("Clear live items error: $e");
      return false;
    }
  }

  // FIX #5: remove a single barcode from the shared live session —
  // called after deleting an item from the list, so a later rescan of
  // the same barcode doesn't get blocked as "already scanned".
  static Future<bool> removeLiveItem({
    required int countingSheetId,
    required String barcode,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/counting/live-items/$countingSheetId/remove'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({'barcode': barcode}),
      );
      return response.statusCode == 200;
    } catch (e) {
      print("Remove live item error: $e");
      return false;
    }
  }

  // FIX #6: check whether this barcode already exists in the ERP for
  // this counting sheet, before submitting. Prevents duplicates.
  static Future<bool> isAlreadyInErp({
    required int countingSheetId,
    required String barcode,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/counting/check-erp-scan'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          'counting_sheet_id': countingSheetId,
          'barcode': barcode,
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['alreadySent'] == true;
      }
      return false;
    } catch (e) {
      print("Check ERP scan error: $e");
      return false; // fail-open: don't block scanning if check fails
    }
  }
}