import 'package:flutter/material.dart';
import 'screens/login_page.dart';
import 'screens/adjustment_entry_page.dart';
import 'screens/adjustment_list_page.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      initialRoute: '/',
      routes: {
        '/': (context) => LoginPage(),
        '/adjustment-entry': (context) => AdjustmentEntryPage(),
        '/adjustments-list': (context) => AdjustmentsListPage(),
      },
    );
  }
}