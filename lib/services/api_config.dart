// Routes de l'API mobile du module Odoo wise_inventory, appelées
// directement sur le serveur Odoo saisi à la connexion.
class ApiConfig {
  // Default network timeout; long operations pass their own.
  static const Duration timeout = Duration(seconds: 20);
  // Default timeout while Odoo is known unreachable: screens fall back to
  // the phone's copy quickly instead of waiting [timeout] each time.
  static const Duration offlineTimeout = Duration(seconds: 5);
  // A scan shouldn't wait longer: past this the number is kept "to verify".
  static const Duration lookupTimeout = Duration(seconds: 8);
  // Sending a batch creates many lines in Odoo.
  static const Duration submitTimeout = Duration(seconds: 90);
  // Full product download at login.
  static const Duration cacheTimeout = Duration(seconds: 120);

  static const String _api = '/wise_inventory/api';

  static const String adjustments = '$_api/adjustments';
  static const String feuilles = '$_api/feuilles';

  static const String lookupProduct = '$_api/counting/lookup_product';
  static const String lookupProducts = '$_api/counting/lookup_products';
  static const String sheetState = '$_api/counting/sheet_state';
  static const String startSheet = '$_api/counting/start_sheet';
  static const String validateSheet = '$_api/counting/validate_sheet';
  static const String submit = '$_api/counting/submit';
  static const String checkErpScan = '$_api/counting/check_erp_scan';
  static const String checkErpScans = '$_api/counting/check_erp_scans';
  static const String sheetLots = '$_api/counting/sheet_lots';
  static const String offlinePack = '$_api/counting/offline_pack';
  static const String liveItems = '$_api/counting/live_items';
  static const String liveScan = '$_api/counting/live_scan';
  static const String liveClear = '$_api/counting/live_clear';
  static const String liveRemove = '$_api/counting/live_remove';

  static const String productsCache = '$_api/products/cache';
  static const String productsByBarcode = '$_api/products/by_barcode';

  static const String consolidationSheets = '$_api/consolidation/sheets';
  static const String consolidationSheet = '$_api/consolidation/sheet';
  static const String updateContradictoryLine =
      '$_api/consolidation/update_contradictory_line';
  static const String validateConsolidationSheet =
      '$_api/consolidation/validate_sheet';
  static const String consolidationZones = '$_api/consolidation/zones';
  static const String createConsolidation = '$_api/consolidation/create';
  static const String applyConsolidation = '$_api/consolidation/apply';
  static const String adjustmentStatus =
      '$_api/consolidation/adjustment_status';

  // Routes standard d'Odoo.
  static const String authenticate = '/web/session/authenticate';
  static const String databaseList = '/web/database/list';
  static const String versionInfo = '/web/webclient/version_info';
}
