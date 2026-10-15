import 'dart:convert';
import 'api_client.dart';
import 'api_config.dart';
import '../models/scanned_item.dart';
import 'local_storage_service.dart';

class CountingService {
  // OFFLINE-FIRST: Check cache, then API.
  // One network round trip per scan: the product and whether this number
  // is already in the ERP for the sheet come back together.
  static Future<({Map<String, dynamic>? product, bool alreadyInErp})>
      lookupProduct(String barcode, {required int countingSheetId}) async {
    try {
      final cachedProduct = await LocalStorageService.getCachedProduct(barcode);
      if (cachedProduct != null) {
        final alreadyInErp = await isAlreadyInErp(
          countingSheetId: countingSheetId,
          barcode: barcode,
        );
        return (product: cachedProduct, alreadyInErp: alreadyInErp);
      }

      final response = await ApiClient.post(
        Uri.parse('${ApiConfig.baseUrl}/counting/lookup-product'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          'barcode': barcode,
          'counting_sheet_id': countingSheetId,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final alreadyInErp = data['already_sent'] == true;
        if (data['success'] == true && data['product'] != null) {
          final product = Map<String, dynamic>.from(data['product']);
          await LocalStorageService.cacheProduct(barcode, product);
          return (product: product, alreadyInErp: alreadyInErp);
        }
        return (product: null, alreadyInErp: alreadyInErp);
      }
      return (product: null, alreadyInErp: false);
    } catch (e) {
      print("Product lookup error: $e");
      return (product: null, alreadyInErp: false);
    }
  }

  static Future<Map<String, dynamic>?> getSheetState(int sheetId) async {
    try {
      final response = await ApiClient.get(
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
      final response = await ApiClient.post(
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
      final response = await ApiClient.post(
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

      final response = await ApiClient.post(
        Uri.parse('${ApiConfig.baseUrl}/counting/submit-scans'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          'counting_sheet_id': countingSheetId,
          'adjustment_id': adjustmentId,
          'items': items.map((e) => e.toJson()).toList(),
        }),
        timeout: ApiConfig.submitTimeout,
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


  // Returns the shared list and its version, or null when the server still
  // has version [since] (nothing changed) or the request failed.
  static Future<({int version, List<Map<String, dynamic>> items})?> getLiveItems(
      int countingSheetId, {int? since}) async {
    try {
      final query = since != null ? '?since=$since' : '';
      final response = await ApiClient.get(
        Uri.parse('${ApiConfig.baseUrl}/counting/live-items/$countingSheetId$query'),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['items'] is List) {
          return (
            version: (data['version'] as num?)?.toInt() ?? 0,
            items: List<Map<String, dynamic>>.from(data['items']),
          );
        }
      }
      return null;
    } catch (e) {
      print("Get live items error: $e");
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>?> pushLiveScan({
    required int countingSheetId,
    required Map<String, dynamic> item,
  }) async {
    try {
      final response = await ApiClient.post(
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
      final response = await ApiClient.post(
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
      final response = await ApiClient.post(
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
      final response = await ApiClient.post(
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

  // Same check as isAlreadyInErp for many barcodes in one request.
  // Returns the barcodes already present in the ERP for this sheet.
  static Future<Set<String>> alreadyInErp({
    required int countingSheetId,
    required List<String> barcodes,
  }) async {
    if (barcodes.isEmpty) return {};
    try {
      final response = await ApiClient.post(
        Uri.parse('${ApiConfig.baseUrl}/counting/check-erp-scans'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          'counting_sheet_id': countingSheetId,
          'barcodes': barcodes,
        }),
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['alreadySent'] is List) {
          return Set<String>.from(data['alreadySent']);
        }
      }
      return {};
    } catch (e) {
      print("Check ERP scans error: $e");
      return {}; // fail-open: the server also skips duplicates on submit
    }
  }
}