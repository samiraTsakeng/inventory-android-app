import 'package:flutter/material.dart';
import 'consolidation_list_page.dart';
import 'consolidation_zones_page.dart';
import 'adjustment_action_page.dart';
import '../services/sheet_cache_service.dart';
import '../services/sync_service.dart';

class ChoicePage extends StatelessWidget {
  final int? adjustmentId;

  const ChoicePage({super.key, this.adjustmentId});

  @override
  Widget build(BuildContext context) {
    final adjId = ModalRoute.of(context)?.settings.arguments as int? ?? adjustmentId;

    if (adjId == null) {
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
                Navigator.pushNamed(
                  context,
                  '/feuilles-list',
                  arguments: adjId,
                );
              },
            ),
            const SizedBox(height: 12),
            _OfflinePrepareCard(adjustmentId: adjId),
            const SizedBox(height: 20),

            // Consolidation Management Card (combines everything)
            _buildChoiceCard(
              context: context,
              title: "Gestion des consolidations",
              subtitle: "Consolider les zones et appliquer au stock",
              icon: Icons.merge_type,
              color: Colors.purple,
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

// Downloads what the counting teams need to work without network: the
// user's sheets, the serial/lot numbers of the inventoried location and
// what each sheet already sent. Shows how fresh the copy on the phone is.
class _OfflinePrepareCard extends StatefulWidget {
  final int adjustmentId;

  const _OfflinePrepareCard({required this.adjustmentId});

  @override
  State<_OfflinePrepareCard> createState() => _OfflinePrepareCardState();
}

class _OfflinePrepareCardState extends State<_OfflinePrepareCard> {
  bool _isPreparing = false;
  int _count = 0;
  DateTime? _updatedAt;

  @override
  void initState() {
    super.initState();
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    final info = await SheetCacheService.info(widget.adjustmentId);
    if (!mounted) return;
    setState(() {
      _count = info.count;
      _updatedAt = info.updatedAt;
    });
  }

  Future<void> _prepare() async {
    if (!SyncService.online.value) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Connexion nécessaire pour préparer le hors ligne'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _isPreparing = true);
    final result = await SheetCacheService.prepareAdjustment(widget.adjustmentId);
    if (!mounted) return;
    setState(() => _isPreparing = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(result == null
            ? 'Préparation impossible, réessayez avec une meilleure connexion'
            : 'Prêt pour le hors ligne : ${result.sheets} feuille(s), ${result.lots} numéros'),
        backgroundColor: result == null ? Colors.red : Colors.green,
      ),
    );
    await _loadInfo();
  }

  String _subtitle() {
    final updatedAt = _updatedAt;
    if (_count == 0 || updatedAt == null) {
      return 'Télécharger feuilles et numéros pour compter sans réseau';
    }
    String two(int n) => n.toString().padLeft(2, '0');
    return 'Prêt : $_count numéros · mis à jour le '
        '${two(updatedAt.day)}/${two(updatedAt.month)} à ${two(updatedAt.hour)}h${two(updatedAt.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    final ready = _count > 0;
    final color = ready ? Colors.green : Colors.teal;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        onTap: _isPreparing ? null : _prepare,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  ready ? Icons.offline_pin : Icons.cloud_download,
                  size: 26,
                  color: color,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Préparer le hors ligne',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _subtitle(),
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
              if (_isPreparing)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              else
                Icon(Icons.refresh, color: color, size: 22),
            ],
          ),
        ),
      ),
    );
  }
}
