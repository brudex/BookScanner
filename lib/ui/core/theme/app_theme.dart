import 'package:flutter/material.dart';

/// Central theme. Contrast and touch-target sizing follow SPEC 6.11
/// accessibility requirements (sufficient contrast, large touch targets).
class AppTheme {
  AppTheme._();

  static const fontFamily = 'ChakraPetch';
  static const accent = Color(0xFF2FBF71);
  static const accentDeep = Color(0xFF1F8F54);
  static const homeBackground = Color(0xFFF4F8F4);
  static const homeCard = Color(0xFFFFFFFF);
  static const homeCardElevated = Color(0xFFFFFFFF);
  static const homeText = Color(0xFF171C19);
  static const homeMuted = Color(0xFF6F786F);
  static const homeHairline = Color(0xFFE4EBE4);
  static const homeIcon = Color(0xFF1A1F1C);
  static const homeDock = Color(0xFFFFFFFF);
  static const homeIconWell = Color(0xFFF1F5F1);

  static const homeGradient = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0xFFE7F6EC), Color(0xFFF6F7F2), Color(0xFFF3F5F8)],
  );

  static List<BoxShadow> get cardShadow => const [
    BoxShadow(color: Color(0x12001820), blurRadius: 18, offset: Offset(0, 8)),
    BoxShadow(color: Color(0x08001820), blurRadius: 4, offset: Offset(0, 1)),
  ];

  static List<BoxShadow> get accentGlow => const [
    BoxShadow(color: Color(0x332FBF71), blurRadius: 18, offset: Offset(0, 8)),
  ];

  static ThemeData light() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      fontFamily: fontFamily,
      colorScheme: ColorScheme.fromSeed(
        seedColor: accent,
        brightness: Brightness.light,
        surface: homeBackground,
        primary: accent,
      ),
    );
    return base.copyWith(
      scaffoldBackgroundColor: homeBackground,
      appBarTheme: const AppBarTheme(
        backgroundColor: homeBackground,
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
