import 'package:flutter/material.dart';
import '../models/scanned_item.dart';
import '../services/counting_service.dart';
import '../services/local_storage_service.dart';

class ScannedItemsListPage extends StatefulWidget {
  final List<ScannedItem> items;
  final String sheetName;
  final int countingSheetId;
  final int adjustmentId;
  final Function(List<ScannedItem>) onItemsUpdated;

  const ScannedItemsListPage({
    Key? key,
    required this.items,
    required this.sheetName,
    required this.countingSheetId,
    required this.adjustmentId,
    required this.onItemsUpdated,
  }) : super(key: key);

  @override
  State<ScannedItemsListPage> createState() => _ScannedItemsListPageState();
}

class _ScannedItemsListPageState extends State<ScannedItemsListPage> {
  late List<ScannedItem> _items;
  bool _isSending = false;
  final TextEditingController _quantityController = TextEditingController();
  int _editingIndex = -1;

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.items);
  }

  void _saveItemQuantity(int index) {
    final newQuantity = int.tryParse(_quantityController.text);
    if (newQuantity != null && newQuantity > 0) {
      setState(() {
        _items[index].quantity = newQuantity;
        _editingIndex = -1;
        _quantityController.clear();
      });
      widget.onItemsUpdated(_items);
      _saveToLocalStorage();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Quantité mise à jour'), duration: Duration(seconds: 1)),
      );
    }
  }

  Future<void> _saveToLocalStorage() async {
    await LocalStorageService.saveScannedItems(widget.countingSheetId, _items);
  }

  void _startEditing(int index) {
    setState(() {
      _editingIndex = index;
      _quantityController.text = _items[index].quantity.toString();
    });
  }

  String _getTrackingText(String tracking) {
    switch (tracking) {
      case 'serial': return 'N° Série';
      case 'lot': return 'Lot';
      case 'none': return 'Sans traçabilité';
      default: return 'Aucune traçabilité';
    }
  }

  Color _getTrackingColor(String tracking) {
    switch (tracking) {
      case 'serial': return Colors.purple;
      case 'lot': return Colors.orange;
      default: return Colors.grey;
    }
  }

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
      final success = await CountingService.submitScannedItems(
        countingSheetId: widget.countingSheetId,
        adjustmentId: widget.adjustmentId,
        items: validItems,
      );

      if (success && mounted) {
        await LocalStorageService.clearScannedItems(widget.countingSheetId);
        setState(() {
          _items.clear();
        });
        widget.onItemsUpdated([]);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Envoyé avec succès !'), backgroundColor: Colors.green),
        );
        Navigator.pop(context, true);
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ Erreur lors de l\'envoi'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erreur: ${e.toString()}'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(widget.sheetName, style: const TextStyle(fontSize: 15)),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          if (_items.isNotEmpty)
            TextButton.icon(
              icon: _isSending
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.send, size: 16),
              label: Text(_isSending ? 'Envoi...' : 'Envoyer', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white)),
              onPressed: _isSending ? null : _sendToERP,
            ),
        ],
      ),
      body: _items.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.inventory, size: 48, color: Colors.grey),
            const SizedBox(height: 12),
            const Text('Aucun article scanné', style: TextStyle(fontSize: 13, color: Colors.grey)),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Retour au scan', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      )
          : Column(
        children: [
          Container(
            margin: const EdgeInsets.all(12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.qr_code, size: 14, color: Colors.blue),
                    const SizedBox(width: 4),
                    Text('${_items.length} articles', style: const TextStyle(fontSize: 12)),
                  ],
                ),
                Row(
                  children: [
                    const Icon(Icons.inventory, size: 14, color: Colors.blue),
                    const SizedBox(width: 4),
                    Text('${_items.fold<int>(0, (sum, item) => sum + item.quantity)} pièces', style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final item = _items[index];
                final isEditing = _editingIndex == index;
                final isSerial = item.tracking == 'serial';
                final trackingText = _getTrackingText(item.tracking);
                final trackingColor = _getTrackingColor(item.tracking);

                return Card(
                  margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: Colors.blue[100],
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Center(
                                child: Text(
                                  '${index + 1}',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    item.productName,
                                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Text(
                                        item.barcode,
                                        style: const TextStyle(fontSize: 9, color: Colors.grey),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                        decoration: BoxDecoration(
                                          color: trackingColor.withOpacity(0.15),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          trackingText,
                                          style: TextStyle(fontSize: 8, color: trackingColor, fontWeight: FontWeight.w500),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Text(
                              isSerial ? 'Quantité fixe: ' : 'Quantité: ',
                              style: const TextStyle(fontSize: 11),
                            ),
                            if (isSerial)
                              Expanded(
                                child: Text(
                                  '1 (N° Série)',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500, color: Colors.purple),
                                ),
                              )
                            else if (isEditing)
                              Expanded(
                                child: TextField(
                                  controller: _quantityController,
                                  keyboardType: TextInputType.number,
                                  decoration: const InputDecoration(
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                  ),
                                  style: const TextStyle(fontSize: 11),
                                ),
                              )
                            else
                              Expanded(
                                child: Text(
                                  '${item.quantity}',
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                                ),
                              ),
                            const SizedBox(width: 6),
                            if (!isSerial && !isEditing)
                              IconButton(
                                icon: const Icon(Icons.edit, size: 16, color: Colors.blue),
                                onPressed: () => _startEditing(index),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            if (!isSerial && isEditing)
                              IconButton(
                                icon: const Icon(Icons.save, size: 16, color: Colors.green),
                                onPressed: () => _saveItemQuantity(index),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            IconButton(
                              icon: const Icon(Icons.delete_outline, size: 16, color: Colors.red),
                              onPressed: () {
                                setState(() {
                                  _items.removeAt(index);
                                  if (_editingIndex == index) {
                                    _editingIndex = -1;
                                    _quantityController.clear();
                                  }
                                });
                                widget.onItemsUpdated(_items);
                                _saveToLocalStorage();
                              },
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