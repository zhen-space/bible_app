import 'package:flutter/material.dart';

import '../models/models.dart';

/// 深淺色主題。所有畫面顏色一律透過 Theme 或 [highlightColor] 取得，
/// 不在 widget 裡寫死顏色（深色模式第一天就要對）。
class AppTheme {
  // 品牌藍（使用者指定）：淺藍 #0086CC、深藍 #005B98。
  // 配色：淺色＝白底＋黑字＋金圖標＋藍強調；深色＝深藍底＋白字＋金圖標。
  static const _blue = Color(0xFF0086CC); // 淺藍（主色）
  static const _blueDeep = Color(0xFF005B98); // 深藍
  static const _blueOnDark = Color(0xFF3EA8E5); // 深色模式用的亮藍
  static const _gold = Color(0xFFC9A227); // 金（圖標）
  static const _goldDark = Color(0xFFD8B84A); // 深色模式的金
  static const _ink = Color(0xFF1C1C1E); // 黑字
  static const _cardBorder = Color(0xFFE4E8EE); // 白卡片在白底上的細邊
  static const _greyContainer = Color(0xFFEEF3F7); // 淺灰藍容器（章節格等）
  static const _navy = Color(0xFF071726); // 深藍底
  static const _navyCard = Color(0xFF0E2438); // 深藍卡片
  static const _navyContainer = Color(0xFF16324B); // 深藍容器

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
      seedColor: _blue,
      brightness: Brightness.light,
    ).copyWith(
      primary: _blue, // 強調藍
      onPrimary: Colors.white,
      secondary: _gold,
      onSecondary: Colors.white,
      tertiary: _gold,
      surface: Colors.white,
      onSurface: _ink,
      surfaceContainerHighest: _greyContainer,
      surfaceContainerHigh: _greyContainer,
      primaryContainer: _blue, // 強調卡（今日經文/導讀方格）＝實心藍
      onPrimaryContainer: Colors.white,
    ),
    useMaterial3: true,
    fontFamily: _fontFamily,
    scaffoldBackgroundColor: Colors.white,
    iconTheme: const IconThemeData(color: _gold),
    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: _cardBorder),
      ),
      margin: EdgeInsets.zero,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: _ink, // 標題黑字
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: _titleStyle,
      iconTheme: IconThemeData(color: _gold), // leading 金
      actionsIconTheme: IconThemeData(color: _gold), // actions 金
    ),
    listTileTheme: const ListTileThemeData(iconColor: _gold),
    dividerTheme: const DividerThemeData(color: _cardBorder, thickness: 1),
  );

  static final ThemeData dark = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: _blue,
      brightness: Brightness.dark,
    ).copyWith(
      primary: _blueOnDark,
      onPrimary: _navy,
      secondary: _goldDark,
      onSecondary: _navy,
      tertiary: _goldDark,
      surface: _navyCard,
      onSurface: Colors.white,
      surfaceContainerHighest: _navyContainer,
      surfaceContainerHigh: _navyContainer,
      primaryContainer: _blueDeep, // 強調卡＝深藍
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
