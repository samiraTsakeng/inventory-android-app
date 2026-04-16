import 'package:flutter/material.dart';
import '../services/feuille_service.dart';

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
      final data =
      await FeuilleService.getFeuilles(widget.adjustmentId);

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

          return ListTile(
            title: Text(f["name"] ?? ""),

            subtitle: Text(
                "Etat: ${f["state"]} | zone: ${getName(f["zone_id"])}"),

            onTap: () {
              print("Clicked feuille: ${f["id"]}");
            },
          );
        },
      ),
    );
  }
}