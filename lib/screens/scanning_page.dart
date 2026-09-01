import 'package:flutter/material.dart';
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
    // ✅ no returnImage/OCR needed anymore — filtering is done on the
    // barcode value itself, so scanning stays fast and fully offline.
  );
  List<ScannedItem> scannedItems = [];
  bool isScanning = true;
  String? lastScannedBarcode;
  bool isLookingUp = false;
  bool isLoading = true;
  bool _isMounted = false;
  Timer? _scanDebounceTimer;
  bool _isProcessingScan = false;

  // ✅ Shared scanning session (two team members, same sheet, two phones).
  // Polls the server for the merged list every few seconds.
  Timer? _liveSyncTimer;
  // Quantity for each barcode that we've added/incremented locally but
  // haven't successfully pushed to the server yet (e.g. no connectivity).
  // Flushed on every poll tick until it succeeds.
  final Map<String, int> _pendingDeltas = {};

  // For scan flash effect
  bool _showScanZone = true;

  @override
  void initState() {
    super.initState();
    _isMounted = true;
    WidgetsBinding.instance.addObserver(this);
    _loadSavedItems();
    // ✅ Poll every 4s for scans made by the other team member on this
    // same counting sheet, and retry pushing anything we couldn't send.
    _liveSyncTimer = Timer.periodic(const Duration(seconds: 4), (_) => _syncLiveSession());
  }

  @override
  void dispose() {
    _isMounted = false;
    WidgetsBinding.instance.removeObserver(this);
    _scanDebounceTimer?.cancel();
    _liveSyncTimer?.cancel();
    scannerController.dispose();
    super.dispose();
  }

  // ✅ Detect when app comes back from background
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      print("🔄 App resumed, reloading scanned items...");
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
          print("✅ Restored ${savedItems.length} scanned items from local storage");

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && scannedItems.isNotEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text('📱 ${scannedItems.length} articles scannés restaurés'),
                  backgroundColor: Colors.blue,
                  duration: const Duration(seconds: 2),
                ),
              );
            }
          });
        } else {
          print("📭 No saved items found for sheet: ${widget.countingSheetId}");
        }
      }
    } catch (e) {
      print("❌ Error loading saved items: $e");
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
      print("💾 Saved ${scannedItems.length} items to local storage");
    }
  }

  // ✅ Runs every 4s: first retries any scan we couldn't push earlier
  // (offline fallback), then pulls the latest shared list and merges in
  // whatever the teammate scanned that we don't have yet.
  Future<void> _syncLiveSession() async {
    if (!_isMounted) return;

    // 1) Flush anything pending (added/incremented while offline).
    if (_pendingDeltas.isNotEmpty) {
      final barcodes = List<String>.from(_pendingDeltas.keys);
      for (final barcode in barcodes) {
        final index = scannedItems.indexWhere((it) => it.barcode == barcode);
        if (index == -1) {
          // Item got removed locally in the meantime — nothing to push.
          _pendingDeltas.remove(barcode);
          continue;
        }
        final delta = _pendingDeltas[barcode]!;
        final item = scannedItems[index];
        final serverItems = await CountingService.pushLiveScan(
          countingSheetId: widget.countingSheetId,
          item: {
            'barcode': barcode,
            'quantity': delta,
            'product_name': item.productName,
            'product_id': item.productId,
            'lot_number': item.lotNumber,
            'lot_id': item.lotId,
            'tracking': item.tracking,
          },
        );
        if (serverItems != null) {
          _pendingDeltas.remove(barcode);
          _mergeServerItems(serverItems);
        }
        // If it failed again, it just stays in _pendingDeltas for next tick.
      }
      await _saveItems();
    }

    // 2) Pull the shared list and merge in anything new.
    final serverItems = await CountingService.getLiveItems(widget.countingSheetId);
    if (serverItems.isNotEmpty) {
      _mergeServerItems(serverItems);
    }
  }

  // Merges the server's shared list into our local `scannedItems`:
  // - barcodes we don't have yet (teammate scanned them) are added
  // - barcodes we DO have, and have nothing pending for, get their
  //   quantity aligned to the server's (authoritative) value
  // - barcodes with a pending local delta are left alone for now — the
  //   server value is stale until our push succeeds, so overwriting here
  //   would silently drop our teammate-visible quantity.
  void _mergeServerItems(List<Map<String, dynamic>> serverItems) {
    if (!_isMounted) return;
    bool changed = false;

    for (final serverItem in serverItems) {
      final barcode = serverItem['barcode'];
      if (barcode == null) continue;
      if (_pendingDeltas.containsKey(barcode)) continue;

      final index = scannedItems.indexWhere((it) => it.barcode == barcode);
      final serverQty = (serverItem['quantity'] is int)
          ? serverItem['quantity'] as int
          : int.tryParse('${serverItem['quantity']}') ?? 1;

      if (index == -1) {
        scannedItems.add(ScannedItem(
          barcode: barcode,
          productName: serverItem['product_name'] ?? '',
          productId: serverItem['product_id'] ?? 0,
          quantity: serverQty,
          lotNumber: serverItem['lot_number'],
          lotId: serverItem['lot_id'],
          tracking: serverItem['tracking'] ?? 'none',
        ));
        changed = true;
      } else if (scannedItems[index].quantity != serverQty) {
        scannedItems[index].quantity = serverQty;
        changed = true;
      }
    }

    if (changed && _isMounted) {
      setState(() {});
      _saveItems();
    }
  }

  // ✅ Pushes a scan (new item or extra quantity for an existing one) to
  // the shared session. On failure (offline), queues it so `_syncLiveSession`
  // retries automatically — the scan is never lost, it just stays local
  // until connectivity returns.
  Future<void> _pushScanOrQueue(ScannedItem item, int addedQuantity) async {
    final serverItems = await CountingService.pushLiveScan(
      countingSheetId: widget.countingSheetId,
      item: {
        'barcode': item.barcode,
        'quantity': addedQuantity,
        'product_name': item.productName,
        'product_id': item.productId,
        'lot_number': item.lotNumber,
        'lot_id': item.lotId,
        'tracking': item.tracking,
      },
    );

    if (serverItems != null) {
      _mergeServerItems(serverItems);
    } else {
      // Offline / server unreachable — retry on the next poll tick.
      _pendingDeltas[item.barcode] = (_pendingDeltas[item.barcode] ?? 0) + addedQuantity;
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

  // Check if barcode already exists in saved batches — scoped to THIS
  // counting sheet, same as the "Lots sauvegardés" page filters
  // (batch_list_page.dart: b.countingSheetId == widget.countingSheetId).
  // Without this scope, a batch saved under a different sheet could block
  // a scan here while that sheet's own batch list still shows empty.
  // ✅ Check ALL batches (synced or not) to prevent double-counting
  Future<bool> _isInSavedBatches(String barcode) async {
    try {
      final batches = await BatchStorageService.getBatches();
      for (final batch in batches) {
        if (batch.countingSheetId != widget.countingSheetId) continue;
        // ✅ Check both synced and non-synced batches
        for (final item in batch.items) {
          if (item.barcode == barcode) {
            return true;
          }
        }
      }
      return false;
    } catch (e) {
      return false;
    }
  }

  // ✅ Process a single barcode
  Future<void> _processBarcode(String barcode) async {
    setState(() {
      isLookingUp = true;
      isScanning = false;
    });

    // ✅ Already in the list (scanned by you OR your teammate, synced via
    // the shared session) — ask how many more to add instead of blocking.
    final existingIndex = scannedItems.indexWhere((item) => item.barcode == barcode);
    if (existingIndex != -1) {
      await _handleDuplicateScan(existingIndex, barcode);
      return;
    }

    // Check if already in saved batches
    final inBatch = await _isInSavedBatches(barcode);
    if (inBatch) {
      // ✅ Show strong warning via DialogBox instead of SnackBar
      if (_isMounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('⚠️ Article déjà compté', style: TextStyle(color: Colors.orange)),
            content: const Text(
              'Cet article a déjà été compté dans cette feuille et sauvegardé dans un lot.\n\n'
              'Si vous le scannez à nouveau, il sera compté deux fois.',
            ),
            actions: [
              TextButton(
                onPressed: () {
                  Navigator.pop(context);
                  setState(() {
                    isLookingUp = false;
                    isScanning = true;
                  });
                },
                child: const Text('OK, annuler'),
              ),
            ],
          ),
        );
      }
      setState(() {
        isLookingUp = false;
        isScanning = true;
      });
      return;
    }

    // Look up product
    final result = await CountingService.lookupProduct(barcode);

    if (_isMounted) {
      if (result != null && result['id'] != 0 && result['id'] != null) {
        final tracking = result['tracking'] ?? 'serial';
        final lotName = result['lot_name'] ?? barcode;
        final lotIdValue = result['lot_id'] ?? 0;
        final productIdValue = result['id'];

        if (tracking == 'lot') {
          await _handleLotProduct(result, barcode, tracking, lotName, lotIdValue, productIdValue);
          return;
        }

        final newItem = ScannedItem(
          barcode: barcode,
          productName: result['name'] ?? 'Unknown',
          productId: productIdValue,
          quantity: 1,
          lotNumber: lotName,
          lotId: lotIdValue,
          tracking: tracking,
        );

        setState(() {
          scannedItems.add(newItem);
          isLookingUp = false;
          isScanning = true;
        });
        _saveItems(); // ✅ Save immediately (local, offline-safe)
        _pushScanOrQueue(newItem, 1); // ✅ Share with teammate's phone

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Ajouté: ${result['name']}'),
            backgroundColor: Colors.green,
            duration: const Duration(milliseconds: 800),
          ),
        );
      } else {
        setState(() {
          isLookingUp = false;
          isScanning = true;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Code non trouvé: $barcode'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // ✅ Barcode already scanned (by this phone or the teammate's) — ask for
  // an additional quantity, add it locally, and share the update.
  Future<void> _handleDuplicateScan(int existingIndex, String barcode) async {
    final existingItem = scannedItems[existingIndex];
    final addedQty = await _showQuantityDialog(
      '${existingItem.productName} (déjà scanné — quantité actuelle: ${existingItem.quantity})',
      barcode,
    );

    if (addedQty == null) {
      if (_isMounted) {
        setState(() {
          isLookingUp = false;
          isScanning = true;
        });
      }
      return;
    }

    if (_isMounted) {
      setState(() {
        scannedItems[existingIndex].quantity += addedQty;
        isLookingUp = false;
        isScanning = true;
      });
      _saveItems();
      _pushScanOrQueue(existingItem, addedQty);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ ${existingItem.productName}: +$addedQty (total ${scannedItems[existingIndex].quantity})'),
          backgroundColor: Colors.green,
          duration: const Duration(milliseconds: 900),
        ),
      );
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
      final newItem = ScannedItem(
        barcode: barcode,
        productName: result['name'] ?? 'Unknown',
        productId: productIdValue,
        quantity: qty,
        lotNumber: lotName,
        lotId: lotIdValue,
        tracking: tracking,
      );

      setState(() {
        scannedItems.add(newItem);
        isScanning = true;
        isLookingUp = false;
      });
      _saveItems(); // ✅ Save immediately (local, offline-safe)
      _pushScanOrQueue(newItem, qty); // ✅ Share with teammate's phone

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('✅ Ajouté: ${result['name']} - Quantité: $qty'),
          backgroundColor: Colors.green,
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
      await _processBarcode(barcodeController.text.trim());
    }
  }

  void onBarcodeDetected(BarcodeCapture capture) async {
    if (!isScanning || isLookingUp || _isProcessingScan) return;
    if (_scanDebounceTimer?.isActive ?? false) return;
    if (capture.barcodes.isEmpty) return;

    _scanDebounceTimer = Timer(const Duration(milliseconds: 400), () {});
    _isProcessingScan = true;

    try {
      // ✅ Use the first barcode detected
      final String? barcode = capture.barcodes.first.rawValue;

      if (barcode == null || barcode.isEmpty) {
        return;
      }

      if (barcode == lastScannedBarcode) return;

      setState(() {
        _showScanZone = false;
        isLookingUp = true;
      });

      lastScannedBarcode = barcode;
      await _processBarcode(barcode);
    } finally {
      Future.delayed(const Duration(milliseconds: 150), () {
        if (_isMounted) setState(() => _showScanZone = true);
      });
      _isProcessingScan = false;
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
        await CountingService.clearLiveItems(widget.countingSheetId); // ✅ reset shared session for both phones
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
              await CountingService.clearLiveItems(widget.countingSheetId); // ✅ reset shared session for both phones
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
                MobileScanner(
                  controller: scannerController,
                  onDetect: onBarcodeDetected,
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

  Widget _buildFocusedScanZone() {
    return IgnorePointer(
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: Colors.red.withOpacity(0.3),
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
                        color: Colors.red.withOpacity(0.15),
                        borderRadius: BorderRadius.circular(2),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.red.withOpacity(0.3),
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
                            color: Colors.red.withOpacity(0.8),
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
                              right: BorderSide(color: Colors.red.withOpacity(0.5), width: 2),
                              top: BorderSide(color: Colors.red.withOpacity(0.5), width: 2),
                              bottom: BorderSide(color: Colors.red.withOpacity(0.5), width: 2),
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
                              left: BorderSide(color: Colors.red.withOpacity(0.5), width: 2),
                              top: BorderSide(color: Colors.red.withOpacity(0.5), width: 2),
                              bottom: BorderSide(color: Colors.red.withOpacity(0.5), width: 2),
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
                              color: Colors.red.withOpacity(0.5),
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
        color: Colors.red.withOpacity(0.5),
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
            color: Colors.red.withOpacity(0.2),
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
                    top: BorderSide(color: Colors.red.withOpacity(0.4), width: 2),
                    left: BorderSide(color: Colors.red.withOpacity(0.4), width: 2),
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
                    top: BorderSide(color: Colors.red.withOpacity(0.4), width: 2),
                    right: BorderSide(color: Colors.red.withOpacity(0.4), width: 2),
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
                    bottom: BorderSide(color: Colors.red.withOpacity(0.4), width: 2),
                    left: BorderSide(color: Colors.red.withOpacity(0.4), width: 2),
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
                    bottom: BorderSide(color: Colors.red.withOpacity(0.4), width: 2),
                    right: BorderSide(color: Colors.red.withOpacity(0.4), width: 2),
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