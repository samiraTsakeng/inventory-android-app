import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'utils/constants.dart';
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
    final baseTextTheme = GoogleFonts.interTextTheme();

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Wise Inventory',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: AppColors.backgroundColor,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.primaryColor,
          primary: AppColors.primaryColor,
          secondary: AppColors.secondaryColor,
          tertiary: AppColors.tertiaryColor,
          error: AppColors.errorColor,
          surface: AppColors.surfaceColor,
        ),
        textTheme: baseTextTheme.apply(
          bodyColor: AppColors.textColor,
          displayColor: AppColors.textColor,
        ),
        appBarTheme: AppBarTheme(
          backgroundColor: AppColors.primaryColor,
          foregroundColor: Colors.white,
          elevation: 0,
          centerTitle: false,
          titleTextStyle: GoogleFonts.inter(
            fontSize: 19,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primaryColor,
            foregroundColor: Colors.white,
            minimumSize: const Size(64, 50),
            elevation: 1,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            textStyle: GoogleFonts.inter(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primaryColor,
            side: const BorderSide(color: AppColors.primaryColor),
            minimumSize: const Size(64, 50),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.secondaryColor,
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surfaceColor,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.borderColor),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: AppColors.borderColor),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.primaryColor, width: 2),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: AppColors.errorColor, width: 1.5),
          ),
          labelStyle: const TextStyle(color: AppColors.textSecondary),
        ),
        cardTheme: CardThemeData(
          elevation: 1.5,
          margin: EdgeInsets.zero,
          color: AppColors.surfaceColor,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: AppColors.borderColor),
          ),
        ),
        chipTheme: ChipThemeData(
          backgroundColor: AppColors.primaryColor.withOpacity(0.08),
          labelStyle: const TextStyle(color: AppColors.primaryColor, fontWeight: FontWeight.w600),
          side: BorderSide.none,
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: AppColors.secondaryColor,
          foregroundColor: Colors.white,
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        ),
        dividerTheme: const DividerThemeData(color: AppColors.borderColor, thickness: 1),
        progressIndicatorTheme: const ProgressIndicatorThemeData(
          color: AppColors.primaryColor,
        ),
      ),
      initialRoute: initialRoute,
      routes: {
        '/': (context) => LoginPage(),
        '/adjustment-entry': (context) => AdjustmentEntryPage(),
        '/adjustments-list': (context) => AdjustmentsListPage(),
      },
      onGenerateRoute: (settings) {
        if (settings.name == '/choice-page') {
          final args = settings.arguments;
          int? adjustmentId;
          dynamic managerId;
          if (args is Map) {
            adjustmentId = args['id'] as int?;
            managerId = args['managerId'];
          } else if (args is int) {
            // Backward-compatible: still support a plain int argument.
            adjustmentId = args;
          }
          return MaterialPageRoute(
            builder: (context) => ChoicePage(adjustmentId: adjustmentId, managerId: managerId),
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