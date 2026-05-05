import 'package:flutter/material.dart';

class ChoicePage extends StatelessWidget {
  final int? adjustmentId;

  const ChoicePage({super.key, this.adjustmentId});

  @override
  Widget build(BuildContext context) {
    // Get adjustmentId from arguments if not provided directly
    final adjId = ModalRoute.of(context)?.settings.arguments as int? ?? adjustmentId;

    if (adjId == null) {
      // If no adjustment ID, go back
      WidgetsBinding.instance.addPostFrameCallback((_) {
        Navigator.pop(context);
      });
      return const Scaffold(
        body: Center(child: Text("Error: No adjustment selected")),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Choisir une option"),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
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
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Counting Sheet Card
            _buildChoiceCard(
              context: context,
              title: "Feuille de comptage",
              subtitle: "Scanner les articles pour le comptage",
              icon: Icons.qr_code_scanner,
              color: Colors.blue,
              onTap: () {
                // Navigate to feuilles list with adjustment ID
                Navigator.pushNamed(
                  context,
                  '/feuilles-list',
                  arguments: adjId,
                );
              },
            ),
            const SizedBox(height: 20),
            // Consolidation Sheet Card (disabled for now)
            _buildChoiceCard(
              context: context,
              title: "Feuille de consolidation",
              subtitle: "Consolider les comptages (à venir)",
              icon: Icons.merge_type,
              color: Colors.grey,
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text("Fonctionnalité à venir"),
                    backgroundColor: Colors.orange,
                  ),
                );
              },
              enabled: false,
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
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: enabled ? Colors.black87 : Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 14,
                        color: enabled ? Colors.grey[600] : Colors.grey[400],
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