import 'package:flutter/material.dart';
import 'local_storage_service.dart';
import 'counting_service.dart';
import 'batch_storage_service.dart';

class SyncService {
  static final SyncService _instance = SyncService._internal();
  bool _isSyncing = false;

  SyncService._internal();

  factory SyncService() => _instance;

  // Sync pending data when internet is available
  Future<void> syncPendingData(BuildContext context) async {
    if (_isSyncing) return;

    _isSyncing = true;

    try {
      // 1. Sync pending scans from LocalStorageService
      // Note: You'll need to add a pending scans table for this
      // Or use the existing batch system

      // 2. Sync unsynced batches
      final batches = await BatchStorageService.getBatches();
      final unsyncedBatches = batches.where((b) => !b.isSynced).toList();

      if (unsyncedBatches.isNotEmpty) {
        print("Syncing ${unsyncedBatches.length} unsynced batches...");
        int syncedCount = 0;

        for (final batch in unsyncedBatches) {
          final result = await CountingService.submitScannedItems(
            countingSheetId: batch.countingSheetId,
            adjustmentId: batch.adjustmentId,
            items: batch.items,
          );

          if (result.success) {
            await BatchStorageService.markBatchAsSynced(batch.id);
            syncedCount++;
          }
        }

        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('$syncedCount lots synchronisés'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        print("No pending data to sync");
      }
    } catch (e) {
      print("Sync error: $e");
    } finally {
      _isSyncing = false;
    }
  }

  // Check if there are pending items
  Future<bool> hasPendingData() async {
    final batches = await BatchStorageService.getBatches();
    final unsyncedBatches = batches.where((b) => !b.isSynced).toList();
    return unsyncedBatches.isNotEmpty;
  }
}