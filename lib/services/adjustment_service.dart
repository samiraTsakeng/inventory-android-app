import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_client.dart';
import 'api_config.dart';
import 'local_storage_service.dart';

class AdjustmentService {
  //static const String _base = "http://127.0.0.1:3000";

  static Future<List<dynamic>> getAdjustments() async {
    final http.Response response;
    try {
      response = await ApiClient.get(Uri.parse(ApiConfig.adjustments));
    } catch (e) {
      // Offline: last list received, if any.
      final cached = await LocalStorageService.getCachedResponse('adjustments');
      if (cached is List) return cached;
      rethrow;
    }

    print("status: ${response.statusCode}");

    if(response.statusCode != 200) {
      throw Exception("server errror: ${response.body}");
    }

    final data = jsonDecode(response.body);

    // HANDLE BACKEND ERRORS (IMPORTANT)
    if (data is Map && data.containsKey("success") && data["success"] == false) {
      throw Exception(data["message"]);
    }

    // ENSURE LIST
    if (data is List) {
      await LocalStorageService.cacheResponse('adjustments', data);
      return data;
    } else {
      throw Exception("Invalid data format from server");
    }
  }
}