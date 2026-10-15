import 'dart:async';
import 'package:http/http.dart' as http;
import 'api_config.dart';

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
