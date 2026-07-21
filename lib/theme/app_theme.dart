import 'package:flutter/material.dart';

class AppTheme {
  static const Color _seedColor = Color(0xFF1F6E5A); // calm teal-green

  static ThemeData light() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seedColor,
        brightness: Brightness.light,
      ),
      appBarTheme: const AppBarTheme(centerTitle: true),
    );
  }

  static ThemeData dark() {
    return ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        seedColor: _seedColor,
        brightness: Brightness.dark,
      ),
      appBarTheme: const AppBarTheme(centerTitle: true),
    );
  }
}

/// Maps the user's font size preference to an actual Arabic text size in
/// logical pixels, used consistently across the Recitation Screen.
double arabicFontSizeValue(String sizeName) {
  switch (sizeName) {
    case 'small':
      return 26;
    case 'large':
      return 38;
    case 'medium':
    default:
      return 32;
  }
}
