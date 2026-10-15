class ApiConfig {
  static const String baseUrl = "http://192.168.10.111:3001";

  // Default network timeout; long operations pass their own.
  static const Duration timeout = Duration(seconds: 20);
  // A scan shouldn't wait longer: past this the number is kept "to verify".
  static const Duration lookupTimeout = Duration(seconds: 8);
  // Sending a batch creates many lines in Odoo.
  static const Duration submitTimeout = Duration(seconds: 90);
  // Full product download at login.
  static const Duration cacheTimeout = Duration(seconds: 120);

  static String get adjustments => "$baseUrl/adjustments";
  static String get login => "$baseUrl/auth/login";
  static String feuilles(int adjustmentId) => "$baseUrl/feuilles/$adjustmentId";
}
