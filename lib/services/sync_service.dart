import 'dart:async';
import 'package:flutter/material.dart';
import 'api_client.dart';
import 'api_config.dart';
import 'auth_service.dart';
import 'counting_service.dart';
import 'batch_storage_service.dart';
import 'offline_actions_service.dart';

// Offline mode: knows whether the backend is reachable (from every API
// call), checks again periodically while it isn't, and when it comes back
// sends what was done offline, sheet by sheet. A sheet can also be sent
// by hand (syncSheet).
class SyncService {
  // false while the backend can't be reached.
  static final ValueNotifier<bool> online = ValueNotifier(true);
  // Saved batches not sent to the ERP yet.
  static final ValueNotifier<int> pendingBatches = ValueNotifier(0);
  // Lets the service show snackbars without a BuildContext (set on
  // MaterialApp.scaffoldMessengerKey).
  static final GlobalKey<ScaffoldMessengerState> messengerKey = GlobalKey();

  // Bumped after each replay of offline work, so open screens (sheet list)
  // reload the states Odoo now has.
  static final ValueNotifier<int> revision = ValueNotifier(0);

  static const Duration _probeInterval = Duration(seconds: 15);
  static Timer? _probeTimer;
  static Future<void>? _flushing;

  // Called once at startup, before runApp.
  static void start({required bool startOffline}) {
    ApiClient.onNetworkStatus = _setOnline;
    ApiClient.reauthenticate = AuthService.reauthenticate;
    refreshPendingCount();
    if (startOffline) {
      _setOnline(false);
    } else {
      // Work left from a previous offline session (app closed before the
      // connection came back) is replayed as soon as the app is up.
      Future.delayed(const Duration(seconds: 2), () async {
        if (await OfflineActionsService.hasPending() ||
            pendingBatches.value > 0 ||
            await CountingService.hasPendingClears()) {
          await flush();
        }
      });
    }
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

  static Future<void> _onReconnected() => flush();

  // Sheets with work to send, in the order Odoo must see it: first the
  // sheets with offline actions, in the order they were done (finish F1
  // before starting F2 of the same zone), then the sheets that only have
  // batches waiting, oldest batch first.
  static Future<List<int>> sheetsToSync() async {
    final order = await OfflineActionsService.sheetsInOrder();
    final batches = (await BatchStorageService.getBatches())
        .where((b) => !b.isSynced)
        .toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    for (final batch in batches) {
      if (!order.contains(batch.countingSheetId)) order.add(batch.countingSheetId);
    }
    return order;
  }

  // Automatic: sends everything done offline, one sheet after the other
  // (start, batches, finish), and shows a summary. Concurrent calls share
  // one run.
  static Future<void> flush() {
    return _flushing ??= _exclusive(() async {
      final results = await _syncSheets(await sheetsToSync());
      _showSummary(results);
    }).whenComplete(() => _flushing = null);
  }

  // Manual: sends one sheet ("Envoyer" on the sheet, or after sending a
  // batch from the batch list). Returns what was done.
  static Future<SheetSyncResult> syncSheet(int sheetId) {
    return _exclusive(() async => (await _syncSheets([sheetId])).first);
  }

  // One sync at a time (automatic and manual), so a start or a finish is
  // never replayed twice in parallel.
  static Future<void> _queue = Future.value();

  static Future<T> _exclusive<T>(Future<T> Function() task) {
    final previous = _queue;
    final done = Completer<void>();
    _queue = done.future;
    return previous.then((_) => task()).whenComplete(done.complete);
  }

  static Future<List<SheetSyncResult>> _syncSheets(List<int> sheetIds) async {
    await CountingService.replayPendingClears();
    final results = <SheetSyncResult>[];
    for (final sheetId in sheetIds) {
      final result = await _syncOneSheet(sheetId);
      results.add(result);
      if (result.offline) break; // Connection lost: retried later.
    }
    revision.value++;
    await refreshPendingCount();
    return results;
  }

  // Start (if done offline) -> its batches, oldest first -> finish (if
  // done offline, and only once every batch reached the ERP). Stops at the
  // first refusal: what follows would be refused too.
  static Future<SheetSyncResult> _syncOneSheet(int sheetId) async {
    final allBatches = await BatchStorageService.getBatches();
    final sheetBatches = allBatches.where((b) => b.countingSheetId == sheetId).toList();
    final result = SheetSyncResult(
      sheetId,
      sheetBatches.isNotEmpty ? sheetBatches.first.sheetName : 'Feuille $sheetId',
    );

    final start = await OfflineActionsService.replayStart(sheetId);
    if (start.isOffline) return result..offline = true;
    if (start.isRefused) return result..error = start.message;
    result.started = start.isDone;

    final pending = sheetBatches.where((b) => !b.isSynced).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    for (final batch in pending) {
      final sent = await CountingService.submitScannedItems(
        countingSheetId: batch.countingSheetId,
        adjustmentId: batch.adjustmentId,
        items: batch.items,
      );
      if (sent.success) {
        await BatchStorageService.markBatchAsSynced(batch.id);
        result.batchesSent++;
      } else if (!online.value) {
        return result..offline = true;
      } else {
        return result..error = '${batch.name} : ${sent.message}';
      }
    }

    final finish = await OfflineActionsService.replayValidate(sheetId);
    if (finish.isOffline) return result..offline = true;
    if (finish.isRefused) return result..error = finish.message;
    result.finished = finish.isDone;
    return result;
  }

  static void _showSummary(List<SheetSyncResult> results) {
    final lines = [
      for (final r in results)
        if (r.didSomething) r.describe(),
    ];
    if (lines.isEmpty) return;
    final ok = results.every((r) => r.error == null && !r.offline);
    messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text([
          'Synchronisation',
          ...lines.take(4),
          if (lines.length > 4) '…',
        ].join('\n')),
        backgroundColor: ok ? Colors.green : Colors.orange,
        duration: Duration(seconds: ok ? 5 : 10),
      ),
    );
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


// What a sheet sync did, for the messages shown to the user.
class SheetSyncResult {
  final int sheetId;
  final String sheetName;
  bool started = false;
  int batchesSent = 0;
  bool finished = false;
  bool offline = false;
  String? error;

  SheetSyncResult(this.sheetId, this.sheetName);

  bool get didSomething =>
      started || batchesSent > 0 || finished || error != null || offline;

  String describe() {
    final done = [
      if (started) 'commencée',
      if (batchesSent > 0) '$batchesSent lot(s) envoyé(s)',
      if (finished) 'terminée',
    ];
    final problem = error != null
        ? 'refusé : $error'
        : offline
            ? 'connexion perdue, reprise plus tard'
            : null;
    if (done.isEmpty && problem == null) return '$sheetName : rien à envoyer';
    return '$sheetName : ${[...done, if (problem != null) problem].join(', ')}';
  }
}
