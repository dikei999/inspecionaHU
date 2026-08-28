import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/constants/app_colors.dart';
import '../core/constants/app_dimensions.dart';

class AppTheme {
  AppTheme._();

  /// Família dos títulos (display/headline/titleLarge/AppBar).
  static const String fontDisplay = 'Sora';

  /// Família do corpo (body, labels, botões, inputs, chips, tabs, nav).
  static const String fontBody = 'Manrope';

  static ThemeData get lightTheme {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
      onPrimary: Colors.white,
      surface: AppColors.surface,
      onSurface: AppColors.textPrimary,
      surfaceContainerHighest: AppColors.background,
      error: AppColors.nonCompliant,
      onError: Colors.white,
      brightness: Brightness.light,
    );

    final textTheme = _buildTextTheme();

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      scaffoldBackgroundColor: AppColors.background,
      fontFamily: fontBody,

      // ── Transições de página suaves (fade-forward Material 3) ─────────────
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
          TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
          TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        },
      ),

      // ── AppBar: fundo branco, sem elevation, ícones azuis ──────────────────
      appBarTheme: const AppBarTheme(
        backgroundColor: AppColors.surface,
        foregroundColor: AppColors.textPrimary,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: Brightness.dark,
        ),
        titleTextStyle: TextStyle(
          fontFamily: fontDisplay,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          letterSpacing: -0.3,
        ),
        iconTheme: IconThemeData(
          color: AppColors.primary,
          size: 24,
        ),
        actionsIconTheme: IconThemeData(
          color: AppColors.primary,
          size: 24,
        ),
        shape: Border(
          bottom: BorderSide(color: AppColors.border, width: 0.5),
        ),
      ),

      // ── Cards: fundo branco, borda fina (sombra via AppShadows nos widgets) ─
      cardTheme: CardThemeData(
        color: AppColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusCard),
          side: const BorderSide(color: AppColors.border, width: AppDimensions.borderWidth),
        ),
        margin: EdgeInsets.zero,
      ),

      // ── Inputs: outlined com label flutuante, foco azul ───────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        labelStyle: const TextStyle(
          fontFamily: fontBody,
          fontSize: 14,
          color: AppColors.textSecondary,
          fontWeight: FontWeight.w400,
        ),
        floatingLabelStyle: const TextStyle(
          fontFamily: fontBody,
          fontSize: 12,
          color: AppColors.primary,
          fontWeight: FontWeight.w500,
        ),
        hintStyle: const TextStyle(
          fontFamily: fontBody,
          fontSize: 14,
          color: AppColors.textDisabled,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusInput),
          borderSide: const BorderSide(color: AppColors.border, width: AppDimensions.borderWidth),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusInput),
          borderSide: const BorderSide(color: AppColors.border, width: AppDimensions.borderWidth),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusInput),
          borderSide: const BorderSide(color: AppColors.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusInput),
          borderSide: const BorderSide(color: AppColors.nonCompliant, width: AppDimensions.borderWidth),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusInput),
          borderSide: const BorderSide(color: AppColors.nonCompliant, width: 1.5),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppDimensions.radiusInput),
          borderSide: const BorderSide(color: AppColors.border, width: AppDimensions.borderWidth),
        ),
        errorStyle: const TextStyle(
          fontFamily: fontBody,
          fontSize: 12,
          color: AppColors.nonCompliant,
        ),
        prefixIconColor: AppColors.textSecondary,
        suffixIconColor: AppColors.textSecondary,
      ),

      // ── ElevatedButton: filled azul, altura 48dp ──────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.border,
          disabledForegroundColor: AppColors.textDisabled,
          // Glow sutil da cor primária nos CTAs (AppShadows.primaryGlow
          // cobre os casos customizados; aqui o equivalente via elevation).
          elevation: 2,
          shadowColor: AppColors.primary.withValues(alpha: 0.35),
          minimumSize: const Size(double.infinity, AppDimensions.buttonHeight),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimensions.radiusButton),
          ),
          textStyle: const TextStyle(
            fontFamily: fontBody,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.1,
          ),
        ),
      ),

      // ── OutlinedButton: borda azul, texto azul ────────────────────────────
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary, width: 1.5),
          minimumSize: const Size(double.infinity, AppDimensions.buttonHeight),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppDimensions.radiusButton),
          ),
          textStyle: const TextStyle(
            fontFamily: fontBody,
            fontSize: 15,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
      ),

      // ── TextButton: texto azul, sem borda ────────────────────────────────
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          minimumSize: const Size(0, 40),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          textStyle: const TextStyle(
            fontFamily: fontBody,
            fontSize: 14,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.1,
          ),
        ),
      ),

      // ── FAB: azul, sem elevation pesada ──────────────────────────────────
      floatingActionButtonTheme: const FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        elevation: 2,
        highlightElevation: 4,
        shape: StadiumBorder(),
      ),

      // ── TabBar: indicador azul, texto seco ───────────────────────────────
      tabBarTheme: const TabBarThemeData(
        labelColor: AppColors.primary,
        unselectedLabelColor: AppColors.textSecondary,
        indicatorColor: AppColors.primary,
        indicatorSize: TabBarIndicatorSize.tab,
        labelStyle: TextStyle(
            fontFamily: fontBody, fontSize: 14, fontWeight: FontWeight.w700),
        unselectedLabelStyle: TextStyle(
            fontFamily: fontBody, fontSize: 14, fontWeight: FontWeight.w500),
        dividerColor: AppColors.border,
      ),

      // ── BottomNavigationBar ───────────────────────────────────────────────
      bottomNavigationBarTheme: const BottomNavigationBarThemeData(
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textSecondary,
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: TextStyle(
            fontFamily: fontBody, fontSize: 12, fontWeight: FontWeight.w700),
        unselectedLabelStyle: TextStyle(
            fontFamily: fontBody, fontSize: 12, fontWeight: FontWeight.w500),
      ),

      // ── SnackBar: arredondado, sem elevation pesada ───────────────────────
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.textPrimary,
        contentTextStyle: const TextStyle(
          fontFamily: fontBody,
          color: Colors.white,
          fontSize: 14,
          fontWeight: FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 4,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      ),

      // ── Divider fino ──────────────────────────────────────────────────────
      dividerTheme: const DividerThemeData(
        color: AppColors.border,
        thickness: AppDimensions.borderWidth,
        space: 0,
      ),

      // ── Chips: status badges arredondados ─────────────────────────────────
      chipTheme: ChipThemeData(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        labelStyle: const TextStyle(
          fontFamily: fontBody,
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
        side: BorderSide.none,
      ),

      // ── Dialog ────────────────────────────────────────────────────────────
      dialogTheme: DialogThemeData(
        backgroundColor: AppColors.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        titleTextStyle: const TextStyle(
          fontFamily: fontDisplay,
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: AppColors.textPrimary,
          letterSpacing: -0.3,
        ),
        contentTextStyle: const TextStyle(
          fontFamily: fontBody,
          fontSize: 14,
          color: AppColors.textSecondary,
          height: 1.5,
        ),
      ),

      // ── ListTile ──────────────────────────────────────────────────────────
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
        minLeadingWidth: 0,
        iconColor: AppColors.primary,
      ),

      // ── CircularProgressIndicator ─────────────────────────────────────────
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: AppColors.primary,
      ),

      // ── PopupMenu ─────────────────────────────────────────────────────────
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surface,
        elevation: 4,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: AppColors.border, width: 0.5),
        ),
        textStyle: const TextStyle(
          fontFamily: fontBody,
          fontSize: 14,
          color: AppColors.textPrimary,
        ),
      ),

      textTheme: textTheme,
    );
  }

  // ── Typography: Sora nos títulos, Manrope no corpo (fontes embutidas) ──────
  static TextTheme _buildTextTheme() {
    TextStyle display(double size, FontWeight weight, Color color,
        {double? height, double? spacing}) {
      return TextStyle(
        fontFamily: fontDisplay,
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: spacing,
      );
    }

    TextStyle body(double size, FontWeight weight, Color color,
        {double? height, double? spacing}) {
      return TextStyle(
        fontFamily: fontBody,
        fontSize: size,
        fontWeight: weight,
        color: color,
        height: height,
        letterSpacing: spacing,
      );
    }

    return TextTheme(
      displayLarge: display(32, FontWeight.w800, AppColors.textPrimary,
          height: 1.2, spacing: -0.8),
      displayMedium: display(28, FontWeight.w800, AppColors.textPrimary,
          height: 1.2, spacing: -0.6),
      headlineLarge: display(24, FontWeight.w800, AppColors.textPrimary,
          height: 1.3, spacing: -0.5),
      headlineMedium: display(22, FontWeight.w800, AppColors.textPrimary,
          height: 1.3, spacing: -0.5),
      headlineSmall: display(18, FontWeight.w700, AppColors.textPrimary,
          height: 1.4, spacing: -0.3),
      titleLarge: display(16, FontWeight.w700, AppColors.textPrimary,
          height: 1.4, spacing: -0.2),
      titleMedium: body(15, FontWeight.w600, AppColors.textPrimary, height: 1.4),
      titleSmall: body(14, FontWeight.w600, AppColors.textPrimary, height: 1.4),
      bodyLarge: body(15, FontWeight.w400, AppColors.textPrimary, height: 1.5),
      bodyMedium:
          body(14, FontWeight.w400, AppColors.textSecondary, height: 1.5),
      bodySmall: body(12, FontWeight.w400, AppColors.textSecondary, height: 1.5),
      labelLarge: body(14, FontWeight.w600, AppColors.textPrimary),
      labelMedium: body(12, FontWeight.w500, AppColors.textSecondary),
      labelSmall: body(11, FontWeight.w500, AppColors.textSecondary),
    );
  }
}
