import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'api_config.dart';

// Outcome of a call whose failure reason must reach the user (Odoo's own
// message, e.g. "Veuillez terminer le comptage précédent").
class ApiResult {
  final bool success;
  final String? message;

  const ApiResult.ok([this.message]) : success = true;
  const ApiResult.error(this.message) : success = false;

  // Builds the result from an API response ({success, message}).
  factory ApiResult.fromResponse(http.Response response) {
    Map<String, dynamic>? data;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) data = decoded;
    } catch (_) {}

    if (response.statusCode == 200 && data?['success'] == true) {
      return ApiResult.ok(data?['message']?.toString());
    }
    if (response.statusCode == 401) {
      return const ApiResult.error(
        'Session expirée : veuillez vous reconnecter.',
      );
    }
    final message = data?['message']?.toString();
    return ApiResult.error(
      message != null && message.isNotEmpty
          ? message
          : 'Erreur serveur (${response.statusCode})',
    );
  }

  // Network failure (timeout, no Wi-Fi...).
  factory ApiResult.fromException(Object e) {
    final text = e.toString().replaceFirst('Exception: ', '');
    if (text.contains('SocketException') || text.contains('ClientException')) {
      return const ApiResult.error(
        'Impossible de joindre le serveur. Vérifiez la connexion.',
      );
    }
    return ApiResult.error(text);
  }
}

// Calls to the Odoo server entered at login, in JSON-RPC, with the Odoo
// session cookie. Every call has a timeout, so a dropped Wi-Fi never leaves
// a screen waiting forever (a timeout throws an Exception with a readable
// message, handled by callers like any other network error).
//
// [call] returns an http.Response shaped like a REST answer, so services
// read it the same way whatever the route:
//  - 200 with the route's result as body;
//  - the result's `_status` when the route sets one (400 refusal, 404...);
//  - 401 when the Odoo session expired (the call is replayed once after
//    logging in again with the saved credentials);
//  - 400 with {success: false, message} for an Odoo error (UserError,
//    ValidationError, access refused...);
//  - 404 when the route doesn't exist (module not updated on the server).
class ApiClient {
  // Set by SyncService: called with true when Odoo answered, false when it
  // could not be reached. Drives the offline mode.
  static void Function(bool online)? onNetworkStatus;

  // Set at startup: logs in again with the saved credentials. Used when
  // Odoo answers that the session expired.
  static Future<bool> Function()? reauthenticate;
  static Future<bool>? _reauthInProgress;

  // Saved by AuthService (URL as typed at login).
  static const String _hostKey = 'session_host';

  static String? _host;
  // Value of the Odoo session_id cookie.
  static String? _sessionId;
  // Whether the last call reached the server (shortens the default
  // timeout while offline).
  static bool _reachable = true;
  // When the server was last found unreachable. While offline, calls fail
  // at once (screens use the phone's copy) and the server is tried again
  // at most every [_retryOfflineAfter].
  static DateTime? _unreachableSince;
  static const Duration _retryOfflineAfter = Duration(seconds: 20);

  // Login with the saved session running at startup: calls wait for it a
  // little, so they carry the new session instead of being refused.
  static Future<void>? startupLogin;

  // Above this size, the answer is decoded in a background isolate.
  static const int _bigBody = 50000;

