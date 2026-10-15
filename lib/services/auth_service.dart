import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_config.dart';
import 'local_storage_service.dart';

class AuthService {
  static const String _sessionHostKey = 'session_host';
  static const String _sessionDbKey = 'session_db';
  static const String _sessionEmailKey = 'session_email';
  static const String _sessionPasswordKey = 'session_password';
  static const String _sessionUidKey = 'session_uid';
  static const String _sessionNameKey = 'session_name';
  static const String _sessionCreatedAtKey = 'session_created_at';
  // ✅ Session expiry: after this long since login, autoLogin() requires
  // the user to sign in again instead of silently reusing stored
  // credentials indefinitely.
  static const Duration _sessionValidity = Duration(days: 14);

  // ✅ Deterministic session id: same host+email always -> same id.
  // Sanitized so it stays a safe, readable SharedPreferences key fragment.
  static String _generateSessionId(String host, String email) {
    final raw = '${host}_$email'.toLowerCase();
    return raw.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  }

  // Backend worst case is ~15s (db list 5s + parallel auth 10s); leave headroom.
  static const Duration _loginTimeout = Duration(seconds: 30);

  static Future<bool> login({
    required String host,
    required String db,
    required String email,
    required String password,
  }) async {
    try {
      // The database name is optional: when empty, the backend detects it from
      // the Odoo URL and authenticates in the same call. The phone never talks
      // to Odoo directly (no extra round-trips from the device).
      final cleanHost = host.trim().replaceAll(RegExp(r'/+$'), '');

      final response = await http
          .post(
        Uri.parse(ApiConfig.login),
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "host": cleanHost,
          "db": db.trim(),
          "email": email,
          "password": password,
        }),
      )
          .timeout(_loginTimeout);

      print("STATUS: ${response.statusCode}");

      if (response.statusCode != 200) {
        String message = "Server error (${response.statusCode})";
        try {
          final errorData = jsonDecode(response.body);
          message = errorData["message"] ?? message;
        } catch (_) {}
        throw Exception(message);
      }

      final data = jsonDecode(response.body);

      if (data["success"] == true) {
        // ✅ Generate a STABLE session ID based on host + email only.
        // IMPORTANT: this must NOT include a timestamp (see LocalStorageService:
        // a changing ID would orphan unsaved scanned items).
        final sessionId = _generateSessionId(cleanHost, email);

        // Use the database the backend actually detected/used.
        final detectedDb = (data["db"] as String?)?.trim().isNotEmpty == true
            ? data["db"] as String
            : db.trim();

        await _saveSession(
          host: cleanHost,
          db: detectedDb,
          email: email,
          password: password,
          uid: data["uid"],
          name: data["name"],
          sessionId: sessionId,
          appToken: data["token"],
        );

        await LocalStorageService.setSessionId(sessionId);
        return true;
      }

      return false;
    } on TimeoutException {
      print("AUTH ERROR: timeout");
      throw Exception(
          "Le serveur ne répond pas. Vérifiez votre connexion et l'adresse du serveur.");
    } on SocketException {
      print("AUTH ERROR: socket");
      throw Exception(
          "Impossible de joindre le serveur de l'application. Vérifiez le réseau Wi-Fi.");
    } catch (e) {
      print("AUTH ERROR: $e");
      rethrow;
    }
  }

  // Auto-login using stored credentials
  static Future<bool> autoLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isLoggedIn = prefs.getBool('is_logged_in') ?? false;

      if (!isLoggedIn) {
        print ("No saved session found");
        return false;
      }

      // ✅ Session expiry: if it's been more than 14 days since the
      // session was created/last refreshed, force a real re-login instead
      // of silently reusing stored credentials forever.
      final createdAtStr = prefs.getString(_sessionCreatedAtKey);
      if (createdAtStr != null) {
        final createdAt = DateTime.tryParse(createdAtStr);
        if (createdAt != null && DateTime.now().difference(createdAt) > _sessionValidity) {
          print("Session expired (older than ${_sessionValidity.inDays} days) — clearing, user must log in again");
          await clearSession();
          return false;
        }
      }

      final session = await getFullSession();
      if (session == null) {
        print("session data incomplete");
        return false;
      }

      final host = session['host'];
      final db = session['db'] ?? '';
      final email = session['email'];
      final password = session['password'];

      if (host == null || email == null || password == null) {
        print("Missing credentials");
        return false;
      }
      print("attempting auto login for: $email");

      // Try to login with stored credentials

      final success = await login(
        host: host,
        db: db,
        email: email,
        password: password,
      );

      if (success) {
        print("auto-login successful!");
        return true;
      } else {
        print("Auto-login failed, clearing session");
        await clearSession();
        return false;
      }
    } catch (e) {
      print("Auto-login error: $e");
      await clearSession();
      return false;
    }
  }

  static Future<void> _saveSession({
    required String host,
    required String db,
    required String email,
    required String password,
    required int uid,
    required String name,
    required String sessionId,
    required String? appToken,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionHostKey, host);
    await prefs.setString(_sessionDbKey, db);
    await prefs.setString(_sessionEmailKey, email);
    await prefs.setString(_sessionPasswordKey, password);
    await prefs.setInt(_sessionUidKey, uid);
    await prefs.setString(_sessionNameKey, name);
    if (appToken != null && appToken.isNotEmpty) {
      await prefs.setString('app_session_token', appToken);
    }
    await prefs.setBool('is_logged_in', true);
    // ✅ Refreshed on every successful login (manual or auto) — this gives
    // a sliding 14-day window: the session expires 14 days after the LAST
    // time the app was successfully opened/used, not from a fixed date.
    await prefs.setString(_sessionCreatedAtKey, DateTime.now().toIso8601String());
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

  static Future<Map<String, String>?> getSavedConnection() async {
    final prefs = await SharedPreferences.getInstance();

    final host = prefs.getString(_sessionHostKey);
    final db = prefs.getString(_sessionDbKey);

    if (host != null && host.trim().isNotEmpty) {
      return {
        'host': host,
        'db': db ?? '',
      };
    }

    return null;
  }

  static Future<Map<String, String?>?> getFullSession() async {
    final prefs = await SharedPreferences.getInstance();
    final host = prefs.getString(_sessionHostKey);
    final db = prefs.getString(_sessionDbKey);
    final email = prefs.getString(_sessionEmailKey);
    final password = prefs.getString(_sessionPasswordKey);
    final uid = prefs.getInt(_sessionUidKey);
    final name = prefs.getString(_sessionNameKey);

    if (host != null && email != null && password != null) {
      return {
        'host': host,
        'db': db ?? '',
        'email': email,
        'password': password,
        'uid': uid?.toString(),
        'name': name ?? '',
      };
    }
    return null;
  }

  // ✅ Clear session (called on logout)
  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionHostKey);
    await prefs.remove(_sessionDbKey);
    await prefs.remove(_sessionEmailKey);
    await prefs.remove(_sessionPasswordKey);
    await prefs.remove(_sessionUidKey);
    await prefs.remove(_sessionNameKey);
    await prefs.remove(_sessionCreatedAtKey);
    await prefs.remove('is_logged_in');
    await prefs.remove('app_session_token');

    // ✅ Clear all local data for this session
    await LocalStorageService.clearAllSessionData();
  }

  static Future<bool> secondAuthentication(String password) async {
    try {
      final session = await getFullSession();
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