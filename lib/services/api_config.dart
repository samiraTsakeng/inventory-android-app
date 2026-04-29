class ApiConfig {
  static const String baseUrl = "http://192.168.1.109:3001";

  static String get adjustments => "$baseUrl/adjustments";
  static String get login => "$baseUrl/auth/login";
  static String feuilles(int adjustmentId) => "$baseUrl/feuilles/$adjustmentId";
}