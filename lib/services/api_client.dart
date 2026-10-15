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
  static Future<http.Response> get(
    Uri url, {
    Map<String, String>? headers,
    Duration? timeout,
  }) =>
      _withTimeout(http.get(url, headers: headers), timeout);

  static Future<http.Response> post(
    Uri url, {
    Map<String, String>? headers,
    Object? body,
    Duration? timeout,
  }) =>
      _withTimeout(http.post(url, headers: headers, body: body), timeout);

  static Future<http.Response> _withTimeout(
      Future<http.Response> request, Duration? timeout) {
    return request.timeout(
      timeout ?? ApiConfig.timeout,
      onTimeout: () =>
          throw Exception('Le serveur ne répond pas (délai dépassé)'),
    );
  }
}
