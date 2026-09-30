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

  // ✅ Shared scanning session (two team members, same sheet, two phones).
  // Polls the server for the merged list every few seconds.
  Timer? _liveSyncTimer;
  // Quantity for each barcode added/incremented locally but not yet
  // pushed to the server (e.g. no connectivity). Retried every poll tick.
  final Map<String, int> _pendingDeltas = {};
  // ✅ When this device last successfully scanned each barcode — used to
  // warn when a "duplicate" scan happens moments after the same one
  // (very likely an accidental re-scan from fatigue, not a new batch).
  final Map<String, DateTime> _lastScanTime = {};

  // ✅ Hardware barcode scanner support (rugged devices with a built-in
  // laser/imager engine set to "keyboard wedge" mode: the scanner types
  // the decoded barcode as keystrokes, ending with Enter — exactly like a
  // very fast typist). We capture that via a Focus node wrapping the page;
  // it never steals focus from actual text fields (search, quantity
  // dialogs) since those consume their own key events first.
  final FocusNode _hardwareScanFocusNode = FocusNode();
  String _hardwareScanBuffer = '';

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
    _hardwareScanFocusNode.dispose();
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

  // ✅ Runs every 4s: retries any scan we couldn't push earlier (offline
  // fallback), then pulls the shared list and merges in whatever the
  // teammate scanned that we don't have yet.
  Future<void> _syncLiveSession() async {
    if (!_isMounted) return;

    if (_pendingDeltas.isNotEmpty) {
      final barcodes = List<String>.from(_pendingDeltas.keys);
      for (final barcode in barcodes) {
        final index = scannedItems.indexWhere((it) => it.barcode == barcode);
        if (index == -1) {
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
      }
      await _saveItems();
    }

    final serverItems = await CountingService.getLiveItems(widget.countingSheetId);
    if (serverItems.isNotEmpty) {
      _mergeServerItems(serverItems);
    }
  }

  // Merges the server's shared list into local `scannedItems`: adds
  // barcodes we don't have yet (teammate scanned them), aligns quantity
  // for barcodes we do have (unless we have a pending unsynced delta for
  // it, in which case the server value is stale until our push succeeds).
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

  // ✅ Pushes a scan (new item or extra quantity) to the shared session.
  // On failure (offline), queues it so `_syncLiveSession` retries
  // automatically — the scan is never lost, just stays local until
  // connectivity returns.
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
      _pendingDeltas[item.barcode] = (_pendingDeltas[item.barcode] ?? 0) + addedQuantity;
    }
  }

  Future<int?> _showQuantityDialog(String productName, String barcode) async {
    final TextEditingController qtyController = TextEditingController(text: '1');

    final result = await showDialog<int>(
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
    _hardwareScanFocusNode.requestFocus(); // ✅ hardware scanner keeps working after the dialog closes
    return result;
  }

  // Check if barcode already exists in saved batches — scoped to THIS
  // counting sheet, same as the "Lots sauvegardés" page filters. Without
  // this scope, a batch saved under a different sheet could block a scan
  // here while that sheet's own batch list still shows empty.
  Future<bool> _isInSavedBatches(String barcode) async {
    try {
      final batches = await BatchStorageService.getBatches();
      for (final batch in batches) {
        if (batch.countingSheetId != widget.countingSheetId) continue;
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

    // ✅ Already in the list (scanned by you OR your teammate, synced via
    // the shared session) — ask for confirmation + quantity instead of
    // silently blocking (see _handleDuplicateScan).
    final existingIndex = scannedItems.indexWhere((item) => item.barcode == barcode);
    if (existingIndex != -1) {
      await _handleDuplicateScan(existingIndex, barcode);
      return;
    }

    // Check if already in a saved batch for THIS sheet
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

    // ✅ Check if this exact barcode was already sent to the ERP for this
    // sheet (covers the case where it was submitted in a previous session
    // or from a teammate's phone, not just what's stored locally).
    final alreadyInErp = await CountingService.isAlreadyInErp(
      countingSheetId: widget.countingSheetId,
      barcode: barcode,
    );
    if (alreadyInErp) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cet article a déjà été envoyé à l\'ERP'), backgroundColor: AppColors.warningColor),
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
        _lastScanTime[barcode] = DateTime.now();
        _saveItems(); // Save immediately (local, offline-safe)
        _pushScanOrQueue(newItem, 1); // ✅ Share with teammate's phone

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(' Ajouté: ${result['name']}'),
            backgroundColor: AppColors.successColor,
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
            content: Text('Code non trouvé: $barcode'),
            backgroundColor: AppColors.errorColor,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  // ✅ Barcode already scanned (by this phone or the teammate's). Fatigue
  // during a long count means a member can accidentally re-scan a group
  // of articles they already did — so instead of jumping straight to a
  // quantity input, we first make them explicitly confirm this really IS
  // an extra/new batch of the same article. If it was scanned moments ago
  // on THIS phone, the warning is much more explicit.
  Future<void> _handleDuplicateScan(int existingIndex, String barcode) async {
    final existingItem = scannedItems[existingIndex];

    final shouldAddMore = await _confirmDuplicateScan(existingItem, barcode);
    if (!shouldAddMore) {
      if (_isMounted) {
        setState(() {
          isLookingUp = false;
          isScanning = true;
        });
      }
      return;
    }

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

    // ✅ Show the computed result before committing — lets the user catch
    // a mistyped quantity before it's saved and shared with the teammate.
    final newTotal = existingItem.quantity + addedQty;
    final confirmed = await _confirmQuantityResult(existingItem, addedQty, newTotal);
    if (!confirmed) {
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
      _lastScanTime[barcode] = DateTime.now();
      _saveItems();
      _pushScanOrQueue(existingItem, addedQty);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${existingItem.productName}: +$addedQty (total ${scannedItems[existingIndex].quantity})'),
          backgroundColor: AppColors.successColor,
          duration: const Duration(milliseconds: 900),
        ),
      );
    }
  }

  // Confirms whether a re-scan of an already-listed barcode is really a
  // new/extra batch to add, or an accidental re-scan. Shows a much more
  // explicit ⚠️ warning when this exact barcode was scanned on THIS phone
  // only moments ago.
  Future<bool> _confirmDuplicateScan(ScannedItem item, String barcode) async {
    final lastScan = _lastScanTime[barcode];
    final isVeryRecent = lastScan != null && DateTime.now().difference(lastScan) < const Duration(seconds: 8);

    final String subtitle;
    if (lastScan != null) {
      final elapsed = DateTime.now().difference(lastScan);
      final elapsedText = elapsed.inMinutes >= 1 ? 'il y a ${elapsed.inMinutes} min' : 'il y a ${elapsed.inSeconds} sec';
      subtitle = 'Dernier scan sur ce téléphone : $elapsedText.';
    } else {
      subtitle = 'Déjà présent dans la liste (scanné par vous ou un coéquipier).';
    }

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(isVeryRecent ? '⚠️ Rescanné à l\'instant' : 'Article déjà scanné'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${item.productName}\nQuantité actuelle: ${item.quantity}'),
            const SizedBox(height: 8),
            Text(
              subtitle,
              style: TextStyle(
                color: isVeryRecent ? AppColors.errorColor : AppColors.textSecondary,
                fontWeight: isVeryRecent ? FontWeight.bold : FontWeight.normal,
              ),
            ),
            if (isVeryRecent) ...[
              const SizedBox(height: 8),
              const Text(
                'Vous venez de le scanner il y a quelques secondes — s\'agit-il vraiment d\'un nouveau lot du même article, ou d\'une erreur de scan ?',
                style: TextStyle(fontSize: 13),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Annuler (erreur de scan)'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: isVeryRecent ? AppColors.warningColor : AppColors.primaryColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Oui, ajouter une quantité'),
          ),
        ],
      ),
    );

    _hardwareScanFocusNode.requestFocus(); // ✅ hardware scanner keeps working after the dialog closes
    return result ?? false;
  }

  // ✅ Shows the RESULT of the quantity addition (current + added = new
  // total) and asks for explicit confirmation before saving/sharing it —
  // a last chance to catch a mistyped quantity.
  Future<bool> _confirmQuantityResult(ScannedItem item, int addedQty, int newTotal) async {
    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Confirmer la quantité'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(item.productName, style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 10),
            Text('Quantité actuelle : ${item.quantity}'),
            Text('Quantité ajoutée : +$addedQty'),
            const Divider(height: 20),
            Text(
              'Nouveau total : $newTotal',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: AppColors.primaryColor),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Non, annuler'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.successColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Oui, enregistrer'),
          ),
        ],
      ),
    );
    _hardwareScanFocusNode.requestFocus(); // ✅ hardware scanner keeps working after the dialog closes
    return result ?? false;
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
      _lastScanTime[barcode] = DateTime.now();
      _saveItems(); // Save immediately (local, offline-safe)
      _pushScanOrQueue(newItem, qty); // ✅ Share with teammate's phone

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
  // ✅ prefillValue is set when this dialog is opened because the physical
  // scanner was used (not tapped open by the user). In that case, the
  // scanned value is shown in the field for a moment — so it's always
  // visible where a manual entry would go — then the dialog continues
  // automatically, exactly as if "Ajouter" had been pressed. Manual typing
  // still works normally in every case.
  Future<void> _addManualBarcode({String? prefillValue}) async {
    final TextEditingController barcodeController = TextEditingController(text: prefillValue ?? '');
    final bool fromHardwareScan = prefillValue != null && prefillValue.isNotEmpty;

    final shouldAdd = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        if (fromHardwareScan) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            Future.delayed(const Duration(milliseconds: 400), () {
              if (Navigator.canPop(context)) {
                Navigator.pop(context, true);
              }
            });
          });
        }

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
            textInputAction: TextInputAction.done,
            // ✅ The physical scanner types the barcode as keystrokes (it
            // has focus via autofocus) then sends Enter — this submits
            // automatically, exactly like tapping "Ajouter", so scanning
            // here continues the normal process without an extra tap.
            onSubmitted: (value) {
              if (value.trim().isNotEmpty) {
                Navigator.pop(context, true);
              }
            },
            decoration: const InputDecoration(
              labelText: "Numéro de série",
              hintText: "Entrez le code-barres manuellement ou scannez",
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
    _hardwareScanFocusNode.requestFocus(); // ✅ hardware scanner keeps working after the dialog closes

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

  // ✅ Captures keystrokes from a physical scanner in "keyboard wedge" mode.
  // Printable characters accumulate in a buffer; Enter (sent by the
  // scanner after each decode) submits the buffer as a scanned barcode
  // through the exact same pipeline as a camera detection.
  KeyEventResult _onHardwareKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;

    if (event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      final scanned = _hardwareScanBuffer.trim();
      _hardwareScanBuffer = '';
      if (scanned.isNotEmpty) {
        _handleHardwareScan(scanned);
      }
      return KeyEventResult.handled;
    }

    final char = event.character;
    if (char != null && char.isNotEmpty) {
      _hardwareScanBuffer += char;
      return KeyEventResult.handled;
    }

    return KeyEventResult.ignored;
  }

  // Same guard/debounce logic as onBarcodeDetected, just fed a plain
  // String instead of a mobile_scanner BarcodeCapture. Instead of
  // processing the barcode silently in the background, it's routed
  // through the manual entry field (see _addManualBarcode) so the scanned
  // value is always visible, then the normal search continues on its own.
  void _handleHardwareScan(String barcode) {
    if (!isScanning || isLookingUp || _isProcessingScan) return;
    if (_scanDebounceTimer?.isActive ?? false) return;
    if (barcode == lastScannedBarcode) return;

    _scanDebounceTimer = Timer(const Duration(milliseconds: 400), () {});
    lastScannedBarcode = barcode;

    _addManualBarcode(prefillValue: barcode);
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
        await CountingService.clearLiveItems(widget.countingSheetId); // ✅ reset shared session for both phones
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
      body: Focus(
        focusNode: _hardwareScanFocusNode,
        autofocus: true,
        onKeyEvent: _onHardwareKeyEvent,
        child: Column(
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