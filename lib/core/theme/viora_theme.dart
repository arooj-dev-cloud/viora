import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

abstract final class VioraColors {
  static const blush = Color(0xFFF5D5E0);
  static const lavender = Color(0xFF6667AB);
  static const mauve = Color(0xFF7B337E);
  static const plum = Color(0xFF420D4B);
  static const midnight = Color(0xFF210635);
  static const charcoal = Color(0xFF1E202C);
  static const secondary = Color(0xFF31323E);
  static const silver = Color(0xFFBFC0D1);
}

abstract final class VioraTheme {
  static ThemeData get dark => ThemeData(
    brightness: Brightness.dark,
    textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
    splashFactory: InkSparkle.splashFactory,
    visualDensity: VisualDensity.standard,
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.white.withValues(alpha: .06),
      selectedColor: VioraColors.mauve,
      side: BorderSide(color: Colors.white.withValues(alpha: .10)),
      labelStyle: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      showCheckmark: false,
      padding: const EdgeInsets.symmetric(horizontal: 6),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: VioraColors.mauve,
      foregroundColor: Colors.white,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: VioraColors.silver,
      subtitleTextStyle: TextStyle(color: VioraColors.silver, fontSize: 13),
    ),
    dividerTheme: DividerThemeData(
      color: Colors.white.withValues(alpha: .08),
      space: 1,
    ),
    progressIndicatorTheme: const ProgressIndicatorThemeData(
      color: VioraColors.blush,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected)
            ? Colors.white
            : VioraColors.silver,
      ),
      trackColor: WidgetStateProperty.resolveWith(
            (s) => s.contains(WidgetState.selected)
            ? VioraColors.mauve
            : Colors.white.withValues(alpha: .12),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: const Color(0xFF2A1740),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    scaffoldBackgroundColor: VioraColors.midnight,
    colorScheme: const ColorScheme.dark(
      primary: VioraColors.blush,
      secondary: VioraColors.lavender,
      surface: VioraColors.charcoal,
    ),
    useMaterial3: true,
    appBarTheme: const AppBarTheme(
      backgroundColor: VioraColors.midnight,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w800,
        letterSpacing: -.4,
        color: Colors.white,
      ),
    ),
    cardTheme: CardThemeData(
      color: const Color(0xFF2A1740),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: const Color(0xFF2A1740),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: Color(0xFF24132F),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xFF3A1F55),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: VioraColors.mauve,
        foregroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 14),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white.withValues(alpha: .07),
      hintStyle: const TextStyle(color: VioraColors.silver),
      contentPadding:
      const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: .18)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(18),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: .18)),
      ),
    ),
  );
}