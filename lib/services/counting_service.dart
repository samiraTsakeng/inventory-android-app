import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import '../models/scanned_item.dart';
import 'local_storage_service.dart';

class CountingService {
  // OFFLINE-FIRST: Check cache, then API
  static Future<Map<String, dynamic>?> lookupProduct(String barcode) async {
    try {
      // 1️ Check local cache FIRST (instant, no internet needed)
      final cachedProduct = await LocalStorageService.getCachedProduct(barcode);
      if (cachedProduct != null) {
        print("Product found in OFFLINE cache: ${cachedProduct['name']}");
        return cachedProduct;
      }

      // 2️ If not in cache, try API (requires internet)
      print(" Looking up product ONLINE: $barcode");
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/counting/lookup-product'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({'barcode': barcode}),
      );

      print("Product lookup status: ${response.statusCode}");
      print("Product lookup body: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['product'] != null) {
          final product = data['product'];
          // Cache the product for future offline use
          await LocalStorageService.cacheProduct(barcode, product);
          print(" Product cached for offline use: ${product['name']}");
          return product;
        }
      }
      return null;
    } catch (e) {
      print("Product lookup error: $e");
      // If offline, return null (product not in cache)
      return null;
    }
  }

  // Get counting sheet state
  static Future<Map<String, dynamic>?> getSheetState(int sheetId) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/counting/sheet-state/$sheetId'),
      );

      print("Sheet state status: ${response.statusCode}");
      print("Sheet state body: ${response.body}");

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

  // Start a counting sheet
  static Future<bool> startSheet(int sheetId) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/counting/start-sheet'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({'sheet_id': sheetId}),
      );

      print("Start sheet status: ${response.statusCode}");
      print("Start sheet body: ${response.body}");

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

  // Validate a counting sheet (finish counting)
  static Future<bool> validateSheet(int sheetId) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/counting/validate-sheet'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({'sheet_id': sheetId}),
      );

      print("Validate sheet status: ${response.statusCode}");
      print("Validate sheet body: ${response.body}");

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

  // Submit scanned items to backend
  static Future<bool> submitScannedItems({
    required int countingSheetId,
    required int adjustmentId,
    required List<ScannedItem> items,
  }) async {
    try {
      if (items.isEmpty) {
        print("No items to submit");
        return false;
      }

      print("Submitting ${items.length} items");

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/counting/submit-scans'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          'counting_sheet_id': countingSheetId,
          'adjustment_id': adjustmentId,
          'items': items.map((e) => e.toJson()).toList(),
        }),
      );

      print("Submit status: ${response.statusCode}");
      print("Submit body: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      } else {
        print("Server returned error status: ${response.statusCode}");
        return false;
      }
    } catch (e) {
      print("Submit error: $e");
      return false;
    }
  }

  // Get number of cached products
  static Future<int> getCachedProductsCount() async {
    return await LocalStorageService.getCachedProductsCount();
  }

  // ✅ Shared scanning session — fetch the current merged list of items
  // scanned by ANY team member on this sheet (polled periodically).
  static Future<List<Map<String, dynamic>>> getLiveItems(int sheetId) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/counting/live-items/$sheetId'),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return List<Map<String, dynamic>>.from(data['items'] ?? []);
        }
      }
      return [];
    } catch (e) {
      print("Get live items error: $e");
      return [];
    }
  }

  // ✅ Shared scanning session — push a scan (new item, or additional
  // quantity for one that's already there) and get back the updated
  // merged list. Returns null if the push failed (offline), so the
  // caller can fall back to local-only storage and retry later.
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
        if (data['success'] == true) {
          return List<Map<String, dynamic>>.from(data['items'] ?? []);
        }
      }
      return null;
    } catch (e) {
      print("Push live scan error: $e");
      return null;
    }
  }

  // ✅ Called once the shared list has been saved into a batch / sent to
  // the ERP, so both phones start the next lot from a clean, empty list.
  static Future<void> clearLiveItems(int sheetId) async {
    try {
      await http.post(
        Uri.parse('${ApiConfig.baseUrl}/counting/live-items/$sheetId/clear'),
      );
    } catch (e) {
      print("Clear live items error: $e");
    }
  }

  // ✅ Checks whether this barcode was already submitted to the ERP for
  // this sheet (not just present locally/in a local batch). Fails "not
  // found" silently if offline/unreachable, so this never blocks scanning.
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
        if (data['success'] == true) return data['alreadySent'] == true;
      }
      return false;
    } catch (e) {
      print("Check already in ERP error: $e");
      return false;
    }
  }
}