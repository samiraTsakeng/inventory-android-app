import 'package:flutter/material.dart';
import '../services/feuille_service.dart';
import '../services/counting_service.dart';
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

  @override
  void initState() {
    super.initState();
    fetchFeuilles();
  }

  void fetchFeuilles() async {
    try {
      final data = await FeuilleService.getFeuilles(widget.adjustmentId);
      // Sort: progress first, then new, then confirm, then cancel
      data.sort((a, b) {
        const order = {'progress': 0, 'new': 1, 'confirm': 2, 'cancel': 3};
        return (order[a['state']] ?? 4) - (order[b['state']] ?? 4);
      });
      setState(() {
        feuilles = data;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }

  String getName(dynamic field) {
    if (field == null) return "";
    if (field is List) return field[1];
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

  Future<void> _startSheet(int sheetId) async {
    setState(() => _startingSheetId = sheetId);
    try {
      final success = await CountingService.startSheet(sheetId);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Comptage commencé'), backgroundColor: Colors.green),
        );
        fetchFeuilles();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ Erreur lors du démarrage'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: ${e.toString()}'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _startingSheetId = null);
    }
  }

  Future<void> _validateSheet(int sheetId) async {
    setState(() => _validatingSheetId = sheetId);
    try {
      final success = await CountingService.validateSheet(sheetId);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ Comptage validé'), backgroundColor: Colors.green),
        );
        fetchFeuilles();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('❌ Erreur lors de la validation'), backgroundColor: Colors.red),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur: ${e.toString()}'), backgroundColor: Colors.red),
      );
    } finally {
      setState(() => _validatingSheetId = null);
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 40, color: Colors.red),
            const SizedBox(height: 8),
            Text("Error: $errorMessage", style: const TextStyle(fontSize: 11)),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  isLoading = true;
                  errorMessage = null;
                  fetchFeuilles();
                });
              },
              child: const Text("Réessayer", style: TextStyle(fontSize: 11)),
            ),
          ],
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
          : SingleChildScrollView(
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

            bool previousSheetActive = false;
            if (index > 0 && feuilles[index - 1]["state"] != 'confirm') {
              previousSheetActive = true;
            }

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
                  mainAxisSize: MainAxisSize.min, // ← shrink to content
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
                      child: Text(
                        getStatusText(sheetState),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: getStatusColor(sheetState),
                        ),
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
                              fontSize: 14,
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
                                  style: TextStyle(fontSize: 10, color: Colors.grey[600]),
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
                                  style: TextStyle(fontSize: 10, color: Colors.grey[600]),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          // Action buttons
                          if (isNew && !previousSheetActive) ...[
                            const SizedBox(height: 6),
                            SizedBox(
                              width: double.infinity,
                              child: ElevatedButton(
                                onPressed: _startingSheetId == countingSheetId ? null : () => _startSheet(countingSheetId),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.green,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                  textStyle: const TextStyle(fontSize: 11),
                                ),
                                child: _startingSheetId == countingSheetId
                                    ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                    : const Text('Commencer'),
                              ),
                            ),
                          ],
                          if (isProgress) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: () {
                                      Navigator.push(
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
                                const SizedBox(width: 4),
                                Expanded(
                                  child: ElevatedButton(
                                    onPressed: _validatingSheetId == countingSheetId ? null : () => _validateSheet(countingSheetId),
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.orange,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 4),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                                      textStyle: const TextStyle(fontSize: 10),
                                    ),
                                    child: _validatingSheetId == countingSheetId
                                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                                        : const Text('Valider'),
                                  ),
                                ),
                              ],
                            ),
                          ],
                          if (isConfirm) ...[
                            const SizedBox(height: 6),
                            const SizedBox(
                              width: double.infinity,
                              child: Text(
                                '✓ Terminé',
                                textAlign: TextAlign.center,
                                style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold),
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