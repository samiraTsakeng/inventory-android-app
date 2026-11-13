import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';
import 'api_config.dart';
import '../utils/barcode.dart';
import '../models/scanned_item.dart';
import 'local_storage_service.dart';
import 'sheet_cache_service.dart';
import 'sync_service.dart';

class CountingService {
  // OFFLINE-FIRST: Check cache, then API.
  // [offline] is true when the number is unknown to the phone and the
  // server couldn't be asked: the caller may keep it "to verify".
  static Future<
    ({Map<String, dynamic>? product, bool alreadyInErp, bool offline})
  >
  lookupProduct(
    String barcode, {
    required int countingSheetId,
    required int adjustmentId,
  }) async {
    barcode = cleanBarcode(barcode);
    // 1. Numbers of the adjustment kept on the phone: no network at all.
    final sheetLot = await SheetCacheService.findLot(adjustmentId, barcode);
    if (sheetLot != null) {
      final sent = await SheetCacheService.isSent(countingSheetId, barcode);
      return (product: sheetLot, alreadyInErp: sent, offline: false);
    }

    try {
      // 2. Number already looked up on this phone.
      final cachedProduct = await LocalStorageService.getCachedProduct(barcode);
      if (cachedProduct != null) {
        final alreadyInErp = await isAlreadyInErp(
          countingSheetId: countingSheetId,
          barcode: barcode,
        );
        return (
          product: cachedProduct,
          alreadyInErp: alreadyInErp,
          offline: false,
        );
      }

      // 3. Unknown here and no network: don't wait for a timeout.
      if (!SyncService.online.value) {
        return (product: null, alreadyInErp: false, offline: true);
      }

      // 4. Ask the server: one round trip returns the product and whether
      // this number is already in the ERP for the sheet.
      final response = await ApiClient.call(
        ApiConfig.lookupProduct,
        params: {'barcode': barcode, 'counting_sheet_id': countingSheetId},
        timeout: ApiConfig.lookupTimeout,
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final alreadyInErp = data['already_sent'] == true;
        if (data['success'] == true && data['product'] != null) {
          final product = Map<String, dynamic>.from(data['product']);
          await LocalStorageService.cacheProduct(barcode, product);
          return (product: product, alreadyInErp: alreadyInErp, offline: false);
        }
        return (product: null, alreadyInErp: alreadyInErp, offline: false);
      }
      return (product: null, alreadyInErp: false, offline: false);
    } catch (e) {
      // Network failure: the number couldn't be checked.
      debugPrint("Product lookup error: $e");
      return (product: null, alreadyInErp: false, offline: true);
    }
  }

