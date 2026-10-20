import 'package:flutter/material.dart';

// Ops Brain Theme: https://tweakcn.com/themes/cmvgxzn9u000004lb0kzwdnli
// OKLCH -> OKLab -> linear sRGB -> IEC 61966-2-1 sRGB, clamped and rounded
// to 8-bit channels. For example primary (0.5112, .2098, 29.2339) = #c20000.
// Native adapter: white interactive surfaces follow the approved white card-body
// requirement; neutral card token is retained separately. Drawing/export colors
// are domain data and do not inherit this chrome theme.
abstract final class AppColors {
  static const Color red = Color(0xFFC20000);
  static const Color black = Color(0xFF000000);
  static const Color wolfGrey = Color(0xFF6B5959);
  static const Color white = Color(0xFFFFFFFF);
  static const Color background = Color(0xFFE6E6E6);
  static const Color foreground = Color(0xFF121B31);
  static const Color card = Color(0xFFBABABA);
  static const Color secondaryForeground = Color(0xFF403535);
  static const Color accent = Color(0xFF917373);
  static const Color destructive = Color(0xFF750006);
  static const Color input = Color(0xFFFF0000);
}

abstract final class AppAssets {
  static const String hollomanLogo =
      'assets/branding/holloman_exterminators.png';
}

ThemeData buildBugManTheme() {
  const radius = BorderRadius.all(Radius.circular(15.6));
  const border = OutlineInputBorder(
    borderRadius: radius,
    borderSide: BorderSide(color: AppColors.black),
  );
  const colors = ColorScheme.light(
    primary: AppColors.red,
    onPrimary: AppColors.white,
    primaryContainer: AppColors.red,
    onPrimaryContainer: AppColors.white,
    secondary: AppColors.white,
    onSecondary: AppColors.secondaryForeground,
    secondaryContainer: AppColors.background,
    onSecondaryContainer: AppColors.foreground,
    tertiary: AppColors.accent,
    onTertiary: AppColors.white,
    error: AppColors.destructive,
    onError: AppColors.white,
    surface: AppColors.white,
    onSurface: AppColors.foreground,
    onSurfaceVariant: AppColors.secondaryForeground,
    outline: AppColors.black,
    surfaceTint: Colors.transparent,
  );
  final base = ThemeData(
    colorScheme: colors,
    scaffoldBackgroundColor: AppColors.background,
    fontFamily: 'Calistoga',
    useMaterial3: true,
  );
  return base.copyWith(
    // Bitter is the supplied readable serif face for dense forms; Calistoga
    // remains the supplied heading/navigation face. Both are bundled offline.
    textTheme: base.textTheme
        .copyWith(
          bodyLarge: base.textTheme.bodyLarge?.copyWith(fontFamily: 'Bitter'),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(fontFamily: 'Bitter'),
          bodySmall: base.textTheme.bodySmall?.copyWith(fontFamily: 'Bitter'),
        )
        .apply(
          bodyColor: AppColors.foreground,
          displayColor: AppColors.foreground,
        ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.red,
      foregroundColor: AppColors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    cardTheme: const CardThemeData(
      color: AppColors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: AppColors.black),
      ),
    ),
    dividerColor: AppColors.black,
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.red,
      foregroundColor: AppColors.white,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.red,
        foregroundColor: AppColors.white,
        shape: const RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.red,
        foregroundColor: AppColors.white,
        shape: const RoundedRectangleBorder(borderRadius: radius),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.red,
      indicatorColor: AppColors.white,
      iconTheme: WidgetStateProperty.resolveWith((states) => IconThemeData(
        color: states.contains(WidgetState.selected) ? AppColors.red : AppColors.white,
      )),
      labelTextStyle: WidgetStateProperty.all(const TextStyle(color: AppColors.white, fontFamily: 'Calistoga')),
    ),
    drawerTheme: const DrawerThemeData(backgroundColor: AppColors.background),
    inputDecorationTheme: const InputDecorationTheme(
      border: border,
      enabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: AppColors.input, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: AppColors.destructive),
      ),
      filled: true,
      fillColor: AppColors.white,
    ),
  );
}
