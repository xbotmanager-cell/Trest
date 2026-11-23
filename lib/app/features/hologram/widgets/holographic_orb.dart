import 'dart:math' as math;
import 'dart:ui' show lerpDouble;
import 'package:material_ui/material_ui.dart';
import 'package:hey_dane/app/core/theme/dane_colors.dart';
import 'package:hey_dane/app/features/hologram/widgets/holographic_d_logo.dart';
import 'package:hey_dane/app/shared/providers/app_state_provider.dart';

/// Gemini Live-inspired circular holographic sound-wave orb.
/// Uses lightweight CustomPainter radial harmonics so low-RAM Android devices
/// sustain fluid 60fps audio-reactive animations.
class HolographicOrb extends StatefulWidget {
  const HolographicOrb({
    super.key,
    required this.state,
    this.audioLevel = 0.0,
    this.size = 220,
    this.onTap,
    this.showCenterCore = true,
  });

  final DaneOrbState state;
  final double audioLevel;
  final double size;
  final VoidCallback? onTap;
  final bool showCenterCore;

  @override
  State<HolographicOrb> createState() => _HolographicOrbState();
}

class _HolographicOrbState extends State<HolographicOrb>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  double _smoothedLevel = 0.0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final targetLevel = widget.audioLevel.clamp(0.0, 1.0);

    return Semantics(
      button: widget.onTap != null,
      label: 'Dane voice orb, status ${widget.state.statusLabel}',
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, _) {
            _smoothedLevel =
                lerpDouble(_smoothedLevel, targetLevel, 0.24) ?? targetLevel;

            final t = _controller.value;
            final baseSpeed = switch (widget.state) {
              DaneOrbState.idle => 0.85,
              DaneOrbState.listening => 1.65 + (_smoothedLevel * 0.9),
              DaneOrbState.thinking => 2.8,
              DaneOrbState.speaking => 2.1 + (_smoothedLevel * 1.1),
              DaneOrbState.error => 0.45,
            };

            final phase = t * math.pi * 2 * baseSpeed;
            final breathingScale = switch (widget.state) {
              DaneOrbState.idle => 0.97 + 0.025 * math.sin(phase),
              DaneOrbState.listening => 0.96 + (_smoothedLevel * 0.11),
              DaneOrbState.thinking => 0.95 + 0.045 * math.sin(phase * 1.5),
              DaneOrbState.speaking =>
                0.97 + (_smoothedLevel * 0.12) + 0.02 * math.sin(phase),
              DaneOrbState.error => 0.98 + 0.015 * math.sin(phase * 2),
            };

            return SizedBox(
              width: widget.size,
              height: widget.size,
              child: Transform.scale(
                scale: breathingScale,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: Size(widget.size, widget.size),
                      painter: _HolographicWaveOrbPainter(
                        phase: phase,
                        state: widget.state,
                        audioLevel: _smoothedLevel,
                      ),
                    ),
                    if (widget.showCenterCore)
                      IgnorePointer(
                        child: Opacity(
                          opacity:
                              widget.state == DaneOrbState.error ? 0.55 : 0.82,
                          child: HolographicDLogo(
                            size: widget.size * 0.34,
                            rotationRadians: -phase * 0.28,
                            glowIntensity: widget.state == DaneOrbState.idle
                                ? 0.65
                                : 0.9 + (_smoothedLevel * 0.1),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HolographicWaveOrbPainter extends CustomPainter {
  const _HolographicWaveOrbPainter({
    required this.phase,
    required this.state,
    required this.audioLevel,
  });

  final double phase;
  final DaneOrbState state;
  final double audioLevel;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.shortestSide * 0.45;

    final (Color primary, Color secondary, Color tertiary) = switch (state) {
      DaneOrbState.idle => (
          DaneColors.cyanCore,
          DaneColors.electricBlue,
          DaneColors.violetPulse,
        ),
      DaneOrbState.listening => (
          DaneColors.cyanCore,
          const Color(0xFF38BDF8),
          DaneColors.electricBlue,
        ),
      DaneOrbState.thinking => (
          DaneColors.violetPulse,
          DaneColors.electricBlue,
          DaneColors.cyanCore,
        ),
      DaneOrbState.speaking => (
          DaneColors.electricBlue,
          DaneColors.cyanCore,
          DaneColors.violetPulse,
        ),
      DaneOrbState.error => (
          DaneColors.alertCrimson,
          DaneColors.cautionAmber,
          DaneColors.alertCrimson,
        ),
    };

    // 1. Soft holographic core field glow (single RadialGradient, zero blur spike)
    final energyBoost = switch (state) {
      DaneOrbState.idle => 0.18,
      DaneOrbState.listening => 0.24 + (audioLevel * 0.20),
      DaneOrbState.thinking => 0.28,
      DaneOrbState.speaking => 0.26 + (audioLevel * 0.22),
      DaneOrbState.error => 0.24,
    };

    final bloomPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          primary.withValues(alpha: energyBoost),
          secondary.withValues(alpha: energyBoost * 0.55),
          tertiary.withValues(alpha: energyBoost * 0.18),
          Colors.transparent,
        ],
        stops: const [0.0, 0.48, 0.78, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: maxRadius * 1.12));
    canvas.drawCircle(center, maxRadius * 1.12, bloomPaint);

    // 2. Translucent spherical glass disc inside orb
    final discPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.25, -0.25),
        colors: [
          DaneColors.surfaceElevated.withValues(alpha: 0.72),
          DaneColors.deepSpace.withValues(alpha: 0.88),
          DaneColors.voidBlack.withValues(alpha: 0.94),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: maxRadius * 0.84));
    canvas.drawCircle(center, maxRadius * 0.84, discPaint);

    // 3. Outer rotating holographic orbital arcs
    final outerBorder = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..color = primary.withValues(alpha: 0.34);
    canvas.drawCircle(center, maxRadius * 0.98, outerBorder);

    final sweepArcPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round
      ..shader = SweepGradient(
        startAngle: phase,
        endAngle: phase + math.pi * 2,
        colors: [
          primary,
          secondary,
          tertiary.withValues(alpha: 0.8),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: maxRadius * 0.92));

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: maxRadius * 0.92),
      phase,
      state == DaneOrbState.thinking ? math.pi * 1.45 : math.pi * 1.15,
      false,
      sweepArcPaint,
    );

    // 4. Internal Gemini-Live-style harmonic sound-wave ribbons
    final waveIntensity = switch (state) {
      DaneOrbState.idle => 0.16,
      DaneOrbState.listening => 0.25 + (audioLevel * 0.75),
      DaneOrbState.thinking => 0.42,
      DaneOrbState.speaking => 0.32 + (audioLevel * 0.68),
      DaneOrbState.error => 0.12,
    };

    _drawHarmonicWaveLoop(
      canvas: canvas,
      center: center,
      baseRadius: maxRadius * 0.68,
      amplitude: maxRadius * 0.11 * waveIntensity,
      harmonics: 5,
      phaseShift: phase,
      strokeWidth: 2.4,
      color: primary.withValues(alpha: 0.92),
    );

    _drawHarmonicWaveLoop(
      canvas: canvas,
      center: center,
      baseRadius: maxRadius * 0.58,
      amplitude: maxRadius * 0.10 * waveIntensity,
      harmonics: 7,
      phaseShift: -phase * 1.25 + 1.1,
      strokeWidth: 1.9,
      color: secondary.withValues(alpha: 0.78),
    );

    _drawHarmonicWaveLoop(
      canvas: canvas,
      center: center,
      baseRadius: maxRadius * 0.48,
      amplitude: maxRadius * 0.08 * waveIntensity,
      harmonics: 3,
      phaseShift: phase * 1.6 + 2.3,
      strokeWidth: 1.5,
      color: tertiary.withValues(alpha: 0.70),
    );

    // 5. Thinking mode orbital energy nodes
    if (state == DaneOrbState.thinking) {
      final nodePaint = Paint()..color = DaneColors.cyanCore;
      for (var i = 0; i < 3; i++) {
        final theta = phase * 1.3 + (i * math.pi * 2 / 3);
        final nodeOffset = Offset(
          center.dx + math.cos(theta) * maxRadius * 0.86,
          center.dy + math.sin(theta) * maxRadius * 0.86,
        );
        canvas.drawCircle(nodeOffset, 3.2, nodePaint);
      }
    }
  }

  void _drawHarmonicWaveLoop({
    required Canvas canvas,
    required Offset center,
    required double baseRadius,
    required double amplitude,
    required int harmonics,
    required double phaseShift,
    required double strokeWidth,
    required Color color,
  }) {
    const sampleCount = 72;
    final path = Path();

    for (var i = 0; i <= sampleCount; i++) {
      final theta = (i / sampleCount) * math.pi * 2;
      final primaryWave = math.sin(theta * harmonics + phaseShift);
      final modulation = math.cos(theta * (harmonics - 2) - phaseShift * 0.7);
      final r =
          baseRadius + amplitude * (0.68 * primaryWave + 0.32 * modulation);
      final x = center.dx + math.cos(theta) * r;
      final y = center.dy + math.sin(theta) * r;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeJoin = StrokeJoin.round
      ..color = color;

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _HolographicWaveOrbPainter oldDelegate) {
    return oldDelegate.phase != phase ||
        oldDelegate.state != state ||
        (oldDelegate.audioLevel - audioLevel).abs() > 0.005;
  }
}