  // Identifies numbers scanned offline ("to verify") in one call.
  // Returns number -> product for those found, or null if the server
  // couldn't be reached.
  static Future<Map<String, Map<String, dynamic>>?> _resolvePending(
    List<String> barcodes,
  ) async {
    try {
      final response = await ApiClient.call(
        ApiConfig.lookupProducts,
        params: {'barcodes': barcodes},
        force: true,
      );
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body);
      if (data['success'] != true || data['products'] is! Map) return null;
      return {
        for (final entry in (data['products'] as Map).entries)
          entry.key as String: Map<String, dynamic>.from(entry.value),
      };
    } catch (e) {
      debugPrint("Resolve pending error: $e");
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getSheetState(int sheetId) async {
    try {
      final response = await ApiClient.call(
        ApiConfig.sheetState,
        params: {'sheet_id': sheetId},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['sheet'];
      }
      return null;
    } catch (e) {
      debugPrint("Get sheet state error: $e");
      return null;
    }
  }

  static Future<ApiResult> startSheet(int sheetId) async {
    try {
      final response = await ApiClient.call(
        ApiConfig.startSheet,
        params: {'sheet_id': sheetId},
      );
      return ApiResult.fromResponse(response);
    } catch (e) {
      debugPrint("Start sheet error: $e");
      return ApiResult.fromException(e);
    }
  }

  static Future<ApiResult> validateSheet(int sheetId) async {
    try {
      final response = await ApiClient.call(
        ApiConfig.validateSheet,
        params: {'sheet_id': sheetId},
      );
      return ApiResult.fromResponse(response);
    } catch (e) {
      debugPrint("Validate sheet error: $e");
      return ApiResult.fromException(e);
    }
  }

  static Future<ApiResult> submitScannedItems({
    required int countingSheetId,
    required int adjustmentId,
    required List<ScannedItem> items,
  }) async {
    try {
      if (items.isEmpty) {
        return const ApiResult.error('Aucun article à envoyer');
      }

      // Numbers scanned offline are identified first. If one doesn't exist
      // in Odoo nothing is sent, so the user can remove it and resend.
      var toSend = items;
      final pending = items
          .where((item) => item.isPendingLookup)
          .map((item) => item.barcode)
          .toSet()
          .toList();
      if (pending.isNotEmpty) {
        final resolved = await _resolvePending(pending);
        if (resolved == null) {
          return const ApiResult.error(
            'Impossible de vérifier les numéros scannés hors ligne. Réessayez.',
          );
        }
        final unknown = pending.where((b) => !resolved.containsKey(b)).toList();
        if (unknown.isNotEmpty) {
          return ApiResult.error(
            '${unknown.length} numéro(s) introuvable(s) dans Odoo : '
            '${unknown.take(5).join(', ')}. '
            'Supprimez-les de la liste puis renvoyez.',
          );
        }
        toSend = items.map((item) {
          final product = resolved[item.barcode];
          if (!item.isPendingLookup || product == null) return item;
          return ScannedItem(
            barcode: item.barcode,
            productName: product['name'] ?? '',
            productId: product['id'],
            quantity: item.quantity,
            lotNumber: product['lot_name'],
            lotId: product['lot_id'],
            tracking: product['tracking'] ?? 'serial',
          );
        }).toList();
      }

      final response = await ApiClient.call(
        ApiConfig.submit,
        params: {
          'counting_sheet_id': countingSheetId,
          'adjustment_id': adjustmentId,
          'items': toSend.map((e) => e.toJson()).toList(),
        },
        timeout: ApiConfig.submitTimeout,
        force: true,
      );
      final result = ApiResult.fromResponse(response);
      if (result.success) {
        // A rescan of these numbers is now flagged even offline.
        await SheetCacheService.markSent(
          countingSheetId,
          toSend.map((item) => item.lotNumber ?? item.barcode),
        );
      }
      return result;
    } catch (e) {
      debugPrint("Submit error: $e");
      return ApiResult.fromException(e);
    }
  }

  // SHARED LIVE SESSION (two phones, same sheet)

  // Returns the shared list and its version, or null when the server still
  // has version [since] (nothing changed) or the request failed.
  static Future<({int version, List<Map<String, dynamic>> items})?>
  getLiveItems(int countingSheetId, {int? since}) async {
    try {
      final response = await ApiClient.call(
        ApiConfig.liveItems,
        params: {'sheet_id': countingSheetId, 'since': ?since},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['items'] is List) {
          return (
            version: (data['version'] as num?)?.toInt() ?? 0,
            items: List<Map<String, dynamic>>.from(data['items']),
          );
        }
      }
      return null;
    } catch (e) {
      debugPrint("Get live items error: $e");
      return null;
    }
  }

