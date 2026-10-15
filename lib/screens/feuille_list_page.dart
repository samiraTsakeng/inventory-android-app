import 'package:flutter/material.dart';
import '../services/feuille_service.dart';
import '../services/counting_service.dart';
import '../services/local_storage_service.dart';
import '../services/batch_storage_service.dart';
import '../services/offline_actions_service.dart';
import '../services/sheet_cache_service.dart';
import '../services/sync_service.dart';
import 'scanning_page.dart';

class FeuilleListPage extends StatefulWidget {
  final int adjustmentId;

  const FeuilleListPage({Key? key, required this.adjustmentId}) : super(key: key);

  @override
  State<FeuilleListPage> createState() => _FeuilleListPageState();
}

class _FeuilleListPageState extends State<FeuilleListPage> {
  List feuilles = [];
  bool isLoading = true;
  String? errorMessage;
  int? _startingSheetId;
  int? _validatingSheetId;


  // saved into a batch / sent to the ERP for that sheet.
  Map<int, int> _pendingCounts = {};
  // Saved batches not sent to the ERP yet, per sheet.
  Map<int, int> _unsyncedBatches = {};
  int? _sendingSheetId;

  @override
  void initState() {
    super.initState();
    fetchFeuilles();
    SyncService.revision.addListener(fetchFeuilles);
  }

  @override
  void dispose() {
    SyncService.revision.removeListener(fetchFeuilles);
    super.dispose();
  }

