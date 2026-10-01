import 'package:flutter/material.dart';

/// Central theme. Contrast and touch-target sizing follow SPEC 6.11
/// accessibility requirements (sufficient contrast, large touch targets).
///
/// Home uses a dark glassmorphism shell (neon green accents on deep emerald
/// blacks). Other flows still use [light]/[dark] Material themes.
class AppTheme {
  AppTheme._();

  static const fontFamily = 'ChakraPetch';

  /// Neon mint — active tabs, tool icons, primary FAB glow.
  static const accent = Color(0xFF3DFF8A);
  static const accentDeep = Color(0xFF1DBF5A);
  static const accentGlowColor = Color(0x663DFF8A);

  static const homeBackground = Color(0xFF07140F);
  static const homeCard = Color(0xCC12241C);
  static const homeCardElevated = Color(0xE6182E24);
  static const homeText = Color(0xFFF2FFF7);
  static const homeMuted = Color(0xFF8FA89A);
  static const homeHairline = Color(0x33A7FFC8);
  static const homeIcon = Color(0xFFE8FFF0);
  static const homeDock = Color(0xE60C1A14);
  static const homeIconWell = Color(0x3318FF7A);

  /// Deep black → emerald wash used behind the home glass layers.
  static const homeGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFF050D0A),
      Color(0xFF0A1F16),
      Color(0xFF04110C),
      Color(0xFF0E281C),
    ],
    stops: [0.0, 0.35, 0.7, 1.0],
  );

  static List<BoxShadow> get cardShadow => const [
    BoxShadow(color: Color(0x66000000), blurRadius: 24, offset: Offset(0, 12)),
    BoxShadow(color: Color(0x223DFF8A), blurRadius: 18, offset: Offset(0, 0)),
  ];

  static List<BoxShadow> get accentGlow => const [
    BoxShadow(
      color: Color(0x883DFF8A),
      blurRadius: 22,
      offset: Offset(0, 6),
      spreadRadius: 1,
    ),
    BoxShadow(
      color: Color(0x443DFF8A),
      blurRadius: 40,
      offset: Offset.zero,
      spreadRadius: 2,
    ),
  ];

  static List<BoxShadow> get glassBorderGlow => const [
    BoxShadow(
      color: Color(0x223DFF8A),
      blurRadius: 12,
      offset: Offset.zero,
    ),
  ];

  /// Material theme used by the home shell (dark glass + neon accent).
  static ThemeData homeShell() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: fontFamily,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.dark,
        surface: homeBackground,
        primary: accent,
        onPrimary: const Color(0xFF04140C),
        onSurface: homeText,
      ),
    );
    return base.copyWith(
      scaffoldBackgroundColor: homeBackground,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: homeText,
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      textTheme: base.textTheme.apply(
        fontFamily: fontFamily,
        bodyColor: homeText,
        displayColor: homeText,
      ),
      primaryTextTheme: base.primaryTextTheme.apply(
        fontFamily: fontFamily,
        bodyColor: homeText,
        displayColor: homeText,
      ),
      dividerColor: homeHairline,
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
      iconButtonTheme: IconButtonThemeData(
        style: IconButton.styleFrom(
          foregroundColor: homeIcon,
          backgroundColor: Colors.transparent,
          shape: const CircleBorder(),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
      ),
      cardTheme: const CardThemeData(
        color: homeCard,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          side: BorderSide(color: homeHairline),
        ),
      ),
      dialogTheme: const DialogThemeData(
        backgroundColor: homeCardElevated,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: Color(0xFF10241C),
        surfaceTintColor: Colors.transparent,
      ),
    );
  }

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: fontFamily,
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF2FBF71),
        brightness: Brightness.light,
        surface: const Color(0xFFF4F8F4),
        primary: const Color(0xFF2FBF71),
      ),
    );
    return base.copyWith(
      scaffoldBackgroundColor: const Color(0xFFF4F8F4),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFF4F8F4),
        foregroundColor: Color(0xFF171C19),
        elevation: 0,
        scrolledUnderElevation: 0,
      ),
      textTheme: base.textTheme.apply(
        fontFamily: fontFamily,
        bodyColor: const Color(0xFF171C19),
        displayColor: const Color(0xFF171C19),
      ),
      primaryTextTheme: base.primaryTextTheme.apply(
        fontFamily: fontFamily,
        bodyColor: const Color(0xFF171C19),
        displayColor: const Color(0xFF171C19),
      ),
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
  }

  static ThemeData dark() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      fontFamily: fontFamily,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.dark,
        surface: const Color(0xFF0E0E10),
        primary: accent,
      ),
    );
    return base.copyWith(
      scaffoldBackgroundColor: const Color(0xFF0E0E10),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF0E0E10),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      textTheme: base.textTheme.apply(fontFamily: fontFamily),
      primaryTextTheme: base.primaryTextTheme.apply(fontFamily: fontFamily),
      visualDensity: VisualDensity.standard,
      materialTapTargetSize: MaterialTapTargetSize.padded,
    );
  }
}
