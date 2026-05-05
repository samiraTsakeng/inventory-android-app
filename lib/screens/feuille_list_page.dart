import 'package:flutter/material.dart';
import '../services/feuille_service.dart';
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

  @override
  void initState() {
    super.initState();
    fetchFeuilles();
  }

  void fetchFeuilles() async {
    try {
      final data = await FeuilleService.getFeuilles(widget.adjustmentId);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("Feuilles", style: TextStyle(fontSize: 16)),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 22),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Image.asset(
              "assets/images/image266622.png",
              height: 28,
              errorBuilder: (context, error, stackTrace) =>
              const Icon(Icons.inventory, color: Colors.white, size: 22),
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
            Text("Error: $errorMessage", style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  isLoading = true;
                  errorMessage = null;
                  fetchFeuilles();
                });
              },
              child: const Text("Réessayer", style: TextStyle(fontSize: 12)),
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
          : Padding(
        padding: const EdgeInsets.all(6.0),
        child: GridView.builder(
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 6,
            mainAxisSpacing: 6,
            childAspectRatio: 0.75,
          ),
          itemCount: feuilles.length,
          itemBuilder: (context, index) {
            final f = feuilles[index];
            final zoneName = getName(f["zone_id"]);

            return Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
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
                children: [
                  // Status bar with scan icon on EVERY card
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: getStatusColor(f["state"]).withOpacity(0.15),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(10),
                        topRight: Radius.circular(10),
                      ),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          getStatusText(f["state"]),
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w500,
                            color: getStatusColor(f["state"]),
                          ),
                        ),
                        // Scan icon on EVERY feuille
                        GestureDetector(
                          onTap: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => ScanningPage(
                                  countingSheetId: f["id"],
                                  adjustmentId: widget.adjustmentId,
                                  zoneName: zoneName,
                                  sheetName: f["name"] ?? "Feuille ${f["id"]}",
                                ),
                              ),
                            );
                          },
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: Colors.blue,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Icon(
                              Icons.qr_code_scanner,
                              size: 12,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Content - smaller
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                f["name"] ?? "Feuille",
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  Icon(Icons.location_on, size: 10, color: Colors.grey[500]),
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
                                  Icon(Icons.person, size: 10, color: Colors.grey[500]),
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
                            ],
                          ),
                          if (f["state"] == 'progress')
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.green.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.play_arrow, size: 8, color: Colors.green),
                                  SizedBox(width: 2),
                                  Text(
                                    "Démarrer",
                                    style: TextStyle(fontSize: 8, color: Colors.green),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}