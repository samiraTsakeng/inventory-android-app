import 'package:flutter/material.dart';
import 'screens/login_page.dart';
import 'screens/adjustment_entry_page.dart';
import 'screens/adjustment_list_page.dart';
import 'screens/choice_page.dart';
import 'screens/feuille_list_page.dart';
import 'screens/scanning_page.dart';
import 'screens/scanned_items_list_page.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Wise inventory',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: 'Roboto',
      ),
      initialRoute: '/',
      routes: {
        '/': (context) => LoginPage(),
        '/adjustment-entry': (context) => AdjustmentEntryPage(),
        '/adjustments-list': (context) => AdjustmentsListPage(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/choice-page') {
          final adjustmentId = settings.arguments as int;
          return MaterialPageRoute(
            builder: (context) => ChoicePage(adjustmentId: adjustmentId),
          );
        }
        if (settings.name == '/feuilles-list') {
          final adjustmentId = settings.arguments as int;
          return MaterialPageRoute(
            builder: (context) => FeuilleListPage(adjustmentId: adjustmentId),
          );
        }
        return null;
      },
    );
  }
}