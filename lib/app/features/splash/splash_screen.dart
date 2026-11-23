import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';
import 'package:hey_dane/app/core/constants/app_identity.dart';
import 'package:hey_dane/app/core/theme/dane_colors.dart';
import 'package:hey_dane/app/features/hologram/widgets/holographic_d_logo.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  Timer? _navigationTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..forward();

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );

    _navigationTimer = Timer(const Duration(milliseconds: 1900), () {
      if (mounted) {
        context.go('/assistant');
      }
    });
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.15),
            radius: 1.1,
            colors: [
              DaneColors.deepSpace,
              DaneColors.voidBlack,
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedBuilder(
                    animation: _controller,
                    builder: (context, _) {
                      return HolographicDLogo(
                        size: 132,
                        rotationRadians: _controller.value * 1.4,
                        glowIntensity: _controller.value,
                      );
                    },
                  ),
                  const SizedBox(height: 28),
                  const Text(
                    AppIdentity.appName,
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 4.0,
                      color: DaneColors.textPrimaryDark,
                    ),
                  ),
                  const SizedBox(height: 10),
                  const Text(
                    AppIdentity.tagline,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w400,
                      letterSpacing: 0.6,
                      color: DaneColors.cyanCore,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
