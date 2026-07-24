import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';

class ConsolidationService {
  // Get all consolidation sheets for an adjustment
  static Future<List<dynamic>> getConsolidationSheets(int adjustmentId) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/consolidation/sheets/$adjustmentId'),
      );

      print("Consolidation sheets status: ${response.statusCode}");
      print("Consolidation sheets body: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data is List) {
          return data;
        } else if (data is Map && data['success'] == true && data['sheets'] != null) {
          return data['sheets'];
        }
        return [];
      } else {
        throw Exception('Failed to fetch consolidation sheets');
      }
    } catch (e) {
      print("Get consolidation sheets error: $e");
      return [];
    }
  }

  // Get consolidation sheet details with lines
  static Future<Map<String, dynamic>?> getConsolidationSheetDetail(int sheetId) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/consolidation/sheet/$sheetId'),
      );

      print("Consolidation sheet detail status: ${response.statusCode}");
      print("Consolidation sheet detail body: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data;
      }
      return null;
    } catch (e) {
      print("Get consolidation sheet detail error: $e");
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

      print("Update contradictory line status: ${response.statusCode}");
      print("Update contradictory line body: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      print("Update contradictory line error: $e");
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

      print("Validate consolidation sheet status: ${response.statusCode}");
      print("Validate consolidation sheet body: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      print("Validate consolidation sheet error: $e");
      return false;
    }
  }
}