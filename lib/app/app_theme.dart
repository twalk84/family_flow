// FILE: lib/app/app_theme.dart
//
// Centralized theme configuration.

import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static ThemeData dark() {
    return ThemeData(
      brightness: Brightness.dark,
      scaffoldBackgroundColor: const Color(0xFF111827),
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.purple,
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    );
  }
}
