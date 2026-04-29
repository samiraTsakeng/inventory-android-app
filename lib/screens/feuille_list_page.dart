import 'package:flutter/material.dart';
import '../services/feuille_service.dart';
import 'scanning_page.dart';

class FeuilleListPage extends StatefulWidget {
  final int adjustmentId;

  FeuilleListPage({required this.adjustmentId});

  @override
  _FeuilleListPageState createState() => _FeuilleListPageState();
}

class _FeuilleListPageState extends State<FeuilleListPage> {
  List feuilles = [];
  bool isLoading = true;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    fetchFeuilles();
  }

  void fetchFeuilles() async {
    try {
      final data = await FeuilleService.getFeuilles(widget.adjustmentId);

      setState(() {
        feuilles = data;
        isLoading = false;
      });
    } catch (e) {
      setState(() {
        errorMessage = e.toString();
        isLoading = false;
      });
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
        title: Text("Feuilles de comptage"),
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : errorMessage != null
          ? Center(child: Text("Error: $errorMessage"))
          : feuilles.isEmpty
          ? Center(child: Text("No feuilles found"))
          : ListView.builder(
        itemCount: feuilles.length,
        itemBuilder: (context, index) {
          final f = feuilles[index];

          return Card(
            margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: f["state"] == 'progress' ? Colors.green : Colors.blue,
                child: Icon(Icons.inventory, color: Colors.white),
              ),
              title: Text(
                f["name"] ?? "",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                "État: ${f["state"] ?? 'Nouveau'} | Zone: ${getName(f["zone_id"])}",
              ),
              trailing: f["state"] == 'progress'
                  ? ElevatedButton.icon(
                icon: Icon(Icons.qr_code_scanner),
                label: Text("Scanner"),
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ScanningPage(
                        countingSheetId: f["id"],
                        adjustmentId: widget.adjustmentId,
                        zoneName: getName(f["zone_id"]),
                        sheetName: f["name"] ?? "Feuille ${f["id"]}",
                      ),
                    ),
                  );
                },
              )
                  : Chip(
                label: Text(f["state"] ?? "Nouveau"),
                backgroundColor: f["state"] == 'confirm' ? Colors.green[100] : Colors.grey[200],
              ),
              onTap: () {
                // Only allow scanning if in progress
                if (f["state"] == 'progress') {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ScanningPage(
                        countingSheetId: f["id"],
                        adjustmentId: widget.adjustmentId,
                        zoneName: getName(f["zone_id"]),
                        sheetName: f["name"] ?? "Feuille ${f["id"]}",
                      ),
                    ),
                  );
                }
              },
            ),
          );
        },
      ),
    );
  }
}