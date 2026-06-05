import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:badges/badges.dart' as badges;
import '../models/scanned_item.dart';
import '../services/counting_service.dart';
import '../services/local_storage_service.dart';
import 'scanned_items_list_page.dart';
import '../models/batch.dart';
import '../services/batch_storage_service.dart';
import 'batch_list_page.dart';

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

  // Helper function to check if barcode is a product barcode (EAN/UPC)
  bool isProductBarcode(String code) {
    return RegExp(r'^\d{8}$|^\d{12}$|^\d{13}$').hasMatch(code);
  }

  // Helper function to detect if a barcode is a valid equipment identifier
  bool isValidEquipmentIdentifier(String code) {
    if (RegExp(r'^\d{14,15}$').hasMatch(code)) return true;
    if (RegExp(r'^[0-9A-F]{14,16}$', caseSensitive: false).hasMatch(code)) return true;
    if (RegExp(r'^\d{19,20}$').hasMatch(code)) return true;
    if (RegExp(r'^\d{10,15}$').hasMatch(code)) return true;
    if (RegExp(r'^[A-Z0-9]{11,12}$', caseSensitive: false).hasMatch(code)) return true;
    if (RegExp(r'^[A-Z0-9]{8,20}$', caseSensitive: false).hasMatch(code) && RegExp(r'[A-Za-z]').hasMatch(code)) return true;
    if (code.length >= 8 && code.length <= 20 && RegExp(r'[A-Za-z]').hasMatch(code) && RegExp(r'\d').hasMatch(code)) return true;
    return false;
  }

  // Manual barcode entry dialog
  Future<void> _addManualBarcode() async {
    final TextEditingController barcodeController = TextEditingController();

    final shouldAdd = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Ajouter un code-barres", style: TextStyle(fontSize: 18)),
          content: TextField(
            controller: barcodeController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: "Numéro de série / IMEI / MEID",
              hintText: "Entrez le code-barres manuellement",
              border: OutlineInputBorder(),
            ),
            style: const TextStyle(fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Annuler", style: TextStyle(fontSize: 14)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green,
                foregroundColor: Colors.white,
              ),
              child: const Text("Ajouter", style: TextStyle(fontSize: 14)),
            ),
          ],
        );
      },
    );

    if (shouldAdd == true && barcodeController.text.isNotEmpty) {
      setState(() {
        isLookingUp = true;
        isScanning = false;
      });

      final barcode = barcodeController.text.trim();

      // Check if already in list
      final existingIndex = scannedItems.indexWhere((item) => item.barcode == barcode);
      if (existingIndex != -1) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⚠️ Ce code-barres est déjà dans la liste'), backgroundColor: Colors.orange),
        );
        setState(() {
          isLookingUp = false;
          isScanning = true;
        });
        return;
      }

      // Check if it's a product barcode
      if (isProductBarcode(barcode)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⚠️ Veuillez scanner un numéro de série, pas un code-barres produit.'), backgroundColor: Colors.orange),
        );
        setState(() {
          isLookingUp = false;
          isScanning = true;
        });
        return;
      }

      // Look up product
      final result = await CountingService.lookupProduct(barcode);

      if (result != null && result['id'] != 0 && result['id'] != null) {
        final tracking = result['tracking'] ?? 'serial';
        final lotName = result['lot_name'] ?? barcode;
        final lotIdValue = result['lot_id'] ?? 0;
        final productIdValue = result['id'];

        // Set quantity based on tracking type
        final initialQuantity = tracking == 'serial' ? 1 : 0;

        setState(() {
          scannedItems.add(ScannedItem(
            barcode: barcode,
            productName: result['name'] ?? 'Unknown',
            productId: productIdValue,
            quantity: initialQuantity,
            lotNumber: lotName,
            lotId: lotIdValue,
            tracking: tracking,
          ));
          _saveItems();
        });

        String trackingText = tracking == 'serial' ? 'N° Série' : (tracking == 'lot' ? 'Lot' : 'Sans traçabilité');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Ajouté manuellement: ${result['name']} ($lotName)'),
            backgroundColor: Colors.green,
            duration: const Duration(milliseconds: 800),
          ),
        );
      } else {
        String errorMessage = result != null && result['message'] != null
            ? result['message']
            : '⚠️ Code-barres non trouvé: $barcode';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(errorMessage),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }

      setState(() {
        isLookingUp = false;
        isScanning = true;
      });
    }
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

    // Check if this barcode (lot OR serial) is already scanned
    final existingIndex = scannedItems.indexWhere((item) => item.barcode == barcode);

    if (existingIndex != -1) {
      // Already scanned - prevent ANY duplicate regardless of type
      setState(() {
        isScanning = true;
        isLookingUp = false;
      });
      if (mounted) {
        String message = scannedItems[existingIndex].tracking == 'serial'
            ? '⚠️ Ce numéro de série a déjà été scanné!'
            : '⚠️ Ce numéro de lot a déjà été scanné! Modifiez la quantité manuellement dans la liste.';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    // Look up product by lot/serial number
    final result = await CountingService.lookupProduct(barcode);

    if (mounted) {
      setState(() {
        if (result != null && result['id'] != 0 && result['id'] != null) {
          String tracking = result['tracking'] ?? 'serial';
          String lotName = result['lot_name'] ?? barcode;
          int lotIdValue = result['lot_id'] ?? 0;
          int productIdValue = result['id'];

          // MODIFICATION 1: Set default lot quantity to 0, serial quantity to 1
          final initialQuantity = tracking == 'serial' ? 1 : 0;

          scannedItems.add(ScannedItem(
            barcode: barcode,
            productName: result['name'] ?? 'Unknown',
            productId: productIdValue,
            quantity: initialQuantity,
            lotNumber: lotName,
            lotId: lotIdValue,
            tracking: tracking,
          ));
          _saveItems();

          String trackingText = tracking == 'serial' ? 'N° Série' : (tracking == 'lot' ? 'Lot' : 'Sans traçabilité');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Ajouté: ${result['name']} ($lotName)'),
              backgroundColor: Colors.green,
              duration: const Duration(milliseconds: 800),
            ),
          );
        } /*else {
          // show appropriate message based on error
          String errorMessage = result != null && result['message'] != null
              ? result['message']
              : '⚠️ Numéro non trouvé: $barcode';

          String barcodeType = result != null && result['barcode_type'] != null
              ? result['barcode_type']
              : '';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(errorMessage),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }*/
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

  void _showSaveConfirmation() async {
    if (scannedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucun article à sauvegarder')),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Enregistrer le batch", style: TextStyle(fontSize: 18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Voulez-vous sauvegarder ce batch ?", style: TextStyle(fontSize: 14)),
            const SizedBox(height: 8),
            Text(
              "Articles: ${scannedItems.length}",
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Non")),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final batchNumber = await _getNextBatchNumber();
              final batchName = "Batch $batchNumber";
              final batch = Batch(
                id: DateTime.now().millisecondsSinceEpoch.toString(),
                name: batchName,
                createdAt: DateTime.now(),
                items: List.from(scannedItems),
                isSynced: false,
                countingSheetId: widget.countingSheetId,
                adjustmentId: widget.adjustmentId,
                zoneName: widget.zoneName,
                sheetName: widget.sheetName,
              );
              await BatchStorageService.saveBatch(batch);
              setState(() {
                scannedItems.clear();
                lastScannedBarcode = null;
                isScanning = true;
              });
              await _saveItems();
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('✅ $batchName sauvegardé (${batch.items.length} articles)'),
                  backgroundColor: Colors.green,
                  action: SnackBarAction(
                    label: 'Voir',
                    textColor: Colors.white,
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => BatchesListPage(
                            countingSheetId: widget.countingSheetId,
                            adjustmentId: widget.adjustmentId,
                            zoneName: widget.zoneName,
                            sheetName: widget.sheetName,
                          ),
                        ),
                      );
                    },
                  ),
                ),
              );
            },
            child: const Text("Oui"),
          ),
        ],
      ),
    );
  }

  Future<int> _getNextBatchNumber() async {
    final batches = await BatchStorageService.getBatches();
    final sheetBatches = batches.where((b) => b.countingSheetId == widget.countingSheetId).toList();
    return sheetBatches.length + 1;
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
          // MODIFICATION 2: Add manual barcode entry button in menu
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'add_barcode') {
                _addManualBarcode();
              } else if (value == 'save') {
                _showSaveConfirmation();
              } else if (value == 'finish') {
                Navigator.pop(context);
              } else if (value == 'batches') {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => BatchesListPage(
                      countingSheetId: widget.countingSheetId,
                      adjustmentId: widget.adjustmentId,
                      zoneName: widget.zoneName,
                      sheetName: widget.sheetName,
                    ),
                  ),
                );
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'add_barcode',
                child: Row(
                  children: [
                    Icon(Icons.qr_code, size: 18, color: Colors.blue),
                    SizedBox(width: 8),
                    Text('Ajouter un code-barres'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'save',
                child: Row(
                  children: [
                    Icon(Icons.save, size: 18),
                    SizedBox(width: 8),
                    Text('Enregistrer'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'batches',
                child: Row(
                  children: [
                    Icon(Icons.folder, size: 18),
                    SizedBox(width: 8),
                    Text('Batches sauvegardés'),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'finish',
                child: Row(
                  children: [
                    Icon(Icons.exit_to_app, size: 18),
                    SizedBox(width: 8),
                    Text('Terminer'),
                  ],
                ),
              ),
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
            ListTile(
              leading: const Icon(Icons.folder),
              title: const Text('Batches sauvegardés'),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => BatchesListPage(
                      countingSheetId: widget.countingSheetId,
                      adjustmentId: widget.adjustmentId,
                      zoneName: widget.zoneName,
                      sheetName: widget.sheetName,
                    ),
                  ),
                );
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