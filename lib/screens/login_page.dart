import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/product_cache_service.dart';
import '../utils/storage.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final hostController = TextEditingController();
  final dbController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  bool onlyPassword = false;
  bool isLoading = false;
  bool _isCaching = false;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    final session = await AuthService.getFullSession();
    if (session != null && session['host'] != null && session['email'] != null) {
      setState(() {
        hostController.text = session['host'] ?? '';
        emailController.text = session['email'] ?? '';
        dbController.text = session['db'] ?? '';
        onlyPassword = true;
      });
    }
  }

  void _resetToFullLogin() {
    setState(() {
      onlyPassword = false;
      passwordController.clear();
    });
  }

  // ✅ Cache products after successful login
  Future<void> _cacheProductsAfterLogin() async {
    if (_isCaching) return;

    setState(() => _isCaching = true);

    try {
      final count = await ProductCacheService.cacheAllProducts();
      print("Cached $count products for offline use");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$count produits chargés pour le mode hors ligne'),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      print("Product caching error: $e");
    } finally {
      if (mounted) {
        setState(() => _isCaching = false);
      }
    }
  }

  void login() async {
    setState(() => isLoading = true);

    try {
      final success = await AuthService.login(
        host: hostController.text.trim(),
        db: dbController.text.trim(),
        email: emailController.text.trim(),
        password: passwordController.text,
      );

      if (success && mounted) {
        // ✅ Cache products in the background
        _cacheProductsAfterLogin();

        Navigator.pushReplacementNamed(context, '/adjustment-entry');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Login failed: ${e.toString()}"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  void secondAuthentication() async {
    setState(() => isLoading = true);

    try {
      final success = await AuthService.secondAuthentication(passwordController.text);

      if (success && mounted) {
        // ✅ Cache products in the background
        _cacheProductsAfterLogin();

        Navigator.pushReplacementNamed(context, '/adjustment-entry');
      } else {
        throw Exception("Invalid password");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Authentication failed: ${e.toString()}"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(height: 60),
                Image.asset(
                  "assets/images/image266622.png",
                  height: 100,
                ),
                const SizedBox(height: 20),
                const Text(
                  "Login here",
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 5),
                const Text(
                  "welcome back",
                  style: TextStyle(color: Colors.grey),
                ),
                const SizedBox(height: 40),

                if (!onlyPassword) ...[
                  _buildTextField(hostController, "Enter URL", "http://your-odoo-server:8069  (sans / à la fin)"),
                  const SizedBox(height: 16),
                  _buildTextField(dbController, "Enter DB name (optional)", "Database name"),
                  const SizedBox(height: 16),
                  _buildTextField(emailController, "Enter email", "admin@example.com", isEmail: true),
                  const SizedBox(height: 16),
                ],

                _buildTextField(passwordController, "Enter Password", "", isPassword: true),

                const SizedBox(height: 30),

                // Loading indicator
                if (_isCaching)
                  const Padding(
                    padding: EdgeInsets.only(bottom: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                        SizedBox(width: 8),
                        Text(
                      "Chargement des produits pour le mode hors ligne...",
                      style: TextStyle(fontSize: 12, color: Colors.blue),
                    ),
                    ],
                  ),
                  ),

                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: isLoading ? null : (onlyPassword ? secondAuthentication : login),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: isLoading
                        ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                        : Text(
                      onlyPassword ? "Login" : "Login",
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                if (onlyPassword)
                  TextButton(
                    onPressed: _resetToFullLogin,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.blue,
                    ),
                    child: const Text(
                      "Retour à la page de connexion",
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField(
      TextEditingController controller,
      String label,
      String hint, {
        bool isPassword = false,
        bool isEmail = false,
      }) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
      ),
      child: TextField(
        controller: controller,
        obscureText: isPassword,
        keyboardType: isEmail ? TextInputType.emailAddress : TextInputType.text,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }
}