import 'dart:convert';
import 'package:http/http.dart' as http;

class FeuilleService {
  static const String _base = "http://127.0.0.1:3000";
  static Future<List<dynamic>> getFeuilles(int adjustmentId) async {
    final response = await http.get(
      Uri.parse(
          "$_base/feuilles/$adjustmentId"),
    );

    print("feuilles status: ${response.statusCode}");
    print("Feuilles body: ${response.body}");

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