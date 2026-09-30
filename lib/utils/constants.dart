import 'package:flutter/material.dart';

class AppColors {
  // Marque
  static const primaryColor = Color(0xFF03045A); // bleu marine du logo
  static const primaryDark = Color(0xFF020339);
  static const primaryLight = Color(0xFF023E8A);
  static const secondaryColor = Color(0xFF0077B6); // bleu océan (accent)
  static const tertiaryColor = Color(0xFF00B4D8); // cyan (highlights, info)

  // États
  static const accentColor = Color(0xFF16A34A); // succès
  static const successColor = Color(0xFF16A34A);
  static const warningColor = Color(0xFFF59E0B);
  static const errorColor = Color(0xFFDC2626);

  // Neutres
  static const backgroundColor = Color(0xFFF4F6FB);
  static const surfaceColor = Color(0xFFFFFFFF);
  static const textColor = Color(0xFF0B1F3A);
  static const textSecondary = Color(0xFF5B6B85);
  static const borderColor = Color(0xFFE2E7F1);

  /// Dégradé de marque utilisé sur les en-têtes / hero.
  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primaryColor, primaryLight],
  );
}

class AppStrings {
  static const appName = 'Inventory Scanner';
  static const login = 'Login';
  static const register = 'Register';
  static const email = 'Email';
  static const password = 'Password';
  static const name = 'Full Name';
  static const phone = "Phone Number";
  static const post = 'Position/Post';
  static const rememberMe = 'Remember Me';
  static const forgotPassword = 'Forgot Password?';
  static const noAccount = 'Don\'t have an account?';
  static const haveAccount = 'Already have an account';
  static const signUp = 'Sign Up';
  static const loginSuccess = 'Login Successful!';
  static const registerSuccess = 'Registration Successful!';
  static const testMode = 'Test mode';
  static const erpMode = 'ERP Mode';

}
