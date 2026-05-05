import 'package:flutter/material.dart';
import '../services/adjustment_service.dart';
import 'choice_page.dart';

class AdjustmentsListPage extends StatefulWidget {
  const AdjustmentsListPage({Key? key}) : super(key: key);

  @override
  State<AdjustmentsListPage> createState() => _AdjustmentsListPageState();
}

class _AdjustmentsListPageState extends State<AdjustmentsListPage> {
  List adjustments = [];
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    fetchAdjustments();
  }

  void fetchAdjustments() async {
    try {
      final data = await AdjustmentService.getAdjustments();
      setState(() {
        adjustments = data;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }

  String formatDate(String? date) {
    if (date == null) return "";
    try {
      final parsedDate = DateTime.parse(date);
      return "${parsedDate.day}/${parsedDate.month}";
    } catch (e) {
      return date;
    }
  }

  Color getStatusColor(String? state) {
    switch (state) {
      case 'draft': return Colors.orange;
      case 'confirm': return Colors.green;
      case 'done': return Colors.blue;
      case 'cancel': return Colors.red;
      default: return Colors.grey;
    }
  }

  String getStatusText(String? state) {
    switch (state) {
      case 'draft': return 'En cours';
      case 'confirm': return 'Confirmé';
      case 'done': return 'Terminé';
      case 'cancel': return 'Annulé';
      default: return state ?? 'Inconnu';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: const Text("Ajustements", style: TextStyle(fontSize: 16)),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 22),
          onPressed: () => Navigator.pushReplacementNamed(context, '/adjustment-entry'),
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
                  fetchAdjustments();
                });
              },
              child: const Text("Réessayer", style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      )
          : adjustments.isEmpty
          ? const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.inventory, size: 40, color: Colors.grey),
            SizedBox(height: 8),
            Text("Aucun ajustement trouvé", style: TextStyle(fontSize: 12)),
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
            childAspectRatio: 0.8,
          ),
          itemCount: adjustments.length,
          itemBuilder: (context, index) {
            final adj = adjustments[index];
            return GestureDetector(
              onTap: () {
                Navigator.pushNamed(
                  context,
                  '/choice-page',
                  arguments: adj["id"],
                );
              },
              child: Container(
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
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                      decoration: BoxDecoration(
                        color: getStatusColor(adj["state"]).withOpacity(0.15),
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(10),
                          topRight: Radius.circular(10),
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            getStatusText(adj["state"]),
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w500,
                              color: getStatusColor(adj["state"]),
                            ),
                          ),
                          Icon(Icons.chevron_right, size: 14, color: Colors.grey[400]),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  adj["name"] ?? "Sans nom",
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
                                    Icon(Icons.calendar_today, size: 10, color: Colors.grey[500]),
                                    const SizedBox(width: 2),
                                    Text(
                                      formatDate(adj["date"]),
                                      style: TextStyle(fontSize: 9, color: Colors.grey[600]),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blue.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    "Voir",
                                    style: TextStyle(fontSize: 9, color: Colors.blue),
                                  ),
                                  SizedBox(width: 2),
                                  Icon(Icons.arrow_forward, size: 8, color: Colors.blue),
                                ],
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
          },
        ),
      ),
    );
  }
}