import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase_options.dart';
import 'providers/providers.dart';
import 'screens/home_screen.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Firebase 目前只設定了 Web；init 失敗「或卡住」都不能擋 App。
  // 注意：Firebase JS SDK 載入失敗時 initializeApp 可能永遠不回來（實測），
  // 必須加 timeout，否則整個 App 白屏。
  if (kIsWeb) {
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.web)
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // 沒網路、設定問題或逾時：登入/同步功能自動隱藏，離線讀經照常。
    }
  }
  runApp(const ProviderScope(child: BibleApp()));
}

class BibleApp extends ConsumerWidget {
  const BibleApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: '聖經',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      home: const HomeScreen(),
    );
  }
}
