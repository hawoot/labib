import 'package:flutter/material.dart';

import 'theme/tokens.dart';

export 'theme/tokens.dart' show brandSeed, Space, Radii, Motion, StatusPalette;

/// One place that defines how labib looks. Every screen inherits this, so the
/// app reads as one product instead of default-Material screens.
///
/// Personality: **sharp & modern** with a violet accent — tight radii, crisp
/// hairlines, restrained colour, high-contrast type. See tokens.dart and
/// attrape-tout/design/native-app-design-language.md.
ThemeData labibTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: brandSeed,
    brightness: brightness,
    // Sharpen: a near-black canvas in dark, near-white in light.
    surface: dark ? const Color(0xFF0E0E12) : const Color(0xFFFAFAFC),
  );
  final base = ThemeData(useMaterial3: true, colorScheme: scheme);
  final hairline = scheme.outlineVariant.withValues(alpha: dark ? 0.6 : 0.7);

  return base.copyWith(
    scaffoldBackgroundColor: scheme.surface,
    splashFactory: InkSparkle.splashFactory,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: dark ? const Color(0xFF17171D) : Colors.white,
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radii.card),
        side: BorderSide(color: hairline),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.xs),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF1C1C24) : const Color(0xFFF1F1F6),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.control),
        borderSide: BorderSide.none,
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.control),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radii.control),
        borderSide: BorderSide(color: scheme.primary, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: Space.xl, vertical: Space.md + 2),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.control)),
        textStyle: const TextStyle(
            fontWeight: FontWeight.w600, fontSize: 15, letterSpacing: -0.1),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: Space.lg + 2, vertical: Space.md + 2),
        side: BorderSide(color: hairline),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(Radii.control)),
        textStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        textStyle: const TextStyle(fontWeight: FontWeight.w600),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      elevation: 1,
      highlightElevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.control)),
    ),
    chipTheme: base.chipTheme.copyWith(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.chip)),
      side: BorderSide.none,
      labelStyle: const TextStyle(
          fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.1),
      padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: 2),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: scheme.surface,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radii.sheet)),
      ),
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.card + 4)),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.control)),
    ),
    dividerTheme: DividerThemeData(color: hairline, space: 1, thickness: 1),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: scheme.surface,
      elevation: 0,
      height: 64,
      indicatorColor: scheme.primary.withValues(alpha: 0.14),
      labelTextStyle: WidgetStateProperty.all(
        const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
    ),
    textTheme: base.textTheme.copyWith(
      headlineMedium: base.textTheme.headlineMedium
          ?.copyWith(fontWeight: FontWeight.w800, letterSpacing: -0.8),
      headlineSmall: base.textTheme.headlineSmall
          ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.5),
      titleLarge: base.textTheme.titleLarge
          ?.copyWith(fontWeight: FontWeight.w700, letterSpacing: -0.3),
      titleMedium: base.textTheme.titleMedium
          ?.copyWith(fontWeight: FontWeight.w600, letterSpacing: -0.1),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.4),
    ),
  );
}
