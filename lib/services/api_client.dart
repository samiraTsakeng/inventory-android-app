import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';

// Outcome of a call whose failure reason must reach the user (Odoo's own
// message, e.g. "Veuillez terminer le comptage précédent").
class ApiResult {
  final bool success;
  final String? message;

  const ApiResult.ok([this.message]) : success = true;
  const ApiResult.error(this.message) : success = false;

  // Builds the result from a backend response ({success, message}).
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
          'Session expirée : veuillez vous reconnecter.');
    }
    final message = data?['message']?.toString();
    return ApiResult.error(message != null && message.isNotEmpty
        ? message
        : 'Erreur serveur (${response.statusCode})');
  }

  // Network failure (timeout, no Wi-Fi...).
  factory ApiResult.fromException(Object e) {
    final text = e.toString().replaceFirst('Exception: ', '');
    if (text.contains('SocketException') || text.contains('ClientException')) {
      return const ApiResult.error(
          'Impossible de joindre le serveur. Vérifiez la connexion.');
    }
    return ApiResult.error(text);
  }
}

// HTTP calls with a timeout, so a dropped Wi-Fi never leaves a screen
// waiting forever. A timeout throws an Exception with a readable message,
// handled by callers like any other network error.
class ApiClient {
  // Set by SyncService: called with true when the backend answered, false
  // when it could not be reached. Drives the offline mode.
  static void Function(bool online)? onNetworkStatus;

  // Set at startup: logs in again with the saved credentials. Used when the
  // backend answers 401 (it restarted and lost the session).
  static Future<bool> Function()? reauthenticate;
  static Future<bool>? _reauthInProgress;

  static Future<http.Response> get(
    Uri url, {
    Map<String, String>? headers,
    Duration? timeout,
  }) =>
      _send(url, () => http.get(url, headers: headers), timeout);

  static Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) =>
      _send(url, () => http.post(url, headers: headers, body: body), timeout);

  static Future<http.Response> _send(Uri url,
      Future<http.Response> Function() request, Duration? timeout) async {
    // Calls made directly to Odoo (database list) say nothing about the
    // backend, so they don't change the online state.
    final isBackend = url.toString().startsWith(ApiConfig.baseUrl);
    var response = await _attempt(request, timeout, isBackend);

    if (isBackend &&
        response.statusCode == 401 &&
        url.toString() != ApiConfig.login &&
        reauthenticate != null) {
      // Concurrent 401s share one login.
      final ok = await (_reauthInProgress ??= reauthenticate!()
          .whenComplete(() => _reauthInProgress = null));
      if (ok) response = await _attempt(request, timeout, isBackend);
    }
    return response;
  }

  static Future<http.Response> _attempt(
      Future<http.Response> Function() request,
      Duration? timeout,
      bool isBackend) async {
    try {
      final response = await request().timeout(timeout ?? ApiConfig.timeout);
      if (isBackend) onNetworkStatus?.call(true);
      return response;
    } on TimeoutException {
      if (isBackend) onNetworkStatus?.call(false);
      throw Exception('Le serveur ne répond pas (délai dépassé)');
    } catch (_) {
      if (isBackend) onNetworkStatus?.call(false);
      rethrow;
    }
  }
}
