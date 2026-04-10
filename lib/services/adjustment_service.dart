import 'dart:convert';
import 'package:http/http.dart' as http;

class AdjustmentService {
  static Future<List<dynamic>> getAdjustments() async {
    final response = await http.get(
      Uri.parse("http://localhost:3000/adjustments"),
    );

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