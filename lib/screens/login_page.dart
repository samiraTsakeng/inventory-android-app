import 'package:flutter/material.dart';
import '../utils/error_messages.dart';
import '../services/auth_service.dart';
import '../services/offline_prep_service.dart';
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

  // Which fields are asked:
  //  - first connection (no server saved): server, database, email, password;
  //  - server saved: email and password ("Changer de serveur" goes back);
  //  - account saved too: password only ("Changer de compte").
  bool onlyPassword = false;
  bool _hasServer = false;
  bool _editServer = false;
  String _savedName = '';
  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    final saved = await AuthService.getSavedConnection();
    if (!mounted || saved == null) return;
    setState(() {
      hostController.text = saved.host;
      dbController.text = saved.db;
      emailController.text = saved.email;
      _savedName = saved.name;
      _hasServer = true;
      onlyPassword = saved.email.isNotEmpty;
    });
  }

  void _resetToFullLogin() {
    AuthService.forgetAccount();
    setState(() {
      onlyPassword = false;
      emailController.clear();
      passwordController.clear();
    });
  }

  void _changeServer() {
    setState(() {
      onlyPassword = false;
      _editServer = true;
    });
  }

  bool get _showServerFields => !_hasServer || _editServer;

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
        // Prepares offline work in the background.
        OfflinePrepService.prepareAll();

        Navigator.pushReplacementNamed(context, '/adjustment-entry');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError(e)),
            backgroundColor: AppColors.errorColor,
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
        // Prepares offline work in the background.
        OfflinePrepService.prepareAll();

        Navigator.pushReplacementNamed(context, '/adjustment-entry');
      } else {
        throw Exception("Mot de passe incorrect");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(friendlyError(e)),
            backgroundColor: AppColors.errorColor,
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
                    backgroundColor: AppColors.warningColor,
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
                    backgroundColor: AppColors.successColor,
                  ),
                );

              } catch (e) {
                Navigator.pop(context); // Close loading
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(friendlyError(e)),
                    backgroundColor: AppColors.errorColor,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primaryColor,
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
                  "Wise Inventory",
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 5),
                Text(
                  onlyPassword
                      ? "Bonjour ${_savedName.isNotEmpty ? _savedName : emailController.text}, entrez votre mot de passe"
                      : _showServerFields
                          ? "Première connexion : indiquez le serveur Odoo"
                          : "Connectez-vous pour continuer",
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: AppColors.textSecondary),
                ),
                const SizedBox(height: 40),

                if (!onlyPassword && _showServerFields) ...[
                  _buildTextField(hostController, "URL du serveur", "http://your-odoo-server:8069"),
                  const SizedBox(height: 16),
                  _buildTextField(dbController, "Nom de la base (optionnel)", "Nom de la base"),
                  const SizedBox(height: 16),
                ],
                if (!onlyPassword) ...[
                  _buildTextField(emailController, "Email", "admin@example.com", isEmail: true),
                  const SizedBox(height: 16),
                ],

                _buildTextField(passwordController, "Mot de passe", "", isPassword: true),

                const SizedBox(height: 30),


                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton(
                    onPressed: isLoading ? null : (onlyPassword ? secondAuthentication : login),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primaryColor,
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
                      onlyPassword ? "Se connecter" : "Se connecter",
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Forgot Password Link
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    TextButton(
                      onPressed: _showForgotPasswordDialog,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.primaryColor,
                      ),
                      child: const Text(
                        "Mot de passe oublié ?",
                        style: TextStyle(fontSize: 14),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 8),

                if (onlyPassword)
                  TextButton(
                    onPressed: _resetToFullLogin,
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                    ),
                    child: const Text(
                      "Changer de compte",
                      style: TextStyle(fontSize: 14),
                    ),
                  ),
                if (_hasServer && !_showServerFields)
                  TextButton.icon(
                    onPressed: _changeServer,
                    icon: const Icon(Icons.dns_outlined, size: 16),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.textSecondary,
                    ),
                    label: Text(
                      "Serveur : ${hostController.text} · Changer",
                      style: const TextStyle(fontSize: 12),
                      overflow: TextOverflow.ellipsis,
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
        color: AppColors.backgroundColor,
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