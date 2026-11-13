import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'api_client.dart';
import 'api_config.dart';
import 'local_storage_service.dart';

// Consolidation screens. What they read (adjustment status, consolidation
// sheets, zones, sheet details) is kept on the phone, so they still open
// without network; [prefetch] downloads it all during the offline
// preparation. Actions (verified quantity, validate, create, apply) change
// the stock in Odoo and need the connection.
class ConsolidationService {
  static const String offlineMessage =
      "Hors ligne : la consolidation de cet inventaire n'a pas encore été "
      "copiée sur ce téléphone. Ouvrez-la une fois avec du réseau.";

  // Calls the route; without network, falls back to the last answer kept
  // under [cacheName] (or throws [offlineMessage] when there is none).
  static Future<({http.Response? response, dynamic cached})> _read(
    String route,
    Map<String, dynamic> params,
    String cacheName,
  ) async {
    try {
      final response = await ApiClient.call(route, params: params);
      return (response: response, cached: null);
    } catch (e) {
      final cached = await LocalStorageService.getCachedResponse(cacheName);
      if (cached != null) return (response: null, cached: cached);
      debugPrint("Consolidation $cacheName offline, no copy: $e");
      throw Exception(offlineMessage);
    }
  }

  // Get all consolidation sheets for an adjustment
  static Future<List<dynamic>> getConsolidationSheets(int adjustmentId) async {
    final cacheName = 'consolidation_sheets_$adjustmentId';
    final read = await _read(ApiConfig.consolidationSheets, {
      'adjustment_id': adjustmentId,
    }, cacheName);
    if (read.cached is List) return read.cached as List;
    final response = read.response!;

    if (response.statusCode != 200) {
      throw Exception(ApiClient.errorMessage(response));
    }
    final data = jsonDecode(response.body);
    final List<dynamic> sheets;
    if (data is List) {
      sheets = data;
    } else if (data is Map &&
        data['success'] == true &&
        data['sheets'] is List) {
      sheets = data['sheets'];
    } else {
      sheets = [];
    }
    await LocalStorageService.cacheResponse(cacheName, sheets);
    return sheets;
  }

