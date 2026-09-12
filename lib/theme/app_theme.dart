import 'package:flutter/material.dart';

import '../models/models.dart';

class AppTheme {
  static const _bluePale = Color(0xFF8AC4DE);
  static const _blueMid = Color(0xFF6C9BD2);
  static const _blue = Color(0xFF0086CC);
  static const _blueDeep = Color(0xFF005B98);
  static const _blueOnDark = Color(0xFF6C9BD2);
  static const _gold = Color(0xFFC9A227);
  static const _goldDark = Color(0xFFD8B84A);
  static const _ink = Color(0xFF1C1C1E);
  static const _separator = Color(0xFFE5E5EA);
  static const _field = Color(0xFFF4F5F7);
  static const _blueContainer = Color(0xFFE4F0F8);
  static const _navy = Color(0xFF071726);
  static const _navyCard = Color(0xFF0E2438);
  static const _navyContainer = Color(0xFF16324B);

  static const brandGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [_blue, _blueDeep],
  );

  static const accentBlue = _blueMid;
  static const paleBlue = _bluePale;
  static const _fontFamily = 'NotoSansTC';

  static const _titleStyle = TextStyle(
    fontFamily: _fontFamily,
    fontSize: 20,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
  );

  static InputDecorationTheme _inputTheme(Color fill, Color outline) =>
      InputDecorationTheme(
        filled: true,
        fillColor: fill,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: outline, width: 1.3),
        ),
      );

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
      surface: Colors.white,
      onSurface: _ink,
      surfaceContainerHighest: _blueContainer,
      surfaceContainerHigh: _blueContainer,
      primaryContainer: _blue,
      onPrimaryContainer: Colors.white,
    ),
    useMaterial3: true,
    fontFamily: _fontFamily,
    scaffoldBackgroundColor: Colors.white,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    iconTheme: const IconThemeData(color: _gold),
    cardTheme: CardThemeData(
      elevation: 0,
      color: Colors.white,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: EdgeInsets.zero,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.white,
      foregroundColor: _ink,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: _titleStyle.copyWith(color: _ink),
      iconTheme: const IconThemeData(color: _gold),
      actionsIconTheme: const IconThemeData(color: _gold),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: _gold,
      contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 3),
      minVerticalPadding: 10,
      minLeadingWidth: 28,
      titleTextStyle: TextStyle(
        fontFamily: _fontFamily,
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: _ink,
      ),
      subtitleTextStyle: TextStyle(
        fontFamily: _fontFamily,
        fontSize: 13,
        color: Color(0xFF6E6E73),
      ),
    ),
    inputDecorationTheme: _inputTheme(_field, _blue),
    dividerTheme: const DividerThemeData(
      color: _separator,
      thickness: 0.7,
      space: 1,
    ),
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
      primaryContainer: _blueDeep,
      onPrimaryContainer: Colors.white,
    ),
    useMaterial3: true,
    fontFamily: _fontFamily,
    scaffoldBackgroundColor: _navy,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    iconTheme: const IconThemeData(color: _goldDark),
    cardTheme: CardThemeData(
      elevation: 0,
      color: _navyCard,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      margin: EdgeInsets.zero,
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: _navy,
      foregroundColor: Colors.white,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: _titleStyle.copyWith(color: Colors.white),
      iconTheme: const IconThemeData(color: _goldDark),
      actionsIconTheme: const IconThemeData(color: _goldDark),
    ),
    listTileTheme: const ListTileThemeData(
      iconColor: _goldDark,
      contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 3),
      minVerticalPadding: 10,
      minLeadingWidth: 28,
      titleTextStyle: TextStyle(
        fontFamily: _fontFamily,
        fontSize: 16,
        fontWeight: FontWeight.w500,
        color: Colors.white,
      ),
      subtitleTextStyle: TextStyle(
        fontFamily: _fontFamily,
        fontSize: 13,
        color: Color(0xFFB7BCC4),
      ),
    ),
    inputDecorationTheme: _inputTheme(_navyContainer, _blueOnDark),
    dividerTheme: const DividerThemeData(
      color: Color(0xFF24394C),
      thickness: 0.7,
      space: 1,
    ),
  );

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
