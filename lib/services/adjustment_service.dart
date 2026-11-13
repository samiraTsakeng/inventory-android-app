import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_client.dart';
import 'api_config.dart';
import 'list_cache.dart';
import 'local_storage_service.dart';

class AdjustmentService {
  //static const String _base = "http://127.0.0.1:3000";

  // The phone's copy at once, refreshed in the background (ListCache).
  // [fresh]: the server's list (offline preparation).
  static Future<List<dynamic>> getAdjustments({bool fresh = false}) =>
      ListCache.get('adjustments', _fetchAdjustments, fresh: fresh);

  static Future<List<dynamic>> _fetchAdjustments() async {
    final http.Response response;
    try {
      response = await ApiClient.call(ApiConfig.adjustments);
    } catch (e) {
      // Offline: last list received, if any.
      final cached = await LocalStorageService.getCachedResponse('adjustments');
      if (cached is List) return cached;
      rethrow;
    }

    debugPrint("status: ${response.statusCode}");

    if (response.statusCode != 200) {
      throw Exception(ApiClient.errorMessage(response));
    }

    final data = jsonDecode(response.body);

    // HANDLE BACKEND ERRORS (IMPORTANT)
    if (data is Map &&
        data.containsKey("success") &&
        data["success"] == false) {
      throw Exception(data["message"]);
    }

    // ENSURE LIST
    if (data is List) {
      await LocalStorageService.cacheResponse('adjustments', data);
      return data;
    } else {
      throw Exception("Réponse inattendue du serveur Odoo.");
    }
  }
}
