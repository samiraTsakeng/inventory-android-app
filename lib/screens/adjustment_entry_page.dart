import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import '../utils/constants.dart';

class AdjustmentEntryPage extends StatefulWidget {
  const AdjustmentEntryPage({super.key});

  @override
  State<AdjustmentEntryPage> createState() => _AdjustmentEntryPageState();
}

class _AdjustmentEntryPageState extends State<AdjustmentEntryPage> {
  bool _isHovered = false;
  bool _isChecking = true;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    final session = await AuthService.getSession();
    if (session == null) {
      // No session, redirect to login
      if (mounted) {
        Navigator.pushReplacementNamed(context, '/');
      }
    }
    if (mounted) {
      setState(() => _isChecking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isChecking) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.backgroundColor,
      appBar: AppBar(
        title: const Text("Ajustement de stock", style: TextStyle(fontSize: 18)),
        centerTitle: true,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, size: 22),
            onPressed: () {
              Scaffold.of(context).openDrawer();
            },
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Image.asset(
              "assets/images/image266622.png",
              height: 30,
              errorBuilder: (context, error, stackTrace) =>
              const Icon(Icons.inventory, color: Colors.white, size: 24),
            ),
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(20, 50, 20, 20),
              decoration: const BoxDecoration(gradient: AppColors.brandGradient),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.asset(
                      "assets/images/image266622.png",
                      height: 42,
                      width: 42,
                      errorBuilder: (context, error, stackTrace) =>
                      const Icon(Icons.inventory, color: Colors.white),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Wise Inventory',
                    style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.inventory_2_outlined, color: AppColors.primaryColor),
              title: const Text('Ajustement de stock'),
              onTap: () {
                Navigator.pop(context);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: AppColors.errorColor),
              title: const Text('Déconnexion', style: TextStyle(color: AppColors.errorColor)),
              onTap: () {
                AuthService.clearSession();
                Navigator.pushReplacementNamed(context, '/');
              },
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),
            MouseRegion(
              onEnter: (_) => setState(() => _isHovered = true),
              onExit: (_) => setState(() => _isHovered = false),
              child: GestureDetector(
                onTap: () {
                  Navigator.pushNamed(context, '/adjustments-list');
                },
                child: AnimatedScale(
                  scale: _isHovered ? 1.06 : 1.0,
                  duration: const Duration(milliseconds: 150),
                  child: Container(
                    padding: const EdgeInsets.all(28),
                    decoration: BoxDecoration(
                      color: AppColors.primaryColor.withOpacity(0.06),
                      shape: BoxShape.circle,
                    ),
                    child: Image.asset(
                      "assets/images/2037740.png",
                      height: 120,
                      errorBuilder: (context, error, stackTrace) =>
                      const Icon(Icons.inventory, size: 120, color: AppColors.primaryColor),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              "Inventaire",
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: AppColors.textColor),
            ),
            const SizedBox(height: 6),
            const Text(
              "Gérez vos ajustements de stock en quelques taps",
              style: TextStyle(fontSize: 13.5, color: AppColors.textSecondary),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: () {
                    Navigator.pushNamed(context, '/adjustments-list');
                  },
                  icon: const Icon(Icons.arrow_forward, size: 20),
                  label: const Text("Continuer", style: TextStyle(fontSize: 16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}