  void fetchFeuilles() async {
    if (!mounted) return;
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final serverData = await FeuilleService.getFeuilles(widget.adjustmentId);
      // Sheets started / finished offline show their new state until the
      // action is replayed in Odoo.
      final pending = await OfflineActionsService.pendingBySheet();
      final data = [
        for (final f in serverData) _withLocalState(f, pending[f['id']]),
      ];
      if (!mounted) return;

      if (data.isNotEmpty) {
        // Sort: progress first, then new, then confirm, then cancel
        data.sort((a, b) {
          const order = {'progress': 0, 'new': 1, 'confirm': 2, 'cancel': 3};
          final orderA = order[a['state']] ?? 4;
          final orderB = order[b['state']] ?? 4;
          return orderA - orderB;
        });
        setState(() {
          feuilles = data;
          isLoading = false;
        });
        _downloadForOffline();
      } else {
        setState(() {
          feuilles = [];
          isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }

    // After sheets are (re)loaded, check local storage for any
    // not-yet-saved scanned items for each one.
    await _loadPendingCounts();
  }

  // Keeps the adjustment's numbers and sheets on the phone, so counting can
  // go on without network. Runs in the background, best effort.
  dynamic _withLocalState(dynamic sheet, String? action) {
    if (action == null || sheet is! Map) return sheet;
    final copy = Map<String, dynamic>.from(sheet);
    copy['_pending'] = action;
    if (action == OfflineActionsService.validate) {
      copy['state'] = 'confirm';
    } else if (copy['state'] == 'new') {
      copy['state'] = 'progress';
    }
    return copy;
  }

  // Skipped when the copy is recent ("Préparer le hors ligne" forces it).
  Future<void> _downloadForOffline() async {
    if (!SyncService.online.value) return;
    final info = await SheetCacheService.info(widget.adjustmentId);
    final updatedAt = info.updatedAt;
    if (updatedAt != null &&
        DateTime.now().difference(updatedAt) < const Duration(minutes: 10)) {
      return;
    }
    await SheetCacheService.prepareAdjustment(widget.adjustmentId);
  }

  // Manual send of one sheet: its offline start, its batches, then its
  // offline finish — the same as the automatic sync, for this sheet only.
  Future<void> _sendSheet(int sheetId) async {
    if (!SyncService.online.value) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Hors ligne : la feuille sera envoyée au retour du réseau'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    setState(() => _sendingSheetId = sheetId);
    final result = await SyncService.syncSheet(sheetId);
    if (!mounted) return;
    setState(() => _sendingSheetId = null);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result.describe()),
        backgroundColor: result.error == null && !result.offline ? Colors.green : Colors.orange,
        duration: const Duration(seconds: 6),
      ),
    );
    // The sheet list reloads through SyncService.revision.
  }

  Future<void> _loadPendingCounts() async {
    final Map<int, int> counts = {};
    for (final f in feuilles) {
      final id = f['id'];
      if (id == null) continue;
      try {
        final items = await LocalStorageService.loadScannedItems(id);
        if (items.isNotEmpty) {
          counts[id] = items.length;
        }
      } catch (e) {
        // Ignore lookup errors for a single sheet, don't block the rest.
      }
    }

    final Map<int, int> unsynced = {};
    try {
      for (final batch in await BatchStorageService.getBatches()) {
        if (batch.isSynced) continue;
        unsynced[batch.countingSheetId] = (unsynced[batch.countingSheetId] ?? 0) + 1;
      }
    } catch (e) {
      // Counts only; the list works without them.
    }

    if (mounted) {
      setState(() {
        _pendingCounts = counts;
        _unsyncedBatches = unsynced;
      });
    }
  }

  String getName(dynamic field) {
    if (field == null) return "";
    if (field is List) return field.length > 1 ? field[1] : field[0].toString();
    return field.toString();
  }

  Color getStatusColor(String? state) {
    switch (state) {
      case 'progress': return Colors.green;
      case 'confirm': return Colors.blue;
      case 'new': return Colors.orange;
      case 'cancel': return Colors.red;
      default: return Colors.grey;
    }
  }

  String getStatusText(String? state) {
    switch (state) {
      case 'progress': return 'En cours';
      case 'confirm': return 'Validé';
      case 'new': return 'Nouveau';
      case 'cancel': return 'Annulé';
      default: return state ?? 'Inconnu';
    }
  }

  // Find the current sheet in progress
  int? getCurrentProgressSheetId() {
    final progressSheet = feuilles.firstWhere(
          (sheet) => sheet['state'] == 'progress',
      orElse: () => null,
    );
    return progressSheet?['id'];
  }

  // Get current sheet name
  String? getCurrentProgressSheetName() {
    final progressSheet = feuilles.firstWhere(
          (sheet) => sheet['state'] == 'progress',
      orElse: () => null,
    );
    return progressSheet?['name'] ?? 'Feuille en cours';
  }

  // Offline: the start is kept and done in Odoo when the connection comes
  // back; the sheet can be scanned right away.
  Future<void> _startOffline(int sheetId) async {
    await OfflineActionsService.add(OfflineActionsService.start, sheetId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Hors ligne : comptage commencé, confirmé par Odoo à la synchronisation'),
        backgroundColor: Colors.orange,
      ),
    );
    fetchFeuilles();
  }

  Future<void> _startSheet(int sheetId) async {
    if (!SyncService.online.value) {
      await _startOffline(sheetId);
      return;
    }
    setState(() => _startingSheetId = sheetId);
    try {
      final result = await CountingService.startSheet(sheetId);
      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Comptage commencé'), backgroundColor: Colors.green),
        );
        fetchFeuilles();
      } else if (!SyncService.online.value) {
        // The connection dropped during the call.
        await _startOffline(sheetId);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message ?? 'Erreur lors du démarrage'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: ${e.toString()}'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _startingSheetId = null);
    }
  }

  Future<void> _validateCurrentSheet() async {
    final sheetId = getCurrentProgressSheetId();
    final sheetName = getCurrentProgressSheetName();

    if (sheetId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucune feuille en cours à terminer'), backgroundColor: Colors.orange),
      );
      return;
    }

    await _confirmAndValidate(sheetId, sheetName);
  }

  // "Terminer" of one sheet (menu or the sheet's own button).
  Future<void> _confirmAndValidate(int sheetId, String? sheetName) async {
    // Online, Odoo would validate the sheet without the batches still on
    // the phone. (Offline the finish already waits for them.)
    final unsynced = _unsyncedBatches[sheetId] ?? 0;
    if (unsynced > 0 && SyncService.online.value) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Envoyez d\'abord les $unsynced lot(s) de cette feuille (bouton Envoyer)'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final shouldValidate = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text("Terminer le comptage", style: TextStyle(fontSize: 18)),
          content: Text(
            "Voulez-vous terminer le comptage \"$sheetName\" ?\n\nCette action est irréversible.",
            style: const TextStyle(fontSize: 14),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text("Non", style: TextStyle(fontSize: 14)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
              child: const Text("Oui, terminer", style: TextStyle(fontSize: 14)),
            ),
          ],
        );
      },
    );

    if (shouldValidate == true) {
      await _validateSheet(sheetId);
    }
  }

  // Offline: the sheet is finished in Odoo once the connection is back and
  // all its batches were sent. Scans not saved into a batch would never be
  // sent, so they must be saved first.
  Future<void> _validateOffline(int sheetId) async {
    final unsaved = _pendingCounts[sheetId] ?? 0;
    if (unsaved > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Enregistrez d\'abord les $unsaved article(s) scanné(s) dans un lot'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }
    await OfflineActionsService.add(OfflineActionsService.validate, sheetId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Hors ligne : comptage terminé, validé dans Odoo après l\'envoi de ses lots'),
        backgroundColor: Colors.orange,
      ),
    );
    fetchFeuilles();
  }

  Future<void> _validateSheet(int sheetId) async {
    if (!SyncService.online.value) {
      await _validateOffline(sheetId);
      return;
    }
    setState(() => _validatingSheetId = sheetId);
    try {
      final result = await CountingService.validateSheet(sheetId);
      if (result.success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Comptage terminé'), backgroundColor: Colors.green),
        );
        fetchFeuilles();
      } else if (!SyncService.online.value) {
        // The connection dropped during the call.
        await _validateOffline(sheetId);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result.message ?? 'Erreur lors de la validation'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: ${e.toString()}'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _validatingSheetId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("Feuilles", style: TextStyle(fontSize: 15)),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          // Menu button with Terminer option
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'terminer') {
                _validateCurrentSheet();
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem<String>(
                value: 'terminer',
                child: Row(
                  children: [
                    Icon(Icons.check_circle, size: 18, color: Colors.green),
                    SizedBox(width: 8),
                    Text('Terminer le comptage en cours'),
                  ],
                ),
              ),
            ],
            child: const Padding(
              padding: EdgeInsets.all(8.0),
              child: Icon(Icons.more_vert, size: 22),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Image.asset(
              "assets/images/image266622.png",
              height: 25,
              errorBuilder: (context, error, stackTrace) =>
              const Icon(Icons.inventory, color: Colors.white, size: 20),
            ),
          ),
        ],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
          ? Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 50, color: Colors.red),
              const SizedBox(height: 16),
              Text(
                errorMessage!,
                style: const TextStyle(fontSize: 13, color: Colors.red),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: () {
                  fetchFeuilles();
                },
                child: const Text("Réessayer", style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
      )
          : feuilles.isEmpty
          ? const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory, size: 40, color: Colors.grey),
            SizedBox(height: 8),
            Text("Aucune feuille trouvée", style: TextStyle(fontSize: 12)),
          ],
        ),
      )
          : Padding(
        padding: const EdgeInsets.all(6.0),
        child: Wrap(
          spacing: 6,
          runSpacing: 6,
          children: List.generate(feuilles.length, (index) {
            final f = feuilles[index];
            final zoneName = getName(f["zone_id"]);
            final sheetName = f["name"] ?? "Feuille ${f["id"]}";
            final countingSheetId = f["id"];
            final sheetState = f["state"];
            final isProgress = sheetState == 'progress';
            final isNew = sheetState == 'new';
            final isConfirm = sheetState == 'confirm';
            final pendingCount = _pendingCounts[countingSheetId] ?? 0;
            // Started / finished offline, not confirmed by Odoo yet.
            final waitingSync = f is Map && f['_pending'] != null;
            final unsyncedBatches = _unsyncedBatches[countingSheetId] ?? 0;
            final hasWorkToSend = waitingSync || unsyncedBatches > 0;
            final isSending = _sendingSheetId == countingSheetId;


            // Teams can start counting at the same time - that's the whole point of having 2 teams!

            final cardWidth = (MediaQuery.of(context).size.width - 18) / 2;

            return SizedBox(
              width: cardWidth,
              child: Container(
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.1),
                      spreadRadius: 1,
                      blurRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Status bar
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                      decoration: BoxDecoration(
                        color: getStatusColor(sheetState).withOpacity(0.15),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(8),
                          topRight: Radius.circular(8),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            waitingSync
                                ? '${getStatusText(sheetState)} · à synchroniser'
                                : getStatusText(sheetState),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: getStatusColor(sheetState),
                            ),
                          ),

                          if (pendingCount > 0)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.orange,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.hourglass_bottom, size: 8, color: Colors.white),
                                  const SizedBox(width: 2),
                                  Text(
                                    '$pendingCount en attente',
                                    style: const TextStyle(
                                      fontSize: 8,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.white,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    // Content
                    Padding(
                      padding: const EdgeInsets.all(6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            sheetName,
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              Icon(Icons.location_on, size: 9, color: Colors.grey[500]),
                              const SizedBox(width: 2),
                              Expanded(
                                child: Text(
                                  zoneName,
                                  style: TextStyle(fontSize: 9, color: Colors.grey[600]),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              Icon(Icons.person, size: 9, color: Colors.grey[500]),
                              const SizedBox(width: 2),
                              Expanded(
                                child: Text(
                                  getName(f["user_id"]),
                                  style: TextStyle(fontSize: 9, color: Colors.grey[600]),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          if (unsyncedBatches > 0) ...[
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Icon(Icons.inventory_2, size: 9, color: Colors.blue[600]),
                                const SizedBox(width: 2),
                                Text(
                                  '$unsyncedBatches lot(s) à envoyer',
                                  style: TextStyle(fontSize: 9, color: Colors.blue[700], fontWeight: FontWeight.w600),
                                ),
                              ],
                            ),
                          ],
                          const SizedBox(height: 6),

                          if (isNew)
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _startingSheetId == countingSheetId ? null : () => _startSheet(countingSheetId),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                  textStyle: const TextStyle(fontSize: 10),
                                ),
                                child: _startingSheetId == countingSheetId
                                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : const Text('Commencer'),
                              ),
                            ),
                          if (isProgress)
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: () async {
                                  await Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => ScanningPage(
                                        countingSheetId: countingSheetId,
                                        adjustmentId: widget.adjustmentId,
                                        zoneName: zoneName,
                                        sheetName: sheetName,
                                      ),
                                    ),
                                  );


                                  _loadPendingCounts();
                                },
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.blue,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                  textStyle: const TextStyle(fontSize: 9),
                                ),
                                child: const Text('Scanner'),
                              ),
                            ),
                          // Finish this sheet (works offline: done in Odoo
                          // at the sync, after its batches).
                          if (isProgress)
                            SizedBox(
                              width: double.infinity,
                              height: 24,
                              child: TextButton(
                                onPressed: _validatingSheetId == countingSheetId
                                    ? null
                                    : () => _confirmAndValidate(countingSheetId, sheetName),
                                style: TextButton.styleFrom(
                                  foregroundColor: Colors.red[700],
                                  padding: EdgeInsets.zero,
                                  textStyle: const TextStyle(fontSize: 9, fontWeight: FontWeight.w600),
                                ),
                                child: const Text('Terminer'),
                              ),
                            ),
                          if (isConfirm)
                            SizedBox(
                              width: double.infinity,
                              child: Text(
                                waitingSync ? '⏳ Terminé · validé à la synchro' : '✓ Terminé',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 10,
                                  color: waitingSync ? Colors.orange : Colors.green,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          // Manual send of this sheet: start, batches, finish.
                          if (hasWorkToSend) ...[
                            const SizedBox(height: 4),
                            SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: isSending ? null : () => _sendSheet(countingSheetId),
                                icon: isSending
                                    ? const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5))
                                    : const Icon(Icons.cloud_upload, size: 12),
                                label: Text(isSending ? 'Envoi…' : 'Envoyer'),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(0, 26),
                                  padding: const EdgeInsets.symmetric(vertical: 2),
                                  textStyle: const TextStyle(fontSize: 9),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}