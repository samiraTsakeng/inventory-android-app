import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../utils/constants.dart';

/// First-connection page used to configure the Odoo server once.
///
/// After a successful configuration/login, only the server URL and database
/// are kept for future connections. The normal LoginPage then asks only for
/// email and password.
class FirstConnectionPage extends StatefulWidget {
  const FirstConnectionPage({super.key});

  @override
  State<FirstConnectionPage> createState() => _FirstConnectionPageState();
}

class _FirstConnectionPageState extends State<FirstConnectionPage> {
  final hostController = TextEditingController();
  final dbController = TextEditingController();
  final emailController = TextEditingController();
  final passwordController = TextEditingController();
  final confirmPasswordController = TextEditingController();

  bool isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadSavedConnection();
  }

  Future<void> _loadSavedConnection() async {
    final connection = await AuthService.getSavedConnection();
    if (!mounted || connection == null) return;

    hostController.text = connection['host'] ?? '';
    dbController.text = connection['db'] ?? '';
  }

  Future<void> _continue() async {
    final host = hostController.text.trim();
    final db = dbController.text.trim();
    final email = emailController.text.trim();
    final password = passwordController.text;
    final confirmPassword = confirmPasswordController.text;

    if (host.isEmpty || email.isEmpty || password.isEmpty || confirmPassword.isEmpty) {
      _showMessage('Veuillez remplir tous les champs obligatoires.', AppColors.warningColor);
      return;
    }

    if (!host.startsWith('http://') && !host.startsWith('https://')) {
      _showMessage(
        'L\'URL du serveur doit commencer par http:// ou https://.',
        AppColors.warningColor,
      );
      return;
    }

    if (password != confirmPassword) {
      _showMessage('Les mots de passe ne correspondent pas.', AppColors.warningColor);
      return;
    }

    setState(() => isLoading = true);

    try {
      // Remove the previous authenticated session, while keeping the
      // connection information that the user is configuring below.
      await AuthService.clearSession();

      final success = await AuthService.login(
        host: host,
        db: db,
        email: email,
        password: password,
      );

      if (success && mounted) {
        Navigator.pushNamedAndRemoveUntil(
          context,
          '/adjustment-entry',
              (route) => false,
        );
      } else if (mounted) {
        _showMessage('Échec de la connexion.', AppColors.errorColor);
      }
    } catch (e) {
      if (mounted) {
        _showMessage('Erreur de connexion : ${e.toString()}', AppColors.errorColor);
      }
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _showMessage(String message, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: color),
    );
  }

  @override
  void dispose() {
    hostController.dispose();
    dbController.dispose();
    emailController.dispose();
    passwordController.dispose();
    confirmPasswordController.dispose();
    super.dispose();
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
                        'assets/images/image266622.png',
                        height: 72,
                        width: 72,
                      ),
                    ),
                    const SizedBox(height: 18),
                    const Text(
                      'Wise Inventory',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Première connexion',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.85),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 24),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Text(
                          'Configurer votre connexion',
                          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Ces informations permettent à l’application de se connecter à votre serveur Odoo. Le serveur et la base seront mémorisés pour les prochaines connexions.',
                          style: TextStyle(
                            fontSize: 12.5,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 20),
                        _buildTextField(
                          hostController,
                          'URL du serveur *',
                          'http://your-odoo-server:8069',
                          icon: Icons.dns_outlined,
                        ),
                        const SizedBox(height: 14),
                        _buildTextField(
                          dbController,
                          'Nom de la base (optionnel)',
                          'Nom de la base',
                          icon: Icons.storage_outlined,
                        ),
                        const SizedBox(height: 14),
                        _buildTextField(
                          emailController,
                          'Email *',
                          'admin@example.com',
                          isEmail: true,
                          icon: Icons.email_outlined,
                        ),
                        const SizedBox(height: 14),
                        _buildTextField(
                          passwordController,
                          'Mot de passe *',
                          '',
                          isPassword: true,
                          icon: Icons.lock_outline,
                        ),
                        const SizedBox(height: 14),
                        _buildTextField(
                          confirmPasswordController,
                          'Confirmer le mot de passe *',
                          '',
                          isPassword: true,
                          icon: Icons.lock_outline,
                        ),
                        const SizedBox(height: 22),
                        SizedBox(
                          height: 52,
                          child: ElevatedButton(
                            onPressed: isLoading ? null : _continue,
                            child: isLoading
                                ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                                : const Text('Se connecter'),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Center(
                          child: TextButton(
                            onPressed: isLoading ? null : () => Navigator.pop(context),
                            child: const Text('Retour à la connexion'),
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
        prefixIcon: icon != null
            ? Icon(icon, color: AppColors.textSecondary, size: 20)
            : null,
      ),
    );
  }
}
