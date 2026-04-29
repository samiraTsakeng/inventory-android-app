import 'package:flutter/material.dart';
import '../models/scanned_item.dart';

class ScannedItemsListPage extends StatefulWidget {
  final List<ScannedItem> items;
  final String sheetName;

  const ScannedItemsListPage({
    Key? key,
    required this.items,
    required this.sheetName,
  }) : super(key: key);

  @override
  State<ScannedItemsListPage> createState() => _ScannedItemsListPageState();
}

class _ScannedItemsListPageState extends State<ScannedItemsListPage> {
  late List<ScannedItem> _items;

  @override
  void initState() {
    super.initState();
    _items = List.from(widget.items);
  }

  void _updateQuantity(int index, int newQuantity) {
    setState(() {
      if (newQuantity > 0) {
        _items[index].quantity = newQuantity;
      } else {
        _items.removeAt(index);
      }
    });
  }

  void _removeItem(int index) {
    setState(() {
      _items.removeAt(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Articles Scannés - ${widget.sheetName}'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          TextButton.icon(
            icon: Icon(Icons.check, color: Colors.white),
            label: Text('Retour au scan', style: TextStyle(color: Colors.white)),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
      body: _items.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory, size: 80, color: Colors.grey),
            SizedBox(height: 20),
            Text(
              'Aucun article scanné',
              style: TextStyle(fontSize: 18, color: Colors.grey),
            ),
            SizedBox(height: 10),
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Retour au scan'),
            ),
          ],
        ),
      )
          : Column(
        children: [
          // Summary card
          Container(
            margin: EdgeInsets.all(16),
            padding: EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.blue[200]!),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Total articles:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  '${_items.length} / 50',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: _items.length >= 50 ? Colors.red : Colors.green,
                  ),
                ),
                Text(
                  'Total pièces:',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  '${_items.fold(0, (sum, item) => sum + item.quantity)}',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),

          // Items table
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: DataTable(
                columnSpacing: 16,
                columns: const [
                  DataColumn(label: Text('#', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Code-barres', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Article', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Qté', style: TextStyle(fontWeight: FontWeight.bold))),
                  DataColumn(label: Text('Actions', style: TextStyle(fontWeight: FontWeight.bold))),
                ],
                rows: _items.asMap().entries.map((entry) {
                  int index = entry.key;
                  ScannedItem item = entry.value;

                  return DataRow(
                    cells: [
                      DataCell(Text('${index + 1}')),
                      DataCell(Text(item.barcode)),
                      DataCell(
                        Container(
                          constraints: BoxConstraints(maxWidth: 200),
                          child: Text(
                          item.productName,
                          style: TextStyle(
                            color: item.productId == 0 ? Colors.orange : null,
                          ),
                          ),
                        ),
                      ),
                      DataCell(
                        Row(
                          children: [
                            IconButton(
                              icon: Icon(Icons.remove_circle_outline, size: 20),
                              onPressed: () => _updateQuantity(index, item.quantity - 1),
                              padding: EdgeInsets.zero,
                              constraints: BoxConstraints(),
                            ),
                            Container(
                              width: 50,
                              child: Text(
                                '${item.quantity}',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 16),
                              ),
                            ),
                            IconButton(
                              icon: Icon(Icons.add_circle_outline, size: 20),
                              onPressed: () => _updateQuantity(index, item.quantity + 1),
                              padding: EdgeInsets.zero,
                              constraints: BoxConstraints(),
                            ),
                          ],
                        ),
                      ),
                      DataCell(
                        IconButton(
                          icon: Icon(Icons.delete_outline, color: Colors.red),
                          onPressed: () => _removeItem(index),
                        ),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
          ),

          // Action buttons
          Container(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    icon: Icon(Icons.arrow_back),
                    label: Text('Continuer le scan'),
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: Icon(Icons.send),
                    label: Text('Envoyer à l\'ERP'),
                    onPressed: _items.isEmpty
                        ? null
                        : () => Navigator.pop(context, _items),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}