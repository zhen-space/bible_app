import 'package:flutter/material.dart';

/// 非網頁平台：不顯示 GIS 按鈕（手機走 signInWithProvider 原生流程）。
Widget googleLoginButton() => const SizedBox.shrink();

bool get gisSupported => false;

/// 與 web 版同名符號（非網頁不會有 GIS 錯誤）。
final ValueNotifier<String?> googleLoginError = ValueNotifier<String?>(null);
