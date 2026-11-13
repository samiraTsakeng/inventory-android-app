import 'package:flutter/material.dart';
import '../utils/error_messages.dart';
import '../services/adjustment_service.dart';
import '../services/offline_prep_service.dart';
import '../utils/constants.dart';
import '../widgets/app_logo.dart';
import '../widgets/app_card.dart';

class AdjustmentsListPage extends StatefulWidget {
  const AdjustmentsListPage({super.key});

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
      if (!mounted) return;
      setState(() {
        adjustments = data;
        isLoading = false;
      });
      // A new adjustment (created since login) is copied to the phone at
      // once, so its counting also works offline.
      OfflinePrepService.ensurePrepared(data);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        errorMessage = friendlyError(e);
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
      case 'draft':
        return AppColors.warningColor;
      case 'confirm':
        return AppColors.successColor;
      case 'done':
        return AppColors.primaryColor;
      case 'cancel':
        return AppColors.errorColor;
      default:
        return AppColors.textSecondary;
    }
  }

  String getStatusText(String? state) {
    switch (state) {
      case 'draft':
        return 'En cours';
      case 'confirm':
        return 'Confirmé';
      case 'done':
        return 'Terminé';
      case 'cancel':
        return 'Annulé';
      default:
        return state ?? 'Inconnu';
    }
  }

  // ✅ Shows the full adjustment info (untruncated name, status, date) in a
  // popup before navigating, since the card itself is too small to show
  // long adjustment names in full.
  void _showAdjustmentDetails(dynamic adj) {
    final name = adj["name"] ?? "Sans nom";
    final state = adj["state"];

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.inventory_2, color: getStatusColor(state), size: 20),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                "Détails de l'ajustement",
                style: TextStyle(fontSize: 16),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: getStatusColor(state).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    getStatusText(state),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: getStatusColor(state),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.calendar_today,
                  size: 12,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  formatDate(adj["date"]),
                  style: TextStyle(
                    fontSize: 13,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Fermer"),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context); // close the popup
              Navigator.pushNamed(
                context,
                '/choice-page',
                arguments: adj["id"],
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryColor,
              foregroundColor: Colors.white,
            ),
            child: const Text("Continuer"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundColor,
      appBar: AppBar(
        title: const Text("Ajustements"),
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 22),
          onPressed: () =>
              Navigator.pushReplacementNamed(context, '/adjustment-entry'),
        ),
        actions: [const AppLogo()],
      ),
      body: isLoading
          ? const Center(child: CircularProgressIndicator())
          : errorMessage != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.error_outline,
                    size: 40,
                    color: AppColors.errorColor,
                  ),
                  const SizedBox(height: 8),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Text(
                      errorMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                  const SizedBox(height: 8),
                  ElevatedButton(
                    onPressed: () {
                      setState(() {
                        isLoading = true;
                        errorMessage = null;
                        fetchAdjustments();
                      });
                    },
                    child: const Text("Réessayer"),
                  ),
                ],
              ),
            )
          : adjustments.isEmpty
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
                    "Aucun ajustement en cours",
                    style: TextStyle(
                      fontSize: 14,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            )
          : RefreshIndicator(
              onRefresh: () async => fetchAdjustments(),
              child: GridView.builder(
                padding: const EdgeInsets.all(16),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  mainAxisExtent: 128,
                ),
                itemCount: adjustments.length,
                itemBuilder: (context, index) {
                  final adj = adjustments[index];
                  final color = getStatusColor(adj["state"]);
                  return AppCard(
                    onTap: () => _showAdjustmentDetails(adj),
                    accentColor: color,
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            AppBadge(
                              text: getStatusText(adj["state"]),
                              color: color,
                            ),
                            const Spacer(),
                            const Icon(
                              Icons.chevron_right,
                              size: 18,
                              color: AppColors.textSecondary,
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Expanded(
                          child: Text(
                            adj["name"] ?? "Sans nom",
                            style: const TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textColor,
                              height: 1.25,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Row(
                          children: [
                            const Icon(
                              Icons.calendar_today_outlined,
                              size: 13,
                              color: AppColors.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              formatDate(adj["date"]),
                              style: const TextStyle(
                                fontSize: 12,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
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
