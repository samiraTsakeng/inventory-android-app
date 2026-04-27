import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';  // ← Add this import

class FeuilleService {
  static Future<List<dynamic>> getFeuilles(int adjustmentId) async {
    final response = await http.get(
      Uri.parse(ApiConfig.feuilles(adjustmentId)),  // ← Use ApiConfig
    );

    print("feuilles status: ${response.statusCode}");
    print("Feuilles body: ${response.body}");

    if (response.statusCode != 200) {
      throw Exception("Server error: ${response.statusCode}");
    }

    final data = jsonDecode(response.body);

    if (data is Map && data["success"] == false) {
      throw Exception(data["message"]);
    }

    if (data is List) {
      return data;
    } else {
      throw Exception("Invalid data format");
    }
  }
}