  // Server used before the first login of this run (saved session).
  static Future<String?> _currentHost() async {
    if (_host != null) return _host;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_hostKey);
    return _host = saved == null ? null : normalizeHost(saved);
  }

  static String normalizeHost(String host) {
    var value = host.trim();
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    if (!value.startsWith('http://') && !value.startsWith('https://')) {
      value = 'http://$value';
    }
    return value;
  }

  // App started without network: the first screens use the phone's copy
  // after [ApiConfig.offlineTimeout] instead of the full timeout.
  static void markUnreachable() {
    _reachable = false;
    _unreachableSince = DateTime.now();
  }

  // Decoded JSON body of a response, off the UI thread when it is large
  // (offline copy of an adjustment).
  static Future<dynamic> decode(http.Response response) {
    final body = response.body;
    return body.length > _bigBody ? compute(_decodeJson, body) : Future.value(jsonDecode(body));
  }

  static void clearSession() {
    _sessionId = null;
    _host = null;
  }

  // Calls a JSON route of the Odoo server.
  // [force]: try the server even while offline (connection check).
  static Future<http.Response> call(
    String route, {
    Map<String, dynamic> params = const {},
    Duration? timeout,
    bool force = false,
  }) async {
    final login = startupLogin;
    if (login != null) {
      // Still logging in after 3 s: the server is probably out of reach,
      // so this call doesn't wait the full timeout either.
      var loggedIn = true;
      await login.timeout(
        const Duration(seconds: 3),
        onTimeout: () => loggedIn = false,
      );
      if (!loggedIn) timeout ??= ApiConfig.offlineTimeout;
    }
    final since = _unreachableSince;
    if (!force &&
        !_reachable &&
        since != null &&
        DateTime.now().difference(since) < _retryOfflineAfter) {
      throw Exception('Hors ligne : serveur injoignable');
    }
    var response = await _attempt(route, params, timeout);

    if (response.statusCode == 401 && reauthenticate != null) {
      // Concurrent expirations share one login.
      final ok = await (_reauthInProgress ??= reauthenticate!().whenComplete(
        () => _reauthInProgress = null,
      ));
      if (ok) response = await _attempt(route, params, timeout);
    }
    return response;
  }

  // Opens an Odoo session. Returns the session info (uid, name...) or
  // throws: [OdooAuthException] when Odoo refused the login, another
  // exception when the server couldn't be reached.
  static Future<Map<String, dynamic>> authenticate({
    required String host,
    required String db,
    required String login,
    required String password,
    Duration? timeout,
  }) async {
    final server = normalizeHost(host);
    final http.Response response;
    try {
      response = await http
          .post(
            Uri.parse('$server${ApiConfig.authenticate}'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'jsonrpc': '2.0',
              'method': 'call',
              'params': {'db': db, 'login': login, 'password': password},
            }),
          )
          .timeout(timeout ?? ApiConfig.timeout);
    } on TimeoutException {
      markUnreachable();
      onNetworkStatus?.call(false);
      throw Exception('Le serveur ne répond pas (délai dépassé)');
    } catch (_) {
      markUnreachable();
      onNetworkStatus?.call(false);
      rethrow;
    }
    _reachable = true;
    onNetworkStatus?.call(true);

    final Map<String, dynamic> data;
    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw Exception(
        "Le serveur n'a pas renvoyé une réponse Odoo valide. Vérifiez l'URL.",
      );
    }
    final error = data['error'];
    if (error is Map) {
      final name =
          (error['data'] is Map ? error['data']['name'] : null)?.toString() ??
          '';
      if (name.contains('AccessDenied')) {
        throw OdooAuthException('Email ou mot de passe incorrect.');
      }
      throw OdooAuthException(_errorMessage(error));
    }
    final result = data['result'];
    if (result is! Map || result['uid'] == null || result['uid'] == false) {
      throw OdooAuthException('Email ou mot de passe incorrect.');
    }

    _host = server;
    _sessionId = _sessionCookie(response) ?? _sessionId;
    return Map<String, dynamic>.from(result);
  }

  // Databases of the server, or an empty list when the server hides it.
  static Future<List<String>> databases(String host) async {
    try {
      final response = await http
          .post(
            Uri.parse('${normalizeHost(host)}${ApiConfig.databaseList}'),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'jsonrpc': '2.0',
              'method': 'call',
              'params': {},
            }),
          )
          .timeout(const Duration(seconds: 10));
      final data = jsonDecode(response.body);
      if (data is Map && data['result'] is List) {
        return List<String>.from(data['result']);
      }
    } catch (e) {
      print("Get databases error: $e");
    }
    return [];
  }

  static Future<http.Response> _attempt(
    String route,
    Map<String, dynamic> params,
    Duration? timeout,
  ) async {
    final host = await _currentHost();
    if (host == null) {
      return _json(401, {'success': false, 'message': 'Non connecté'});
    }

    final http.Response raw;
    try {
      raw = await http
          .post(
            Uri.parse('$host$route'),
            headers: {
              'Content-Type': 'application/json',
              if (_sessionId != null) 'Cookie': 'session_id=$_sessionId',
            },
            body: jsonEncode({
              'jsonrpc': '2.0',
              'method': 'call',
              'params': params,
            }),
          )
          .timeout(
            timeout ??
                (_reachable ? ApiConfig.timeout : ApiConfig.offlineTimeout),
          );
      _reachable = true;
      onNetworkStatus?.call(true);
    } on TimeoutException {
      markUnreachable();
      onNetworkStatus?.call(false);
      throw Exception('Le serveur ne répond pas (délai dépassé)');
    } catch (_) {
      markUnreachable();
      onNetworkStatus?.call(false);
      rethrow;
    }

    _sessionId = _sessionCookie(raw) ?? _sessionId;

    if (raw.statusCode == 404) {
      return _json(404, {
        'success': false,
        'message':
            "Le module wise_inventory n'est pas à jour sur le serveur Odoo.",
      });
    }
    if (raw.statusCode != 200) {
      return _json(raw.statusCode, {
        'success': false,
        'message': 'Erreur serveur (${raw.statusCode})',
      });
    }

    // Large answers (offline copy) are unwrapped off the UI thread.
    final body = raw.body;
    final unwrapped = body.length > _bigBody
        ? await compute(_unwrapRpc, body)
        : _unwrapRpc(body);
    if (unwrapped.sessionExpired) _sessionId = null;
    return http.Response.bytes(
      utf8.encode(unwrapped.body),
      unwrapped.status,
      headers: const {'content-type': 'application/json; charset=utf-8'},
    );
  }

  // Message to show for a failed response: Odoo's reason when there is
  // one, otherwise a generic French message.
  static String errorMessage(http.Response response) {
    try {
      final data = jsonDecode(response.body);
      final message = data is Map ? data['message'] : null;
      if (message is String && message.isNotEmpty) return message;
    } catch (_) {}
    return 'Erreur du serveur Odoo (${response.statusCode}).';
  }

  static String _errorMessage(Map error) => _rpcErrorMessage(error);


  static String? _sessionCookie(http.Response response) {
    final header = response.headers['set-cookie'];
    if (header == null) return null;
    return RegExp(r'session_id=([^;,\s]+)').firstMatch(header)?.group(1);
  }

  static http.Response _json(int status, Object? body) => http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    status,
    headers: const {'content-type': 'application/json; charset=utf-8'},
  );
}

