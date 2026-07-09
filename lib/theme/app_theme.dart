import 'package:flutter/material.dart';

import '../models/models.dart';

/// 深淺色主題。所有畫面顏色一律透過 Theme 或 [highlightColor] 取得，
/// 不在 widget 裡寫死顏色（深色模式第一天就要對）。
class AppTheme {
  // 配色：淺色＝白底＋藍＋金＋黑字；深色＝深藍底＋白字＋金。
  static const _blue = Color(0xFF1565C0); // 主色藍
  static const _blueLight = Color(0xFF7FB0E8); // 深色模式的亮藍
  static const _gold = Color(0xFFC9A227); // 金（強調）
  static const _goldDark = Color(0xFFD4AF37); // 深色模式的金
  static const _ink = Color(0xFF1A1A1A); // 黑字
  static const _navy = Color(0xFF0B1D33); // 深藍底
  static const _navySurface = Color(0xFF10243D); // 深藍卡片

  /// 打包的繁中字型（網頁版不依賴 Google CDN，各平台字型一致）。
  static const _fontFamily = 'NotoSansTC';

  static final ThemeData light = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: _blue,
      brightness: Brightness.light,
    ).copyWith(
      primary: _blue,
      onPrimary: Colors.white,
      secondary: _gold,
      onSecondary: Colors.white,
      tertiary: _gold,
      onTertiary: Colors.white,
      surface: Colors.white,
      onSurface: _ink,
    ),
    useMaterial3: true,
    fontFamily: _fontFamily,
    scaffoldBackgroundColor: Colors.white,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: _ink,
      elevation: 0,
      scrolledUnderElevation: 1,
    ),
  );

  static final ThemeData dark = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: _blue,
      brightness: Brightness.dark,
    ).copyWith(
      primary: _blueLight,
      onPrimary: _navy,
      secondary: _goldDark,
      onSecondary: _navy,
      tertiary: _goldDark,
      surface: _navySurface,
      onSurface: Colors.white,
    ),
    useMaterial3: true,
    fontFamily: _fontFamily,
    scaffoldBackgroundColor: _navy,
    appBarTheme: const AppBarTheme(
      backgroundColor: _navy,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 1,
    ),
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
