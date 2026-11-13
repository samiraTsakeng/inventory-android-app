import 'package:flutter/material.dart';
import '../utils/constants.dart';
import '../widgets/app_logo.dart';
import '../widgets/app_card.dart';
import '../services/offline_prep_service.dart';
import '../services/user_rights.dart';
import 'adjustment_action_page.dart';

class ChoicePage extends StatelessWidget {
  final int? adjustmentId;

  const ChoicePage({super.key, this.adjustmentId});

  @override
  Widget build(BuildContext context) {
    final adjId =
        ModalRoute.of(context)?.settings.arguments as int? ?? adjustmentId;

    if (adjId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pop(context);
      });
      return const Scaffold(
        body: Center(child: Text("Aucun ajustement sélectionné")),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Choisir une option"),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [const AppLogo()],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Counting Sheet Card
            _buildChoiceCard(
              context: context,
              title: "Feuille de comptage",
              subtitle: "Scanner les articles pour le comptage",
              icon: Icons.qr_code_scanner,
              color: AppColors.secondaryColor,
              onTap: () {
                Navigator.pushNamed(
                  context,
                  '/feuilles-list',
                  arguments: adjId,
                );
              },
            ),
            const SizedBox(height: 14),
            // Copies the adjustment to the phone if it isn't yet.
            _AutoPrepare(adjustmentId: adjId),

            // Consolidations: only for the Odoo group that sees them
            // (Resp. Ajustement), as in Odoo; hidden while unknown.
            ValueListenableBuilder<bool?>(
              valueListenable: UserRights.consolidation,
              builder: (context, allowed, _) {
                if (allowed != true) return const SizedBox.shrink();
                return _buildChoiceCard(
                  context: context,
                  title: "Gestion des consolidations",
                  subtitle: "Consolider les zones et appliquer au stock",
                  icon: Icons.merge_type,
                  color: AppColors.primaryLight,
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => AdjustmentActionPage(
                          adjustmentId: adjId,
                          adjustmentName: 'Ajustement $adjId',
                        ),
                      ),
                    );
                  },
                  enabled: true,
                );
              },
            ),
          ],
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
    return AppCard(
      onTap: enabled ? onTap : null,
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          _IconTile(
            icon: icon,
            color: enabled ? color : AppColors.textSecondary,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _titleStyle),
                const SizedBox(height: 4),
                Text(subtitle, style: _subtitleStyle),
              ],
            ),
          ),
          Icon(
            Icons.chevron_right,
            color: enabled ? color : AppColors.textSecondary,
          ),
        ],
      ),
    );
  }
}

const _titleStyle = TextStyle(
  fontSize: 16,
  fontWeight: FontWeight.w600,
  color: AppColors.textColor,
);
const _subtitleStyle = TextStyle(
  fontSize: 13,
  color: AppColors.textSecondary,
  height: 1.3,
);

// Colored square behind a card's icon, same on every card.
class _IconTile extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _IconTile({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 28, color: color),
    );
  }
}

// No card: once logged in, the app works offline on its own. Opening an
// adjustment that isn't on the phone yet copies it (sheets, numbers in
// stock, consolidation) in the background.
class _AutoPrepare extends StatefulWidget {
  final int adjustmentId;

  const _AutoPrepare({required this.adjustmentId});

  @override
  State<_AutoPrepare> createState() => _AutoPrepareState();
}

class _AutoPrepareState extends State<_AutoPrepare> {
  @override
  void initState() {
    super.initState();
    OfflinePrepService.ensurePrepared([
      {'id': widget.adjustmentId},
    ]);
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
