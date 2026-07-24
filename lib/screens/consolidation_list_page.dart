import 'package:flutter/material.dart';
import '../services/consolidation_service.dart';
import 'consolidation_detail_page.dart';

class ConsolidationListPage extends StatefulWidget {
  final int adjustmentId;

  const ConsolidationListPage({Key? key, required this.adjustmentId}) : super(key: key);

  @override
  State<ConsolidationListPage> createState() => _ConsolidationListPageState();
}

class _ConsolidationListPageState extends State<ConsolidationListPage> {
  List consolidationSheets = [];
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
      final data = await ConsolidationService.getConsolidationSheets(widget.adjustmentId);
      setState(() {
        consolidationSheets = data;
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
    if (field is List) return field.length > 1 ? field[1] : field[0].toString();
    return field.toString();
  }

  Color getStatusColor(String? state) {
    switch (state) {
      case 'confirm': return Colors.green;
      case 'progress': return Colors.orange;
      case 'new': return Colors.blue;
      case 'cancel': return Colors.red;
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

  int getTotalLines(Map sheet) {
    final countingLines = sheet['counting_line_ids'] as List? ?? [];
    final contradictoryLines = sheet['counting_contradictory_line_ids'] as List? ?? [];
    return countingLines.length + contradictoryLines.length;
  }

  int getVerifiedLines(Map sheet) {
    final contradictoryLines = sheet['counting_contradictory_line_ids'] as List? ?? [];
    int verified = 0;
    for (final line in contradictoryLines) {
      if (line['verified_qty'] != null && line['verified_qty'] > 0) {
        verified++;
      }
    }
    return verified;
  }

  bool hasContradictoryLines(Map sheet) {
    final contradictoryLines = sheet['counting_contradictory_line_ids'] as List? ?? [];
    return contradictoryLines.isNotEmpty;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("Consolidations", style: TextStyle(fontSize: 16)),
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
                onPressed: fetchConsolidationSheets,
                child: const Text("Réessayer", style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
      )
          : consolidationSheets.isEmpty
          ? const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.merge_type, size: 40, color: Colors.grey),
            SizedBox(height: 8),
            Text("Aucune consolidation trouvée", style: TextStyle(fontSize: 12)),
            SizedBox(height: 4),
            Text(
              "Les consolidations sont créées automatiquement",
              style: TextStyle(fontSize: 11, color: Colors.grey),
            ),
          ],
        ),
      )
          : Padding(
        padding: const EdgeInsets.all(8.0),
        child: ListView.builder(
          itemCount: consolidationSheets.length,
          itemBuilder: (context, index) {
            final sheet = consolidationSheets[index];
            final zoneName = getName(sheet['zone_id']);
            final sheetName = sheet['name'] ?? "Consolidation ${sheet['id']}";
            final state = sheet['state'];
            final totalLines = getTotalLines(sheet);
            final verifiedLines = getVerifiedLines(sheet);
            final hasContradictory = hasContradictoryLines(sheet);
            final isProgress = state == 'progress' || state == 'new';
            final isConfirm = state == 'confirm';

            return GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ConsolidationDetailPage(
                      sheetId: sheet['id'],
                      sheetName: sheetName,
                      zoneName: zoneName,
                    ),
                  ),
                );
              },
              child: Card(
                margin: const EdgeInsets.only(bottom: 8),
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: getStatusColor(state).withOpacity(0.3),
                      width: 2,
                    ),
                  ),
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
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.grey[600],
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
                                  Text(
                                    "$verifiedLines/$totalLines vérifiées",
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.orange,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                if (isConfirm)
                                  const Icon(
                                    Icons.check_circle,
                                    size: 14,
                                    color: Colors.green,
                                  ),
                                if (hasContradictory && isProgress)
                                  const Icon(
                                    Icons.warning_amber,
                                    size: 14,
                                    color: Colors.orange,
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