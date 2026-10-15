import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'api_client.dart';
import 'api_config.dart';
import 'local_storage_service.dart';

// Offline scanning: the lot/serial numbers in stock in the sheet's location
// (with their product) and the numbers already sent to the ERP for the
// sheet, kept on the phone per account and per sheet. Downloaded while
// online (sheet list, scanning page), used by every scan so it needs no
// network.
class SheetCacheService {
  static const String _prefix = 'sheet_lots_';

  // Decoded caches, so a scan doesn't decode the stored JSON again.
  static final Map<String, _SheetCache> _memory = {};

  static Future<String> _key(int sheetId) async {
    final sessionId = await LocalStorageService.getSessionId();
    return '$_prefix${sessionId}_$sheetId';
  }

  // Downloads the sheet's numbers. Returns how many are available offline,
  // or null when the server couldn't be reached (the previous copy stays).
  static Future<int?> refresh(int sheetId) async {
    try {
      final response = await ApiClient.get(
        Uri.parse('${ApiConfig.baseUrl}/counting/sheet-lots/$sheetId'),
        timeout: ApiConfig.cacheTimeout,
      );
      if (response.statusCode != 200) return null;
      final data = jsonDecode(response.body);
      if (data['success'] != true || data['lots'] is! List) return null;

      final lots = <String, Map<String, dynamic>>{};
      for (final lot in data['lots']) {
        final name = lot['lot_name'];
        if (name is String) lots[name] = Map<String, dynamic>.from(lot);
      }
      final cache = _SheetCache(
        lots: lots,
        sent: Set<String>.from(data['sent'] ?? const []),
        updatedAt: DateTime.now(),
      );

      final key = await _key(sheetId);
      _memory[key] = cache;
      await _persist(key, cache);
      return lots.length;
    } catch (e) {
      print("Sheet cache refresh error: $e");
      return null;
    }
  }

  // Product of a number kept for this sheet, or null if it isn't known.
  static Future<Map<String, dynamic>?> findLot(int sheetId, String barcode) async {
    return (await _load(sheetId))?.lots[barcode];
  }

  // Whether this number was already sent to the ERP for the sheet (as of
  // the last download, plus what this phone sent since).
  static Future<bool> isSent(int sheetId, String barcode) async {
    return (await _load(sheetId))?.sent.contains(barcode) ?? false;
  }

  static Future<int> count(int sheetId) async {
    return (await _load(sheetId))?.lots.length ?? 0;
  }

  // Called after a successful send, so a rescan offline is flagged.
  static Future<void> markSent(int sheetId, Iterable<String> numbers) async {
    final key = await _key(sheetId);
    final cache = await _load(sheetId);
    if (cache == null) return;
    cache.sent.addAll(numbers);
    await _persist(key, cache);
  }

  static Future<_SheetCache?> _load(int sheetId) async {
    final key = await _key(sheetId);
    final cached = _memory[key];
    if (cached != null) return cached;

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(key);
    if (raw == null) return null;
    try {
      final cache = _SheetCache.fromJson(jsonDecode(raw));
      _memory[key] = cache;
      return cache;
    } catch (e) {
      print("Sheet cache read error: $e");
      return null;
    }
  }

  static Future<void> _persist(String key, _SheetCache cache) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, jsonEncode(cache.toJson()));
  }
}

class _SheetCache {
  final Map<String, Map<String, dynamic>> lots;
  final Set<String> sent;
  final DateTime updatedAt;

  _SheetCache({required this.lots, required this.sent, required this.updatedAt});

  Map<String, dynamic> toJson() => {
        'lots': lots.values.toList(),
        'sent': sent.toList(),
        'updated_at': updatedAt.toIso8601String(),
      };

  factory _SheetCache.fromJson(Map<String, dynamic> json) => _SheetCache(
        lots: {
          for (final lot in json['lots'] as List)
            lot['lot_name'] as String: Map<String, dynamic>.from(lot),
        },
        sent: Set<String>.from(json['sent'] ?? const []),
        updatedAt: DateTime.tryParse(json['updated_at'] ?? '') ?? DateTime.now(),
      );
}
