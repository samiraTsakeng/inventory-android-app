import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/constants.dart';
import 'adjustment_service.dart';
import 'auth_service.dart';
import 'local_storage_service.dart';
import 'sheet_cache_service.dart';
import 'sync_service.dart';

// Automatic offline preparation: once connected, everything needed to count
// without network is downloaded with the user's Odoo rights, for every
// adjustment they work on (list of adjustments, their sheets, the serial /
// lot numbers in stock and what each sheet already sent).
//
// Runs after login, at startup when Odoo answers, and when the connection
// comes back (if the last preparation is older than [_refreshAfter]). The
// user can then count with no network at all.
class OfflinePrepService {
  static const Duration _refreshAfter = Duration(minutes: 15);
  static const String _lastRunPrefix = 'offline_prep_last_';

  // true while a preparation is running.
  static final ValueNotifier<bool> running = ValueNotifier(false);
  // Bumped after each preparation, so open screens reload what's cached.
  static final ValueNotifier<int> revision = ValueNotifier(0);

  static Future<OfflinePrepResult?>? _current;

  // Prepares every adjustment. Concurrent calls share one run. Returns
  // null when Odoo couldn't be reached.
  static Future<OfflinePrepResult?> prepareAll({bool notify = true}) {
    return _current ??= _run(notify).whenComplete(() => _current = null);
  }

  // Prepares again if the last preparation is old (connection back).
  static Future<void> refreshIfStale() async {
    // Not connected yet, or a login is saving its session: the login page
    // starts the preparation itself once logged in.
    if (AuthService.loginInProgress || !await AuthService.isLoggedIn()) return;
    final last = await lastRun();
    if (last == null || DateTime.now().difference(last) > _refreshAfter) {
      await prepareAll();
    }
  }

  static Future<DateTime?> lastRun() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(await _lastRunKey());
    return raw == null ? null : DateTime.tryParse(raw);
  }

  static Future<String> _lastRunKey() async =>
      '$_lastRunPrefix${await LocalStorageService.getSessionId()}';

  static Future<OfflinePrepResult?> _run(bool notify) async {
    if (!SyncService.online.value) return null;
    running.value = true;
    try {
      final List<dynamic> adjustments;
      try {
        adjustments = await AdjustmentService.getAdjustments();
      } catch (e) {
        print("Offline prep: adjustments unavailable: $e");
        return null;
      }
      // getAdjustments falls back to the cached list without network.
      if (!SyncService.online.value) return null;

      var prepared = 0;
      var sheets = 0;
      var numbers = 0;
      var failed = 0;
      for (final adjustment in adjustments) {
        final id = adjustment is Map ? adjustment['id'] : null;
        if (id is! int) continue;
        final result = await SheetCacheService.prepareAdjustment(id);
        if (result == null) {
          failed++;
          // Network lost in the middle: stop, what's done is kept.
          if (!SyncService.online.value) break;
          continue;
        }
        if (result.sheets > 0) {
          prepared++;
          sheets += result.sheets;
          numbers += result.lots;
        }
      }

      final result = OfflinePrepResult(
          adjustments: prepared, sheets: sheets, numbers: numbers, failed: failed);
      if (failed == 0) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(await _lastRunKey(), DateTime.now().toIso8601String());
      }
      if (notify) _notify(result);
      return result;
    } finally {
      running.value = false;
      revision.value++;
    }
  }

  static void _notify(OfflinePrepResult result) {
    final messenger = SyncService.messengerKey.currentState;
    if (messenger == null) return;
    final ok = result.failed == 0;
    final text = result.sheets == 0
        ? (ok
            ? 'Mode hors ligne prêt : aucune feuille de comptage à préparer.'
            : 'Préparation du hors ligne incomplète. Réessayez avec une meilleure connexion.')
        : ok
            ? 'Mode hors ligne prêt : ${result.sheets} feuille(s), ${result.numbers} numéros.'
            : 'Hors ligne préparé en partie (${result.sheets} feuille(s)). '
                'Réessayez avec une meilleure connexion.';
    messenger.showSnackBar(SnackBar(
      content: Text(text),
      backgroundColor: ok ? AppColors.successColor : AppColors.warningColor,
      duration: const Duration(seconds: 3),
    ));
  }
}

class OfflinePrepResult {
  final int adjustments;
  final int sheets;
  final int numbers;
  final int failed;

  const OfflinePrepResult({
    required this.adjustments,
    required this.sheets,
    required this.numbers,
    required this.failed,
  });
}
