import 'package:flutter/material.dart';
import '../utils/constants.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:badges/badges.dart' as badges;
import 'dart:async';
import 'package:flutter/services.dart';
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

class _ScanningPageState extends State<ScanningPage> with SingleTickerProviderStateMixin, WidgetsBindingObserver {
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
  Timer? _scanDebounceTimer;
  bool _isProcessingScan = false;

  // For scan flash effect
  bool _showScanZone = true;

  @override
  void initState() {
    super.initState();
    _isMounted = true;
    WidgetsBinding.instance.addObserver(this);
    _loadSavedItems();
  }

  @override
  void dispose() {
    _isMounted = false;
    WidgetsBinding.instance.removeObserver(this);
    _scanDebounceTimer?.cancel();
    scannerController.dispose();
    super.dispose();
  }

  // Detect when app comes back from background
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      print("App resumed, reloading scanned items...");
      _loadSavedItems();
    }
  }

  Future<void> _loadSavedItems() async {
    try {
      setState(() {
        isLoading = true;
      });

      // Load items from local storage
      final savedItems = await LocalStorageService.loadScannedItems(widget.countingSheetId);

      if (_isMounted) {
        setState(() {
          scannedItems = savedItems;
          isLoading = false;
        });

        // Show count of restored items
        if (savedItems.isNotEmpty) {
          print("Restored ${savedItems.length} scanned items from local storage");

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && scannedItems.isNotEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('${scannedItems.length} articles scannés restaurés'),
                  backgroundColor: AppColors.primaryColor,
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          });
        } else {
          print(" No saved items found for sheet: ${widget.countingSheetId}");
        }
      }
    } catch (e) {
      print("Error loading saved items: $e");
      if (_isMounted) {
        setState(() {
          scannedItems = [];
          isLoading = false;
        });
      }
    }
  }

  Future<void> _saveItems() async {
    if (_isMounted) {
      await LocalStorageService.saveScannedItems(widget.countingSheetId, scannedItems);
      print("Saved ${scannedItems.length} items to local storage");
    }
  }

  Future<int?> _showQuantityDialog(String productName, String barcode) async {
    final TextEditingController qtyController = TextEditingController(text: '1');

    return showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            const Icon(Icons.numbers, color: AppColors.primaryColor, size: 20),
            const SizedBox(width: 8),
            Expanded(child: Text('Quantité pour $productName', overflow: TextOverflow.ellipsis)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Code: $barcode', style: const TextStyle(color: AppColors.textSecondary, fontSize: 13)),
            const SizedBox(height: 14),
            TextField(
              controller: qtyController,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Quantité',
                prefixIcon: Icon(Icons.tag, size: 20),
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

  //  Process a single barcode
  Future<void> _processBarcode(String barcode) async {
    setState(() {
      isLookingUp = true;
      isScanning = false;
    });

    // Check if already in current list
    final existingIndex = scannedItems.indexWhere((item) => item.barcode == barcode);
    if (existingIndex != -1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cet article est déjà dans la liste'), backgroundColor: AppColors.warningColor),
      );
      setState(() {
        isLookingUp = false;
        isScanning = true;
      });
      return;
    }

    // Check if already in saved batches
    final inBatch = await _isInSavedBatches(barcode);
    if (inBatch) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cet article est déjà dans un lot sauvegardé'), backgroundColor: AppColors.warningColor),
      );
      setState(() {
        isLookingUp = false;
        isScanning = true;
      });
      return;
    }

    // Look up product
    final result = await CountingService.lookupProduct(barcode);

    if (_isMounted) {
      setState(() {
        if (result != null && result['id'] != 0 && result['id'] != null) {
          final tracking = result['tracking'] ?? 'serial';
          final lotName = result['lot_name'] ?? barcode;
          final lotIdValue = result['lot_id'] ?? 0;
          final productIdValue = result['id'];

          if (tracking == 'lot') {
            _handleLotProduct(result, barcode, tracking, lotName, lotIdValue, productIdValue);
            return;
          }

          scannedItems.add(ScannedItem(
            barcode: barcode,
            productName: result['name'] ?? 'Unknown',
            productId: productIdValue,
            quantity: 1,
            lotNumber: lotName,
            lotId: lotIdValue,
            tracking: tracking,
          ));
          _saveItems(); // Save immediately
          isLookingUp = false;
          isScanning = true;

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(' Ajouté: ${result['name']}'),
              backgroundColor: AppColors.successColor,
              duration: const Duration(milliseconds: 800),
            ),
          );
        } else {
          isLookingUp = false;
          isScanning = true;

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Code non trouvé: $barcode'),
              backgroundColor: AppColors.errorColor,
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
        _saveItems(); // Save immediately
        isScanning = true;
        isLookingUp = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ajouté: ${result['name']} - Quantité: $qty'),
          backgroundColor: AppColors.successColor,
          duration: const Duration(milliseconds: 800),
        ),
      );
    }
  }

  // Manual barcode entry
  Future<void> _addManualBarcode() async {
    final TextEditingController barcodeController = TextEditingController();

    final shouldAdd = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.keyboard_outlined, color: AppColors.primaryColor, size: 20),
              SizedBox(width: 8),
              Text("Saisir manuellement", style: TextStyle(fontSize: 18)),
            ],
          ),
          content: TextField(
            controller: barcodeController,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: "Numéro de série",
              hintText: "Entrez le code-barres manuellement",
              prefixIcon: Icon(Icons.qr_code, size: 20),
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
                backgroundColor: AppColors.successColor,
                foregroundColor: Colors.white,
              ),
              child: const Text("Ajouter", style: TextStyle(fontSize: 14)),
            ),
          ],
        );
      },
    );

    if (shouldAdd == true && barcodeController.text.isNotEmpty) {
      await _processBarcode(barcodeController.text.trim());
    }
  }

  void onBarcodeDetected(BarcodeCapture capture) async {
    if (!isScanning || isLookingUp || _isProcessingScan) return;
    if (_scanDebounceTimer?.isActive ?? false) return;

    _scanDebounceTimer = Timer(const Duration(milliseconds: 400), () {});
    _isProcessingScan = true;

    final barcode = capture.barcodes.first.rawValue;
    if (barcode == null || barcode == lastScannedBarcode) {
      _isProcessingScan = false;
      return;
    }

    setState(() {
      _showScanZone = false;
      isScanning = false;
      isLookingUp = true;
      lastScannedBarcode = barcode;
    });

    Future.delayed(const Duration(milliseconds: 150), () {
      if (_isMounted) {
        setState(() => _showScanZone = true);
      }
    });

    await _processBarcode(barcode);

    _isProcessingScan = false;
  }

  void _logout() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text("Déconnexion"),
        content: const Text("Voulez-vous vraiment vous déconnecter ?"),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Non")),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
            },
            style: ElevatedButton.styleFrom(backgroundColor: AppColors.errorColor),
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
          const SnackBar(content: Text(" Envoyé avec succès !"), backgroundColor: AppColors.successColor),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de l\'envoi'), backgroundColor: AppColors.errorColor),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.save_outlined, color: AppColors.primaryColor, size: 20),
            SizedBox(width: 8),
            Text("Enregistrer le lot", style: TextStyle(fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("Voulez-vous sauvegarder ce lot ?", style: TextStyle(fontSize: 14)),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.primaryColor.withOpacity(0.08),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                "Articles: ${scannedItems.length}",
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primaryColor),
              ),
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
                  content: Text('$batchName sauvegardé (${batch.items.length} articles)'),
                  backgroundColor: AppColors.successColor,
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
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black.withOpacity(0.35),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.zoneName,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          overflow: TextOverflow.ellipsis,
        ),
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
            tooltip: 'Saisie manuelle',
            icon: const Icon(Icons.keyboard_outlined, size: 22, color: Colors.white),
            onPressed: _addManualBarcode,
          ),
          IconButton(
            tooltip: 'Enregistrer le lot',
            icon: const Icon(Icons.save_outlined, size: 22, color: Colors.white),
            onPressed: _showSaveConfirmation,
          ),
          badges.Badge(
            showBadge: scannedItems.isNotEmpty,
            badgeStyle: const badges.BadgeStyle(badgeColor: AppColors.tertiaryColor),
            badgeContent: Text('${scannedItems.length}', style: const TextStyle(fontSize: 10, color: Colors.black)),
            child: IconButton(
              tooltip: 'Articles scannés',
              icon: const Icon(Icons.list_alt, size: 22, color: Colors.white),
              onPressed: navigateToSummary,
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'logout') {
                _logout();
              }
            },
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'logout',
                child: Row(
                  children: [
                    Icon(Icons.logout, size: 18, color: AppColors.errorColor),
                    SizedBox(width: 8),
                    Text('Déconnexion', style: TextStyle(color: AppColors.errorColor)),
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
              decoration: BoxDecoration(color: AppColors.primaryColor),
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
            ListTile(
              leading: const Icon(Icons.inventory, color: AppColors.primaryColor),
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
                MobileScanner(
                  controller: scannerController,
                  onDetect: onBarcodeDetected,
                ),
                // Voile dégradé pour la lisibilité de l'AppBar sur la caméra
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  height: 110,
                  child: IgnorePointer(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.black.withOpacity(0.55), Colors.transparent],
                        ),
                      ),
                    ),
                  ),
                ),
                if (_showScanZone)
                  _buildFocusedScanZone(),
                _buildCornerIndicators(),
                if (isLookingUp)
                  Positioned(
                    bottom: 20,
                    left: 20,
                    right: 20,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.75),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.tertiaryColor),
                          ),
                          SizedBox(width: 10),
                          Text('Recherche du produit...', style: TextStyle(color: Colors.white, fontSize: 12.5)),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Panneau d'état
          Container(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            decoration: const BoxDecoration(
              color: AppColors.surfaceColor,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(22),
                topRight: Radius.circular(22),
              ),
              boxShadow: [
                BoxShadow(color: Colors.black26, blurRadius: 12, offset: Offset(0, -4)),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        widget.sheetName,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: AppColors.textColor),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: AppColors.primaryColor.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${scannedItems.length}',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: AppColors.primaryColor),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: (scannedItems.length / 999).clamp(0.0, 1.0),
                    minHeight: 5,
                    backgroundColor: AppColors.borderColor,
                    color: AppColors.tertiaryColor,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  scannedItems.isEmpty
                      ? "Scannez le code-barres"
                      : "${scannedItems.length} article${scannedItems.length > 1 ? 's' : ''} scanné${scannedItems.length > 1 ? 's' : ''}",
                  style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 46,
                  child: ElevatedButton.icon(
                    icon: const Icon(Icons.list_alt, size: 18),
                    label: Text('Voir la liste (${scannedItems.length})', style: const TextStyle(fontSize: 13)),
                    onPressed: navigateToSummary,
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
        foregroundColor: AppColors.primaryColor,
        onPressed: () => scannerController.toggleTorch(),
        child: const Icon(Icons.flash_on, size: 20),
      ),
    );
  }

  Widget _buildFocusedScanZone() {
    return IgnorePointer(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: AppColors.tertiaryColor.withOpacity(0.3),
            width: 1,
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(
                margin: EdgeInsets.symmetric(
                  vertical: MediaQuery.of(context).size.height * 0.40,
                ),
                child: Stack(
                  children: [
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 30),
                      decoration: BoxDecoration(
                        color: AppColors.tertiaryColor.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.tertiaryColor.withOpacity(0.3),
                            blurRadius: 10,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      height: 3,
                      child: Stack(
                        children: [
                          Container(
                            margin: const EdgeInsets.symmetric(horizontal: 40),
                            height: 2,
                            color: AppColors.tertiaryColor.withOpacity(0.8),
                          ),
                          Positioned(
                            left: 0,
                            right: 0,
                            top: 0,
                            bottom: 0,
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 20),
                              child: Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  _buildDot(),
                                  _buildDot(),
                                  _buildDot(),
                                  _buildDot(),
                                  _buildDot(),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      left: 10,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            border: Border(
                              right: BorderSide(color: AppColors.tertiaryColor.withOpacity(0.5), width: 2),
                              top: BorderSide(color: AppColors.tertiaryColor.withOpacity(0.5), width: 2),
                              bottom: BorderSide(color: AppColors.tertiaryColor.withOpacity(0.5), width: 2),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      right: 10,
                      top: 0,
                      bottom: 0,
                      child: Center(
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            border: Border(
                              left: BorderSide(color: AppColors.tertiaryColor.withOpacity(0.5), width: 2),
                              top: BorderSide(color: AppColors.tertiaryColor.withOpacity(0.5), width: 2),
                              bottom: BorderSide(color: AppColors.tertiaryColor.withOpacity(0.5), width: 2),
                            ),
                          ),
                        ),
                      ),
                    ),
                    Positioned(
                      bottom: 20,
                      left: 0,
                      right: 0,
                      child: Center(
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.6),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'SCANNEZ ICI',
                            style: TextStyle(
                              color: AppColors.tertiaryColor.withOpacity(0.5),
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              letterSpacing: 3,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDot() {
    return Container(
      width: 3,
      height: 3,
      decoration: BoxDecoration(
        color: AppColors.tertiaryColor.withOpacity(0.5),
        shape: BoxShape.circle,
      ),
    );
  }

  Widget _buildCornerIndicators() {
    return IgnorePointer(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: AppColors.tertiaryColor.withOpacity(0.2),
            width: 1,
          ),
        ),
        child: Stack(
          children: [
            Positioned(
              top: 10,
              left: 10,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: AppColors.tertiaryColor.withOpacity(0.4), width: 2),
                    left: BorderSide(color: AppColors.tertiaryColor.withOpacity(0.4), width: 2),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 10,
              right: 10,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  border: Border(
                    top: BorderSide(color: AppColors.tertiaryColor.withOpacity(0.4), width: 2),
                    right: BorderSide(color: AppColors.tertiaryColor.withOpacity(0.4), width: 2),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 10,
              left: 10,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: AppColors.tertiaryColor.withOpacity(0.4), width: 2),
                    left: BorderSide(color: AppColors.tertiaryColor.withOpacity(0.4), width: 2),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 10,
              right: 10,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: AppColors.tertiaryColor.withOpacity(0.4), width: 2),
                    right: BorderSide(color: AppColors.tertiaryColor.withOpacity(0.4), width: 2),
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