import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:badges/badges.dart' as badges;
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

    final existingIndex = scannedItems.indexWhere((item) => item.barcode == barcode);

    if (existingIndex != -1) {
      setState(() {
        scannedItems[existingIndex].quantity++;
        isScanning = true;
        isLookingUp = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${scannedItems[existingIndex].productName}: ${scannedItems[existingIndex].quantity}'),
            duration: const Duration(milliseconds: 800),
          ),
        );
      }
      return;
    }

    final product = await CountingService.lookupProduct(barcode);

    if (mounted) {
      setState(() {
        if (product != null) {
          scannedItems.add(ScannedItem(
            barcode: barcode,
            productName: product['name'] ?? 'Unknown',
            productId: product['id'] ?? 0,
            quantity: 1,
          ));
        } else {
          scannedItems.add(ScannedItem(
            barcode: barcode,
            productName: '❓ Produit inconnu',
            productId: 0,
            quantity: 1,
          ));
        }
        isScanning = true;
        isLookingUp = false;
      });
    }

    if (scannedItems.length >= 50) {
      setState(() => isScanning = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Limite de 50 articles atteinte!'), backgroundColor: Colors.orange),
        );
      }
    }
  }

  void _showSaveConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Enregistrer", style: TextStyle(fontSize: 18)),
        content: const Text("Voulez-vous vraiment enregistrer les articles scannés ?", style: TextStyle(fontSize: 14)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Non")),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Articles enregistrés"), backgroundColor: Colors.green),
              );
            },
            child: const Text("Oui"),
          ),
        ],
      ),
    );
  }

  Future<void> submitScans() async {
    if (scannedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucun article à envoyer')),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    final success = await CountingService.submitScannedItems(
      countingSheetId: widget.countingSheetId,
      adjustmentId: widget.adjustmentId,
      items: scannedItems,
    );

    if (mounted) {
      Navigator.pop(context);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Envoyé avec succès !"), backgroundColor: Colors.green),
        );
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
          const SnackBar(content: Text('❌ Erreur lors de l\'envoi'), backgroundColor: Colors.red),
        );
      }
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
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.zoneName, style: const TextStyle(fontSize: 16)),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 22),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'save') _showSaveConfirmation();
              else if (value == 'finish') Navigator.pop(context);
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'save', child: Text('Enregistrer')),
              PopupMenuItem(value: 'finish', child: Text('Terminer')),
            ],
            child: const Padding(
              padding: EdgeInsets.all(8.0),
              child: Icon(Icons.more_vert, size: 22),
            ),
          ),
          badges.Badge(
            showBadge: scannedItems.isNotEmpty,
            badgeContent: Text('${scannedItems.length}', style: const TextStyle(fontSize: 10)),
            child: IconButton(
              icon: const Icon(Icons.list, size: 22),
              onPressed: navigateToSummary,
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Camera preview
          Expanded(
            flex: 3,
            child: Stack(
              children: [
                MobileScanner(
                  controller: scannerController,
                  onDetect: onBarcodeDetected,
                ),
                if (!isScanning)
                  Container(color: Colors.black54, child: const Center(child: CircularProgressIndicator())),
                if (isLookingUp)
                  Positioned(
                    bottom: 20,
                    left: 20,
                    right: 20,
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.black87,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                          SizedBox(width: 10),
                          Text('Recherche...', style: TextStyle(color: Colors.white, fontSize: 12)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Progress panel
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.white,
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(widget.sheetName, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                    Text('${scannedItems.length}/50', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: scannedItems.length / 50,
                    minHeight: 4,
                    backgroundColor: Colors.grey[200],
                    color: isLimitReached ? Colors.red : Colors.green,
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.list, size: 18),
                        label: Text('Liste (${scannedItems.length})', style: const TextStyle(fontSize: 12)),
                        onPressed: navigateToSummary,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.grey[200],
                          foregroundColor: Colors.black87,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.send, size: 18),
                        label: const Text('Envoyer', style: TextStyle(fontSize: 12)),
                        onPressed: scannedItems.isEmpty ? null : submitScans,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        mini: true,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        onPressed: () => scannerController.toggleTorch(),
        child: const Icon(Icons.flash_on, size: 20),
      ),
    );
  }
}