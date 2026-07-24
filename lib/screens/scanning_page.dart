import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:badges/badges.dart' as badges;
import 'dart:async';
import '../models/scanned_item.dart';
import '../services/counting_service.dart';
import '../services/local_storage_service.dart';
import 'scanned_items_list_page.dart';
import '../models/batch.dart';
import '../services/batch_storage_service.dart';
import 'batch_list_page.dart';
import 'feuille_list_page.dart';

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

class _ScanningPageState extends State<ScanningPage> with SingleTickerProviderStateMixin {
  final MobileScannerController scannerController = MobileScannerController(
    facing: CameraFacing.back,
    torchEnabled: false,
  );
  List<ScannedItem> scannedItems = [];
  bool isScanning = true;
  String? lastScannedBarcode;
  bool isLookingUp = false;
  bool isLoading = true;
  bool _isMounted = false;

  // Laser animation
  late AnimationController _laserAnimationController;
  late Animation<double> _laserAnimation;
  bool _isLaserOn = true;

  @override
  void initState() {
    super.initState();
    _isMounted = true;
    _loadSavedItems();

    // Laser animation - constantly scanning
    _laserAnimationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);

    _laserAnimation = Tween<double>(begin: 0.1, end: 0.9).animate(
      CurvedAnimation(
        parent: _laserAnimationController,
        curve: Curves.easeInOut,
      ),
    );
  }

  Future<void> _loadSavedItems() async {
    final savedItems = await LocalStorageService.loadScannedItems(widget.countingSheetId);
    if (_isMounted) {
      setState(() {
        scannedItems = savedItems;
        isLoading = false;
      });
    }
  }

  Future<void> _saveItems() async {
    if (_isMounted) {
      await LocalStorageService.saveScannedItems(widget.countingSheetId, scannedItems);
    }
  }

  Future<int?> _showQuantityDialog(String productName, String barcode) async {
    final TextEditingController qtyController = TextEditingController(text: '1');

    return showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text('Quantité pour $productName'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Code: $barcode'),
            const SizedBox(height: 12),
            TextField(
              controller: qtyController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Quantité',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, null),
            child: const Text('Annuler'),
          ),
          ElevatedButton(
            onPressed: () {
              final qty = int.tryParse(qtyController.text);
              if (qty != null && qty > 0) {
                Navigator.pop(context, qty);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Veuillez entrer une quantité valide')),
                );
              }
            },
            child: const Text('Ajouter'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _isMounted = false;
    _laserAnimationController.dispose();
    scannerController.dispose();
    super.dispose();
  }

  // Check if barcode already exists in saved batches
  Future<bool> _isInSavedBatches(String barcode) async {
    try {
      final batches = await BatchStorageService.getBatches();
      for (final batch in batches) {
        if (!batch.isSynced) {
          for (final item in batch.items) {
            if (item.barcode == barcode) {
              return true;
            }
          }
        }
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  // Manual barcode entry
  Future<void> _addManualBarcode() async {
    final TextEditingController barcodeController = TextEditingController();

    final shouldAdd = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Saisir manuellement", style: TextStyle(fontSize: 18)),
          content: TextField(
            controller: barcodeController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: "Numéro de série",
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

      final existingIndex = scannedItems.indexWhere((item) => item.barcode == barcode);
      if (existingIndex != -1) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⚠️ Cet article est déjà dans la liste'), backgroundColor: Colors.orange),
        );
        setState(() {
          isLookingUp = false;
          isScanning = true;
        });
        return;
      }

      final inBatch = await _isInSavedBatches(barcode);
      if (inBatch) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⚠️ Cet article est déjà dans un lot sauvegardé'), backgroundColor: Colors.orange),
        );
        setState(() {
          isLookingUp = false;
          isScanning = true;
        });
        return;
      }

      final result = await CountingService.lookupProduct(barcode);

      if (result != null && result['id'] != 0 && result['id'] != null) {
        final tracking = result['tracking'] ?? 'serial';
        final lotName = result['lot_name'] ?? barcode;
        final lotIdValue = result['lot_id'] ?? 0;
        final productIdValue = result['id'];

        int finalQuantity = tracking == 'serial' ? 1 : 0;
        if (tracking == 'lot') {
          final qty = await _showQuantityDialog(result['name'] ?? 'Unknown', barcode);
          if (qty == null) {
            setState(() {
              isLookingUp = false;
              isScanning = true;
            });
            return;
          }
          finalQuantity = qty;
        }

        setState(() {
          scannedItems.add(ScannedItem(
            barcode: barcode,
            productName: result['name'] ?? 'Unknown',
            productId: productIdValue,
            quantity: finalQuantity,
            lotNumber: lotName,
            lotId: lotIdValue,
            tracking: tracking,
          ));
          _saveItems();
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Ajouté: ${result['name']}'),
            backgroundColor: Colors.green,
            duration: const Duration(milliseconds: 800),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('⚠️ Code-barres non trouvé: $barcode'),
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

  // ✅ LASER SCANNER - Only scans when barcode is detected
  void onBarcodeDetected(BarcodeCapture capture) async {
    // Only scan if laser is active and not already processing
    if (!isScanning || isLookingUp) return;

    final barcode = capture.barcodes.first.rawValue;
    if (barcode == null || barcode == lastScannedBarcode) return;

    // ✅ LASER FLASH - quick flash when scanning
    setState(() {
      _isLaserOn = false;
      isScanning = false;
      isLookingUp = true;
      lastScannedBarcode = barcode;
    });

    // Flash back on after 200ms
    Future.delayed(const Duration(milliseconds: 200), () {
      if (_isMounted) {
        setState(() {
          _isLaserOn = true;
        });
      }
    });

    // Check if already in current list
    final existingIndex = scannedItems.indexWhere((item) =>
    item.barcode == barcode);
    if (existingIndex != -1) {
      setState(() {
        isScanning = true;
        isLookingUp = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Cet article a déjà été scanné!'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    // Check if already in saved batches
    final inBatch = await _isInSavedBatches(barcode);
    if (inBatch) {
      setState(() {
        isScanning = true;
        isLookingUp = false;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('⚠️ Cet article est déjà dans un lot sauvegardé'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }

    // Look up product
    final result = await CountingService.lookupProduct(barcode);

    if (_isMounted) {
      setState(() {
        if (result != null && result['id'] != 0 && result['id'] != null) {
          //product found (either from cache or API)
          String tracking = result['tracking'] ?? 'serial';
          String lotName = result['lot_name'] ?? barcode;
          int lotIdValue = result['lot_id'] ?? 0;
          int productIdValue = result['id'];

          //for lot, ask for quantity

          if (tracking == 'lot') {
            //handle lot product

            _handleLotProduct(
                result, barcode, tracking, lotName, lotIdValue, productIdValue);
            return;
          }
          //serial product - add
          scannedItems.add(ScannedItem(
            barcode: barcode,
            productName: result['name'] ?? 'Unknown',
            productId: productIdValue,
            quantity: 1,
            lotNumber: lotName,
            lotId: lotIdValue,
            tracking: tracking,
          ));
          _saveItems();
          isScanning = true;
          isLookingUp = false;

          String source = result['fromCache'] == true ? '💾 (cache)' : '🌐';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('✅ Ajouté: ${result['name']}'),
              backgroundColor: Colors.green,
              duration: const Duration(milliseconds: 800),
            ),
          );
        } else {
          //product not found (cache filled and API failed)
          isScanning = true;
          isLookingUp = false;


          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('⚠️ Code-barres non trouvé: $barcode'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      });
    }
  }

  Future<void> _handleLotProduct(Map<String, dynamic> result, String barcode, String tracking, String lotName, int lotIdValue, int productIdValue) async {
    final qty = await _showQuantityDialog(result['name'] ?? 'Unknown', barcode);
    if (qty == null) {
      if (_isMounted) {
        setState(() {
          isScanning = true;
          isLookingUp = false;
        });
      }
      return;
    }

    if (_isMounted) {
      setState(() {
        scannedItems.add(ScannedItem(
          barcode: barcode,
          productName: result['name'] ?? 'Unknown',
          productId: productIdValue,
          quantity: qty,
          lotNumber: lotName,
          lotId: lotIdValue,
          tracking: tracking,
        ));
        _saveItems();
        isScanning = true;
        isLookingUp = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Ajouté: ${result['name']} - Quantité: $qty'),
          backgroundColor: Colors.green,
          duration: const Duration(milliseconds: 800),
        ),
      );
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

    if (_isMounted) {
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
            if (_isMounted) {
              setState(() {
                scannedItems = updatedItems;
                _saveItems();
              });
            }
          },
        ),
      ),
    );
  }

  void navigateToFeuilleList() {
    // Navigate back to the feuille list page
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (context) => FeuilleListPage(
          adjustmentId: widget.adjustmentId,
        ),
      ),
          (route) => false,
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
        title: const Text("Enregistrer le lot", style: TextStyle(fontSize: 18)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Voulez-vous sauvegarder ce lot ?", style: TextStyle(fontSize: 14)),
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
              final batchName = "lot $batchNumber";
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
              if (_isMounted) {
                setState(() {
                  scannedItems.clear();
                  lastScannedBarcode = null;
                  isScanning = true;
                });
                await _saveItems();

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

              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('✅ $batchName sauvegardé (${batch.items.length} articles)'),
                  backgroundColor: Colors.green,
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
    if (isLoading) {
      return const Scaffold(
        backgroundColor: Colors.black,
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, size: 22),
            onPressed: () {
              Scaffold.of(context).openDrawer();
            },
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.create_sharp, size: 22, color: Colors.white),
            onPressed: _addManualBarcode,
          ),
          IconButton(
            icon: const Icon(Icons.save, size: 22, color: Colors.white),
            onPressed: _showSaveConfirmation,
          ),
          // ✅ Added: List icon to navigate to scanned items
          badges.Badge(
            showBadge: scannedItems.isNotEmpty,
            badgeContent: Text('${scannedItems.length}', style: const TextStyle(fontSize: 10)),
            child: IconButton(
              icon: const Icon(Icons.list, size: 22, color: Colors.white),
              onPressed: navigateToSummary,
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'logout') {
                _logout();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 18, color: Colors.red),
                    SizedBox(width: 8),
                    Text('Déconnexion', style: TextStyle(color: Colors.red)),
                  ],
                ),
              ),
            ],
            child: const Padding(
              padding: EdgeInsets.all(8.0),
              child: Icon(Icons.more_vert, size: 22, color: Colors.white),
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
                    'Wise Inventory',
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
            // ✅ Added: Feuilles de comptage
            ListTile(
              leading: const Icon(Icons.inventory, color: Colors.blue),
              title: const Text('Feuilles de comptage'),
              onTap: () {
                Navigator.pop(context);
                navigateToFeuilleList();
              },
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
              title: const Text('Lots sauvegardés'),
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
          ],
        ),
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: Stack(
              children: [
                // Camera preview
                MobileScanner(
                  controller: scannerController,
                  onDetect: onBarcodeDetected,
                ),

                // ✅ LASER SCANNER EFFECT - Red laser line
                if (_isLaserOn)
                  AnimatedBuilder(
                    animation: _laserAnimation,
                    builder: (context, child) {
                      return CustomPaint(
                        painter: LaserScannerPainter(
                          laserPosition: _laserAnimation.value,
                        ),
                        size: Size.infinite,
                      );
                    },
                  ),

                // Corner indicators
                _buildCornerIndicators(),

                // Looking up overlay
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
                    Text('${scannedItems.length}', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: scannedItems.length / 999,
                    minHeight: 4,
                    backgroundColor: Colors.grey[200],
                    color: Colors.green,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  scannedItems.isEmpty
                      ? "Scannez le code-barres"
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

  Widget _buildCornerIndicators() {
    return IgnorePointer(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: Colors.red.withOpacity(0.5),
            width: 2,
          ),
        ),
        child: Stack(
          children: [
            // Top-left corner
            Positioned(
              top: 10,
              left: 10,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Colors.red, width: 3),
                    left: BorderSide(color: Colors.red, width: 3),
                  ),
                ),
              ),
            ),
            // Top-right corner
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: Colors.red, width: 3),
                    right: BorderSide(color: Colors.red, width: 3),
                  ),
                ),
              ),
            ),
            // Bottom-left corner
            Positioned(
              bottom: 10,
              left: 10,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Colors.red, width: 3),
                    left: BorderSide(color: Colors.red, width: 3),
                  ),
                ),
              ),
            ),
            // Bottom-right corner
            Positioned(
              bottom: 10,
              right: 10,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Colors.red, width: 3),
                    right: BorderSide(color: Colors.red, width: 3),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ✅ LASER SCANNER PAINTER - Thin laser line that moves up and down
