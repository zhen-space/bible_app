import 'package:flutter/material.dart';

/// 非網頁平台：不顯示 GIS 按鈕（手機走 signInWithProvider 原生流程）。
Widget googleLoginButton() => const SizedBox.shrink();

bool get gisSupported => false;
