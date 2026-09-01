import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/auth_service.dart';
import '../services/product_cache_service.dart';
import '../utils/storage.dart';
import '../utils/constants.dart';

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

  //  Cache products after successful login
  Future<void> _cacheProductsAfterLogin() async {
    if (_isCaching) return;

    setState(() => _isCaching = true);

    try {
      final count = await ProductCacheService.cacheAllProducts();
      print("Cached $count products for offline use");

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(' $count produits chargés pour le mode hors ligne'),
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
        // Cache products in the background
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
        // Cache products in the background
        _cacheProductsAfterLogin();

        Navigator.pushReplacementNamed(context, '/adjustment-entry');
      } else {
        throw Exception("Invalid password");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(" Authentication failed: ${e.toString()}"),
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

  // Forgot Password Dialog
  void _showForgotPasswordDialog() {
    final TextEditingController emailController = TextEditingController();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text(
          "Réinitialiser le mot de passe",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              "Entrez votre email pour recevoir un lien de réinitialisation:",
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: emailController,
              decoration: const InputDecoration(
                labelText: "Email",
                hintText: "admin@example.com",
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.email),
              ),
              keyboardType: TextInputType.emailAddress,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Annuler"),
          ),
          ElevatedButton(
            onPressed: () async {
              final email = emailController.text.trim();

              if (email.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Veuillez entrer votre email'),
                    backgroundColor: Colors.orange,
                  ),
                );
                return;
              }

              // Show loading
              showDialog(
                context: context,
                barrierDismissible: false,
                builder: (context) => const Center(child: CircularProgressIndicator()),
              );

              try {
                // TODO: Implement actual password reset API call
                // For now, simulate API call
                await Future.delayed(const Duration(seconds: 2));

                Navigator.pop(context); // Close loading
                Navigator.pop(context); // Close dialog

                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Un lien de réinitialisation a été envoyé à votre email'),
                    backgroundColor: Colors.green,
                  ),
                );

              } catch (e) {
                Navigator.pop(context); // Close loading
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Erreur: ${e.toString()}'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.blue,
              foregroundColor: Colors.white,
            ),
            child: const Text("Envoyer"),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.backgroundColor,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Hero de marque
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(24, 36, 24, 40),
                decoration: const BoxDecoration(gradient: AppColors.brandGradient),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.15),
                            blurRadius: 16,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Image.asset(
                        "assets/images/image266622.png",
                        height: 72,
                        width: 72,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      "Wise Inventory",
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.2,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      onlyPassword
                          ? "Ravi de vous revoir"
                          : "Connectez-vous pour continuer",
                      style: TextStyle(color: Colors.white.withOpacity(0.85), fontSize: 14),
                    ),
                  ],
                ),
              ),

              // Carte de connexion
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (onlyPassword) ...[
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 18,
                                backgroundColor: AppColors.primaryColor.withOpacity(0.1),
                                child: const Icon(Icons.person, color: AppColors.primaryColor, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      emailController.text,
                                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                    Text(
                                      hostController.text,
                                      style: const TextStyle(color: AppColors.textSecondary, fontSize: 12),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 20),
                        ] else ...[
                          _buildTextField(hostController, "URL du serveur", "http://your-odoo-server:8069",
                              icon: Icons.dns_outlined),
                          const SizedBox(height: 14),
                          _buildTextField(dbController, "Nom de la base (optionnel)", "Nom de la base",
                              icon: Icons.storage_outlined),
                          const SizedBox(height: 14),
                          _buildTextField(emailController, "Email", "admin@example.com",
                              isEmail: true, icon: Icons.email_outlined),
                          const SizedBox(height: 14),
                        ],

                        _buildTextField(passwordController, "Mot de passe", "",
                            isPassword: true, icon: Icons.lock_outline),

                        const SizedBox(height: 22),

                        // Loading indicator
                        if (_isCaching)
                          const Padding(
                            padding: EdgeInsets.only(bottom: 12),
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
                                  "Chargement des produits...",
                                  style: TextStyle(fontSize: 12, color: AppColors.secondaryColor),
                                ),
                              ],
                            ),
                          ),

                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: isLoading ? null : (onlyPassword ? secondAuthentication : login),
                            child: isLoading
                                ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                                : const Text("Se connecter"),
                          ),
                        ),

                        const SizedBox(height: 10),

                        // Forgot Password Link
                        Center(
                          child: TextButton(
                            onPressed: _showForgotPasswordDialog,
                            child: const Text("Mot de passe oublié ?"),
                          ),
                        ),

                        if (onlyPassword)
                          Center(
                            child: TextButton(
                              onPressed: _resetToFullLogin,
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.textSecondary,
                              ),
                              child: const Text("Changer de compte"),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
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
        IconData? icon,
      }) {
    return TextField(
      controller: controller,
      obscureText: isPassword,
      keyboardType: isEmail ? TextInputType.emailAddress : TextInputType.text,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        prefixIcon: icon != null ? Icon(icon, color: AppColors.textSecondary, size: 20) : null,
      ),
    );
  }
}