import 'package:flutter/material.dart';
import '../services/adjustment_service.dart';

class AdjustmentsListPage extends StatefulWidget {
  @override
  _AdjustmentsListPageState createState() =>
      _AdjustmentsListPageState();
}

class _AdjustmentsListPageState extends State<AdjustmentsListPage> {
  List adjustments = [];
  bool isLoading = true;
  String? errorMessage; // ✅ ADD THIS

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
      // ✅ HANDLE ERROR (VERY IMPORTANT)
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });

      print("FETCH ERROR: $e");
    }
  }

  String getName(dynamic field) {
    if (field == null) return "";
    if (field is List) return field[1];
    return field.toString();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Ajustements"),
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())

      // ✅ SHOW ERROR INSTEAD OF LOADING FOREVER
          : errorMessage != null
          ? Center(
        child: Text(
          "Error: $errorMessage",
          style: TextStyle(color: Colors.red),
        ),
      )

      // ✅ NORMAL DATA DISPLAY
          : adjustments.isEmpty
          ? Center(child: Text("No adjustments found"))

          : SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text("Date")),
            DataColumn(label: Text("Emplacement")),
            DataColumn(label: Text("Zone")),
            DataColumn(label: Text("Responsable")),
            DataColumn(label: Text("Equipe")),
            DataColumn(label: Text("Statut")),
          ],
          rows: adjustments.map<DataRow>((adj) {
            return DataRow(
              cells: [
                DataCell(Text(adj["date_comptage"] ?? "")),
                DataCell(Text(getName(adj["emplacement_id"]))),
                DataCell(Text(getName(adj["zone_id"]))),
                DataCell(Text(getName(adj["responsable_id"]))),
                DataCell(Text(getName(adj["equipe_id"]))),
                DataCell(Text(adj["state"] ?? "")),
              ],

              // ✅ MAKE ROW CLICKABLE
              onSelectChanged: (selected) {
                if (selected == true) {
                  print("Clicked adjustment: ${adj["id"]}");
                }
              },
            );
          }).toList(),
        ),
      ),
    );
  }
}