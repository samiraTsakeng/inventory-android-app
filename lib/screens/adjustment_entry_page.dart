import 'package:flutter/material.dart';
import '../services/auth_service.dart';

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
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Ajustement de stock", style: TextStyle(fontSize: 18)),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
        elevation: 0,
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
            const DrawerHeader(
              decoration: BoxDecoration(color: Colors.blue),
              child: Text(
                'Wise Inventory',
                style: TextStyle(color: Colors.white, fontSize: 24),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.inventory),
              title: const Text('Ajustement de stock'),
              onTap: () {
                Navigator.pop(context);
              },
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: const Text('Déconnexion', style: TextStyle(color: Colors.red)),
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
                child: Transform.scale(
                  scale: _isHovered ? 1.1 : 1.0,
                  child: Image.asset(
                    "assets/images/2037740.png",
                    height: 140,
                    errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.inventory, size: 140, color: Colors.blue),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              "Inventaire",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.all(20),
              child: SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: () {
                    Navigator.pushNamed(context, '/adjustments-list');
                  },
                  child: const Text("Continuer", style: TextStyle(fontSize: 16)),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}