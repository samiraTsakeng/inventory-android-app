import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../services/product_cache_service.dart';
import '../utils/constants.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final emailController = TextEditingController();
  final passwordController = TextEditingController();

  String _host = '';
  String _db = '';
  bool _hasSavedConnection = false;
  bool isLoading = false;
  bool _isCaching = false;

  @override
  void initState() {
    super.initState();
    _loadSavedConnection();
  }

  Future<void> _loadSavedConnection() async {
    final connection = await AuthService.getSavedConnection();

    if (!mounted) return;

    setState(() {
      _host = connection?['host'] ?? '';
      _db = connection?['db'] ?? '';
      _hasSavedConnection = _host.isNotEmpty;
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
      if (!_hasSavedConnection || _host.isEmpty) {
        throw Exception("Aucune configuration serveur enregistrée. Utilisez le lien de première connexion.");
      }

      final email = emailController.text.trim();
      final password = passwordController.text;

      if (email.isEmpty || password.isEmpty) {
        throw Exception("Veuillez renseigner votre email et votre mot de passe.");
      }

      final success = await AuthService.login(
        host: _host,
        db: _db,
        email: email,
        password: password,
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
                      "Connectez-vous pour continuer",
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
                        _buildTextField(
                          emailController,
                          "Email",
                          "admin@example.com",
                          isEmail: true,
                          icon: Icons.email_outlined,
                        ),
                        const SizedBox(height: 14),
                        _buildTextField(passwordController, "Mot de passe", "",
                            isPassword: true, icon: Icons.lock_outline),

                        if (!_hasSavedConnection) ...[
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: AppColors.warningColor.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: AppColors.warningColor.withOpacity(0.25),
                              ),
                            ),
                            child: const Text(
                              "Pour une première connexion, configurez d'abord le serveur et la base de données via le lien ci-dessous.",
                              style: TextStyle(fontSize: 12.5),
                            ),
                          ),
                        ],

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
                            onPressed: isLoading ? null : login,
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

                        Center(
                          child: TextButton.icon(
                            onPressed: () async {
                              await Navigator.pushNamed(context, '/register');
                              await _loadSavedConnection();
                            },
                            icon: const Icon(Icons.person_add_outlined, size: 18),
                            label: const Text("Première connexion / Créer un compte"),
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