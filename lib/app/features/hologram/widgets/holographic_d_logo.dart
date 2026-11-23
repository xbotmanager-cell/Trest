import 'dart:math' as math;
import 'package:material_ui/material_ui.dart';
import 'package:hey_dane/app/core/theme/dane_colors.dart';

/// Futuristic holographic "D" emblem without any embedded text.
class HolographicDLogo extends StatelessWidget {
  const HolographicDLogo({
    super.key,
    this.size = 96,
    this.rotationRadians = 0,
    this.glowIntensity = 0.85,
  });

  final double size;
  final double rotationRadians;
  final double glowIntensity;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _HolographicDPainter(
          rotationRadians: rotationRadians,
          glowIntensity: glowIntensity,
        ),
      ),
    );
  }
}

class _HolographicDPainter extends CustomPainter {
  const _HolographicDPainter({
    required this.rotationRadians,
    required this.glowIntensity,
  });

  final double rotationRadians;
  final double glowIntensity;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide * 0.44;

    // Outer orbital arc
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.032
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: rotationRadians,
        endAngle: rotationRadians + math.pi * 2,
        colors: [
          DaneColors.cyanCore.withValues(alpha: 0.95),
          DaneColors.electricBlue.withValues(alpha: 0.6),
          DaneColors.violetPulse.withValues(alpha: 0.85),
          DaneColors.cyanCore.withValues(alpha: 0.15),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      rotationRadians,
      math.pi * 1.68,
      false,
      ringPaint,
    );

    // Subtle radial halo
    final haloPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          DaneColors.cyanCore.withValues(alpha: 0.22 * glowIntensity),
          DaneColors.violetPulse.withValues(alpha: 0.08 * glowIntensity),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius * 1.15));
    canvas.drawCircle(center, radius * 1.15, haloPaint);

    // Geometric holographic "D" symbol
    final dWidth = size.shortestSide * 0.42;
    final dHeight = size.shortestSide * 0.50;
    final left = center.dx - dWidth * 0.44;
    final top = center.dy - dHeight * 0.5;
    final right = left + dWidth;
    final bottom = top + dHeight;

    final dPath = Path()
      ..moveTo(left, top)
      ..lineTo(left + dWidth * 0.46, top)
      ..cubicTo(
        right + dWidth * 0.12,
        top,
        right + dWidth * 0.12,
        bottom,
        left + dWidth * 0.46,
        bottom,
      )
      ..lineTo(left, bottom)
      ..close();

    final dStrokePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.058
      ..strokeJoin = StrokeJoin.round
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          DaneColors.cyanCore,
          DaneColors.electricBlue,
          DaneColors.violetPulse,
        ],
      ).createShader(Rect.fromLTRB(left, top, right, bottom));

    canvas.drawPath(dPath, dStrokePaint);

    // Inner core facet accent inside the D stem
    final stemGlow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.shortestSide * 0.025
      ..strokeCap = StrokeCap.round
      ..color = DaneColors.cyanCore.withValues(alpha: 0.9);
    canvas.drawLine(
      Offset(left + dWidth * 0.18, top + dHeight * 0.24),
      Offset(left + dWidth * 0.18, bottom - dHeight * 0.24),
      stemGlow,
    );
  }

  @override
  bool shouldRepaint(covariant _HolographicDPainter oldDelegate) {
    return oldDelegate.rotationRadians != rotationRadians ||
        oldDelegate.glowIntensity != glowIntensity;
  }
}
