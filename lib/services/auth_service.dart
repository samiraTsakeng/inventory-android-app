import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';
class AuthService {
  // Use 127.0.0.1 — in Chrome, "localhost" doesn't reach your backend
  static const String _base = "http://localhost:3001";

  static Future<bool> login({
    required String host,
    required String db,
    required String email,
    required String password,
  }) async {
    try {
      final response = await http.post(
        Uri.parse(ApiConfig.login),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "host": host,
          "db": db,
          "email": email,
          "password": password,
        }),
      );

      print("STATUS: ${response.statusCode}");
      print("BODY: ${response.body}");

      if (response.statusCode != 200) {
        throw Exception(jsonDecode(response.body)["message"] ?? "Server error");
      }

      final data = jsonDecode(response.body);
      return data["success"] == true;

    } catch (e) {
      print("AUTH ERROR: $e");
      rethrow;
    }
  }
}