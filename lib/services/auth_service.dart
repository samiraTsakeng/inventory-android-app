import 'dart:convert';
import 'package:http/http.dart' as http;

class AuthService {
  static Future<bool> login({
    required String host,
    required String db,
    required String email,
    required String password,
  }) async {

    final response = await http.post(
      Uri.parse("http://localhost:3000/auth/login"),
      headers: {"Content-Type": "application/json"},
      body: jsonEncode({
        "host": host,
        "db": db,
        "email": email,
        "password": password
      }),
    );

    final data = jsonDecode(response.body);
    return data["success"];
  }
}