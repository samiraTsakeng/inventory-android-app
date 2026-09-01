import 'package:flutter/material.dart';
import '../utils/constants.dart';
import '../services/feuille_service.dart';
import '../services/counting_service.dart';
import '../services/local_storage_service.dart';
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

  @override
  void initState() {
    super.initState();
    fetchFeuilles();
  }

  void fetchFeuilles() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final data = await FeuilleService.getFeuilles(widget.adjustmentId);

      if (data is List && data.isNotEmpty) {
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
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }

    // After sheets are (re)loaded, check local storage for any
    // not-yet-saved scanned items for each one.
    await _loadPendingCounts();
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
    if (mounted) {
      setState(() {
        _pendingCounts = counts;
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
      case 'progress': return AppColors.successColor;
      case 'confirm': return AppColors.primaryColor;
      case 'new': return AppColors.warningColor;
      case 'cancel': return AppColors.errorColor;
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

  Future<void> _startSheet(int sheetId) async {
    setState(() => _startingSheetId = sheetId);
    try {
      final success = await CountingService.startSheet(sheetId);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Comptage commencé'), backgroundColor: AppColors.successColor),
        );
        fetchFeuilles();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors du démarrage'), backgroundColor: AppColors.errorColor),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: ${e.toString()}'), backgroundColor: AppColors.errorColor),
      );
    } finally {
      setState(() => _startingSheetId = null);
    }
  }

  Future<void> _validateCurrentSheet() async {
    final sheetId = getCurrentProgressSheetId();
    final sheetName = getCurrentProgressSheetName();

    if (sheetId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Aucune feuille en cours à terminer'), backgroundColor: AppColors.warningColor),
      );
      return;
    }

    final shouldValidate = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Row(
            children: [
              Icon(Icons.check_circle_outline, color: AppColors.primaryColor, size: 20),
              SizedBox(width: 8),
              Text("Terminer le comptage", style: TextStyle(fontSize: 18)),
            ],
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

  Future<void> _validateSheet(int sheetId) async {
    setState(() => _validatingSheetId = sheetId);
    try {
      final success = await CountingService.validateSheet(sheetId);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Comptage terminé'), backgroundColor: AppColors.successColor),
        );
        fetchFeuilles();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de la validation'), backgroundColor: AppColors.errorColor),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: ${e.toString()}'), backgroundColor: AppColors.errorColor),
      );
    } finally {
      setState(() => _validatingSheetId = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundColor,
      appBar: AppBar(
        title: const Text("Feuilles", style: TextStyle(fontSize: 15)),
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
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            itemBuilder: (context) => [
              const PopupMenuItem<String>(
                value: 'terminer',
                child: Row(
                  children: [
                    Icon(Icons.check_circle, size: 18, color: AppColors.successColor),
                    SizedBox(width: 8),
                    Text('Terminer le comptage en cours'),
                  ],
                ),
              ),
            ],
            child: const Padding(
              padding: EdgeInsets.all(8.0),
              child: Icon(Icons.more_vert, size: 22, color: Colors.white),
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
              const Icon(Icons.error_outline, size: 50, color: AppColors.errorColor),
              const SizedBox(height: 16),
              Text(
                errorMessage!,
                style: const TextStyle(fontSize: 13, color: AppColors.errorColor),
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
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: AppColors.primaryColor.withOpacity(0.06),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.description_outlined, size: 36, color: AppColors.primaryColor),
            ),
            const SizedBox(height: 12),
            const Text("Aucune feuille trouvée", style: TextStyle(fontSize: 12.5, color: AppColors.textSecondary)),
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


            // Teams can start counting at the same time - that's the whole point of having 2 teams!

            final cardWidth = (MediaQuery.of(context).size.width - 18) / 2;

            return SizedBox(
              width: cardWidth,
              child: Container(
                decoration: BoxDecoration(
                  color: AppColors.surfaceColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.borderColor),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primaryColor.withOpacity(0.05),
                      spreadRadius: 1,
                      blurRadius: 4,
                      offset: const Offset(0, 2),
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
                            getStatusText(sheetState),
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
                                color: AppColors.warningColor,
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
                          const SizedBox(height: 6),

                          if (isNew)
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _startingSheetId == countingSheetId ? null : () => _startSheet(countingSheetId),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: AppColors.successColor,
                                  foregroundColor: Colors.white,
                                  minimumSize: Size.zero,
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
                                  backgroundColor: AppColors.primaryColor,
                                  foregroundColor: Colors.white,
                                  minimumSize: Size.zero,
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                  textStyle: const TextStyle(fontSize: 9),
                                ),
                                child: const Text('Scanner'),
                              ),
                            ),
                          if (isConfirm)
                            const SizedBox(
                              width: double.infinity,
                              child: Text(
                                '✓ Terminé',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 10, color: AppColors.successColor, fontWeight: FontWeight.bold),
                              ),
                            ),
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