// Odoo refused the login (wrong credentials, unknown database...).
class OdooAuthException implements Exception {
  final String message;
  OdooAuthException(this.message);

  @override
  String toString() => message;
}

dynamic _decodeJson(String body) => jsonDecode(body);

String _rpcErrorMessage(Map error) {
  final details = error['data'];
  final message = details is Map ? details['message'] : null;
  return (message ?? error['message'] ?? 'Erreur Odoo').toString();
}

// JSON-RPC answer of Odoo turned into the app's body and status (see
// ApiClient). A plain function so it can run in an isolate.
({int status, String body, bool sessionExpired}) _unwrapRpc(String raw) {
  String encode(Object? value) => jsonEncode(value);
  final dynamic data;
  try {
    data = jsonDecode(raw);
  } catch (_) {
    return (
      status: 502,
      body: encode({'success': false, 'message': 'Réponse invalide du serveur Odoo'}),
      sessionExpired: false,
    );
  }

  final error = data is Map ? data['error'] : null;
  if (error is Map) {
    final name =
        (error['data'] is Map ? error['data']['name'] : null)?.toString() ?? '';
    if (name.contains('SessionExpired')) {
      return (
        status: 401,
        body: encode({'success': false, 'message': 'Session expirée'}),
        sessionExpired: true,
      );
    }
    return (
      status: 400,
      body: encode({'success': false, 'message': _rpcErrorMessage(error)}),
      sessionExpired: false,
    );
  }

  final result = data is Map ? data['result'] : null;
  var status = 200;
  if (result is Map && result['_status'] is int) {
    status = result.remove('_status') as int;
  }
  return (status: status, body: encode(result), sessionExpired: false);
}
