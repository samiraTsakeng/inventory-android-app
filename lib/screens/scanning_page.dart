import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/scanned_item.dart';
import '../services/counting_service.dart';
import 'scanned_items_list_page.dart';

class ScanningPage extends StatefulWidget {
  final int countingSheetId;
  final int adjustmentId;
  final String zoneName;
  final String sheetName;

  const ScanningPage({
    Key? key,
    required this.countingSheetId,
    required this.adjustmentId,
    required this.zoneName,
    required this.sheetName,
  }) : super(key: key);

  @override
  State<ScanningPage> createState() => _ScanningPageState();
}

class _ScanningPageState extends State<ScanningPage> {
  final MobileScannerController scannerController = MobileScannerController();
  final List<ScannedItem> scannedItems = [];
  bool isScanning = true;
  String? lastScannedBarcode;
  bool isLookingUp = false;

  @override
  void dispose() {
    scannerController.dispose();
    super.dispose();
  }

  void onBarcodeDetected(BarcodeCapture capture) async {
    if (!isScanning || isLookingUp) return;

    final barcode = capture.barcodes.first.rawValue;
    if (barcode == null || barcode == lastScannedBarcode) return;

    setState(() {
      isScanning = false;
      isLookingUp = true;
      lastScannedBarcode = barcode;
    });

    // Check if already scanned
    final existingItem = scannedItems.firstWhere(
          (item) => item.barcode == barcode,
      orElse: () => ScannedItem(barcode: barcode),
    );

    if (existingItem.productId != 0) {
      // Item already scanned, increment quantity
      setState(() {
        existingItem.quantity++;
        isScanning = true;
        isLookingUp = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${existingItem.productName}: Quantité ${existingItem.quantity}'),
            duration: Duration(seconds: 1),
          ),
        );
      }
      return;
    }

    // Look up product in Odoo
    final product = await CountingService.lookupProduct(barcode);

    setState(() {
      if (product != null) {
        scannedItems.add(ScannedItem(
          barcode: barcode,
          productName: product['name'] ?? 'Unknown',
          productId: product['id'] ?? 0,
          quantity: 1,
        ));

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Ajouté: ${product['name']}'),
              backgroundColor: Colors.green,
              duration: Duration(seconds: 1),
            ),
          );
        }
      } else {
        // Product not found, add as unknown
        scannedItems.add(ScannedItem(
          barcode: barcode,
          productName: '❓ Produit inconnu',
          productId: 0,
          quantity: 1,
        ));

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('⚠️ Produit non trouvé: $barcode'),
              backgroundColor: Colors.orange,
              duration: Duration(seconds: 2),
            ),
          );
        }
      }

      isScanning = true;
      isLookingUp = false;
    });

    // Disable scanning after 50 items
    if (scannedItems.length >= 50) {
      setState(() {
        isScanning = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Limite de 50 articles atteinte!'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  Future<void> submitScans() async {
    if (scannedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Aucun article à envoyer')),
      );
      return;
    }

    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(child: CircularProgressIndicator()),
    );

    final success = await CountingService.submitScannedItems(
      countingSheetId: widget.countingSheetId,
      adjustmentId: widget.adjustmentId,
      items: scannedItems,
    );

    Navigator.pop(context); // Close loading dialog

    if (success) {
      // Navigate to summary page
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (context) => ScannedItemsListPage(
            items: scannedItems,
            sheetName: widget.sheetName,
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur lors de l\'envoi. Réessayez.'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void navigateToSummary() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ScannedItemsListPage(
          items: scannedItems,
          sheetName: widget.sheetName,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLimitReached = scannedItems.length >= 50;

    return Scaffold(
      appBar: AppBar(
        title: Text('Scan - ${widget.zoneName}'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: Badge(
              label: Text('${scannedItems.length}'),
              child: Icon(Icons.list),
            ),
            onPressed: navigateToSummary,
          ),
          IconButton(
            icon: Icon(Icons.send),
            onPressed: scannedItems.isEmpty ? null : submitScans,
          ),
        ],
      ),
      body: Column(
        children: [
          // Camera preview
          Expanded(
            flex: 2,
            child: Stack(
              children: [
                MobileScanner(
                  controller: scannerController,
                  onDetect: onBarcodeDetected,
                ),
                if (!isScanning)
                  Container(
                    color: Colors.black54,
                    child: Center(
                      child: CircularProgressIndicator(),
                    ),
                  ),
                if (isLookingUp)
                  Positioned(
                    bottom: 20,
                    left: 0,
                    right: 0,
                    child: Container(
                      padding: EdgeInsets.all(12),
                      margin: EdgeInsets.symmetric(horizontal: 20),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          ),
                          SizedBox(width: 10),
                          Text(
                            'Recherche du produit...',
                            style: TextStyle(color: Colors.white),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),

          // Info panel
          Container(
            padding: EdgeInsets.all(16),
            color: Colors.grey[100],
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Feuille: ${widget.sheetName}',
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'Zone: ${widget.zoneName}',
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
                SizedBox(height: 10),
                LinearProgressIndicator(
                  value: scannedItems.length / 50,
                  backgroundColor: Colors.grey[300],
                  color: isLimitReached ? Colors.red : Colors.green,
                ),
                SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Articles scannés: ${scannedItems.length}'),
                    Text('Limite: 50'),
                  ],
                ),
                if (isLimitReached)
                  Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      '⚠️ Limatte atteinte! Envoyez les données.',
                      style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                    ),
                  ),
                if (lastScannedBarcode != null && isScanning)
                  Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Dernier scan: $lastScannedBarcode',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ),
              ],
            ),
          ),

          // Action buttons
          Container(
            padding: EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    icon: Icon(Icons.visibility),
                    label: Text('Voir la liste (${scannedItems.length})'),
                    onPressed: navigateToSummary,
                    style: ElevatedButton.styleFrom(
                      padding: EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    icon: Icon(Icons.send),
                    label: Text('Envoyer'),
                    onPressed: scannedItems.isEmpty ? null : submitScans,
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
      floatingActionButton: FloatingActionButton(
        child: Icon(Icons.flash_on),
        onPressed: () {
          scannerController.toggleTorch();
        },
      ),
    );
  }
}