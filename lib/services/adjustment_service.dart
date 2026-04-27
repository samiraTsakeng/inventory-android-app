import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';

class AdjustmentService {
  //static const String _base = "http://127.0.0.1:3000";

  static Future<List<dynamic>> getAdjustments() async {
    final response = await http.get(
      Uri.parse(ApiConfig.adjustments),
    );

    print("status: ${response.statusCode}");
    print("Body: ${response.body}");

    if(response.statusCode != 200) {
      throw Exception("server errror: ${response.body}");
    }

    final data = jsonDecode(response.body);

    // ✅ HANDLE BACKEND ERRORS (IMPORTANT)
    if (data is Map && data.containsKey("success") && data["success"] == false) {
      throw Exception(data["message"]);
    }

    // ✅ ENSURE LIST
    if (data is List) {
      return data;
    } else {
      throw Exception("Invalid data format from server");
    }
  }
}