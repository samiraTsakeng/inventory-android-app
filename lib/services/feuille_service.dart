import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';

class FeuilleService {
  static Future<List<dynamic>> getFeuilles(int adjustmentId) async {
    try {
      final response = await http.get(
        Uri.parse(ApiConfig.feuilles(adjustmentId)),
      );

      print("feuilles status: ${response.statusCode}");
      print("Feuilles body: ${response.body}");

      if (response.statusCode != 200) {
        final errorData = jsonDecode(response.body);
        print("Error response: $errorData");
        // Return empty list and let the UI handle the error via exception
        throw Exception(errorData['message'] ?? 'Server error');
      }

      final data = jsonDecode(response.body);
      print("Decoded data type: ${data.runtimeType}");

      if (data is Map && data.containsKey("success") && data["success"] == false) {
        throw Exception(data["message"] ?? 'Unknown error');
      }

      if (data is List) {
        return data;
      } else {
        throw Exception("Invalid data format from server");
      }
    } catch (e) {
      print("Feuilles service error: $e");
      rethrow;
    }
  }
}