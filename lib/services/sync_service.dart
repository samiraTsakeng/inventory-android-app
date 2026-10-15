import 'dart:async';
import 'package:flutter/material.dart';
import 'api_client.dart';
import 'api_config.dart';
import 'auth_service.dart';
import 'counting_service.dart';
import 'batch_storage_service.dart';

// Offline mode: knows whether the backend is reachable (from every API
// call), checks again periodically while it isn't, and when it comes back
// sends the batches saved in the meantime.
class SyncService {
  // false while the backend can't be reached.
  static final ValueNotifier<bool> online = ValueNotifier(true);
  // Saved batches not sent to the ERP yet.
  static final ValueNotifier<int> pendingBatches = ValueNotifier(0);
  // Lets the service show snackbars without a BuildContext (set on
  // MaterialApp.scaffoldMessengerKey).
  static final GlobalKey<ScaffoldMessengerState> messengerKey = GlobalKey();

  static const Duration _probeInterval = Duration(seconds: 15);
  static Timer? _probeTimer;
  static bool _isSyncing = false;

  // Called once at startup, before runApp.
  static void start({required bool startOffline}) {
    ApiClient.onNetworkStatus = _setOnline;
    ApiClient.reauthenticate = AuthService.reauthenticate;
    if (startOffline) _setOnline(false);
    refreshPendingCount();
  }

  static void _setOnline(bool value) {
    if (online.value == value) return;
    online.value = value;
    if (value) {
      _probeTimer?.cancel();
      _probeTimer = null;
      _onReconnected();
    } else {
      _probeTimer ??= Timer.periodic(_probeInterval, (_) => _probe());
    }
  }

  // Any answer from the backend switches back online (through ApiClient).
  static Future<void> _probe() async {
    try {
      await ApiClient.get(
        Uri.parse('${ApiConfig.baseUrl}/'),
        timeout: const Duration(seconds: 5),
      );
    } catch (_) {}
  }

  static Future<void> _onReconnected() async {
    await CountingService.replayPendingClears();
    if (pendingBatches.value == 0) return;
    final result = await syncPendingData();
    if (result.synced == 0 && result.failed == 0) return;
    messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(result.failed == 0
            ? 'Connexion rétablie : ${result.synced} lot(s) envoyé(s)'
            : 'Connexion rétablie : ${result.synced} lot(s) envoyé(s), '
                '${result.failed} en échec (voir la liste des lots)'),
        backgroundColor: result.failed == 0 ? Colors.green : Colors.orange,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  // Sends every saved batch not synced yet. Safe to run alongside a manual
  // send: the backend skips lines already in the ERP.
  static Future<({int synced, int failed})> syncPendingData() async {
    if (_isSyncing) return (synced: 0, failed: 0);
    _isSyncing = true;
    int synced = 0;
    int failed = 0;

    try {
      final batches = await BatchStorageService.getBatches();
      for (final batch in batches.where((b) => !b.isSynced)) {
        final result = await CountingService.submitScannedItems(
          countingSheetId: batch.countingSheetId,
          adjustmentId: batch.adjustmentId,
          items: batch.items,
        );

        if (result.success) {
          await BatchStorageService.markBatchAsSynced(batch.id);
          synced++;
        } else {
          failed++;
          print("Auto-sync failed for ${batch.name}: ${result.message}");
          // Connection lost again: the next reconnection retries.
          if (!online.value) break;
        }
      }
    } catch (e) {
      print("Sync error: $e");
    } finally {
      _isSyncing = false;
      await refreshPendingCount();
    }
    return (synced: synced, failed: failed);
  }

  static Future<void> refreshPendingCount() async {
    try {
      final batches = await BatchStorageService.getBatches();
      pendingBatches.value = batches.where((b) => !b.isSynced).length;
    } catch (_) {}
  }

  // Check if there are pending items
  static Future<bool> hasPendingData() async {
    final batches = await BatchStorageService.getBatches();
    return batches.any((b) => !b.isSynced);
  }
}
