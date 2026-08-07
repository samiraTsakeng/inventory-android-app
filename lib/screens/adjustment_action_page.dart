import 'package:flutter/material.dart';
import '../services/consolidation_service.dart';
import 'consolidation_zones_page.dart';
import 'consolidation_list_page.dart';

class AdjustmentActionPage extends StatefulWidget {
  final int adjustmentId;
  final String adjustmentName;

  const AdjustmentActionPage({
    Key? key,
    required this.adjustmentId,
    required this.adjustmentName,
  }) : super(key: key);

  @override
  State<AdjustmentActionPage> createState() => _AdjustmentActionPageState();
}

class _AdjustmentActionPageState extends State<AdjustmentActionPage> {
  bool isLoading = true;
  bool isApplying = false;
  bool canApplyConsolidation = false;
  bool isConsolidated = false;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    fetchStatus();
  }

  Future<void> fetchStatus() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final status = await ConsolidationService.getAdjustmentStatus(widget.adjustmentId);
      setState(() {
        if (status != null) {
          isConsolidated = status['consolidated'] ?? false;
          canApplyConsolidation = status['display_consolid'] ?? false;
        }
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
    }
  }

  Future<void> applyConsolidation() async {
    final shouldApply = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Appliquer la consolidation", style: TextStyle(fontSize: 18)),
        content: const Text(
          "Voulez-vous appliquer toutes les consolidations à l'ajustement ?\n\n"
              "Cette action va mettre à jour les quantités réelles dans l'ajustement de stock.\n\n"
              "Cette action est irréversible !",
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Annuler", style: TextStyle(fontSize: 14)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: const Text("Appliquer", style: TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );

    if (shouldApply != true) return;

    setState(() => isApplying = true);

    try {
      final success = await ConsolidationService.applyConsolidation(widget.adjustmentId);

      setState(() => isApplying = false);

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Consolidation appliquée avec succès!'),
            backgroundColor: Colors.green,
          ),
        );
        await fetchStatus();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erreur lors de l\'application de la consolidation'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      setState(() => isApplying = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erreur: ${e.toString()}'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(widget.adjustmentName, style: const TextStyle(fontSize: 16)),
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
                onPressed: fetchStatus,
                child: const Text("Réessayer", style: TextStyle(fontSize: 12)),
              ),
            ],
          ),
        ),
      )
          : Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Status card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isConsolidated ? Colors.green[50] : Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isConsolidated ? Colors.green[300]! : Colors.blue[300]!,
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isConsolidated ? Icons.check_circle : Icons.info_outline,
                    color: isConsolidated ? Colors.green : Colors.blue,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      isConsolidated
                          ? "Consolidation déjà appliquée"
                          : canApplyConsolidation
                          ? "Consolidations prêtes à être appliquées"
                          : "En attente de consolidations...",
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: isConsolidated ? Colors.green[700] : Colors.blue[700],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Action buttons
            if (!isConsolidated) ...[
              // Consolidate Zones Button
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ConsolidationZonesPage(
                          adjustmentId: widget.adjustmentId,
                          adjustmentName: widget.adjustmentName,
                        ),
                      ),
                    ).then((_) => fetchStatus());
                  },
                  icon: const Icon(Icons.merge_type, size: 20),
                  label: const Text(
                    'Consolider les zones',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // View Consolidations Button
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ConsolidationListPage(
                          adjustmentId: widget.adjustmentId,
                        ),
                      ),
                    ).then((_) => fetchStatus());
                  },
                  icon: const Icon(Icons.list, size: 20),
                  label: const Text(
                    'Voir les consolidations',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[700],
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // Apply Consolidation Button (only shows when ready)
              if (canApplyConsolidation)
                SizedBox(
                  width: double.infinity,
                  height: 55,
                  child: ElevatedButton.icon(
                    onPressed: isApplying ? null : applyConsolidation,
                    icon: isApplying
                        ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                        : const Icon(Icons.check_circle, size: 20),
                    label: Text(
                      isApplying ? 'Application en cours...' : 'Appliquer la consolidation',
                      style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
            ],

            if (isConsolidated) ...[
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Text(
                    'L\'ajustement a été consolidé avec succès.',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                height: 55,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ConsolidationListPage(
                          adjustmentId: widget.adjustmentId,
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.list, size: 20),
                  label: const Text(
                    'Voir les consolidations',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}