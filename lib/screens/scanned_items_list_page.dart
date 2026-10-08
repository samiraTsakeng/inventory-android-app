import 'package:flutter/material.dart';
import '../utils/constants.dart';
import '../models/scanned_item.dart';
import '../services/counting_service.dart';
import '../services/local_storage_service.dart';
import '../services/batch_storage_service.dart';

class ScannedItemsListPage extends StatefulWidget {
  final List<ScannedItem> items;
  final String sheetName;
  final int countingSheetId;
  final int adjustmentId;
  final Function(List<ScannedItem>) onItemsUpdated;
  // Optional callback kept for compatibility with existing callers.
  final Function(ScannedItem item, int newQuantity)? onItemEdited;
  // ✅ When set, this page is showing a saved batch (opened from
  // "Lots sauvegardés") — edits persist into that batch.
  final String? batchId;

  const ScannedItemsListPage({
    Key? key,
    required this.items,
    required this.sheetName,
    required this.countingSheetId,
    required this.adjustmentId,
    required this.onItemsUpdated,
    this.onItemEdited,
    this.batchId,
  }) : super(key: key);

  @override
  State<ScannedItemsListPage> createState() => _ScannedItemsListPageState();
}

class _ScannedItemsListPageState extends State<ScannedItemsListPage> {
  late List<ScannedItem> _items;
  List<ScannedItem> _filteredItems = [];
  String _searchQuery = '';
  bool _isSending = false;
  final TextEditingController _quantityController = TextEditingController();
  int _editingIndex = -1;

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.items);
    _filteredItems = List.from(_items);
  }

  void _filterItems(String query) {
    setState(() {
      _searchQuery = query.toLowerCase();
      if (query.isEmpty) {
        _filteredItems = List.from(_items);
      } else {
        _filteredItems = _items
            .where((item) =>
        item.productName.toLowerCase().contains(_searchQuery) ||
            item.barcode.contains(_searchQuery))
            .toList();
      }
    });
  }

  // ✅ Pencil edit — REPLACES the quantity, updates parent, persists,
  // and persists the change locally..
  void _saveItemQuantity(int filteredIndex) {
    final newQuantity = int.tryParse(_quantityController.text);
    if (newQuantity == null || newQuantity < 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Quantité invalide'),
          backgroundColor: AppColors.errorColor,
        ),
      );
      return;
    }

    final item = _filteredItems[filteredIndex];
    final realIndex = _items.indexWhere((it) => it.barcode == item.barcode);
    if (realIndex == -1) return;

    setState(() {
      _items[realIndex].quantity = newQuantity;
      item.quantity = newQuantity;
      _editingIndex = -1;
      _quantityController.clear();
    });

    widget.onItemsUpdated(_items);
    _persistChanges();
    widget.onItemEdited?.call(_items[realIndex], newQuantity);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Quantité mise à jour'),
        duration: Duration(seconds: 1),
      ),
    );
  }

  Future<void> _persistChanges() async {
    if (widget.batchId != null) {
      await BatchStorageService.updateBatchItems(widget.batchId!, _items);
    } else {
      await LocalStorageService.saveScannedItems(widget.countingSheetId, _items);
    }
  }

  // Delete locally and persist the change.
  Future<void> _deleteItem(ScannedItem item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Supprimer cet article ?'),
        content: Text('${item.productName}\nQuantité: ${item.quantity}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.errorColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Supprimer'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final realIndex = _items.indexWhere((it) => it.barcode == item.barcode);
    if (realIndex == -1) return;

    setState(() {
      _items.removeAt(realIndex);
      _filteredItems.removeWhere((it) => it.barcode == item.barcode);
      if (_editingIndex >= _filteredItems.length) {
        _editingIndex = -1;
        _quantityController.clear();
      }
    });

    widget.onItemsUpdated(_items);
    await _persistChanges();

    if (widget.batchId == null) {
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Article supprimé'),
          backgroundColor: AppColors.successColor,
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  void _startEditing(int filteredIndex) {
    setState(() {
      _editingIndex = filteredIndex;
      _quantityController.text =
          _filteredItems[filteredIndex].quantity.toString();
    });
  }

  String _getTrackingText(String tracking) {
    switch (tracking) {
      case 'serial':
        return 'N° Série';
      case 'lot':
        return 'Lot';
      case 'none':
        return 'Sans traçabilité';
      default:
        return 'Aucune traçabilité';
    }
  }

  Color _getTrackingColor(String tracking) {
    switch (tracking) {
      case 'serial':
        return AppColors.secondaryColor;
      case 'lot':
        return AppColors.warningColor;
      default:
        return Colors.grey;
    }
  }

  // ✅ Send to ERP:
  //   1. Pre-flight ERP check per barcode (skip already-present ones).
  //   2. Submit only the new ones.
  //   3. Partial failure → popup listing failed barcodes + reasons, keep
  //      them in the list for retry.
  //   4. Full success → clear the local list.
  Future<void> _sendToERP() async {
    if (_items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucun article à envoyer')),
      );
      return;
    }

    final validItems = _items.where((item) => item.productId != 0).toList();
    if (validItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucun produit valide à envoyer')),
      );
      return;
    }

    setState(() => _isSending = true);

    try {
      final alreadyInErp = <String>[];
      final toSubmit = <ScannedItem>[];

      for (final item in validItems) {
        final exists = await CountingService.isAlreadyInErp(
          countingSheetId: widget.countingSheetId,
          barcode: item.barcode,
        );
        if (exists) {
          alreadyInErp.add(item.barcode);
        } else {
          toSubmit.add(item);
        }
      }

      if (toSubmit.isEmpty) {
        setState(() => _isSending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Tous les articles (${alreadyInErp.length}) existent déjà dans l\'ERP. Rien à envoyer.',
            ),
            backgroundColor: AppColors.warningColor,
          ),
        );
        await _clearAllAfterSubmit();
        return;
      }

      final result = await CountingService.submitScannedItems(
        countingSheetId: widget.countingSheetId,
        adjustmentId: widget.adjustmentId,
        items: toSubmit,
      );

      if (!mounted) return;

      if (!result.success) {
        setState(() => _isSending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message ?? 'Erreur lors de l\'envoi'),
            backgroundColor: AppColors.errorColor,
          ),
        );
        return;
      }

      // Partial failures — show details and keep them for retry.
      if (result.failedBarcodes.isNotEmpty) {
        await _showFailedItemsDialog(result);

        final failedSet = result.failedBarcodes.toSet();
        final remaining =
        _items.where((it) => failedSet.contains(it.barcode)).toList();

        setState(() {
          _items = remaining;
          _filteredItems = List.from(remaining);
          _isSending = false;
        });
        widget.onItemsUpdated(remaining);
        await LocalStorageService.saveScannedItems(
          widget.countingSheetId,
          remaining,
        );
        return;
      }

      // Full success.
      if (widget.batchId != null) {
        await BatchStorageService.markBatchAsSynced(widget.batchId!);
      } else {
        await _clearAllAfterSubmit();
      }

      final msg = alreadyInErp.isEmpty
          ? 'Envoyé avec succès !'
          : 'Envoyé : ${result.submittedCount} • Ignorés (déjà dans l\'ERP) : ${alreadyInErp.length}';

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: AppColors.successColor),
      );
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _isSending = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erreur: ${e.toString()}'),
            backgroundColor: AppColors.errorColor,
          ),
        );
      }
    }
  }

  // ✅ Popup listing failed barcodes + the Odoo reason for each.
  Future<void> _showFailedItemsDialog(SubmitResult result) async {
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.warning_amber,
                color: AppColors.warningColor, size: 22),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '${result.failedBarcodes.length} article(s) non envoyé(s)',
                style: const TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Ces articles n\'ont pas pu être envoyés à l\'ERP :',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 10),
              ...result.failedDetails.map(
                    (f) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '• ${f['barcode']}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          fontFamily: 'monospace',
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(left: 12, top: 2),
                        child: Text(
                          f['reason'] ?? '',
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Ces articles restent dans la liste pour être corrigés et renvoyés.',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Compris'),
          ),
        ],
      ),
    );
  }

  Future<void> _clearAllAfterSubmit() async {
    await LocalStorageService.clearScannedItems(widget.countingSheetId);

    if (mounted) {
      setState(() {
        _items.clear();
        _filteredItems.clear();
        _isSending = false;
      });
      widget.onItemsUpdated([]);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundColor,
      appBar: AppBar(
        title: Text(widget.sheetName, style: const TextStyle(fontSize: 15)),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_items.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Container(
                  height: 36,
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: TextButton.icon(
                    icon: _isSending
                        ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.send, size: 15, color: Colors.white),
                    label: Text(
                      _isSending ? 'Envoi...' : 'Envoyer',
                      style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white),
                    ),
                    onPressed: _isSending ? null : _sendToERP,
                  ),
                ),
              ),
            ),
        ],
      ),
      body: _items.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primaryColor.withOpacity(0.06),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.inventory_2_outlined,
                  size: 44, color: AppColors.primaryColor),
            ),
            const SizedBox(height: 16),
            const Text('Aucun article scanné',
                style: TextStyle(
                    fontSize: 14, color: AppColors.textSecondary)),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.qr_code_scanner, size: 18),
              label: const Text('Retour au scan',
                  style: TextStyle(fontSize: 13)),
              style: OutlinedButton.styleFrom(
                  minimumSize: const Size(180, 44)),
            ),
          ],
        ),
      )
          : Column(
        children: [
          // Search bar
          Container(
            margin: const EdgeInsets.fromLTRB(12, 12, 12, 6),
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: AppColors.surfaceColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.borderColor),
            ),
            child: TextField(
              onChanged: (value) => _filterItems(value),
              decoration: const InputDecoration(
                hintText: 'Rechercher un article...',
                border: InputBorder.none,
                icon: Icon(Icons.search,
                    color: AppColors.textSecondary, size: 20),
              ),
            ),
          ),

          Container(
            margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
            padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.primaryColor.withOpacity(0.06),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.qr_code,
                        size: 15, color: AppColors.primaryColor),
                    const SizedBox(width: 5),
                    Text('${_items.length} articles',
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primaryColor)),
                  ],
                ),
                Container(
                    width: 1,
                    height: 14,
                    color: AppColors.primaryColor.withOpacity(0.2)),
                Row(
                  children: [
                    const Icon(Icons.inventory_2_outlined,
                        size: 15, color: AppColors.primaryColor),
                    const SizedBox(width: 5),
                    Text(
                        '${_items.fold<int>(0, (sum, item) => sum + item.quantity)} pièces',
                        style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: AppColors.primaryColor)),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _filteredItems.length,
              itemBuilder: (context, index) {
                final item = _filteredItems[index];
                final isEditing = _editingIndex == index;
                final isSerial = item.tracking == 'serial';
                final trackingText = _getTrackingText(item.tracking);
                final trackingColor = _getTrackingColor(item.tracking);

                return Card(
                  margin: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 5),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: AppColors.primaryColor
                                    .withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Center(
                                child: Text(
                                  '${index + 1}',
                                  style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                      color: AppColors.primaryColor),
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment:
                                CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.productName,
                                    style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: AppColors.textColor),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 4),
                                  Row(
                                    children: [
                                      Icon(Icons.qr_code_2,
                                          size: 11,
                                          color: Colors.grey[500]),
                                      const SizedBox(width: 3),
                                      Text(
                                        item.barcode,
                                        style: const TextStyle(
                                            fontSize: 10,
                                            color: AppColors
                                                .textSecondary),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding:
                                        const EdgeInsets.symmetric(
                                            horizontal: 5,
                                            vertical: 2),
                                        decoration: BoxDecoration(
                                          color: trackingColor
                                              .withOpacity(0.12),
                                          borderRadius:
                                          BorderRadius.circular(5),
                                        ),
                                        child: Text(
                                          trackingText,
                                          style: TextStyle(
                                              fontSize: 9,
                                              color: trackingColor,
                                              fontWeight:
                                              FontWeight.w600),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Divider(height: 1),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text(
                              isSerial
                                  ? 'Quantité fixe: '
                                  : 'Quantité: ',
                              style: const TextStyle(
                                  fontSize: 11.5,
                                  color: AppColors.textSecondary),
                            ),
                            if (isSerial)
                              const Expanded(
                                child: Text(
                                  '1 (N° Série)',
                                  style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w600,
                                      color:
                                      AppColors.secondaryColor),
                                ),
                              )
                            else if (isEditing)
                              Expanded(
                                child: SizedBox(
                                  height: 34,
                                  child: TextField(
                                    controller: _quantityController,
                                    keyboardType:
                                    TextInputType.number,
                                    autofocus: true,
                                    decoration: const InputDecoration(
                                      contentPadding:
                                      EdgeInsets.symmetric(
                                          horizontal: 10,
                                          vertical: 6),
                                    ),
                                    style:
                                    const TextStyle(fontSize: 12),
                                  ),
                                ),
                              )
                            else
                              Expanded(
                                child: Text(
                                  '${item.quantity}',
                                  style: const TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.textColor),
                                ),
                              ),
                            const SizedBox(width: 4),
                            if (!isSerial && !isEditing)
                              IconButton(
                                icon: const Icon(Icons.edit_outlined,
                                    size: 18,
                                    color: AppColors.primaryColor),
                                onPressed: () => _startEditing(index),
                                padding: EdgeInsets.zero,
                                constraints:
                                const BoxConstraints(),
                              ),
                            if (!isSerial && isEditing)
                              IconButton(
                                icon: const Icon(Icons.check_circle,
                                    size: 20,
                                    color: AppColors.successColor),
                                onPressed: () =>
                                    _saveItemQuantity(index),
                                padding: EdgeInsets.zero,
                                constraints:
                                const BoxConstraints(),
                              ),
                            const SizedBox(width: 8),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  size: 18, color: AppColors.errorColor),
                              onPressed: () => _deleteItem(item),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                            ),
                          ],
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
    );
  }
}