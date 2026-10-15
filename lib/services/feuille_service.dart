import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_client.dart';
import 'api_config.dart';
import 'local_storage_service.dart';

class FeuilleService {
  static Future<List<dynamic>> getFeuilles(int adjustmentId) async {
    final cacheName = 'feuilles_$adjustmentId';
    try {
      final http.Response response;
      try {
        response = await ApiClient.get(Uri.parse(ApiConfig.feuilles(adjustmentId)));
      } catch (e) {
        // Offline: last list received for this adjustment, if any.
        final cached = await LocalStorageService.getCachedResponse(cacheName);
        if (cached is List) return cached;
        rethrow;
      }

      print("feuilles status: ${response.statusCode}");

      if (response.statusCode != 200) {
        final errorData = jsonDecode(response.body);
        print("Error response: $errorData");
        // Return empty list and let the UI handle the error via exception
        throw Exception(errorData['message'] ?? 'Server error');
      }

      final data = jsonDecode(response.body);

      if (data is Map && data.containsKey("success") && data["success"] == false) {
        throw Exception(data["message"] ?? 'Unknown error');
      }

      if (data is List) {
        await LocalStorageService.cacheResponse(cacheName, data);
        return data;
      } else {
        throw Exception("Invalid data format from server");
      }
    } catch (e) {
      print("Feuilles service error: $e");
      rethrow;
    }
  }
}