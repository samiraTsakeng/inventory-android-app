import 'package:flutter/material.dart';

class AdjustmentEntryPage extends StatefulWidget {
  @override
  _AdjustmentEntryPageState createState() => _AdjustmentEntryPageState();
}

class _AdjustmentEntryPageState extends State<AdjustmentEntryPage> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            // Top bar with back button and logo
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, size: 28),
                    onPressed: () {
                      Navigator.pop(context);
                    },
                  ),
                  // Blue logo placeholder
                  Image.asset(
                    "assets/images/image266622.png",
                    height: 40,
                    errorBuilder: (context, error, stackTrace) =>
                    const Icon(Icons.inventory, size: 40, color: Colors.blue),
                  ),
                ],
              ),
            ),
            const Spacer(),
            // Center icon
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
              "Ajustement de stock",
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
            ),
            const Spacer(),
            // Continue button
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