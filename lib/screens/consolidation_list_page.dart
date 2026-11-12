import 'package:flutter/material.dart';
import '../utils/constants.dart';
import '../services/consolidation_service.dart';
import 'consolidation_detail_page.dart';

class ConsolidationListPage extends StatefulWidget {
  final int adjustmentId;

  const ConsolidationListPage({Key? key, required this.adjustmentId}) : super(key: key);

  @override
  State<ConsolidationListPage> createState() => _ConsolidationListPageState();
}

class _ConsolidationListPageState extends State<ConsolidationListPage> {
  List<dynamic> consolidationSheets = [];
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    fetchConsolidationSheets();
  }

  Future<void> fetchConsolidationSheets() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      print("Fetching consolidation sheets for adjustment: ${widget.adjustmentId}");
      final data = await ConsolidationService.getConsolidationSheets(widget.adjustmentId);
      print("Data received: $data");

      // Ensure data is a list
      if (data is List) {
        setState(() {
          consolidationSheets = data;
          isLoading = false;
        });
        print("Loaded ${consolidationSheets.length} consolidation sheets");
      } else {
        print("Data is not a list: ${data.runtimeType}");
        setState(() {
          consolidationSheets = [];
          isLoading = false;
          errorMessage = "Format de données invalide";
        });
      }
    } catch (e) {
      print("Error fetching consolidation sheets: $e");
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }

  String getName(dynamic field) {
    if (field == null) return "";
    if (field is List) return field.length > 1 ? field[1] : field[0].toString();
    if (field is Map && field.containsKey('name')) return field['name'];
    return field.toString();
  }

  int getSheetId(dynamic sheet) {
    if (sheet is Map && sheet.containsKey('id')) {
      return sheet['id'] is int ? sheet['id'] : int.tryParse(sheet['id'].toString()) ?? 0;
    }
    return 0;
  }

  String getSheetState(dynamic sheet) {
    if (sheet is Map && sheet.containsKey('state')) {
      return sheet['state']?.toString() ?? 'new';
    }
    return 'new';
  }

  Color getStatusColor(String? state) {
    switch (state) {
      case 'confirm': return AppColors.successColor;
      case 'progress': return AppColors.warningColor;
      case 'new': return AppColors.primaryColor;
      case 'cancel': return AppColors.errorColor;
      default: return Colors.grey;
    }
  }

  String getStatusText(String? state) {
    switch (state) {
      case 'confirm': return 'Validé';
      case 'progress': return 'En cours';
      case 'new': return 'Nouveau';
      case 'cancel': return 'Annulé';
      default: return state ?? 'Inconnu';
    }
  }

  int getTotalLines(Map<String, dynamic> sheet) {
    final countingLines = sheet['counting_line_ids'] as List? ?? [];
    final contradictoryLines = sheet['counting_contradictory_line_ids'] as List? ?? [];
    return countingLines.length + contradictoryLines.length;
  }

  bool hasContradictoryLines(Map<String, dynamic> sheet) {
    final contradictoryLines = sheet['counting_contradictory_line_ids'] as List? ?? [];
    return contradictoryLines.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundColor,
      appBar: AppBar(
        title: const Text("Consolidations", style: TextStyle(fontSize: 16)),
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
                onPressed: fetchConsolidationSheets,
                child: const Text("Réessayer", style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
      )
          : consolidationSheets.isEmpty
          ? Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: AppColors.primaryColor.withOpacity(0.06),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.merge_type, size: 36, color: AppColors.primaryColor),
              ),
              const SizedBox(height: 14),
              const Text("Aucune consolidation trouvée", style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: AppColors.textColor)),
              const SizedBox(height: 6),
              const Text(
                "Les consolidations sont créées après validation des comptages",
                style: TextStyle(fontSize: 11.5, color: AppColors.textSecondary),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      )
          : Padding(
        padding: const EdgeInsets.all(8.0),
        child: ListView.builder(
          itemCount: consolidationSheets.length,
          itemBuilder: (context, index) {
            final sheet = consolidationSheets[index] as Map<String, dynamic>;
            final sheetId = getSheetId(sheet);
            final sheetName = sheet['name'] ?? "Consolidation ${sheetId}";
            final zoneName = getName(sheet['zone_id']);
            final state = getSheetState(sheet);
            final totalLines = getTotalLines(sheet);
            final hasContradictory = hasContradictoryLines(sheet);
            final isProgress = state == 'progress' || state == 'new';
            final isConfirm = state == 'confirm';

            print("Building card: $sheetName (ID: $sheetId, State: $state)");

            return GestureDetector(
              onTap: () {
                if (sheetId > 0) {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ConsolidationDetailPage(
                        sheetId: sheetId,
                        sheetName: sheetName,
                        zoneName: zoneName,
                      ),
                    ),
                  );
                }
              },
              child: Card(
                margin: const EdgeInsets.only(bottom: 10),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: getStatusColor(state).withOpacity(0.3), width: 1.5),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      // Icon
                      Container(
                        width: 50,
                        height: 50,
                        decoration: BoxDecoration(
                          color: getStatusColor(state).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(25),
                        ),
                        child: Icon(
                          Icons.merge_type,
                          color: getStatusColor(state),
                          size: 28,
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Content
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
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
                            const SizedBox(height: 4),
                            Text(
                              "Zone: $zoneName",
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: getStatusColor(state).withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Text(
                                    getStatusText(state),
                                    style: TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w500,
                                      color: getStatusColor(state),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                if (hasContradictory && isProgress)
                                  const Icon(
                                    Icons.warning_amber,
                                    size: 14,
                                    color: AppColors.warningColor,
                                  ),
                                if (isConfirm)
                                  const Icon(
                                    Icons.check_circle,
                                    size: 14,
                                    color: AppColors.successColor,
                                  ),
                                const SizedBox(width: 4),
                                Text(
                                  "$totalLines lignes",
                                  style: const TextStyle(
                                    fontSize: 10,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Arrow
                      Icon(
                        Icons.chevron_right,
                        color: Colors.grey[400],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}