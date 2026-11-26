import 'package:flutter/material.dart';

/// Tokens calqués sur le POS web (`frontend/src/styles.css`).
class PosColors {
  static const bg = Color(0xFFF4F5F7);
  static const surface = Color(0xFFFFFFFF);
  static const sidebar = Color(0xFF0F172A);
  static const ink = Color(0xFF0F172A);
  static const muted = Color(0xFF64748B);
  static const accent = Color(0xFFD97706);
  static const pos = Color(0xFFEEF0F4);
  static const danger = Color(0xFFDC2626);
  static const success = Color(0xFF16A34A);
  static const warning = Color(0xFFEA580C);
  static const info = Color(0xFF2563EB);
  static const progress = Color(0xFF4F46E5);
  static const paid = Color(0xFF166534);
  static const line = Color(0xFFE2E8F0);
}

ThemeData buildPosTheme() {
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: PosColors.accent,
      primary: PosColors.accent,
      surface: PosColors.surface,
      brightness: Brightness.light,
    ),
    scaffoldBackgroundColor: PosColors.pos,
    fontFamily: 'Roboto',
  );

  return base.copyWith(
    appBarTheme: const AppBarTheme(
      backgroundColor: PosColors.sidebar,
      foregroundColor: Colors.white,
      elevation: 0,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: PosColors.accent,
        foregroundColor: Colors.white,
        minimumSize: const Size(48, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Colors.white,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: PosColors.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: PosColors.line),
      ),
    ),
    cardTheme: CardThemeData(
      color: PosColors.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: PosColors.line),
      ),
    ),
  );
}
