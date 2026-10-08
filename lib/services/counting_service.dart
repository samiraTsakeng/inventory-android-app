import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import '../models/scanned_item.dart';
import 'local_storage_service.dart';

/// ✅ Returned by submitScannedItems so the UI knows which barcodes failed.
class SubmitResult {
  final bool success;
  final int submittedCount;
  final List<String> failedBarcodes;
  final List<Map<String, String>> failedDetails;
  final String? message;

  SubmitResult({
    required this.success,
    this.submittedCount = 0,
    this.failedBarcodes = const [],
    this.failedDetails = const [],
    this.message,
  });
}

class CountingService {

  // PRODUCT LOOKUP
  // Single-barcode lookup (kept for manual entry + legacy callers).
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
        headers: await ApiConfig.authHeaders(json: true),
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

  // Batch lookup — send all barcodes on the article in ONE request.
  static Future<Map<String, dynamic>?> lookupProductsBatch(
      List<String> barcodes, {int? countingSheetId}) async {
    if (barcodes.isEmpty) return null;
    try {
      //Offline-first: if ANY barcode is cached, return that product.
      for (final b in barcodes) {
        final cached = await LocalStorageService.getCachedProduct(b);
        if (cached != null) {
          print("Batch: found in OFFLINE cache: ${cached['name']}");
          return cached;
        }
      }

      // One HTTP call for all barcodes.
      print("Batch lookup ONLINE for ${barcodes.length} barcodes");
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/counting/lookup-products-batch'),
        headers: await ApiConfig.authHeaders(json: true),
        body: jsonEncode({
          'barcodes': barcodes,
          if (countingSheetId != null) 'counting_sheet_id': countingSheetId,
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['product'] != null) {
          final product = data['product'];
          // Cache only the barcode that is actually registered in Odoo.
          // Do not cache the other detected barcodes, otherwise an
          // unregistered alternate barcode could appear valid offline.
          final matchedBarcode = product['barcode']?.toString();
          if (matchedBarcode != null && matchedBarcode.isNotEmpty) {
            await LocalStorageService.cacheProduct(matchedBarcode, product);
          }
          return product;
        }
      }
      return null;
    } catch (e) {
      print("Batch lookup error: $e");
      return null;
    }
  }

  // COUNTING SHEET LIFECYCLE

  static Future<Map<String, dynamic>?> getSheetState(int sheetId) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/counting/sheet-state/$sheetId'),
        headers: await ApiConfig.authHeaders(),
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
        headers: await ApiConfig.authHeaders(json: true),
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
        headers: await ApiConfig.authHeaders(json: true),
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
  // SUBMIT TO ERP
  // Rich result: success flag, count, and failed barcodes + reasons.
  static Future<SubmitResult> submitScannedItems({
    required int countingSheetId,
    required int adjustmentId,
    required List<ScannedItem> items,
  }) async {
    try {
      if (items.isEmpty) {
        return SubmitResult(success: false, message: 'No items to submit');
      }

      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/counting/submit-scans'),
        headers: await ApiConfig.authHeaders(json: true),
        body: jsonEncode({
          'counting_sheet_id': countingSheetId,
          'adjustment_id': adjustmentId,
          'items': items.map((e) => e.toJson()).toList(),
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        final rawFailed = data['failed_items'] as List? ?? [];
        final failedBarcodes = <String>[];
        final failedDetails = <Map<String, String>>[];

        for (final f in rawFailed) {
          if (f is String) {
            failedBarcodes.add(f);
            failedDetails.add({'barcode': f, 'reason': 'Erreur inconnue'});
          } else if (f is Map) {
            final bc = f['barcode']?.toString() ?? '';
            final reason = f['reason']?.toString() ?? 'Erreur inconnue';
            failedBarcodes.add(bc);
            failedDetails.add({'barcode': bc, 'reason': reason});
          }
        }

        return SubmitResult(
          success: data['success'] == true,
          submittedCount: data['submitted_count'] ?? 0,
          failedBarcodes: failedBarcodes,
          failedDetails: failedDetails,
          message: data['message'],
        );
      }
      return SubmitResult(
        success: false,
        message: 'Erreur serveur (${response.statusCode})',
      );
    } catch (e) {
      print("Submit error: $e");
      return SubmitResult(success: false, message: e.toString());
    }
  }

  static Future<int> getCachedProductsCount() async {
    return await LocalStorageService.getCachedProductsCount();
  }

  static Future<bool> isAlreadyInErp({
    required int countingSheetId,
    required String barcode,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/counting/check-erp-scan'),
        headers: await ApiConfig.authHeaders(json: true),
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