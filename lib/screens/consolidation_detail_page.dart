import 'package:flutter/material.dart';
import '../utils/constants.dart';
import '../services/consolidation_service.dart';

class ConsolidationDetailPage extends StatefulWidget {
  final int sheetId;
  final String sheetName;
  final String zoneName;

  const ConsolidationDetailPage({
    Key? key,
    required this.sheetId,
    required this.sheetName,
    required this.zoneName,
  }) : super(key: key);

  @override
  State<ConsolidationDetailPage> createState() => _ConsolidationDetailPageState();
}

class _ConsolidationDetailPageState extends State<ConsolidationDetailPage> {
  Map<String, dynamic>? sheetData;
  bool isLoading = true;
  bool isSaving = false;
  String? errorMessage;
  Map<int, TextEditingController> _quantityControllers = {};

  @override
  void initState() {
    super.initState();
    fetchDetail();
  }

  Future<void> fetchDetail() async {
    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    try {
      final data = await ConsolidationService.getConsolidationSheetDetail(widget.sheetId);
      if (data != null) {
        setState(() {
          sheetData = data;
          isLoading = false;

          // Initialize controllers for contradictory lines
          final contradictoryLines = data['counting_contradictory_line_ids'] as List? ?? [];
          for (final line in contradictoryLines) {
            final id = line['id'];
            if (!_quantityControllers.containsKey(id)) {
              _quantityControllers[id] = TextEditingController(
                text: line['verified_qty']?.toString() ?? '',
              );
            }
          }
        });
      } else {
        setState(() {
          errorMessage = "Impossible de charger les détails";
          isLoading = false;
        });
      }
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
    if (field is Map && field.containsKey('name')) return field['name'];
    return field.toString();
  }

  String _initials(dynamic userField) {
    // userField is either null, an int, or [id, name]
    if (userField == null) return '';
    String name = '';
    if (userField is List && userField.length > 1) {
      name = userField[1]?.toString() ?? '';
    } else if (userField is Map && userField.containsKey('name')) {
      name = userField['name']?.toString() ?? '';
    } else {
      name = userField.toString();
    }
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '';
    if (parts.length == 1) {
      return parts.first.substring(0, parts.first.length >= 2 ? 2 : 1).toUpperCase();
    }
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  Color getStatusColor(String? state) {
    switch (state) {
      case 'confirm': return AppColors.successColor;
      case 'progress': return AppColors.warningColor;
      case 'new': return AppColors.primaryColor;
      case 'cancel': return AppColors.errorColor;
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

  Future<void> _saveVerifiedQuantity(int lineId) async {
    final controller = _quantityControllers[lineId];
    if (controller == null) return;

    final value = int.tryParse(controller.text);
    if (value == null || value < 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Veuillez entrer une quantité valide'),
          backgroundColor: AppColors.warningColor,
        ),
      );
      return;
    }

    setState(() => isSaving = true);

    final success = await ConsolidationService.updateContradictoryLine(lineId, value);

    setState(() => isSaving = false);

    if (success) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(' Quantité vérifiée sauvegardée'),
          backgroundColor: AppColors.successColor,
        ),
      );
      await fetchDetail();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(' Erreur lors de la sauvegarde'),
          backgroundColor: AppColors.errorColor,
        ),
      );
    }
  }

  Future<void> _removeContradictoryLine(int lineId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Retirer la ligne contradictoire ?'),
        content: const Text(
          'Cette ligne sera retirée de la liste dans l\'application uniquement. '
              'Aucune modification ne sera faite dans l\'ERP.',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Non'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.errorColor,
              foregroundColor: Colors.white,
            ),
            child: const Text('Oui'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() {
      final lines = sheetData!['counting_contradictory_line_ids'] as List;
      lines.removeWhere((l) => l['id'] == lineId);
      _quantityControllers[lineId]?.dispose();
      _quantityControllers.remove(lineId);
    });
  }

  Future<void> _validateConsolidation() async {
    final shouldValidate = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.fact_check_outlined, color: AppColors.primaryColor, size: 20),
            SizedBox(width: 8),
            Text("Valider la consolidation", style: TextStyle(fontSize: 18)),
          ],
        ),
        content: Text(
          "Voulez-vous valider la consolidation \"${widget.sheetName}\" ?\n\nCette action est irréversible et mettra à jour le stock.",
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Non", style: TextStyle(fontSize: 14)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.successColor,
              foregroundColor: Colors.white,
            ),
            child: const Text("Oui, valider", style: TextStyle(fontSize: 14)),
          ),
        ],
      ),
    );

    if (shouldValidate == true) {
      setState(() => isSaving = true);

      final success = await ConsolidationService.validateConsolidationSheet(widget.sheetId);

      setState(() => isSaving = false);

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(' Consolidation validée avec succès !'),
            backgroundColor: AppColors.successColor,
          ),
        );
        Navigator.pop(context, true);
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(' Erreur lors de la validation'),
            backgroundColor: AppColors.errorColor,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    for (final controller in _quantityControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (errorMessage != null || sheetData == null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("Détails", style: TextStyle(fontSize: 16)),
          centerTitle: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, size: 20),
            onPressed: () => Navigator.pop(context),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.error_outline, size: 50, color: AppColors.errorColor),
                const SizedBox(height: 16),
                Text(
                  errorMessage ?? "Erreur de chargement",
                  style: const TextStyle(fontSize: 13, color: AppColors.errorColor),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: fetchDetail,
                  child: const Text("Réessayer", style: TextStyle(fontSize: 12)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final state = sheetData!['state'];
    final isConfirm = state == 'confirm';
    final isProgress = state == 'progress' || state == 'new';
    final contradictoryLines = sheetData!['counting_contradictory_line_ids'] as List? ?? [];
    final countingLines = sheetData!['counting_line_ids'] as List? ?? [];

    final allVerified = contradictoryLines.every(
            (line) => line['verified_qty'] != null && line['verified_qty'] > 0
    );

    return Scaffold(
      backgroundColor: AppColors.backgroundColor,
      appBar: AppBar(
        title: Text(widget.sheetName, style: const TextStyle(fontSize: 15)),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: getStatusColor(state).withOpacity(0.2),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              getStatusText(state),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: getStatusColor(state),
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Zone info and team summary
          Container(
            padding: const EdgeInsets.all(12),
            color: AppColors.surfaceColor,
            child: Column(
              children: [
                Row(
                  children: [
                    const Icon(Icons.location_on, size: 16, color: AppColors.textSecondary),
                    const SizedBox(width: 8),
                    Text(
                      "Zone: ${widget.zoneName}",
                      style: const TextStyle(fontSize: 13, color: AppColors.textSecondary),
                    ),
                    const Spacer(),
                    Text(
                      "Total: ${countingLines.length + contradictoryLines.length} lignes",
                      style: const TextStyle(fontSize: 12, color: AppColors.textSecondary),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    // Team 1 badge
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.primaryColor.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.primaryColor.withOpacity(0.25)),
                        ),
                        child: Center(
                          child: Text(
                            //show initials of the counter in charge of sheet 1
                            " Équipe 1 ${_initials(sheetData!['counting_sheet_1']?['user_id'])}",
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: AppColors.primaryColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Team 2 badge
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        decoration: BoxDecoration(
                          color: AppColors.secondaryColor.withOpacity(0.06),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: AppColors.secondaryColor.withOpacity(0.25)),
                        ),
                        child: Center(
                          child: Text(
                            " Équipe 2 ${_initials(sheetData!['counting_sheet_2']?['user_id'])}",
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: AppColors.secondaryColor,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Lines
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  // Corresponding lines (both teams agree)
                  if (countingLines.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.successColor.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.successColor.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.check_circle, size: 16, color: AppColors.successColor),
                          const SizedBox(width: 8),
                          Expanded(
                          child: Text(
                            " Lignes correspondantes (${countingLines.length})",
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppColors.successColor,
                            ),
                          ),
                          ),
                        ],
                      ),
                    ),
                    //const SizedBox(height: 8),

                    const SizedBox(height: 12),
                  ],
                  // Contradictory lines (teams disagree)
                  if (contradictoryLines.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: AppColors.warningColor.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.warningColor.withOpacity(0.3)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.warning_amber, size: 16, color: AppColors.warningColor),
                          const SizedBox(width: 8),
                          Text(
                            "️ Lignes contradictoires (${contradictoryLines.length})",
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: AppColors.warningColor,
                            ),
                          ),
                          const Spacer(),
                          if (isProgress)
                            Text(
                              "${contradictoryLines.where((l) => l['verified_qty'] != null && l['verified_qty'] > 0).length}/${contradictoryLines.length} vérifiées",
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...contradictoryLines.asMap().entries.map((entry) {
                      final index = entry.key;
                      final line = entry.value;
                      final lineId = line['id'];
                      final isVerified = line['verified_qty'] != null && line['verified_qty'] > 0;
                      final controller = _quantityControllers[lineId] ?? TextEditingController();

                      // Get quantities from both teams
                      final team1Qty = line['counted_qty_1'] ?? '?';
                      final team2Qty = line['counted_qty_2'] ?? '?';

                      return Card(
                        margin: const EdgeInsets.only(bottom: 8),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    width: 30,
                                    height: 30,
                                    decoration: BoxDecoration(
                                      color: (isVerified ? AppColors.successColor : AppColors.warningColor).withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Center(
                                      child: Text(
                                        '${index + 1}',
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          color: isVerified ? AppColors.successColor : AppColors.warningColor,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          getName(line['lot_id']),
                                          style: const TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Text(
                                          getName(line['product_id']),
                                          style: const TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textSecondary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  if (isVerified)
                                    const Icon(Icons.check_circle, size: 20, color: AppColors.successColor),
                                  // delete button
                                  IconButton(
                                    icon: const Icon(Icons.delete_outline, size:18, color: AppColors.errorColor),
                                    onPressed: () => _removeContradictoryLine(lineId),
                                    padding: EdgeInsets.zero,
                                    constraints: const BoxConstraints(),
                                    tooltip: 'retirer cette ligne',

                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              // Team comparison - NOW SHOWS ACTUAL QUANTITIES
                              Row(
                                children: [
                                  // Team 1
                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                                      decoration: BoxDecoration(
                                        color: AppColors.primaryColor.withOpacity(0.06),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Column(
                                        children: [
                                          Text(
                                            "Équipe 1",
                                            style: TextStyle(
                                              fontSize: 9,
                                              color: AppColors.primaryColor,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          Text(
                                            "$team1Qty",
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // VS
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 4),
                                    child: const Text(
                                      "VS",
                                      style: TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                        color: AppColors.textSecondary,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  // Team 2
                                  Expanded(
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                                      decoration: BoxDecoration(
                                        color: AppColors.secondaryColor.withOpacity(0.06),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Column(
                                        children: [
                                          Text(
                                            "Équipe 2",
                                            style: TextStyle(
                                              fontSize: 9,
                                              color: AppColors.secondaryColor,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                          Text(
                                            "$team2Qty",
                                            style: const TextStyle(
                                              fontSize: 16,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              // Verified quantity
                              if (isProgress)
                                Row(
                                  children: [
                                    Expanded(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                                        decoration: BoxDecoration(
                                          color: isVerified ? AppColors.successColor.withOpacity(0.08) : AppColors.backgroundColor,
                                          borderRadius: BorderRadius.circular(6),
                                          border: isVerified ? Border.all(color: AppColors.successColor.withOpacity(0.3)) : null,
                                        ),
                                        child: Column(
                                          children: [
                                            Text(
                                              "Quantité vérifiée",
                                              style: TextStyle(
                                                fontSize: 9,
                                                color: isVerified ? AppColors.successColor : AppColors.textSecondary,
                                                fontWeight: FontWeight.w500,
                                              ),
                                            ),
                                            isVerified
                                                ? Text(
                                              "${line['verified_qty']}",
                                              style: const TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.bold,
                                                color: AppColors.successColor,
                                              ),
                                            )
                                                : Row(
                                              children: [
                                                Expanded(
                                                  child: TextField(
                                                    controller: controller,
                                                    keyboardType: TextInputType.number,
                                                    decoration: const InputDecoration(
                                                      border: InputBorder.none,
                                                      hintText: '0',
                                                      contentPadding: EdgeInsets.zero,
                                                    ),
                                                    style: const TextStyle(fontSize: 14),
                                                  ),
                                                ),
                                                IconButton(
                                                  icon: const Icon(Icons.save, size: 18, color: AppColors.primaryColor),
                                                  onPressed: isSaving
                                                      ? null
                                                      : () => _saveVerifiedQuantity(lineId),
                                                  padding: EdgeInsets.zero,
                                                  constraints: const BoxConstraints(),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              if (isConfirm)
                                Text(
                                  "Quantité vérifiée: ${line['verified_qty'] ?? '-'}",
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.successColor,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    }),
                    const SizedBox(height: 12),
                  ],
                  // Validate button
                  if (isProgress)
                    SizedBox(
                      width: double.infinity,
                      height: 50,
                      child: ElevatedButton(
                        onPressed: isSaving || !allVerified
                            ? null
                            : _validateConsolidation,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.successColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: isSaving
                            ? const CircularProgressIndicator(color: Colors.white)
                            : Text(
                          allVerified
                              ? " Valider la consolidation"
                              : " Vérifiez toutes les lignes contradictoires",
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                  if (isConfirm)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      margin: const EdgeInsets.only(top: 4),
                      decoration: BoxDecoration(
                        color: AppColors.successColor.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text(
                        '✓ Consolidation validée',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 16,
                          color: AppColors.successColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}