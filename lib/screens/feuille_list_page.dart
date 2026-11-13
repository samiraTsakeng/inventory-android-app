import 'package:flutter/material.dart';
import '../utils/error_messages.dart';
import '../utils/constants.dart';
import '../widgets/app_logo.dart';
import '../widgets/app_card.dart';
import '../services/feuille_service.dart';
import '../services/counting_service.dart';
import '../services/local_storage_service.dart';
import '../services/batch_storage_service.dart';
import '../services/offline_actions_service.dart';
import '../services/offline_prep_service.dart';
import '../services/sync_service.dart';
import 'scanning_page.dart';

class FeuilleListPage extends StatefulWidget {
  final int adjustmentId;

  const FeuilleListPage({super.key, required this.adjustmentId});

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
  bool _sendingAll = false;

  @override
  void initState() {
    super.initState();
    fetchFeuilles();
    SyncService.revision.addListener(fetchFeuilles);
    // Offline copy refreshed: show the sheets it brought.
    OfflinePrepService.revision.addListener(fetchFeuilles);
  }

  @override
  void dispose() {
    SyncService.revision.removeListener(fetchFeuilles);
    OfflinePrepService.revision.removeListener(fetchFeuilles);
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
      } else {
        setState(() {
          feuilles = [];
          isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = friendlyError(e);
        isLoading = false;
      });
    }

