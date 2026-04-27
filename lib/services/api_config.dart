class ApiConfig {
  static const String baseUrl = "http://localhost:3001";

  static String get adjustments => "$baseUrl/adjustments";
  static String get login => "$baseUrl/auth/login";
}