  // Get consolidation sheet details with lines
  static Future<Map<String, dynamic>?> getConsolidationSheetDetail(
    int sheetId,
  ) async {
    final cacheName = 'consolidation_sheet_$sheetId';
    try {
      final read = await _read(ApiConfig.consolidationSheet, {
        'sheet_id': sheetId,
      }, cacheName);
      if (read.cached is Map) {
        return Map<String, dynamic>.from(read.cached as Map);
      }
      final response = read.response!;
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body);
      if (data is! Map) return null;
      await LocalStorageService.cacheResponse(cacheName, data);
      return Map<String, dynamic>.from(data);
    } catch (e) {
      debugPrint("Get consolidation sheet detail error: $e");
      return null;
    }
  }

  // Update verified quantity for a contradictory line
  static Future<ApiResult> updateContradictoryLine(
    int lineId,
    int verifiedQty,
  ) async {
    try {
      final response = await ApiClient.call(
        ApiConfig.updateContradictoryLine,
        params: {'line_id': lineId, 'verified_qty': verifiedQty},
      );
      return ApiResult.fromResponse(response);
    } catch (e) {
      debugPrint("updateContradictoryLine error: $e");
      return _offlineAction(e);
    }
  }

  // Validate consolidation sheet
  static Future<ApiResult> validateConsolidationSheet(int sheetId) async {
    try {
      final response = await ApiClient.call(
        ApiConfig.validateConsolidationSheet,
        params: {'sheet_id': sheetId},
        timeout: ApiConfig.submitTimeout,
      );
      return ApiResult.fromResponse(response);
    } catch (e) {
      debugPrint("validateConsolidationSheet error: $e");
      return _offlineAction(e);
    }
  }

  // Zones ready for consolidation
  static Future<List<dynamic>> getConsolidationZones(int adjustmentId) async {
    final cacheName = 'consolidation_zones_$adjustmentId';
    final read = await _read(ApiConfig.consolidationZones, {
      'adjustment_id': adjustmentId,
    }, cacheName);
    if (read.cached is List) return read.cached as List;
    final response = read.response!;

    if (response.statusCode != 200) {
      throw Exception(ApiClient.errorMessage(response));
    }
    final data = jsonDecode(response.body);
    final zones =
        data is Map && data['success'] == true && data['zones'] is List
        ? data['zones'] as List
        : <dynamic>[];
    await LocalStorageService.cacheResponse(cacheName, zones);
    return zones;
  }

  // Create consolidation sheet (uses existing Odoo wizard)
  static Future<int?> createConsolidationSheet({
    required int adjustmentId,
    required int zoneId,
  }) async {
    final http.Response response;
    try {
      response = await ApiClient.call(
        ApiConfig.createConsolidation,
        params: {'adjustment_id': adjustmentId, 'zone_id': zoneId},
        timeout: ApiConfig.submitTimeout,
      );
    } catch (e) {
      debugPrint("Create consolidation error: $e");
      throw Exception(_offlineAction(e).message);
    }

    if (response.statusCode == 200) {
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        return data['consolidation_sheet_id'];
      }
      return null;
    }
    throw Exception(ApiClient.errorMessage(response));
  }

  // Apply consolidation to stock
  static Future<ApiResult> applyConsolidation(int adjustmentId) async {
    try {
      final response = await ApiClient.call(
        ApiConfig.applyConsolidation,
        params: {'adjustment_id': adjustmentId},
        timeout: ApiConfig.submitTimeout,
      );
      return ApiResult.fromResponse(response);
    } catch (e) {
      debugPrint("applyConsolidation error: $e");
      return _offlineAction(e);
    }
  }

  // Adjustment status
  static Future<Map<String, dynamic>?> getAdjustmentStatus(
    int adjustmentId,
  ) async {
    final cacheName = 'adjustment_status_$adjustmentId';
    try {
      final read = await _read(ApiConfig.adjustmentStatus, {
        'adjustment_id': adjustmentId,
      }, cacheName);
      if (read.cached is Map) {
        return Map<String, dynamic>.from(read.cached as Map);
      }
      final response = read.response!;
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body);
      if (data is Map && data['success'] == true && data['adjustment'] is Map) {
        final adjustment = Map<String, dynamic>.from(data['adjustment']);
        await LocalStorageService.cacheResponse(cacheName, adjustment);
        return adjustment;
      }
      return null;
    } catch (e) {
      debugPrint("Get adjustment status error: $e");
      return null;
    }
  }

  // Offline preparation: keeps on the phone everything the consolidation
  // screens of the adjustment read. Users without consolidation rights get
  // an Odoo refusal, ignored here.
  static Future<void> prefetch(int adjustmentId) async {
    try {
      await getAdjustmentStatus(adjustmentId);
      final sheets = await getConsolidationSheets(adjustmentId);
      try {
        await getConsolidationZones(adjustmentId);
      } catch (_) {}
      for (final sheet in sheets) {
        final id = sheet is Map ? sheet['id'] : null;
        if (id is int) await getConsolidationSheetDetail(id);
      }
    } catch (e) {
      debugPrint("Consolidation prefetch $adjustmentId: $e");
    }
  }

  // An action needs Odoo: clear message when the network is the cause.
  static ApiResult _offlineAction(Object e) {
    final result = ApiResult.fromException(e);
    final text = e.toString();
    if (text.contains('SocketException') ||
        text.contains('ClientException') ||
        text.contains('délai dépassé') ||
        text.contains('Hors ligne')) {
      return const ApiResult.error(
        'Hors ligne : cette action modifie le stock dans Odoo et a besoin '
        'du réseau. Réessayez une fois la connexion revenue.',
      );
    }
    return result;
  }
}