    // After sheets are (re)loaded, check local storage for any
    // not-yet-saved scanned items for each one.
    await _loadPendingCounts();
  }

  // Sheet as the phone sees it: started / finished offline until the action
  // is sent to Odoo.
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

  // "Tout envoyer": every sheet with work waiting, one after the other.
  Future<void> _sendAll() async {
    if (!SyncService.online.value) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Hors ligne : touchez le bandeau « Réessayer » une fois le réseau revenu',
          ),
          backgroundColor: AppColors.warningColor,
        ),
      );
      return;
    }
    setState(() => _sendingAll = true);
    await SyncService.flush(); // Shows the per-sheet summary.
    if (mounted) setState(() => _sendingAll = false);
  }

  // Manual send of one sheet: its offline start, its batches, then its
  // offline finish.
  Future<void> _sendSheet(int sheetId) async {
    if (!SyncService.online.value) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Hors ligne : la feuille sera envoyée au retour du réseau',
          ),
          backgroundColor: AppColors.warningColor,
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
        backgroundColor: result.error == null && !result.offline
            ? AppColors.successColor
            : AppColors.warningColor,
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
        unsynced[batch.countingSheetId] =
            (unsynced[batch.countingSheetId] ?? 0) + 1;
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
      case 'progress':
        return AppColors.successColor;
      case 'confirm':
        return AppColors.secondaryColor;
      case 'new':
        return AppColors.warningColor;
      case 'cancel':
        return AppColors.errorColor;
      default:
        return AppColors.textSecondary;
    }
  }

  String getStatusText(String? state) {
    switch (state) {
      case 'progress':
        return 'En cours';
      case 'confirm':
        return 'Validé';
      case 'new':
        return 'Nouveau';
      case 'cancel':
        return 'Annulé';
      default:
        return state ?? 'Inconnu';
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
        content: Text(
          'Hors ligne : comptage commencé, confirmé par Odoo à la synchronisation',
        ),
        backgroundColor: AppColors.warningColor,
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Comptage commencé'),
              backgroundColor: AppColors.successColor,
            ),
          );
        }
        fetchFeuilles();
      } else if (!SyncService.online.value) {
        // The connection dropped during the call.
        await _startOffline(sheetId);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.message ?? 'Erreur lors du démarrage'),
              backgroundColor: AppColors.errorColor,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError(e)),
            backgroundColor: AppColors.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _startingSheetId = null);
    }
  }

  Future<void> _validateCurrentSheet() async {
    final sheetId = getCurrentProgressSheetId();
    final sheetName = getCurrentProgressSheetName();

    if (sheetId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Aucune feuille en cours à terminer'),
          backgroundColor: AppColors.warningColor,
        ),
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
          content: Text(
            'Envoyez d\'abord les $unsynced lot(s) de cette feuille (bouton Envoyer)',
          ),
          backgroundColor: AppColors.warningColor,
        ),
      );
      return;
    }

    final shouldValidate = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text(
            "Terminer le comptage",
            style: TextStyle(fontSize: 18),
          ),
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
                backgroundColor: AppColors.errorColor,
                foregroundColor: Colors.white,
              ),
              child: const Text(
                "Oui, terminer",
                style: TextStyle(fontSize: 14),
              ),
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
          content: Text(
            'Enregistrez d\'abord les $unsaved article(s) scanné(s) dans un lot',
          ),
          backgroundColor: AppColors.warningColor,
        ),
      );
      return;
    }
    await OfflineActionsService.add(OfflineActionsService.validate, sheetId);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Hors ligne : comptage terminé, validé dans Odoo après l\'envoi de ses lots',
        ),
        backgroundColor: AppColors.warningColor,
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Comptage terminé'),
              backgroundColor: AppColors.successColor,
            ),
          );
        }
        fetchFeuilles();
      } else if (!SyncService.online.value) {
        // The connection dropped during the call.
        await _validateOffline(sheetId);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result.message ?? 'Erreur lors de la validation'),
              backgroundColor: AppColors.errorColor,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError(e)),
            backgroundColor: AppColors.errorColor,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _validatingSheetId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundColor,
      appBar: AppBar(
        title: const Text("Feuilles de comptage"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          // "Tout envoyer": shown when sheets have batches or offline
          // starts/finishes waiting. Nothing is ever sent without it.
          if (_unsyncedBatches.isNotEmpty ||
              feuilles.any((f) => f is Map && f['_pending'] != null))
            _sendingAll
                ? const Padding(
                    padding: EdgeInsets.all(14),
                    child: SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    ),
                  )
                : IconButton(
                    tooltip: 'Tout envoyer',
                    icon: const Icon(Icons.cloud_upload, size: 22),
                    onPressed: _sendAll,
                  ),
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
                    Icon(
                      Icons.check_circle,
                      size: 18,
                      color: AppColors.successColor,
                    ),
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
          const AppLogo(),
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
                    const Icon(
                      Icons.error_outline,
                      size: 50,
                      color: AppColors.errorColor,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      errorMessage!,
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppColors.errorColor,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    ElevatedButton(
                      onPressed: () {
                        fetchFeuilles();
                      },
                      child: const Text("Réessayer"),
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
                  Icon(
                    Icons.inventory,
                    size: 40,
                    color: AppColors.textSecondary,
                  ),
                  SizedBox(height: 8),
                  Text(
                    "Aucune feuille de comptage",
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: () async => fetchFeuilles(),
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: feuilles.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
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
                  final unsyncedBatches =
                      _unsyncedBatches[countingSheetId] ?? 0;
                  final hasWorkToSend = waitingSync || unsyncedBatches > 0;
                  final isSending = _sendingSheetId == countingSheetId;
                  final color = getStatusColor(sheetState);

                  return AppCard(
                    accentColor: color,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            AppBadge(
                              text: waitingSync
                                  ? '${getStatusText(sheetState)} · à synchroniser'
                                  : getStatusText(sheetState),
                              color: waitingSync
                                  ? AppColors.warningColor
                                  : color,
                            ),
                            const Spacer(),
                            if (pendingCount > 0)
                              AppBadge(
                                text: '$pendingCount en attente',
                                color: AppColors.warningColor,
                                icon: Icons.hourglass_bottom,
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          sheetName,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: AppColors.textColor,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        _SheetInfo(
                          icon: Icons.location_on_outlined,
                          text: zoneName,
                        ),
                        const SizedBox(height: 2),
                        _SheetInfo(
                          icon: Icons.person_outline,
                          text: getName(f["user_id"]),
                        ),
                        if (unsyncedBatches > 0) ...[
                          const SizedBox(height: 2),
                          _SheetInfo(
                            icon: Icons.inventory_2_outlined,
                            text: '$unsyncedBatches lot(s) à envoyer',
                            color: AppColors.secondaryColor,
                          ),
                        ],
                        const SizedBox(height: 12),
                        if (isNew)
                          SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: _startingSheetId == countingSheetId
                                  ? null
                                  : () => _startSheet(countingSheetId),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.successColor,
                                minimumSize: const Size(0, 44),
                              ),
                              icon: _startingSheetId == countingSheetId
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.play_arrow_rounded,
                                      size: 20,
                                    ),
                              label: const Text('Commencer'),
                            ),
                          ),
                        if (isProgress)
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
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
                                    backgroundColor: AppColors.secondaryColor,
                                    minimumSize: const Size(0, 44),
                                  ),
                                  icon: const Icon(
                                    Icons.qr_code_scanner,
                                    size: 20,
                                  ),
                                  label: const Text('Scanner'),
                                ),
                              ),
                              const SizedBox(width: 10),
                              // Finish this sheet (works offline: done in Odoo
                              // at the sync, after its batches).
                              OutlinedButton(
                                onPressed: _validatingSheetId == countingSheetId
                                    ? null
                                    : () => _confirmAndValidate(
                                        countingSheetId,
                                        sheetName,
                                      ),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: AppColors.errorColor,
                                  side: const BorderSide(
                                    color: AppColors.errorColor,
                                  ),
                                  minimumSize: const Size(0, 44),
                                ),
                                child: const Text('Terminer'),
                              ),
                            ],
                          ),
                        if (isConfirm)
                          Row(
                            children: [
                              Icon(
                                waitingSync
                                    ? Icons.schedule
                                    : Icons.check_circle,
                                size: 18,
                                color: waitingSync
                                    ? AppColors.warningColor
                                    : AppColors.successColor,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                waitingSync
                                    ? 'Terminé · validé à la synchronisation'
                                    : 'Comptage terminé',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: waitingSync
                                      ? AppColors.warningColor
                                      : AppColors.successColor,
                                ),
                              ),
                            ],
                          ),
                        // Manual send of this sheet: start, batches, finish.
                        if (hasWorkToSend) ...[
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: isSending
                                  ? null
                                  : () => _sendSheet(countingSheetId),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 44),
                              ),
                              icon: isSending
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.cloud_upload_outlined,
                                      size: 20,
                                    ),
                              label: Text(
                                isSending ? 'Envoi…' : 'Envoyer à Odoo',
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
    );
  }
}

// One information line of a sheet card (zone, team leader, batches).
class _SheetInfo extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;

  const _SheetInfo({
    required this.icon,
    required this.text,
    this.color = AppColors.textSecondary,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            style: TextStyle(fontSize: 13, color: color),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
