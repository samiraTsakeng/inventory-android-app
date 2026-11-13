import 'package:flutter/material.dart';

// Wise logo of the title bars. The logo is a navy disc, the same color as
// the bars: it sits on a white ring so it stays visible on every screen
// (navy bars, the black scanning bar, the brand gradient).
class AppLogo extends StatelessWidget {
  final double size;
  final EdgeInsetsGeometry padding;

  const AppLogo({
    super.key,
    this.size = 32,
    this.padding = const EdgeInsets.only(right: 12, left: 4),
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding,
      child: Center(
        child: Container(
          width: size,
          height: size,
          padding: const EdgeInsets.all(2),
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 4,
                offset: Offset(0, 1),
              ),
            ],
          ),
          child: ClipOval(
            child: Image.asset(
              "assets/images/image266622.png",
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => const Icon(
                Icons.inventory_2,
                color: Color(0xFF03045A),
                size: 18,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