class LaserScannerPainter extends CustomPainter {
  final double laserPosition;

  LaserScannerPainter({required this.laserPosition});

  @override
  void paint(Canvas canvas, Size size) {
    final centerY = size.height * laserPosition;
    final startX = size.width * 0.05;
    final endX = size.width * 0.95;

    // 1. Laser line (thin, bright red)
    final laserPaint = Paint()
      ..color = Colors.red.withOpacity(0.9)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 2);

    canvas.drawLine(
      Offset(startX, centerY),
      Offset(endX, centerY),
      laserPaint,
    );

    // 2. Glow effect (wider, dimmer)
    final glowPaint = Paint()
      ..color = Colors.red.withOpacity(0.2)
      ..strokeWidth = 12
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    canvas.drawLine(
      Offset(startX, centerY),
      Offset(endX, centerY),
      glowPaint,
    );

    // 3. Laser dot at the ends
    final dotPaint = Paint()
      ..color = Colors.red.withOpacity(0.9)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(Offset(startX, centerY), 4, dotPaint);
    canvas.drawCircle(Offset(endX, centerY), 4, dotPaint);

    // 4. Scan bracket indicators (left and right)
    final bracketPaint = Paint()
      ..color = Colors.red.withOpacity(0.6)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    // Left bracket
    canvas.drawLine(
      Offset(startX - 10, centerY - 20),
      Offset(startX - 10, centerY - 10),
      bracketPaint,
    );
    canvas.drawLine(
      Offset(startX - 10, centerY + 20),
      Offset(startX - 10, centerY + 10),
      bracketPaint,
    );
    canvas.drawLine(
      Offset(startX - 10, centerY - 20),
      Offset(startX - 5, centerY - 20),
      bracketPaint,
    );
    canvas.drawLine(
      Offset(startX - 10, centerY + 20),
      Offset(startX - 5, centerY + 20),
      bracketPaint,
    );

    // Right bracket
    canvas.drawLine(
      Offset(endX + 10, centerY - 20),
      Offset(endX + 10, centerY - 10),
      bracketPaint,
    );
    canvas.drawLine(
      Offset(endX + 10, centerY + 20),
      Offset(endX + 10, centerY + 10),
      bracketPaint,
    );
    canvas.drawLine(
      Offset(endX + 10, centerY - 20),
      Offset(endX + 5, centerY - 20),
      bracketPaint,
    );
    canvas.drawLine(
      Offset(endX + 10, centerY + 20),
      Offset(endX + 5, centerY + 20),
      bracketPaint,
    );
  }

  @override
  bool shouldRepaint(LaserScannerPainter oldDelegate) {
    return oldDelegate.laserPosition != laserPosition;
  }
}