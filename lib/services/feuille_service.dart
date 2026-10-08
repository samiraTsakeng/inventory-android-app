import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_config.dart';
import 'local_storage_service.dart';

class FeuilleService {
  static Future<List<dynamic>> getFeuilles(int adjustmentId) async {
    http.Response response;
    try {
      response = await http
          .get(Uri.parse(ApiConfig.feuilles(adjustmentId)), headers: await ApiConfig.authHeaders())
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      // ✅ True network failure (offline, timeout, DNS, unreachable host…)
      // — fall back to the last successfully fetched list for this
      // adjustment, so the counting sheets page stays usable offline,
      // the same way products already work offline.
      print("Feuilles fetch network error, falling back to cache: $e");
      final cached = await LocalStorageService.getCachedFeuilles(adjustmentId);
      if (cached.isNotEmpty) {
        print("Loaded ${cached.length} feuilles from offline cache");
        return cached;
      }
      // Nothing cached yet (first time offline) — surface the real error
      // instead of silently pretending there are zero counting sheets.
      rethrow;
    }

    try {
      print("feuilles status: ${response.statusCode}");
      print("Feuilles body: ${response.body}");

      if (response.statusCode != 200) {
        final errorData = jsonDecode(response.body);
        print("Error response: $errorData");
        // Return empty list and let the UI handle the error via exception
        throw Exception(errorData['message'] ?? 'Server error');
      }

      final data = jsonDecode(response.body);
      print("Decoded data type: ${data.runtimeType}");

      if (data is Map && data.containsKey("success") && data["success"] == false) {
        throw Exception(data["message"] ?? 'Unknown error');
      }

      if (data is List) {
        // ✅ Cache every successful fetch so it's available offline later.
        await LocalStorageService.cacheFeuilles(adjustmentId, data);
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