import 'package:flutter/material.dart';

/// Central theme. Contrast and touch-target sizing follow SPEC 6.11
/// accessibility requirements (sufficient contrast, large touch targets).
class AppTheme {
  AppTheme._();

  static ThemeData light() => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF2D5D8A)),
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
  );

  static ThemeData dark() => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF2D5D8A),
      brightness: Brightness.dark,
    ),
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
  );
}
