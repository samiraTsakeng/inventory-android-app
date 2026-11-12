import 'api_client.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'local_storage_service.dart';

enum AutoLoginResult {
  success,
  // Saved session kept, server unreachable: the app opens offline.
  offline,
  rejected,
  noSession,
}

// Odoo refused the credentials (as opposed to a network failure).
class AuthRejectedException implements Exception {
  final String message;
  AuthRejectedException(this.message);

  @override
  String toString() => message;
}

class AuthService {
  static const String _sessionHostKey = 'session_host';
  static const String _sessionDbKey = 'session_db';
  static const String _sessionEmailKey = 'session_email';
  static const String _sessionPasswordKey = 'session_password';
  static const String _sessionUidKey = 'session_uid';
  static const String _sessionNameKey = 'session_name';

  // ✅ Deterministic session id: same host+email always -> same id.
  // Sanitized so it stays a safe, readable SharedPreferences key fragment.
  static String _generateSessionId(String host, String email) {
    final raw = '${host}_$email'.toLowerCase();
    return raw.replaceAll(RegExp(r'[^a-z0-9]+'), '_');
  }

  static Future<bool> login({
    required String host,
    required String db,
    required String email,
    required String password,
  }) async {
    final server = ApiClient.normalizeHost(host);
    // Short: at startup without network the app opens offline sooner.
    const timeout = Duration(seconds: 12);
    final Map<String, dynamic> info;
    String dbName = db.trim();
    try {
      if (dbName.isNotEmpty) {
        info = await ApiClient.authenticate(
          host: server,
          db: dbName,
          login: email,
          password: password,
          timeout: timeout,
        );
      } else {
        // No database given: the one where these credentials are accepted.
        final found = await _authenticateAnyDatabase(
          server,
          email,
          password,
          timeout,
        );
        dbName = found.db;
        info = found.info;
      }
    } on OdooAuthException catch (e) {
      // Odoo refused the credentials: the saved session is forgotten.
      throw AuthRejectedException(e.message);
    }

    // ✅ Stable session id based on host + email only. It must NOT include a
    // timestamp: every app start (silent autoLogin() in main.dart) calls
    // this login(). If the id changed on every login, it would change the
    // SharedPreferences namespace used to persist not-yet-saved scanned
    // items (see LocalStorageService), orphaning articles scanned before a
    // battery death or crash. Deterministic per account, the same user
    // always maps back to the same storage keys.
    final sessionId = _generateSessionId(host, email);

    await _saveSession(
      host: host,
      db: dbName,
      email: email,
      password: password,
      uid: info['uid'] as int,
      name: (info['name'] ?? info['username'] ?? email).toString(),
      sessionId: sessionId,
    );
    await LocalStorageService.setSessionId(sessionId);
    return true;
  }

  // Tries the server's databases (or common names when the list is hidden)
  // until one accepts the credentials.
  static Future<({String db, Map<String, dynamic> info})>
  _authenticateAnyDatabase(
    String host,
    String email,
    String password,
    Duration timeout,
  ) async {
    final listed = await ApiClient.databases(host);
    final candidates = listed.isNotEmpty
        ? listed
        : const ['odoo_db', 'odoo', 'postgres', 'default'];
    OdooAuthException? lastRefusal;
    for (final candidate in candidates) {
      try {
        final info = await ApiClient.authenticate(
          host: host,
          db: candidate,
          login: email,
          password: password,
          timeout: timeout,
        );
        return (db: candidate, info: info);
      } on OdooAuthException catch (e) {
        lastRefusal = e;
      }
    }
    if (listed.length == 1 && lastRefusal != null) throw lastRefusal;
    throw OdooAuthException(
      listed.isEmpty
          ? 'Base de données introuvable : renseignez le nom de la base.'
          : 'Email ou mot de passe incorrect.',
    );
  }

  // Auto-login using stored credentials.
  // Without network the saved session is kept and the app opens offline:
  // scanned items and batches stay on the phone. The session is only
  // cleared when Odoo explicitly rejects the credentials.
  static Future<AutoLoginResult> autoLogin() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final isLoggedIn = prefs.getBool('is_logged_in') ?? false;

      if (!isLoggedIn) {
        print("No saved session found");
        return AutoLoginResult.noSession;
      }
      final session = await getFullSession();
      if (session == null) {
        print("session data incomplete");
        return AutoLoginResult.noSession;
      }

      print("attempting auto login for: ${session['email']}");
      final success = await reauthenticate(rethrowErrors: true);

      if (success) {
        print("auto-login successful!");
        return AutoLoginResult.success;
      } else {
        print("Auto-login failed, clearing session");
        await clearSession();
        return AutoLoginResult.rejected;
      }
    } on AuthRejectedException catch (e) {
      print("Auto-login rejected: $e");
      await clearSession();
      return AutoLoginResult.rejected;
    } catch (e) {
      print("Auto-login offline: $e");
      return AutoLoginResult.offline;
    }
  }

  // Logs in again with the saved credentials, without touching local data.
  // Used at startup, when the network comes back and when Odoo answers
  // that the session expired.
  static Future<bool> reauthenticate({bool rethrowErrors = false}) async {
    try {
      final session = await getFullSession();
      if (session == null) return false;
      return await login(
        host: session['host']!,
        db: session['db'] ?? '',
        email: session['email']!,
        password: session['password']!,
      );
    } catch (e) {
      if (rethrowErrors) rethrow;
      print("Re-authentication failed: $e");
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
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionHostKey, host);
    await prefs.setString(_sessionDbKey, db);
    await prefs.setString(_sessionEmailKey, email);
    await prefs.setString(_sessionPasswordKey, password);
    await prefs.setInt(_sessionUidKey, uid);
    await prefs.setString(_sessionNameKey, name);
    await prefs.setBool('is_logged_in', true);
  }

  static Future<Map<String, String?>?> getSession() async {
    final prefs = await SharedPreferences.getInstance();
    final host = prefs.getString(_sessionHostKey);
    final db = prefs.getString(_sessionDbKey);
    final email = prefs.getString(_sessionEmailKey);

    if (host != null && email != null) {
      return {'host': host, 'db': db ?? '', 'email': email};
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
    await prefs.remove('is_logged_in');
    ApiClient.clearSession();

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
