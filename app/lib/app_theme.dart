import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Mi Manitas color palette — matches landing page (mimanitas.me)
class AppColors {
  // Primary navy palette
  static const navyDark = Color(0xFF1E3A5F);
  static const navyLight = Color(0xFF2A4F7A);
  static const navyDarker = Color(0xFF152B47);

  // Accent colors
  static const orange = Color(0xFFE85000);
  static const orangeHover = Color(0xFFC84400);
  static const gold = Color(0xFFFFB700);

  // Backgrounds
  static const background = Color(0xFFF8FAFC);
  static const surface = Colors.white;

  // Derived / utility
  static const navyShadow = Color(0x141E3A5F); // rgba(30,58,95,0.08)
  static const navyShadowElevated = Color(0x241E3A5F); // rgba(30,58,95,0.14)
  static const orangeLight = Color(0xFFFFF0E8);
  static const goldLight = Color(0xFFFFF8E1);
  static const navyVeryLight = Color(0xFFE8EDF3);

  // Semantic status colors
  static const success = Color(0xFF16A34A);
  static const successLight = Color(0xFFDCFCE7);
  static const successBorder = Color(0xFFA7F3D0);

  static const error = Color(0xFFDC2626);
  static const errorLight = Color(0xFFFEE2E2);
  static const errorBorder = Color(0xFFFECACA);

  static const info = Color(0xFF1D4ED8);
  static const infoLight = Color(0xFFDBEAFE);
  static const infoBorder = Color(0xFFBFDBFE);

  static const warning = Color(0xFFD97706);
  static const warningLight = Color(0xFFFFFBEB);

  // Borders & dividers (from landing page CSS)
  static const border = Color(0xFFE2E8F0);
  static const divider = Color(0xFFE5E7EB);

  // Text on dark backgrounds
  static const darkTextPrimary = Colors.white;
  static const darkTextSecondary = Color(0xBFFFFFFF); // 0.75 opacity
  static const darkTextMuted = Color(0xA6FFFFFF); // 0.65 opacity

  // Dark section overlay colors
  static const darkOverlay = Color(0x12FFFFFF); // rgba(255,255,255,0.07)
  static const darkBorder = Color(0x1FFFFFFF); // rgba(255,255,255,0.12)

  // Text
  static const textDark = Color(0xFF1E293B);
  static const textMuted = Color(0xFF64748B);
}

/// Reusable decorations matching landing page shadow/card styles
class AppDecorations {
  static BoxDecoration card({double borderRadius = 16}) => BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: const [
          BoxShadow(
            color: AppColors.navyShadow,
            blurRadius: 16,
            offset: Offset(0, 4),
          ),
        ],
      );

  static BoxDecoration elevatedCard({double borderRadius = 16}) =>
      BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: const [
          BoxShadow(
            color: AppColors.navyShadowElevated,
            blurRadius: 40,
            offset: Offset(0, 8),
          ),
        ],
      );

  static BoxDecoration darkCard({double borderRadius = 16}) => BoxDecoration(
        color: AppColors.darkOverlay,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: AppColors.darkBorder),
      );

  static BoxDecoration badge() => BoxDecoration(
        color: AppColors.gold,
        borderRadius: BorderRadius.circular(20),
      );

  static BoxDecoration statusBanner({
    required Color background,
    required Color border,
    double borderRadius = 8,
  }) =>
      BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(color: border),
      );
}

/// Reusable text styles matching landing page typography
class AppTextStyles {
  static TextStyle sectionTitle() => GoogleFonts.nunito(
        fontSize: 24,
        fontWeight: FontWeight.w800,
        color: AppColors.navyDark,
      );

  static TextStyle cardTitle() => GoogleFonts.nunito(
        fontSize: 17,
        fontWeight: FontWeight.w700,
        color: AppColors.textDark,
      );

