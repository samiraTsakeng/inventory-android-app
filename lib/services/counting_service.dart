import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import '../models/scanned_item.dart';

class CountingService {
  // Look up product by barcode
  static Future<Map<String, dynamic>?> lookupProduct(String barcode) async {
    try {
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
          return data['product'];
        }
      }
      return null;
    } catch (e) {
      print("Product lookup error: $e");
      return null;
    }
  }

  // Submit scanned items to backend
  static Future<bool> submitScannedItems({
    required int countingSheetId,
    required int adjustmentId,
    required List<ScannedItem> items,
  }) async {
    try {
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
      }
      return false;
    } catch (e) {
      print("Submit error: $e");
      return false;
    }
  }
}