import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'utils/constants.dart';
import 'screens/login_page.dart';
import 'screens/adjustment_entry_page.dart';
import 'screens/adjustment_list_page.dart';
import 'screens/choice_page.dart';
import 'screens/feuille_list_page.dart';
import 'screens/consolidation_list_page.dart';
import 'services/api_client.dart';
import 'services/auth_service.dart';
import 'services/local_storage_service.dart';
import 'services/sync_service.dart';
import 'services/offline_prep_service.dart';
import 'widgets/offline_banner.dart';
import 'screens/adjustment_action_page.dart';

// Lets main() go back to the login page once the app is shown.
final GlobalKey<NavigatorState> appNavigatorKey = GlobalKey();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Release build: the debug messages aren't written to the phone's log.
  if (kReleaseMode) debugPrint = (String? message, {int? wrapWidth}) {};

  // Once, after an update: offline copies leave SharedPreferences.
  await LocalStorageService.migrateLargeData();

  // With a saved session the app opens at once, online or not, and logs in
  // again in the background: offline, nothing waits for the server.
  final hasSession = await AuthService.hasSavedSession();
  if (!hasSession) await AuthService.clearSession();

  AuthService.loggedIn.value = hasSession;
  SyncService.start(startOffline: false);

  runApp(MyApp(initialRoute: hasSession ? '/adjustment-entry' : '/'));
  if (!hasSession) return;

  final login = AuthService.autoLogin();
  ApiClient.startupLogin = login.then((_) {});
  final result = await login;
  ApiClient.startupLogin = null;
  debugPrint("Auto-login result: $result");

  switch (result) {
    case AutoLoginResult.success:
      // Connected: downloads what's needed to work offline.
      unawaited(OfflinePrepService.prepareAll());
    case AutoLoginResult.offline:
      // Server unreachable (already reported by ApiClient): the app keeps
      // working on the phone's copy.
      break;
    case AutoLoginResult.rejected:
    case AutoLoginResult.noSession:
      // Odoo refused the saved credentials: back to the login page.
      AuthService.loggedIn.value = false;
      appNavigatorKey.currentState?.pushNamedAndRemoveUntil('/', (_) => false);
      SyncService.messengerKey.currentState?.showSnackBar(
        const SnackBar(
          content: Text('Session expirée : veuillez vous reconnecter.'),
          backgroundColor: AppColors.errorColor,
        ),
      );
  }
}

class MyApp extends StatelessWidget {
  final String initialRoute;
  const MyApp({super.key, this.initialRoute = '/'});

  // The phone's own font (Roboto on Android): nothing to download at
  // startup, works offline. Built once.
  static final ThemeData _theme = _buildTheme();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      scaffoldMessengerKey: SyncService.messengerKey,
      navigatorKey: appNavigatorKey,
      builder: (context, child) => OfflineBanner(child: child!),
      debugShowCheckedModeBanner: false,
      title: 'Wise Inventory',
      theme: _theme,
      initialRoute: initialRoute,
      routes: {
        '/': (context) => LoginPage(),
        '/adjustment-entry': (context) => AdjustmentEntryPage(),
        '/adjustments-list': (context) => AdjustmentsListPage(),
      },
      onGenerateRoute: _route,
    );
  }

  static ThemeData _buildTheme() {
    return ThemeData(
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
      textTheme: Typography.material2021().black.apply(
        bodyColor: AppColors.textColor,
        displayColor: AppColors.textColor,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: AppColors.primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: const TextStyle(
          fontSize: 17,
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
          textStyle: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
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
        style: TextButton.styleFrom(foregroundColor: AppColors.secondaryColor),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfaceColor,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 14,
        ),
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
      // Same look as AppCard for the remaining Material cards.
      cardTheme: CardThemeData(
        elevation: 0.5,
        margin: EdgeInsets.zero,
        color: AppColors.surfaceColor,
        surfaceTintColor: Colors.transparent,
        shadowColor: const Color(0x330B1F3A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDecor.cardRadius),
          side: const BorderSide(color: AppColors.borderColor),
        ),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.primaryColor.withValues(alpha: 0.08),
        labelStyle: const TextStyle(
          color: AppColors.primaryColor,
          fontWeight: FontWeight.w600,
        ),
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
      dividerTheme: const DividerThemeData(
        color: AppColors.borderColor,
        thickness: 1,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primaryColor,
      ),
    );
  }

  static Route<dynamic>? _route(RouteSettings settings) {
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
  }
}
