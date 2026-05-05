import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_config.dart';

class AuthService {
  static const String _sessionHostKey = 'session_host';
  static const String _sessionDbKey = 'session_db';
  static const String _sessionEmailKey = 'session_email';

  static Future<bool> login({
    required String host,
    required String db,
    required String email,
    required String password,
  }) async {
    try {
      // First, get available databases
      List<String> databases = await _getDatabases(host);
      print("Available databases: $databases");

      String dbName = db.trim();

      // If no database provided, use the first available
      if (dbName.isEmpty && databases.isNotEmpty) {
        dbName = databases.first;
        print("Auto-selected database: $dbName");
      }

      // If still no database, try to detect
      if (dbName.isEmpty) {
        dbName = await _detectDatabase(host, email, password);
        if (dbName.isEmpty) {
          throw Exception("No database found. Please check your connection.");
        }
      }

      final response = await http.post(
        Uri.parse(ApiConfig.login),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "host": host,
          "db": dbName,
          "email": email,
          "password": password,
        }),
      );

      print("STATUS: ${response.statusCode}");
      print("BODY: ${response.body}");

      if (response.statusCode != 200) {
        final errorData = jsonDecode(response.body);
        throw Exception(errorData["message"] ?? "Server error");
      }

      final data = jsonDecode(response.body);

      if (data["success"] == true) {
        // Save session
        await _saveSession(host, dbName, email);
        return true;
      }

      return false;

    } catch (e) {
      print("AUTH ERROR: $e");
      rethrow;
    }
  }

  static Future<List<String>> _getDatabases(String host) async {
    try {
      final response = await http.post(
        Uri.parse("$host/web/database/list"),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['result'] != null && data['result'] is List) {
          return List<String>.from(data['result']);
        }
      }
      return [];
    } catch (e) {
      print("Get databases error: $e");
      return [];
    }
  }

  static Future<String> _detectDatabase(String host, String email, String password) async {
    try {
      // Try to authenticate with common database names
      final commonDbs = ['odoo_db', 'odoo', 'postgres', 'default'];

      for (String dbName in commonDbs) {
        try {
          final response = await http.post(
            Uri.parse(ApiConfig.login),
            headers: {"Content-Type": "application/json"},
            body: jsonEncode({
              "host": host,
              "db": dbName,
              "email": email,
              "password": password,
            }),
          );

          if (response.statusCode == 200) {
            final data = jsonDecode(response.body);
            if (data["success"] == true) {
              return dbName;
            }
          }
        } catch (e) {
          continue;
        }
      }
      return '';
    } catch (e) {
      print("Detect database error: $e");
      return '';
    }
  }

  static Future<void> _saveSession(String host, String db, String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionHostKey, host);
    await prefs.setString(_sessionDbKey, db);
    await prefs.setString(_sessionEmailKey, email);
  }

  static Future<Map<String, String?>?> getSession() async {
    final prefs = await SharedPreferences.getInstance();
    final host = prefs.getString(_sessionHostKey);
    final db = prefs.getString(_sessionDbKey);
    final email = prefs.getString(_sessionEmailKey);

    if (host != null && email != null) {
      return {
        'host': host,
        'db': db ?? '',
        'email': email,
      };
    }
    return null;
  }

  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionHostKey);
    await prefs.remove(_sessionDbKey);
    await prefs.remove(_sessionEmailKey);
  }

  static Future<bool> secondAuthentication(String password) async {
    try {
      final session = await getSession();
      if (session == null) {
        throw Exception("No session found. Please login again.");
      }

      return await login(
        host: session['host']!,
        db: session['db'] ?? '',
        email: session['email']!,
        password: password,
      );
    } catch (e) {
      print("Second authentication error: $e");
      rethrow;
    }
  }
}