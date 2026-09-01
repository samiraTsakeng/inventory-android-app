import 'package:flutter/material.dart';
import '../utils/constants.dart';
import '../services/consolidation_service.dart';

class ConsolidationZonesPage extends StatefulWidget {
  final int adjustmentId;
  final String adjustmentName;

  const ConsolidationZonesPage({
    Key? key,
    required this.adjustmentId,
    required this.adjustmentName,
  }) : super(key: key);

  @override
  State<ConsolidationZonesPage> createState() => _ConsolidationZonesPageState();
}

class _ConsolidationZonesPageState extends State<ConsolidationZonesPage> {
  List<dynamic> zones = [];
  bool isLoading = true;
  bool isProcessing = false;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    fetchZones();
  }

  Future<void> fetchZones() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final data = await ConsolidationService.getConsolidationZones(widget.adjustmentId);
      setState(() {
        zones = data;
        isLoading = false;
      });
      print("Loaded ${zones.length} zones ready for consolidation");
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }

  Future<void> consolidateZone(int zoneId, String zoneName) async {
    final shouldConsolidate = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.merge_type, color: AppColors.primaryColor, size: 20),
            SizedBox(width: 8),
            Text("Consolider la zone", style: TextStyle(fontSize: 18)),
          ],
        ),
        content: Text(
          "Voulez-vous consolider la zone \"$zoneName\" ?\n\nLes deux feuilles de comptage seront comparées et une feuille de consolidation sera créée.",
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
            child: const Text("Consolider", style: TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );

    if (shouldConsolidate != true) return;

    setState(() => isProcessing = true);

    try {
      final sheetId = await ConsolidationService.createConsolidationSheet(
        adjustmentId: widget.adjustmentId,
        zoneId: zoneId,
      );

      setState(() => isProcessing = false);

      if (sheetId != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Consolidation créée avec succès!'),
            backgroundColor: AppColors.successColor,
          ),
        );
        await fetchZones();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erreur lors de la création de la consolidation'),
            backgroundColor: AppColors.errorColor,
          ),
        );
      }
    } catch (e) {
      setState(() => isProcessing = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur: ${e.toString()}'),
          backgroundColor: AppColors.errorColor,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundColor,
      appBar: AppBar(
        title: const Text("Zones à consolider", style: TextStyle(fontSize: 16)),
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
                onPressed: fetchZones,
                child: const Text("Réessayer", style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
      )
          : zones.isEmpty
          ? Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.successColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle, size: 44, color: AppColors.successColor),
            ),
            const SizedBox(height: 18),
            const Text(
              "Toutes les zones sont consolidées !",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.textColor),
            ),
            const SizedBox(height: 8),
            const Text(
              "Retournez pour appliquer la consolidation",
              style: TextStyle(fontSize: 13, color: AppColors.textSecondary),
            ),
          ],
        ),
      )
          : Padding(
        padding: const EdgeInsets.all(12.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.primaryColor.withOpacity(0.06),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: AppColors.primaryColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${zones.length} zone(s) prête(s) à être consolidée(s)',
                      style: TextStyle(
                        fontSize: 13,
                        color: AppColors.primaryColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: ListView.builder(
                itemCount: zones.length,
                itemBuilder: (context, index) {
                  final zone = zones[index];
                  final zoneName = zone['name'] ?? 'Zone ${zone['id']}';
                  final sheetCount = zone['sheets']?.length ?? 0;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Row(
                        children: [
                          Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: AppColors.primaryColor.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(25),
                            ),
                            child: const Icon(
                              Icons.merge_type,
                              color: AppColors.primaryColor,
                              size: 28,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  zoneName,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  '$sheetCount feuilles de comptage prêtes',
                                  style: const TextStyle(
                                    fontSize: 12,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          ElevatedButton(
                            onPressed: isProcessing
                                ? null
                                : () => consolidateZone(zone['id'], zoneName),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.successColor,
                              foregroundColor: Colors.white,
                              minimumSize: Size.zero,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                            child: isProcessing
                                ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                                : const Text(
                              'Consolider',
                              style: TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}