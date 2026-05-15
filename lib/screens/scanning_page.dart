import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:badges/badges.dart' as badges;
import '../models/scanned_item.dart';
import '../services/counting_service.dart';
import '../services/local_storage_service.dart';
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
  final MobileScannerController scannerController = MobileScannerController(
    facing: CameraFacing.back,
    torchEnabled: false,
  );
  List<ScannedItem> scannedItems = [];
  bool isScanning = true;
  String? lastScannedBarcode;
  bool isLookingUp = false;
  bool isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSavedItems();
  }

  Future<void> _loadSavedItems() async {
    final savedItems = await LocalStorageService.loadScannedItems(widget.countingSheetId);
    setState(() {
      scannedItems = savedItems;
      isLoading = false;
    });
  }

  Future<void> _saveItems() async {
    await LocalStorageService.saveScannedItems(widget.countingSheetId, scannedItems);
  }

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

    // Check if already scanned - prevent duplicate
    final existingIndex = scannedItems.indexWhere((item) => item.barcode == barcode);

    if (existingIndex != -1) {
      final existingItem = scannedItems[existingIndex];

      // for serial tracking, prevent quantity increase
      if (existingItem.tracking == 'serial') {
      setState(() {
        isScanning = true;
        isLookingUp = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Cet article a déjà été scanné! Modifiez la quantité manuellement.'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    } else {
        //for lot or none, increment qty
      setState(() {
        scannedItems[existingIndex].quantity++;
        isScanning = true;
        isLookingUp = false;
      });
      }
      }

    // Look up product - only registered products
    final product = await CountingService.lookupProduct(barcode);

    if (mounted) {
      setState(() {
        if (product != null && product['id'] != 0) {
          //get tracking value from odoo (values: 'none', 'lot', 'serial')
          String tracking = product['tracking'] ?? 'none';

          //for serial tracking, qty is always 1
          int quantity = tracking == 'serial' ? 1 : 1;

          // Only add registered products
          scannedItems.add(ScannedItem(
            barcode: barcode,
            productName: product['name'] ?? 'Unknown',
            productId: product['id'] ?? 0,
            quantity: quantity,
            //quantity: tracking == 'serial' ? 1 : 1,
            lotNumber: '',
            tracking: tracking,
          ));
          _saveItems();
           String trackingText = tracking == 'serial' ? 'Numero de serie' : (tracking == 'lot' ? 'lot': 'Sans traçabilité');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Ajouté: ${product['name']} ($trackingText)'),
              backgroundColor: Colors.green,
              duration: const Duration(milliseconds: 800),
            ),
          );
        } else {
          // Ignore non-registered products
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('⚠️ Produit non trouvé: $barcode (ignoré)'),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 2),
            ),
          );
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

  void _logout() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Déconnexion"),
        content: const Text("Voulez-vous vraiment vous déconnecter ?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Non")),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Oui", style: TextStyle(color: Colors.white)),
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

    // Filter only registered products (productId != 0)
    final validItems = scannedItems.where((item) => item.productId != 0).toList();

    if (validItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucun produit valide à envoyer')),
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
      items: validItems,
    );

    if (mounted) {
      Navigator.pop(context);
      if (success) {
        // Clear local storage and list
        await LocalStorageService.clearScannedItems(widget.countingSheetId);
        setState(() {
          scannedItems.clear();
          lastScannedBarcode = null;
          isScanning = true;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("✅ Envoyé avec succès !"), backgroundColor: Colors.green),
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
          countingSheetId: widget.countingSheetId,
          adjustmentId: widget.adjustmentId,
          onItemsUpdated: (updatedItems) {
            setState(() {
              scannedItems = updatedItems;
              _saveItems();
            });
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLimitReached = scannedItems.length >= 50;

    if (isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(widget.zoneName, style: const TextStyle(fontSize: 16)),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, size: 22),
            onPressed: () {
              Scaffold.of(context).openDrawer();
            },
          ),
        ),
        actions: [
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
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: Colors.blue),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  const Text(
                    'Inventory App',
                    style: TextStyle(color: Colors.white, fontSize: 24),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    widget.sheetName,
                    style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 12),
                  ),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.qr_code_scanner),
              title: const Text('Scanner'),
              onTap: () {
                Navigator.pop(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.list),
              title: const Text('Articles scannés'),
              onTap: () {
                Navigator.pop(context);
                navigateToSummary();
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Déconnexion', style: TextStyle(color: Colors.red)),
              onTap: _logout,
            ),
          ],
        ),
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
          // Progress panel (NO SEND BUTTON HERE)
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
                Text(
                  scannedItems.isEmpty
                      ? "Scan des articles (1 à 50)"
                      : "${scannedItems.length} article${scannedItems.length > 1 ? 's' : ''} scanné${scannedItems.length > 1 ? 's' : ''}",
                  style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                ),
                const SizedBox(height: 8),
                ElevatedButton.icon(
                  icon: const Icon(Icons.list, size: 18),
                  label: Text('Voir la liste (${scannedItems.length})', style: const TextStyle(fontSize: 12)),
                  onPressed: navigateToSummary,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
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