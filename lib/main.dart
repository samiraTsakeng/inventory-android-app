import 'package:flutter/material.dart';
import 'screens/login_page.dart';
import 'screens/adjustment_entry_page.dart';
import 'screens/adjustment_list_page.dart';
import 'screens/choice_page.dart';
import 'screens/feuille_list_page.dart';
import 'screens/scanning_page.dart';
import 'screens/scanned_items_list_page.dart';
import 'screens/batch_list_page.dart';
import 'screens/consolidation_list_page.dart';
import 'services/auth_service.dart';
import 'screens/adjustment_action_page.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Try auto-login on app start
  bool autoLoginSuccess = false;
  try {
    autoLoginSuccess = await AuthService.autoLogin();
    print("Auto-login result: $autoLoginSuccess");
  } catch (e) {
    print("Auto-login error: $e");
  }

  // If auto-login fails, clear session to force login
  if (!autoLoginSuccess) {
    await AuthService.clearSession();
  }

  runApp(MyApp(initialRoute: autoLoginSuccess ? '/adjustment-entry' : '/'));
}

class MyApp extends StatelessWidget {
  final String initialRoute;
  const MyApp({Key? key, this.initialRoute = '/'}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Wise Inventory',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        fontFamily: 'Roboto',
      ),
      initialRoute: initialRoute,
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
        if (settings.name == '/consolidation-list') {
          final adjustmentId = settings.arguments as int;
          return MaterialPageRoute(
            builder: (context) => ConsolidationListPage(adjustmentId: adjustmentId),
          );
        }
        if (settings.name == '/adjustment-action') {
          final args = settings.arguments as Map<String, dynamic>;
          return MaterialPageRoute(
            builder: (context) => AdjustmentActionPage(
              adjustmentId: args['adjustmentId'],
              adjustmentName: args['adjustmentName'] ?? 'Ajustement',
            ),
          );
        }

        return null;
      },
    );
  }
}