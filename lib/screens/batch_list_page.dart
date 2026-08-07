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
  List<Batch> _selectedBatches = [];
  bool _isLoading = true;
  bool _isSyncing = false;
  bool _isSelectionMode = false;

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
    _selectedBatches.clear();
    _isSelectionMode = false;
    setState(() => _isLoading = false);
  }

  void _toggleSelection(Batch batch) {
    setState(() {
      if (_selectedBatches.contains(batch)) {
        _selectedBatches.remove(batch);
      } else {
        _selectedBatches.add(batch);
      }
      _isSelectionMode = _selectedBatches.isNotEmpty;
    });
  }

  void _selectAll() {
    setState(() {
      if (_selectedBatches.length == _batches.length) {
        _selectedBatches.clear();
        _isSelectionMode = false;
      } else {
        _selectedBatches = List.from(_batches);
        _isSelectionMode = true;
      }
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectedBatches.clear();
      _isSelectionMode = false;
    });
  }

  Future<void> _deleteSelectedBatches() async {
    if (_selectedBatches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aucun lot sélectionné'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    // Check if any selected batch is already synced
    final hasSynced = _selectedBatches.any((b) => b.isSynced);

    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Supprimer les lots", style: TextStyle(fontSize: 18)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Voulez-vous supprimer ${_selectedBatches.length} lot(s) sélectionné(s) ?",
                style: const TextStyle(fontSize: 14),
              ),
              if (hasSynced) ...[
                const SizedBox(height: 8),
                const Text(
                  "Certains lots sont déjà synchronisés. Ils seront également supprimés.",
                  style: TextStyle(fontSize: 12, color: Colors.orange),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Annuler", style: TextStyle(fontSize: 14)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: Text(
                "Supprimer ${_selectedBatches.length} lot(s)",
                style: const TextStyle(fontSize: 14),
              ),
            ),
          ],
        );
      },
    );

    if (shouldDelete == true) {
      setState(() => _isLoading = true);

      int deletedCount = 0;
      for (final batch in _selectedBatches) {
        await BatchStorageService.removeBatch(batch.id);
        deletedCount++;
      }

      await _loadBatches();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$deletedCount lot(s) supprimé(s) avec succès'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _deleteSingleBatch(Batch batch) async {
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Supprimer le lot", style: TextStyle(fontSize: 18)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Voulez-vous supprimer le lot \"${batch.name}\" ?",
                style: const TextStyle(fontSize: 14),
              ),
              if (batch.isSynced) ...[
                const SizedBox(height: 8),
                const Text(
                  "Ce lot est déjà synchronisé. Il sera également supprimé.",
                  style: TextStyle(fontSize: 12, color: Colors.orange),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Annuler", style: TextStyle(fontSize: 14)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text("Supprimer", style: TextStyle(fontSize: 14)),
            ),
          ],
        );
      },
    );

    if (shouldDelete == true) {
      setState(() => _isLoading = true);
      await BatchStorageService.removeBatch(batch.id);
      await _loadBatches();

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Lot "${batch.name}" supprimé avec succès'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _syncBatch(Batch batch) async {
    setState(() => _isSyncing = true);

    try {
      final success = await CountingService.submitScannedItems(
        countingSheetId: batch.countingSheetId,
        adjustmentId: batch.adjustmentId,
        items: batch.items,
      );

      if (success) {
        await BatchStorageService.markBatchAsSynced(batch.id);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Lot synchronisé avec succès !'),
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
            content: Text('Erreur: ${e.toString()}'),
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
          content: Text('Aucun lot à synchroniser'),
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
          content: Text(' $successCount lots synchronisés, $failCount échoués'),
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
          sheetName: 'Lot: ${batch.name}',
          countingSheetId: batch.countingSheetId,
          adjustmentId: batch.adjustmentId,
          onItemsUpdated: (updatedItems) {
            batch.items.clear();
            batch.items.addAll(updatedItems);
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final unsyncedCount = _batches.where((b) => !b.isSynced).length;
    final selectedCount = _selectedBatches.length;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: _isSelectionMode
            ? Text('$selectedCount lot(s) sélectionné(s)')
            : const Text('Lots sauvegardés', style: TextStyle(fontSize: 16)),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: _isSelectionMode
            ? IconButton(
          icon: const Icon(Icons.close, size: 22),
          onPressed: _exitSelectionMode,
        )
            : IconButton(
          icon: const Icon(Icons.arrow_back, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (!_isSelectionMode && _batches.isNotEmpty)
            IconButton(
              icon: _isSyncing
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.sync, size: 20),
              onPressed: _isSyncing ? null : _syncAllBatches,
            ),
          if (_isSelectionMode)
            IconButton(
              icon: const Icon(Icons.delete, size: 20),
              onPressed: selectedCount > 0 ? _deleteSelectedBatches : null,
            ),
          if (_isSelectionMode)
            IconButton(
              icon: Icon(
                _selectedBatches.length == _batches.length
                    ? Icons.deselect
                    : Icons.select_all,
                size: 20,
              ),
              onPressed: _selectAll,
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
              'Aucun lot sauvegardé',
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
            const SizedBox(height: 8),
            Text(
              'Scannez et utilisez "Enregistrer" pour créer un lot',
              style: TextStyle(color: Colors.grey[500], fontSize: 12),
            ),
          ],
        ),
      )
          : Column(
        children: [
          // Summary
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
                    '${_batches.length} lot(s) total',
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                  Text(
                    '$unsyncedCount à synchroniser',
                    style: const TextStyle(fontSize: 13),
                  ),
                ],
              ),
            ),
          ),
          // List
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(8),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 2,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 0.85,
              ),
              itemCount: _batches.length,
              itemBuilder: (context, index) {
                final batch = _batches[index];
                final isSelected = _selectedBatches.contains(batch);
                final isSynced = batch.isSynced;

                return GestureDetector(
                  onTap: () {
                    if (_isSelectionMode) {
                      _toggleSelection(batch);
                    } else {
                      _viewBatchItems(batch);
                    }
                  },
                  onLongPress: () {
                    if (!_isSelectionMode) {
                      _toggleSelection(batch);
                    }
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      color: isSelected ? Colors.blue[50] : Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: isSelected
                          ? Border.all(color: Colors.blue, width: 2)
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
                        // Checkbox for selection mode
                        if (_isSelectionMode)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Checkbox(
                              value: isSelected,
                              onChanged: (_) => _toggleSelection(batch),
                              activeColor: Colors.blue,
                            ),
                          ),
                        // Icon
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: isSynced ? Colors.green[100] : Colors.blue[100],
                            borderRadius: BorderRadius.circular(25),
                          ),
                          child: Icon(
                            isSynced ? Icons.check_circle : Icons.save,
                            color: isSynced ? Colors.green : Colors.blue,
                            size: 28,
                          ),
                        ),
                        const SizedBox(height: 8),
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
                        const SizedBox(height: 4),
                        Text(
                          isSynced ? 'Synchronisé' : 'En attente',
                          style: TextStyle(
                            fontSize: 10,
                            color: isSynced ? Colors.green : Colors.orange,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        // Action buttons (only if not in selection mode)
                        if (!_isSelectionMode && !isSynced)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                ElevatedButton(
                                  onPressed: _isSyncing ? null : () => _syncBatch(batch),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green,
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(20),
                                    ),
                                  ),
                                  child: const Text('Sync', style: TextStyle(fontSize: 10)),
                                ),
                                const SizedBox(width: 6),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                                  onPressed: () => _deleteSingleBatch(batch),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ),
                          ),
                        if (!_isSelectionMode && isSynced)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.red),
                              onPressed: () => _deleteSingleBatch(batch),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
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
      floatingActionButton: _batches.isNotEmpty && !_isSelectionMode
          ? Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // Delete all button
          FloatingActionButton.extended(
            onPressed: _isSyncing ? null : _deleteSelectedBatches,
            icon: const Icon(Icons.delete, size: 20),
            label: const Text('Tout supprimer'),
            backgroundColor: Colors.red,
            foregroundColor: Colors.white,
          ),
          const SizedBox(width: 12),
          // Sync all button
          FloatingActionButton.extended(
            onPressed: _isSyncing ? null : _syncAllBatches,
            icon: _isSyncing
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.sync, size: 20),
            label: const Text('Tout synchroniser'),
            backgroundColor: Colors.green,
            foregroundColor: Colors.white,
          ),
        ],
      )
          : null,
    );
  }
}