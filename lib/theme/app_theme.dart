import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: AppColors.background,
      colorScheme: const ColorScheme.dark(
        primary: AppColors.primary,
        onPrimary: AppColors.onPrimary,
        primaryContainer: AppColors.primaryContainer,
        onPrimaryContainer: AppColors.onPrimaryContainer,
        secondary: AppColors.secondary,
        onSecondary: AppColors.onSecondary,
        secondaryContainer: AppColors.secondaryContainer,
        onSecondaryContainer: AppColors.onSecondaryContainer,
        tertiary: AppColors.tertiary,
        onTertiary: AppColors.onTertiary,
        tertiaryContainer: AppColors.tertiaryContainer,
        onTertiaryContainer: AppColors.onTertiaryContainer,
        error: AppColors.error,
        onError: AppColors.onError,
        errorContainer: AppColors.errorContainer,
        onErrorContainer: AppColors.onErrorContainer,
        surface: AppColors.surface,
        onSurface: AppColors.onSurface,
        onSurfaceVariant: AppColors.onSurfaceVariant,
        outline: AppColors.outline,
        outlineVariant: AppColors.outlineVariant,
        inverseSurface: AppColors.inverseSurface,
        onInverseSurface: AppColors.inverseOnSurface,
        inversePrimary: AppColors.inversePrimary,
      ),
      textTheme: _buildTextTheme(),
      fontFamily: 'Plus Jakarta Sans',
    );
  }

  static TextTheme _buildTextTheme() {
    final plusJakarta = GoogleFonts.plusJakartaSansTextTheme();
    final playfair = GoogleFonts.playfairDisplayTextTheme();

    return TextTheme(
      // Display
      displayLarge: playfair.displayLarge?.copyWith(
        fontSize: 36, fontWeight: FontWeight.w600,
        color: AppColors.onSurface, letterSpacing: -0.02,
      ),
      displayMedium: playfair.displayMedium?.copyWith(
        fontSize: 32, fontWeight: FontWeight.w600,
        color: AppColors.onSurface,
      ),
      displaySmall: playfair.displaySmall?.copyWith(
        fontSize: 28, fontWeight: FontWeight.w600,
        color: AppColors.onSurface,
      ),

      // Headlines
      headlineLarge: playfair.headlineLarge?.copyWith(
        fontSize: 28, fontWeight: FontWeight.w600,
        color: AppColors.onSurface,
      ),
      headlineMedium: playfair.headlineMedium?.copyWith(
        fontSize: 22, fontWeight: FontWeight.w500,
        color: AppColors.onSurface,
      ),
      headlineSmall: playfair.headlineSmall?.copyWith(
        fontSize: 18, fontWeight: FontWeight.w500,
        color: AppColors.onSurface,
      ),

      // Titles
      titleLarge: plusJakarta.titleLarge?.copyWith(
        fontSize: 20, fontWeight: FontWeight.w700,
        color: AppColors.onSurface,
      ),
      titleMedium: plusJakarta.titleMedium?.copyWith(
        fontSize: 16, fontWeight: FontWeight.w600,
        color: AppColors.onSurface,
      ),
      titleSmall: plusJakarta.titleSmall?.copyWith(
        fontSize: 14, fontWeight: FontWeight.w600,
        color: AppColors.onSurface,
      ),

      // Body
      bodyLarge: plusJakarta.bodyLarge?.copyWith(
        fontSize: 16, fontWeight: FontWeight.w400,
        color: AppColors.onSurface,
      ),
      bodyMedium: plusJakarta.bodyMedium?.copyWith(
        fontSize: 14, fontWeight: FontWeight.w400,
        color: AppColors.onSurface,
      ),
      bodySmall: plusJakarta.bodySmall?.copyWith(
        fontSize: 12, fontWeight: FontWeight.w400,
        color: AppColors.onSurfaceVariant,
      ),

      // Labels
      labelLarge: plusJakarta.labelLarge?.copyWith(
        fontSize: 14, fontWeight: FontWeight.w600,
        color: AppColors.onSurface, letterSpacing: 0.03,
      ),
      labelMedium: plusJakarta.labelMedium?.copyWith(
        fontSize: 12, fontWeight: FontWeight.w600,
        color: AppColors.onSurface, letterSpacing: 0.05,
      ),
      labelSmall: plusJakarta.labelSmall?.copyWith(
        fontSize: 10, fontWeight: FontWeight.w600,
        color: AppColors.onSurfaceVariant, letterSpacing: 0.05,
      ),
    );
  }

  // ── Reusable Decorations ──
  static BoxDecoration get cardDecoration => BoxDecoration(
    color: AppColors.surfaceContainer.withValues(alpha: 0.85),
    borderRadius: BorderRadius.circular(24),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.5),
        blurRadius: 28,
        offset: const Offset(0, 12),
      ),
    ],
  );

  static BoxDecoration get primaryGlowCard => BoxDecoration(
    color: AppColors.surfaceContainerLow.withValues(alpha: 0.9),
    borderRadius: BorderRadius.circular(24),
    boxShadow: [
      BoxShadow(
        color: Colors.black.withValues(alpha: 0.6),
        blurRadius: 36,
        offset: const Offset(0, 16),
      ),
    ],
  );

  static BoxDecoration get gradientButton => BoxDecoration(
    gradient: const LinearGradient(
      colors: [AppColors.secondaryFixedDim, AppColors.secondary],
    ),
    borderRadius: BorderRadius.circular(999),
    boxShadow: [
      BoxShadow(
        color: AppColors.secondary.withValues(alpha: 0.4),
        blurRadius: 24,
      ),
    ],
  );

  static BorderRadius get smallRadius => BorderRadius.circular(16);
  static BorderRadius get mediumRadius => BorderRadius.circular(24);
  static BorderRadius get largeRadius => BorderRadius.circular(32);
  static BorderRadius get pillRadius => BorderRadius.circular(999);
}
