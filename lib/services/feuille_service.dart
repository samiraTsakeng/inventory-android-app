import 'dart:convert';
import 'package:http/http.dart' as http;

class FeuilleService {
  static Future<List<dynamic>> getFeuilles(int adjustmentId) async {
    final response = await http.get(
      Uri.parse(
          "http://localhost:3000/feuilles/$adjustmentId"),
    );

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