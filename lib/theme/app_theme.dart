import 'package:flutter/material.dart';

import '../models/models.dart';

/// 深淺色主題。所有畫面顏色一律透過 Theme 或 [highlightColor] 取得，
/// 不在 widget 裡寫死顏色（深色模式第一天就要對）。
class AppTheme {
  static const _seed = Color(0xFF6D4C41); // 溫暖的棕色，讀經氛圍

  static ThemeData light = ThemeData(
    colorScheme: ColorScheme.fromSeed(seedColor: _seed),
    useMaterial3: true,
    scaffoldBackgroundColor: const Color(0xFFFDFBF7),
  );

  static ThemeData dark = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: Brightness.dark,
    ),
    useMaterial3: true,
  );

  /// 螢光筆顏色（深淺色各一組，不寫死單一色）。
  static Color highlightColor(HighlightColor c, bool isDark) {
    switch (c) {
      case HighlightColor.yellow:
        return isDark ? const Color(0x59FFEB3B) : const Color(0x66FFF176);
      case HighlightColor.green:
        return isDark ? const Color(0x594CAF50) : const Color(0x66A5D6A7);
      case HighlightColor.blue:
        return isDark ? const Color(0x592196F3) : const Color(0x6690CAF9);
      case HighlightColor.pink:
        return isDark ? const Color(0x59E91E63) : const Color(0x66F48FB1);
      case HighlightColor.orange:
        return isDark ? const Color(0x59FF9800) : const Color(0x66FFCC80);
    }
  }

  /// 螢光筆選色器上顯示的實色。
  static Color highlightSwatch(HighlightColor c) {
    switch (c) {
      case HighlightColor.yellow:
        return const Color(0xFFFDD835);
      case HighlightColor.green:
        return const Color(0xFF66BB6A);
      case HighlightColor.blue:
        return const Color(0xFF42A5F5);
      case HighlightColor.pink:
        return const Color(0xFFEC407A);
      case HighlightColor.orange:
        return const Color(0xFFFFA726);
    }
  }
}
