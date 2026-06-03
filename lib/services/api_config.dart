import 'package:flutter/material.dart';
import 'package:http/http.dart';

class ApiConfig {
  static const String baseUrl = "http://192.168.10.164:3001";

  static String get adjustments => "$baseUrl/adjustments";
  static String get login => "$baseUrl/auth/login";
  static String feuilles(int adjustmentId) => "$baseUrl/feuilles/$adjustmentId";
}

