import 'package:shared_preferences/shared_preferences.dart';

class Storage {
  static Future<void> saveUserData(
      String host, String db, String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('host', host);
    await prefs.setString('db', db);
    await prefs.setString('email', email);
  }

  static Future<Map<String, String>?> getUserData() async {
    final prefs = await SharedPreferences.getInstance();
    final host = prefs.getString('host');
    final email = prefs.getString('email');
    if (host == null || email == null) return null;
    return {
      'host': host,
      'db': prefs.getString('db') ?? '',
      'email': email,
    };
  }

  static Future<void> clearUserData() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.clear();
  }
}