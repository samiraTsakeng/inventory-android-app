import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class Storage {
  static final _storage = FlutterSecureStorage();

  static Future saveUserData(String host, String db, String email) async {
    await _storage.write(key: "host", value: host);
    await _storage.write(key: "db", value: db);
    await _storage.write(key: "email", value: email);
  }

  static Future<Map<String, String>?> getUserData() async {
    String? host = await _storage.read(key: "host");
    String? email = await _storage.read(key: "email");

    if (host != null && email != null) {
      return {
        "host": host,
        "email": email
      };
    }
    return null;
  }
}