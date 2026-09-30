import 'package:flutter/material.dart';
import 'consolidation_list_page.dart';
import 'consolidation_zones_page.dart';
import 'adjustment_action_page.dart';
import '../utils/constants.dart';
import '../services/auth_service.dart';

class ChoicePage extends StatelessWidget {
  final int? adjustmentId;
  final dynamic managerId;

  const ChoicePage({super.key, this.adjustmentId, this.managerId});

  // ✅ "Gérer les consolidations" is only meant for whoever is responsible
  // for this adjustment (its manager_id in Odoo — a many2one, so it comes
  // back as [id, display_name] or sometimes just an id/false).
  Future<bool> _isCurrentUserManager(dynamic mgrId) async {
    if (mgrId == null || mgrId == false) return false;
    final session = await AuthService.getFullSession();
    final currentUid = int.tryParse(session?['uid'] ?? '');
    if (currentUid == null) return false;

    final managerUid = mgrId is List ? mgrId[0] : mgrId;
    return managerUid == currentUid;
  }

  @override
  Widget build(BuildContext context) {
    final args = ModalRoute.of(context)?.settings.arguments;
    int? adjId = adjustmentId;
    dynamic mgrId = managerId;
    if (args is Map) {
      adjId = args['id'] as int? ?? adjId;
      mgrId = args['managerId'] ?? mgrId;
    } else if (args is int) {
      adjId = args;
    }

    if (adjId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pop(context);
      });
      return const Scaffold(
        body: Center(child: Text("Error: No adjustment selected")),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.backgroundColor,
      appBar: AppBar(
        title: const Text("Choisir une option"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Image.asset(
              "assets/images/image266622.png",
              height: 35,
              errorBuilder: (context, error, stackTrace) =>
              const Icon(Icons.inventory, color: Colors.white),
            ),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: FutureBuilder<bool>(
          future: _isCurrentUserManager(mgrId),
          builder: (context, snapshot) {
            final isManager = snapshot.data ?? false;
            final stillChecking = snapshot.connectionState == ConnectionState.waiting;

            return Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Counting Sheet Card
                _buildChoiceCard(
                  context: context,
                  title: "Feuille de comptage",
                  subtitle: "Scanner les articles pour le comptage",
                  icon: Icons.qr_code_scanner,
                  color: AppColors.primaryColor,
                  onTap: () {
                    Navigator.pushNamed(
                      context,
                      '/feuilles-list',
                      arguments: adjId,
                    );
                  },
                ),
                const SizedBox(height: 20),

                // Consolidation Management Card — disabled for non-managers
                // so a user can't tap into a screen they'll just get
                // blocked from once inside.
                _buildChoiceCard(
                  context: context,
                  title: "Gestion des consolidations",
                  subtitle: isManager || stillChecking
                      ? "Consolider les zones et appliquer au stock"
                      : "Réservé au responsable de cet ajustement",
                  icon: Icons.merge_type,
                  color: AppColors.secondaryColor,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AdjustmentActionPage(
                          adjustmentId: adjId!,
                          adjustmentName: 'Ajustement $adjId',
                        ),
                      ),
                    );
                  },
                  enabled: stillChecking || isManager,
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildChoiceCard({
    required BuildContext context,
    required String title,
    required String subtitle,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return Card(
      elevation: enabled ? 4 : 1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            color: enabled ? Colors.white : Colors.grey[50],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, size: 32, color: enabled ? color : Colors.grey),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: enabled ? AppColors.textColor : Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: enabled ? AppColors.textSecondary : Colors.grey[400],
                      ),
                    ),
                  ],
                ),
              ),
              if (enabled)
                Icon(Icons.arrow_forward_ios, color: color, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}