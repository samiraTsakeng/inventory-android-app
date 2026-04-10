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
      backgroundColor: Colors.grey[200],

      body: SafeArea(
        child: Column(
          children: [

            // 🔙 Back button
            Align(
              alignment: Alignment.topLeft,
              child: IconButton(
                icon: Icon(Icons.arrow_back),
                onPressed: () {
                  Navigator.pop(context);
                },
              ),
            ),

            Spacer(),

            // 🔵 YOUR ICON HERE
            MouseRegion(
              onEnter: (_) => setState(() => _isHovered = true),
              onExit: (_) => setState(() => _isHovered = false),
              child: GestureDetector(
                onTap: () {
                  Navigator.pushNamed(context, '/adjustments-list');
                },
                child: Transform.scale(
                  scale: _isHovered ? 1.2 : 1.0,
                  child: Image.asset(
                    "assets/images/2037740.png", // replace with your real path
                    height: 120,
                  ),
                ),
              ),
            ),

            SizedBox(height: 20),

            Text(
              "Ajustement de stock",
              style: TextStyle(fontSize: 16),
            ),

            Spacer(),

            Padding(
              padding: EdgeInsets.all(20),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  minimumSize: Size(double.infinity, 50),
                ),
                onPressed: () {
                  // next page (we will build next)
                },
                child: Text("Continuer"),
              ),
            )
          ],
        ),
      ),
    );
  }
}