  static TextStyle cardSubtitle() => GoogleFonts.inter(
        fontSize: 14,
        color: AppColors.textMuted,
      );

  static TextStyle bodyMuted() => GoogleFonts.inter(
        fontSize: 14,
        color: AppColors.textMuted,
      );

  static TextStyle body() => GoogleFonts.inter(
        fontSize: 14,
        color: AppColors.textDark,
      );

  static TextStyle priceAmount() => GoogleFonts.nunito(
        fontSize: 20,
        fontWeight: FontWeight.w800,
        color: AppColors.navyDark,
      );

  static TextStyle statusLabel({required Color color}) => GoogleFonts.inter(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: color,
      );

  static TextStyle formLabel() => GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.textDark,
      );

  static TextStyle buttonText() => GoogleFonts.nunito(
        fontSize: 16,
        fontWeight: FontWeight.w700,
      );
}

/// Centralized theme for the Mi Manitas app
class AppTheme {
  static ThemeData get lightTheme {
    final nunitoTextTheme = GoogleFonts.nunitoTextTheme();
    final interTextTheme = GoogleFonts.interTextTheme();

    // Merge: Nunito for headings, Inter for body/labels
    final textTheme = interTextTheme.copyWith(
      displayLarge: nunitoTextTheme.displayLarge?.copyWith(color: AppColors.textDark),
      displayMedium: nunitoTextTheme.displayMedium?.copyWith(color: AppColors.textDark),
      displaySmall: nunitoTextTheme.displaySmall?.copyWith(color: AppColors.textDark),
      headlineLarge: nunitoTextTheme.headlineLarge?.copyWith(color: AppColors.textDark),
      headlineMedium: nunitoTextTheme.headlineMedium?.copyWith(color: AppColors.textDark),
      headlineSmall: nunitoTextTheme.headlineSmall?.copyWith(color: AppColors.textDark),
      titleLarge: nunitoTextTheme.titleLarge?.copyWith(color: AppColors.textDark),
      titleMedium: nunitoTextTheme.titleMedium?.copyWith(color: AppColors.textDark),
      titleSmall: nunitoTextTheme.titleSmall?.copyWith(color: AppColors.textDark),
      bodyLarge: interTextTheme.bodyLarge?.copyWith(color: AppColors.textDark),
      bodyMedium: interTextTheme.bodyMedium?.copyWith(color: AppColors.textDark),
      bodySmall: interTextTheme.bodySmall?.copyWith(color: AppColors.textMuted),
      labelLarge: interTextTheme.labelLarge?.copyWith(color: AppColors.textDark),
      labelMedium: interTextTheme.labelMedium?.copyWith(color: AppColors.textMuted),
      labelSmall: interTextTheme.labelSmall?.copyWith(color: AppColors.textMuted),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: AppColors.navyDark,
        brightness: Brightness.light,
        primary: AppColors.navyDark,
        secondary: AppColors.orange,
        tertiary: AppColors.gold,
        surface: AppColors.surface,
      ),
      scaffoldBackgroundColor: AppColors.background,
      textTheme: textTheme,
      dividerColor: AppColors.divider,
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.navyDark,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.orange,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          textStyle: GoogleFonts.nunito(
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.navyDark,
          side: const BorderSide(color: AppColors.navyLight, width: 1.5),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.orange,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.orange, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.error, width: 2),
        ),
        filled: false,
      ),
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.orange,
        foregroundColor: Colors.white,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.navyDark,
      ),
      snackBarTheme: SnackBarThemeData(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        behavior: SnackBarBehavior.floating,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: AppColors.navyVeryLight,
        selectedColor: AppColors.orange,
        labelStyle: GoogleFonts.inter(fontSize: 13),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        side: BorderSide.none,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.orange;
          return null;
        }),
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) return AppColors.orange;
          return null;
        }),
        trackColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.orange.withOpacity(0.5);
          }
          return null;
        }),
      ),
    );
  }
}
