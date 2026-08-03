import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';

class ConsolidationService {
  // Get all consolidation sheets for an adjustment
  static Future<List<dynamic>> getConsolidationSheets(int adjustmentId) async {
    try {
      print("📥 Calling API: ${ApiConfig.baseUrl}/consolidation/sheets/$adjustmentId");

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/consolidation/sheets/$adjustmentId'),
      );

      print("📥 Response status: ${response.statusCode}");
      print("📥 Response body: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print("📥 Decoded data type: ${data.runtimeType}");

        if (data is List) {
          print("✅ Data is a list with ${data.length} items");
          return data;
        } else if (data is Map && data.containsKey('success') && data['success'] == true) {
          if (data.containsKey('sheets') && data['sheets'] is List) {
            print("✅ Found sheets in response: ${data['sheets'].length}");
            return data['sheets'];
          }
          return [];
        }
        return [];
      } else {
        print("❌ Server returned error: ${response.statusCode}");
        throw Exception('Failed to fetch consolidation sheets: ${response.statusCode}');
      }
    } catch (e) {
      print("❌ Get consolidation sheets error: $e");
      rethrow;
    }
  }

  // Get consolidation sheet details with lines
  static Future<Map<String, dynamic>?> getConsolidationSheetDetail(int sheetId) async {
    try {
      print("📥 Getting detail for sheet: $sheetId");

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/consolidation/sheet/$sheetId'),
      );

      print("📥 Detail status: ${response.statusCode}");
      print("📥 Detail body: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print("✅ Detail data loaded successfully");
        return data;
      }
      return null;
    } catch (e) {
      print("❌ Get consolidation sheet detail error: $e");
      return null;
    }
  }

  // Update verified quantity for a contradictory line
  static Future<bool> updateContradictoryLine(int lineId, int verifiedQty) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/consolidation/update-contradictory-line'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          'line_id': lineId,
          'verified_qty': verifiedQty,
        }),
      );

      print("📥 Update contradictory line status: ${response.statusCode}");
      print("📥 Update contradictory line body: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      print("❌ Update contradictory line error: $e");
      return false;
    }
  }

  // Validate consolidation sheet
  static Future<bool> validateConsolidationSheet(int sheetId) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/consolidation/validate-sheet'),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          'sheet_id': sheetId,
        }),
      );

      print("📥 Validate consolidation sheet status: ${response.statusCode}");
      print("📥 Validate consolidation sheet body: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      print("❌ Validate consolidation sheet error: $e");
      return false;
    }
  }
}