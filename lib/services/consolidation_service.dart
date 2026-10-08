import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';

class ConsolidationService {
  // Get all consolidation sheets for an adjustment
  static Future<List<dynamic>> getConsolidationSheets(int adjustmentId) async {
    try {
      print(" Calling API: ${ApiConfig.baseUrl}/consolidation/sheets/$adjustmentId");

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/consolidation/sheets/$adjustmentId'),
        headers: await ApiConfig.authHeaders(),
      );

      print(" Response status: ${response.statusCode}");
      print(" Response body: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print(" Decoded data type: ${data.runtimeType}");

        if (data is List) {
          print(" Data is a list with ${data.length} items");
          return data;
        } else if (data is Map && data.containsKey('success') && data['success'] == true) {
          if (data.containsKey('sheets') && data['sheets'] is List) {
            print(" Found sheets in response: ${data['sheets'].length}");
            return data['sheets'];
          }
          return [];
        }
        return [];
      } else {
        print(" Server returned error: ${response.statusCode}");
        throw Exception('Failed to fetch consolidation sheets: ${response.statusCode}');
      }
    } catch (e) {
      print(" Get consolidation sheets error: $e");
      rethrow;
    }
  }

  // Get consolidation sheet details with lines
  static Future<Map<String, dynamic>?> getConsolidationSheetDetail(int sheetId) async {
    try {
      print(" Getting detail for sheet: $sheetId");

      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/consolidation/sheet/$sheetId'),
        headers: await ApiConfig.authHeaders(),
      );

      print(" Detail status: ${response.statusCode}");
      print(" Detail body: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        print(" Detail data loaded successfully");
        return data;
      }
      return null;
    } catch (e) {
      print(" Get consolidation sheet detail error: $e");
      return null;
    }
  }

  // Update verified quantity for a contradictory line
  static Future<bool> updateContradictoryLine(int lineId, int verifiedQty) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/consolidation/update-contradictory-line'),
        headers: await ApiConfig.authHeaders(json: true),
        body: jsonEncode({
          'line_id': lineId,
          'verified_qty': verifiedQty,
        }),
      );

      print(" Update contradictory line status: ${response.statusCode}");
      print(" Update contradictory line body: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      print(" Update contradictory line error: $e");
      return false;
    }
  }

  // Validate consolidation sheet
  static Future<bool> validateConsolidationSheet(int sheetId) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/consolidation/validate-sheet'),
        headers: await ApiConfig.authHeaders(json: true),
        body: jsonEncode({
          'sheet_id': sheetId,
        }),
      );

      print(" Validate consolidation sheet status: ${response.statusCode}");
      print(" Validate consolidation sheet body: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      print(" Validate consolidation sheet error: $e");
      return false;
    }
  }

  // NEW: Get zones ready for consolidation
  static Future<List<dynamic>> getConsolidationZones(int adjustmentId) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/consolidation/zones/$adjustmentId'),
        headers: await ApiConfig.authHeaders(),
      );

      print(" Get zones status: ${response.statusCode}");
      print(" Get zones body: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['zones'] ?? [];
        }
        return [];
      }
      throw Exception('Failed to fetch consolidation zones');
    } catch (e) {
      print(" Get consolidation zones error: $e");
      rethrow;
    }
  }

  //  NEW: Create consolidation sheet (uses existing Odoo wizard)
  static Future<int?> createConsolidationSheet({
    required int adjustmentId,
    required int zoneId,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/consolidation/create'),
        headers: await ApiConfig.authHeaders(json: true),
        body: jsonEncode({
          'adjustment_id': adjustmentId,
          'zone_id': zoneId,
        }),
      );

      print(" Create consolidation status: ${response.statusCode}");
      print(" Create consolidation body: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['consolidation_sheet_id'];
        }
        return null;
      }
      throw Exception('Failed to create consolidation sheet');
    } catch (e) {
      print("Create consolidation error: $e");
      rethrow;
    }
  }

  // NEW: Apply consolidation to stock
  static Future<bool> applyConsolidation(int adjustmentId) async {
    try {
      final response = await http.post(
        Uri.parse('${ApiConfig.baseUrl}/consolidation/apply'),
        headers: await ApiConfig.authHeaders(json: true),
        body: jsonEncode({
          'adjustment_id': adjustmentId,
        }),
      );

      print(" Apply consolidation status: ${response.statusCode}");
      print(" Apply consolidation body: ${response.body}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['success'] == true;
      }
      return false;
    } catch (e) {
      print("Apply consolidation error: $e");
      return false;
    }
  }

  // NEW: Get adjustment status
  static Future<Map<String, dynamic>?> getAdjustmentStatus(int adjustmentId) async {
    try {
      final response = await http.get(
        Uri.parse('${ApiConfig.baseUrl}/consolidation/adjustment-status/$adjustmentId'),
        headers: await ApiConfig.authHeaders(),
      );

      print("Adjustment status: ${response.statusCode}");

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return data['adjustment'];
        }
        return null;
      }
      return null;
    } catch (e) {
      print("Get adjustment status error: $e");
      return null;
    }
  }
}

