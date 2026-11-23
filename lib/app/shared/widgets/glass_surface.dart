import 'dart:ui';
import 'package:material_ui/material_ui.dart';
import 'package:hey_dane/app/core/theme/dane_colors.dart';

class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.borderRadius = 20,
    this.borderColor,
    this.backgroundColor,
    this.blurSigma = 14,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final double borderRadius;
  final Color? borderColor;
  final Color? backgroundColor;
  final double blurSigma;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final resolvedBg = backgroundColor ??
        (isDark
            ? DaneColors.surfaceGlass.withValues(alpha: 0.72)
            : DaneColors.surfaceLight.withValues(alpha: 0.88));
    final resolvedBorder = borderColor ??
        (isDark ? DaneColors.borderDark : DaneColors.borderLight);

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: resolvedBg,
            borderRadius: BorderRadius.circular(borderRadius),
            border: Border.all(color: resolvedBorder, width: 1),
          ),
          child: child,
        ),
      ),
    );
  }
}
