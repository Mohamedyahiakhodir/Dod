import 'package:flutter/material.dart';

class C {
  static const bg = Color(0xFF0B0B0F);
  static const surface = Color(0xFF15151B);
  static const surface2 = Color(0xFF1E1E26);
  static const surface3 = Color(0xFF292932);
  static const line = Color(0x14FFFFFF);
  static const text = Color(0xFFF4F4F7);
  static const muted = Color(0xFF8D8D9A);
  static const accent = Color(0xFF25F4EE);
  static const accentInk = Color(0xFF00201F);
  static const rec = Color(0xFFFE2C55);
  static const ok = Color(0xFF34D399);
  static const warn = Color(0xFFFFB020);
  static const bad = Color(0xFFFF453A);
}

ThemeData buildTheme() {
  final base = ThemeData.dark(useMaterial3: true);
  return base.copyWith(
    scaffoldBackgroundColor: C.bg,
    colorScheme: const ColorScheme.dark(primary: C.accent, onPrimary: C.accentInk, surface: C.surface, onSurface: C.text, secondary: C.rec),
    canvasColor: C.surface,
    dividerColor: C.line,
    splashFactory: InkSparkle.splashFactory,
    textTheme: base.textTheme.apply(bodyColor: C.text, displayColor: C.text),
    sliderTheme: SliderThemeData(
      trackHeight: 5,
      activeTrackColor: C.accent,
      inactiveTrackColor: C.surface3,
      thumbColor: Colors.white,
      overlayColor: C.accent.withValues(alpha: 0.15),
      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 11),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? C.accentInk : Colors.white),
      trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? C.accent : C.surface3),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: const Color(0xF2282830),
      contentTextStyle: const TextStyle(color: C.text),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: C.surface2,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
    ),
  );
}
