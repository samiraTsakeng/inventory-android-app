import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';
import 'api_config.dart';
import 'local_storage_service.dart';

// Offline counting: kept on the phone per account,
//  - per adjustment: the lot/serial numbers in stock in the inventoried
//    location, with their product (shared by all the adjustment's sheets);
//  - per sheet: the numbers already sent to the ERP.
// Downloaded while online ("Préparer le hors ligne", sheet list, scanning
// page); every scan reads it, so scanning needs no network.
class SheetCacheService {
  static const String _lotsPrefix = 'adj_lots_';
  static const String _sentPrefix = 'sheet_sent_';

  // Decoded copies, so a scan doesn't decode the stored JSON again.
  static final Map<String, _LotCache> _lots = {};
  static final Map<String, Set<String>> _sent = {};

  static Future<String> _lotsKey(int adjustmentId) async =>
      '$_lotsPrefix${await LocalStorageService.getSessionId()}_$adjustmentId';

  static Future<String> _sentKey(int sheetId) async =>
      '$_sentPrefix${await LocalStorageService.getSessionId()}_$sheetId';

  // Downloads everything needed to count the adjustment offline: the
  // user's sheets (kept for the sheet list), the numbers and what each
  // sheet already sent. Returns null when the server couldn't be reached.
  static Future<({int sheets, int lots})?> prepareAdjustment(int adjustmentId) async {
    try {
      final response = await ApiClient.get(
        Uri.parse('${ApiConfig.baseUrl}/counting/offline-pack/$adjustmentId'),
        timeout: ApiConfig.cacheTimeout,
      );
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body);
      if (data['success'] != true || data['lots'] is! List || data['feuilles'] is! List) {
        return null;
      }

      final feuilles = data['feuilles'] as List;
      await LocalStorageService.cacheResponse('feuilles_$adjustmentId', feuilles);
      final lotCount = await _storeLots(adjustmentId, data['lots']);

      final sent = (data['sent'] as Map?) ?? const {};
      for (final sheet in feuilles) {
        final sheetId = sheet['id'];
        if (sheetId is! int) continue;
        await _storeSent(sheetId, List<String>.from(sent['$sheetId'] ?? const []));
      }
      return (sheets: feuilles.length, lots: lotCount);
    } catch (e) {
      print("Prepare adjustment error: $e");
      return null;
    }
  }

  // Same for a single sheet (scanning page): refreshes the numbers and what
  // the sheet already sent. Returns how many numbers are available offline,
  // or null when the server couldn't be reached (the previous copy stays).
  static Future<int?> refresh(int sheetId, int adjustmentId) async {
    try {
      final response = await ApiClient.get(
        Uri.parse('${ApiConfig.baseUrl}/counting/sheet-lots/$sheetId'),
        timeout: ApiConfig.cacheTimeout,
      );
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body);
      if (data['success'] != true || data['lots'] is! List) return null;

      await _storeSent(sheetId, List<String>.from(data['sent'] ?? const []));
      return await _storeLots(adjustmentId, data['lots']);
    } catch (e) {
      print("Sheet cache refresh error: $e");
      return null;
    }
  }

  // Product of a number of the adjustment's location, or null.
  static Future<Map<String, dynamic>?> findLot(int adjustmentId, String barcode) async {
    return (await _loadLots(adjustmentId))?.lots[barcode];
  }

  // Whether this number was already sent to the ERP for the sheet (as of
  // the last download, plus what this phone sent since).
  static Future<bool> isSent(int sheetId, String barcode) async {
    return (await _loadSent(sheetId)).contains(barcode);
  }

  // Numbers available offline for the adjustment and when they were taken.
  static Future<({int count, DateTime? updatedAt})> info(int adjustmentId) async {
    final cache = await _loadLots(adjustmentId);
    return (count: cache?.lots.length ?? 0, updatedAt: cache?.updatedAt);
  }

  // Called after a successful send, so a rescan offline is flagged.
  static Future<void> markSent(int sheetId, Iterable<String> numbers) async {
    final sent = await _loadSent(sheetId);
    sent.addAll(numbers);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(await _sentKey(sheetId), sent.toList());
  }

  static Future<int> _storeLots(int adjustmentId, List lots) async {
    final cache = _LotCache(
      lots: {
        for (final lot in lots)
          if (lot['lot_name'] is String)
            lot['lot_name'] as String: Map<String, dynamic>.from(lot),
      },
      updatedAt: DateTime.now(),
    );
    final key = await _lotsKey(adjustmentId);
    _lots[key] = cache;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(cache.toJson()));
    return cache.lots.length;
  }

  static Future<void> _storeSent(int sheetId, List<String> numbers) async {
    final key = await _sentKey(sheetId);
    _sent[key] = numbers.toSet();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(key, numbers);
  }

  static Future<_LotCache?> _loadLots(int adjustmentId) async {
    final key = await _lotsKey(adjustmentId);
    final cached = _lots[key];
    if (cached != null) return cached;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return null;
    try {
      final cache = _LotCache.fromJson(jsonDecode(raw));
      _lots[key] = cache;
      return cache;
    } catch (e) {
      print("Lot cache read error: $e");
      return null;
    }
  }

  static Future<Set<String>> _loadSent(int sheetId) async {
    final key = await _sentKey(sheetId);
    final cached = _sent[key];
    if (cached != null) return cached;

    final prefs = await SharedPreferences.getInstance();
    final sent = (prefs.getStringList(key) ?? const []).toSet();
    _sent[key] = sent;
    return sent;
  }
}

class _LotCache {
  final Map<String, Map<String, dynamic>> lots;
  final DateTime updatedAt;

  _LotCache({required this.lots, required this.updatedAt});

  Map<String, dynamic> toJson() => {
        'lots': lots.values.toList(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory _LotCache.fromJson(Map<String, dynamic> json) => _LotCache(
        lots: {
          for (final lot in json['lots'] as List)
            lot['lot_name'] as String: Map<String, dynamic>.from(lot),
        },
        updatedAt: DateTime.tryParse(json['updated_at'] ?? '') ?? DateTime.now(),
      );
}
