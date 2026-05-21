import 'package:flutter/material.dart';
import '../models/batch.dart';
import '../services/batch_storage_service.dart';
import '../services/counting_service.dart';
import '../services/local_storage_service.dart';
import '../models/scanned_item.dart';
import 'scanned_items_list_page.dart';

class BatchesListPage extends StatefulWidget {
  final int countingSheetId;
  final int adjustmentId;
  final String zoneName;
  final String sheetName;

  const BatchesListPage({
    Key? key,
    required this.countingSheetId,
    required this.adjustmentId,
    required this.zoneName,
    required this.sheetName,
  }) : super(key: key);

  @override
  State<BatchesListPage> createState() => _BatchesListPageState();
}

class _BatchesListPageState extends State<BatchesListPage> {
  List<Batch> _batches = [];
  bool _isLoading = true;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadBatches();
  }

  Future<void> _loadBatches() async {
    setState(() => _isLoading = true);
    final batches = await BatchStorageService.getBatches();
    // Filter batches for current counting sheet
    _batches = batches.where((b) => b.countingSheetId == widget.countingSheetId).toList();
    setState(() => _isLoading = false);
  }

  Future<void> _syncBatch(Batch batch) async {
    setState(() => _isSyncing = true);

    try {
      // Send batch items to ERP
      final success = await CountingService.submitScannedItems(
        countingSheetId: batch.countingSheetId,
        adjustmentId: batch.adjustmentId,
        items: batch.items,
      );

      if (success) {
        // Mark batch as synced and remove
        await BatchStorageService.markBatchAsSynced(batch.id);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('✅ Batch synchronisé avec succès !'),
              backgroundColor: Colors.green,
            ),
          );
          await _loadBatches();
        }
      } else {
        throw Exception('Échec de la synchronisation');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Erreur: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  Future<void> _syncAllBatches() async {
    final unsyncedBatches = _batches.where((b) => !b.isSynced).toList();
    if (unsyncedBatches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aucun batch à synchroniser'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isSyncing = true);

    int successCount = 0;
    int failCount = 0;

    for (final batch in unsyncedBatches) {
      try {
        final success = await CountingService.submitScannedItems(
          countingSheetId: batch.countingSheetId,
          adjustmentId: batch.adjustmentId,
          items: batch.items,
        );

        if (success) {
          await BatchStorageService.markBatchAsSynced(batch.id);
          successCount++;
        } else {
          failCount++;
        }
      } catch (e) {
        failCount++;
      }
    }

    if (mounted) {
      setState(() => _isSyncing = false);
      await _loadBatches();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ $successCount batches synchronisés, $failCount échoués'),
          backgroundColor: failCount > 0 ? Colors.orange : Colors.green,
        ),
      );
    }
  }

  void _viewBatchItems(Batch batch) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ScannedItemsListPage(
          items: batch.items,
          sheetName: 'Batch: ${batch.name}',
          countingSheetId: batch.countingSheetId,
          adjustmentId: batch.adjustmentId,
          onItemsUpdated: (updatedItems) {
            // Update batch items
            batch.items.clear();
            batch.items.addAll(updatedItems);
            // In a real app, you'd save the updated batch
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text('Batches sauvegardés', style: TextStyle(fontSize: 16)),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 22),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_batches.isNotEmpty)
            IconButton(
              icon: _isSyncing
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.sync, size: 20),
              onPressed: _isSyncing ? null : _syncAllBatches,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _batches.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'Aucun batch sauvegardé',
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
            const SizedBox(height: 8),
            Text(
              'Scannez et utilisez "Enregistrer" pour créer un batch',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
          ],
        ),
      )
          : Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${_batches.length} batch(es)',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  Text(
                    '${_batches.where((b) => !b.isSynced).length} à synchroniser',
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 0.8,
              ),
              itemCount: _batches.length,
              itemBuilder: (context, index) {
                final batch = _batches[index];
                return GestureDetector(
                  onTap: () => _viewBatchItems(batch),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: batch.isSynced
                          ? Border.all(color: Colors.green, width: 2)
                          : null,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.grey.withOpacity(0.1),
                          spreadRadius: 1,
                          blurRadius: 4,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: batch.isSynced ? Colors.green[100] : Colors.blue[100],
                            borderRadius: BorderRadius.circular(25),
                          ),
                          child: Icon(
                            batch.isSynced ? Icons.check_circle : Icons.save,
                            color: batch.isSynced ? Colors.green : Colors.blue,
                            size: 28,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          batch.name,
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${batch.items.length} articles',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          batch.isSynced ? 'Synchronisé' : 'En attente',
                          style: TextStyle(
                            fontSize: 10,
                            color: batch.isSynced ? Colors.green : Colors.orange,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (!batch.isSynced)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: ElevatedButton(
                              onPressed: _isSyncing ? null : () => _syncBatch(batch),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.green,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(20),
                                ),
                              ),
                              child: const Text('Sync', style: TextStyle(fontSize: 10)),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: _batches.isNotEmpty
          ? FloatingActionButton.extended(
        onPressed: _isSyncing ? null : _syncAllBatches,
        icon: _isSyncing
            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.sync),
        label: const Text('Tout synchroniser'),
        backgroundColor: Colors.green,
      )
          : null,
    );
  }
}