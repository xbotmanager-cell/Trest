import 'package:material_ui/material_ui.dart';
import 'package:hey_dane/app/core/theme/dane_colors.dart';

class DaneTheme {
  DaneTheme._();

  static ThemeData get darkTheme {
    const colorScheme = ColorScheme.dark(
      primary: DaneColors.cyanCore,
      onPrimary: DaneColors.voidBlack,
      secondary: DaneColors.electricBlue,
      onSecondary: Colors.white,
      tertiary: DaneColors.violetPulse,
      onTertiary: Colors.white,
      surface: DaneColors.deepSpace,
      onSurface: DaneColors.textPrimaryDark,
      error: DaneColors.alertCrimson,
      onError: Colors.white,
      outline: DaneColors.borderDark,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: DaneColors.voidBlack,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: DaneColors.textPrimaryDark,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        ),
      ),
      cardTheme: CardThemeData(
        color: DaneColors.surfaceGlass.withValues(alpha: 0.78),
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: DaneColors.borderDark, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: DaneColors.surfaceGlass.withValues(alpha: 0.85),
        hintStyle: const TextStyle(color: DaneColors.textSecondaryDark),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: DaneColors.borderDark),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: DaneColors.borderDark),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: DaneColors.cyanCore, width: 1.5),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: DaneColors.deepSpace.withValues(alpha: 0.94),
        indicatorColor: DaneColors.cyanCore.withValues(alpha: 0.16),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: DaneColors.cyanCore, size: 22);
          }
          return const IconThemeData(
              color: DaneColors.textSecondaryDark, size: 22);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              color: DaneColors.cyanCore,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            );
          }
          return const TextStyle(
            color: DaneColors.textSecondaryDark,
            fontSize: 11,
            fontWeight: FontWeight.w500,
          );
        }),
      ),
    );
  }

  static ThemeData get lightTheme {
    const colorScheme = ColorScheme.light(
      primary: DaneColors.electricBlueDeep,
      onPrimary: Colors.white,
      secondary: DaneColors.cyanDeep,
      onSecondary: Colors.white,
      tertiary: DaneColors.violetPulse,
      onTertiary: Colors.white,
      surface: DaneColors.surfaceLight,
      onSurface: DaneColors.textPrimaryLight,
      error: DaneColors.alertCrimson,
      onError: Colors.white,
      outline: DaneColors.borderLight,
    );

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: DaneColors.cloudCanvas,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: DaneColors.textPrimaryLight,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: DaneColors.surfaceLight,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: const BorderSide(color: DaneColors.borderLight, width: 1),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: DaneColors.surfaceLight,
        hintStyle: const TextStyle(color: DaneColors.textSecondaryLight),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: DaneColors.borderLight),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: DaneColors.borderLight),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide:
              const BorderSide(color: DaneColors.electricBlueDeep, width: 1.5),
        ),
      ),
    );
  }
}
