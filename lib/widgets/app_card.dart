import 'package:flutter/material.dart';
import '../utils/constants.dart';

// The single card of the app: white surface, same radius, border and soft
// shadow on every screen. [accentColor] draws a thin status stripe on the
// left (sheet / adjustment state); [onTap] adds the ripple.
class AppCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? accentColor;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;
  final Color? borderColor;

  const AppCard({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.accentColor,
    this.padding = const EdgeInsets.all(14),
    this.margin = EdgeInsets.zero,
    this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppDecor.cardRadius);
    Widget content = Padding(padding: padding, child: child);
    if (accentColor != null) {
      content = IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: accentColor),
            Expanded(child: content),
          ],
        ),
      );
    }

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: AppColors.surfaceColor,
        borderRadius: radius,
        border: Border.all(color: borderColor ?? AppColors.borderColor),
        boxShadow: AppDecor.cardShadow,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(onTap: onTap, onLongPress: onLongPress, child: content),
      ),
    );
  }
}

// Small colored label (status, count...), same on every screen.
class AppBadge extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;

  const AppBadge({
    super.key,
    required this.text,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppDecor.badgeRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