  // The scans made since the last push, in one call (instead of one call
  // per scan). Returns the shared list as it is now, or null if it
  // couldn't be sent (the scans stay queued). A server without this route
  // (module not updated yet) gets them one by one, as before.
  static Future<List<Map<String, dynamic>>?> pushLiveScans({
    required int countingSheetId,
    required List<Map<String, dynamic>> items,
  }) async {
    try {
      final response = await ApiClient.call(
        ApiConfig.livePush,
        params: {'counting_sheet_id': countingSheetId, 'items': items},
      );
      if (response.statusCode == 404) {
        List<Map<String, dynamic>>? last;
        for (final item in items) {
          last = await pushLiveScan(
            countingSheetId: countingSheetId,
            item: item,
          );
          if (last == null) return null;
        }
        return last;
      }
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['items'] is List) {
          return List<Map<String, dynamic>>.from(data['items']);
        }
      }
      return null;
    } catch (e) {
      debugPrint("Push live scans error: $e");
      return null;
    }
  }

  static Future<List<Map<String, dynamic>>?> pushLiveScan({
    required int countingSheetId,
    required Map<String, dynamic> item,
  }) async {
    try {
      final response = await ApiClient.call(
        ApiConfig.liveScan,
        params: {'counting_sheet_id': countingSheetId, ...item},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['items'] is List) {
          return List<Map<String, dynamic>>.from(data['items']);
        }
      }
      return null;
    } catch (e) {
      debugPrint("Push live scan error: $e");
      return null;
    }
  }

  // A clear that failed (offline) is remembered and replayed before any
  // other live sync, otherwise the old shared list would come back on the
  // phone once the connection returns.
  static const String _pendingClearsKey = 'pending_live_clears';
  static Future<void>? _replaying;

  static Future<bool> clearLiveItems(int countingSheetId) async {
    final ok = await _postClear(countingSheetId);
    if (!ok) await _setPendingClear(countingSheetId, true);
    return ok;
  }

  static Future<bool> hasPendingClears() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_pendingClearsKey) ?? const []).isNotEmpty;
  }

  // Replays the clears still pending. Concurrent callers share one run, so
  // a scanning page can await it before pushing its queued scans.
  static Future<void> replayPendingClears() {
    return _replaying ??= _doReplayPendingClears().whenComplete(
      () => _replaying = null,
    );
  }

  static Future<void> _doReplayPendingClears() async {
    final prefs = await SharedPreferences.getInstance();
    final pending = prefs.getStringList(_pendingClearsKey) ?? const [];
    for (final id in pending) {
      final sheetId = int.tryParse(id);
      if (sheetId == null || await _postClear(sheetId)) {
        await _setPendingClear(sheetId ?? -1, false, raw: id);
      }
    }
  }

  static Future<bool> _postClear(int countingSheetId) async {
    try {
      final response = await ApiClient.call(
        ApiConfig.liveClear,
        params: {'sheet_id': countingSheetId},
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint("Clear live items error: $e");
      return false;
    }
  }

  static Future<void> _setPendingClear(
    int sheetId,
    bool pending, {
    String? raw,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final ids = (prefs.getStringList(_pendingClearsKey) ?? []).toSet();
    final id = raw ?? '$sheetId';
    if (pending) {
      ids.add(id);
    } else {
      ids.remove(id);
    }
    await prefs.setStringList(_pendingClearsKey, ids.toList());
  }

  // FIX #5: remove a single barcode from the shared live session —
  // called after deleting an item from the list, so a later rescan of
  // the same barcode doesn't get blocked as "already scanned".
  static Future<bool> removeLiveItem({
    required int countingSheetId,
    required String barcode,
  }) async {
    try {
      final response = await ApiClient.call(
        ApiConfig.liveRemove,
        params: {'sheet_id': countingSheetId, 'barcode': barcode},
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint("Remove live item error: $e");
      return false;
    }
  }

  // FIX #6: check whether this barcode already exists in the ERP for
  // this counting sheet, before submitting. Prevents duplicates.
  static Future<bool> isAlreadyInErp({
    required int countingSheetId,
    required String barcode,
  }) async {
    // Offline: answer from what the phone knows instead of waiting.
    if (!SyncService.online.value) {
      return SheetCacheService.isSent(countingSheetId, barcode);
    }
    try {
      final response = await ApiClient.call(
        ApiConfig.checkErpScan,
        params: {'counting_sheet_id': countingSheetId, 'barcode': barcode},
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['alreadySent'] == true;
      }
      return false;
    } catch (e) {
      debugPrint("Check ERP scan error: $e");
      return false; // fail-open: don't block scanning if check fails
    }
  }

  // Same check as isAlreadyInErp for many barcodes in one request.
  // Returns the barcodes already present in the ERP for this sheet.
  static Future<Set<String>> alreadyInErp({
    required int countingSheetId,
    required List<String> barcodes,
  }) async {
    if (barcodes.isEmpty) return {};
    try {
      final response = await ApiClient.call(
        ApiConfig.checkErpScans,
        params: {'counting_sheet_id': countingSheetId, 'barcodes': barcodes},
        force: true,
      );
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['alreadySent'] is List) {
          return Set<String>.from(data['alreadySent']);
        }
      }
      return {};
    } catch (e) {
      debugPrint("Check ERP scans error: $e");
      return {}; // fail-open: the server also skips duplicates on submit
    }
  }
}
