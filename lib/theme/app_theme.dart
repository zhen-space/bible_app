import 'package:flutter/material.dart';

import '../models/models.dart';

/// 深淺色主題。所有畫面顏色一律透過 Theme 或 [highlightColor] 取得，
/// 不在 widget 裡寫死顏色（深色模式第一天就要對）。
class AppTheme {
  // 配色：淺色＝天空藍底＋黑字＋金圖標；深色＝深藍底＋白字＋金圖標。
  static const _gold = Color(0xFFC9A227); // 金（圖標/強調）
  static const _goldDark = Color(0xFFD8B84A); // 深色模式的金（亮一點）
  static const _ink = Color(0xFF1C1C1E); // 黑字（iOS label 黑）
  static const _skyBg = Color(0xFFEAF4FC); // 天空藍背景（淺）
  static const _skyCard = Color(0xFFFFFFFF); // 白卡片（浮在天空藍上）
  static const _skyContainer = Color(0xFFDCEBFA); // 淺藍容器
  static const _navy = Color(0xFF0A1626); // 深藍底
  static const _navyCard = Color(0xFF13233A); // 深藍卡片
  static const _navyContainer = Color(0xFF1C3350); // 深藍容器

  /// 打包的繁中字型（網頁版不依賴 Google CDN，各平台字型一致）。
  static const _fontFamily = 'NotoSansTC';

  // iOS 風大標題（左對齊、粗體、稍大）。
  static const _titleStyle = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
  );

  static final ThemeData light = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: _gold,
      brightness: Brightness.light,
    ).copyWith(
      primary: _gold, // 圖標/強調＝金
      onPrimary: Colors.white,
      secondary: _gold,
      onSecondary: Colors.white,
      tertiary: _gold,
      surface: _skyCard,
      onSurface: _ink,
      surfaceContainerHighest: _skyContainer,
      surfaceContainerHigh: _skyContainer,
      primaryContainer: _skyContainer,
      onPrimaryContainer: _ink,
    ),
    useMaterial3: true,
    fontFamily: _fontFamily,
    scaffoldBackgroundColor: _skyBg,
    iconTheme: const IconThemeData(color: _gold),
    cardTheme: CardThemeData(
      elevation: 0,
      color: _skyCard,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      margin: EdgeInsets.zero,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: _skyBg,
      foregroundColor: _ink, // 標題黑字
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: _titleStyle,
      iconTheme: IconThemeData(color: _gold), // leading 金
      actionsIconTheme: IconThemeData(color: _gold), // actions 金
    ),
    listTileTheme: const ListTileThemeData(iconColor: _gold),
  );

  static final ThemeData dark = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: _gold,
      brightness: Brightness.dark,
    ).copyWith(
      primary: _goldDark,
      onPrimary: _navy,
      secondary: _goldDark,
      onSecondary: _navy,
      tertiary: _goldDark,
      surface: _navyCard,
      onSurface: Colors.white,
      surfaceContainerHighest: _navyContainer,
      surfaceContainerHigh: _navyContainer,
      primaryContainer: _navyContainer,
      onPrimaryContainer: Colors.white,
    ),
    useMaterial3: true,
    fontFamily: _fontFamily,
    scaffoldBackgroundColor: _navy,
    iconTheme: const IconThemeData(color: _goldDark),
    cardTheme: CardThemeData(
      elevation: 0,
      color: _navyCard,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      margin: EdgeInsets.zero,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: _navy,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: _titleStyle,
      iconTheme: IconThemeData(color: _goldDark),
      actionsIconTheme: IconThemeData(color: _goldDark),
    ),
    listTileTheme: const ListTileThemeData(iconColor: _goldDark),
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
