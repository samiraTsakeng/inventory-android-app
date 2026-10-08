import 'package:shared_preferences/shared_preferences.dart';

class ApiConfig {
  static const String baseUrl = "http://192.168.10.111:3001";

  static String get adjustments => "$baseUrl/adjustments";
  static String get login => "$baseUrl/auth/login";
  static String feuilles(int adjustmentId) => "$baseUrl/feuilles/$adjustmentId";

  static Future<Map<String, String>> authHeaders({bool json = false}) async {
    final prefs = await SharedPreferences.getInstance();
    final token = prefs.getString('app_session_token');
    final headers = <String, String>{};
    if (json) headers['Content-Type'] = 'application/json';
    if (token != null && token.isNotEmpty) headers['Authorization'] = 'Bearer $token';
    return headers;
  }
}
