import 'package:flutter/foundation.dart';
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
        response = await ApiClient.call(
          ApiConfig.feuilles,
          params: {'adjustment_id': adjustmentId},
        );
      } catch (e) {
        // Offline: last list received for this adjustment, if any.
        final cached = await LocalStorageService.getCachedResponse(cacheName);
        if (cached is List) return cached;
        debugPrint("Feuilles $adjustmentId offline, no copy: $e");
        throw Exception(
          "Hors ligne : les feuilles de cet inventaire n'ont pas encore été "
          "copiées sur ce téléphone. Ouvrez-le une fois avec du réseau.",
        );
      }

      debugPrint("feuilles status: ${response.statusCode}");

      if (response.statusCode != 200) {
        final errorData = jsonDecode(response.body);
        debugPrint("Error response: $errorData");
        // Return empty list and let the UI handle the error via exception
        throw Exception(
          errorData['message'] ?? ApiClient.errorMessage(response),
        );
      }

      final data = jsonDecode(response.body);

      if (data is Map &&
          data.containsKey("success") &&
          data["success"] == false) {
        throw Exception(data["message"] ?? 'Erreur inconnue.');
      }

      if (data is List) {
        await LocalStorageService.cacheResponse(cacheName, data);
        return data;
      } else {
        throw Exception("Réponse inattendue du serveur Odoo.");
      }
    } catch (e) {
      debugPrint("Feuilles service error: $e");
      rethrow;
    }
  }
}
