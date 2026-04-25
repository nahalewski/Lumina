import 'package:flutter/material.dart';

class SakuraTheme {
  // Colors from DESIGN.md
  static const Color background = Color(0xFF131313);
  static const Color surface = Color(0xFF131313);
  static const Color surfaceBright = Color(0xFF393939);
  static const Color surfaceContainerLow = Color(0xFF1C1B1B);
  static const Color surfaceContainer = Color(0xFF201F1F);
  static const Color surfaceContainerHigh = Color(0xFF2A2A2A);
  
  static const Color primary = Color(0xFFFFDEE3);
  static const Color sakuraPink = Color(0xFFFFB7C5); // The beacon for interaction
  static const Color onPrimary = Color(0xFF50212D);
  static const Color primaryContainer = Color(0xFFFFB7C5);
  static const Color onPrimaryContainer = Color(0xFF7B4551);
  
  static const Color onSurface = Color(0xFFE5E2E1);
  static const Color onSurfaceVariant = Color(0xFFD6C2C4);
  static const Color outline = Color(0xFF9E8C8F);

  static ThemeData get themeData {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: background,
      colorScheme: const ColorScheme.dark(
        primary: sakuraPink,
        onPrimary: onPrimary,
        secondary: Color(0xFFD2C3C5),
        surface: surface,
        onSurface: onSurface,
        onSurfaceVariant: onSurfaceVariant,
        outline: outline,
      ),
      textTheme: const TextTheme(
        displayLarge: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 72,
          fontWeight: FontWeight.w700,
          letterSpacing: -1.44,
          color: onSurface,
        ),
        headlineLarge: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 40,
          fontWeight: FontWeight.w600,
          color: onSurface,
        ),
        headlineMedium: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 32,
          fontWeight: FontWeight.w500,
          color: onSurface,
        ),
        bodyLarge: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 24,
          fontWeight: FontWeight.w400,
          color: onSurface,
        ),
        bodyMedium: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 20,
          fontWeight: FontWeight.w400,
          color: onSurface,
        ),
        labelLarge: TextStyle(
          fontFamily: 'Manrope',
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.9,
          color: onSurface,
        ),
      ),
    );
  }
}
