import 'package:flutter/material.dart';

/// Veniamin dark theme — user palette
const _bg = Color(0xFF1E1E1E);
const _surface = Color(0xFF252526);
const _border = Color(0xFF3C3C3C);
const _accent = Color(0xFF007C42);
const _text = Color(0xFFD4D4D4);
const _dim = Color(0xFF808080);
const _yellow = Color(0xFFD29922);
const _red = Color(0xFFF85149);
const _blue = Color(0xFF58A6FF);
const _purple = Color(0xFFA371F7);

final veniaminTheme = ThemeData(
  brightness: Brightness.dark,
  scaffoldBackgroundColor: _bg,
  primaryColor: _accent,
  colorScheme: const ColorScheme.dark(
    primary: _accent,
    secondary: _blue,
    surface: _surface,
    error: _red,
    onPrimary: _text,
    onSecondary: _bg,
    onSurface: _text,
    onError: _text,
  ),
  fontFamily: 'JetBrains Mono',
  fontFamilyFallback: const [
    'Fira Code',
    'Cascadia Code',
    'Consolas',
    'monospace',
  ],
  textTheme: const TextTheme(
    bodyLarge: TextStyle(color: _text, fontSize: 14, height: 1.4),
    bodyMedium: TextStyle(color: _text, fontSize: 13, height: 1.4),
    bodySmall: TextStyle(color: _dim, fontSize: 12, height: 1.3),
    titleLarge: TextStyle(
      color: _accent,
      fontSize: 18,
      fontWeight: FontWeight.w600,
    ),
    titleMedium: TextStyle(
      color: _blue,
      fontSize: 15,
      fontWeight: FontWeight.w500,
    ),
    labelLarge: TextStyle(
      color: _text,
      fontSize: 13,
      fontWeight: FontWeight.w500,
    ),
  ),
  inputDecorationTheme: InputDecorationTheme(
    filled: true,
    fillColor: _surface,
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: const BorderSide(color: _border),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: const BorderSide(color: _border),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(4),
      borderSide: const BorderSide(color: _accent, width: 1.5),
    ),
    hintStyle: const TextStyle(color: _dim),
    labelStyle: const TextStyle(color: _dim),
  ),
  elevatedButtonTheme: ElevatedButtonThemeData(
    style: ElevatedButton.styleFrom(
      backgroundColor: _accent,
      foregroundColor: _text,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      textStyle: const TextStyle(
        fontFamily: 'JetBrains Mono',
        fontWeight: FontWeight.w600,
      ),
    ),
  ),
  outlinedButtonTheme: OutlinedButtonThemeData(
    style: OutlinedButton.styleFrom(
      foregroundColor: _blue,
      side: const BorderSide(color: _border),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    ),
  ),
  appBarTheme: const AppBarTheme(
    backgroundColor: _surface,
    elevation: 0,
    titleTextStyle: TextStyle(
      color: _accent,
      fontSize: 16,
      fontWeight: FontWeight.w600,
      fontFamily: 'JetBrains Mono',
    ),
    iconTheme: IconThemeData(color: _text),
  ),
  dividerColor: _border,
  cardColor: _surface,
);

class VColors {
  static const bg = _bg;
  static const surface = _surface;
  static const border = _border;
  static const accent = _accent;
  static const green = _accent;
  static const blue = _blue;
  static const yellow = _yellow;
  static const red = _red;
  static const purple = _purple;
  static const text = _text;
  static const dim = _dim;
  static const system = _dim;
}
