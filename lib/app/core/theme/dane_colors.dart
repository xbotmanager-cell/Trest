import 'package:flutter/material.dart';

class DaneColors {
  DaneColors._();

  // Core Holographic Palette (Dark Mode)
  static const Color voidBlack = Color(0xFF050814);
  static const Color deepSpace = Color(0xFF0A1026);
  static const Color surfaceGlass = Color(0xFF101836);
  static const Color surfaceElevated = Color(0xFF162044);

  // Holographic Accents
  static const Color cyanCore = Color(0xFF00E5FF);
  static const Color electricBlue = Color(0xFF2979FF);
  static const Color violetPulse = Color(0xFF7C4DFF);

  // Semantic Status
  static const Color nominalGreen = Color(0xFF10B981);
  static const Color cautionAmber = Color(0xFFF59E0B);
  static const Color alertCrimson = Color(0xFFEF4444);

  // Typography (Dark)
  static const Color textPrimaryDark = Color(0xFFF0F6FF);
  static const Color textSecondaryDark = Color(0xFF94A3B8);
  static const Color borderDark = Color(0x2E00E5FF);

  // Light Mode Counterparts
  static const Color cloudCanvas = Color(0xFFF4F7FB);
  static const Color surfaceLight = Color(0xFFFFFFFF);
  static const Color surfaceLightMuted = Color(0xFFEAF0F8);
  static const Color cyanDeep = Color(0xFF0088A3);
  static const Color electricBlueDeep = Color(0xFF1D4ED8);
  static const Color textPrimaryLight = Color(0xFF0B1224);
  static const Color textSecondaryLight = Color(0xFF475569);
  static const Color borderLight = Color(0x1F0B1224);

  static const LinearGradient holographicGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [cyanCore, electricBlue, violetPulse],
  );
}
