import 'package:cloud_firestore/cloud_firestore.dart';
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
      // 網頁版 Firestore 預設走 WebChannel，在部分瀏覽器/網路會默默卡死
      // （.get() 永遠不回也不報錯 → 同步停在「同步中…」）。強制 long-polling
      // 走一般 HTTP 輪詢，幾乎所有環境都通，代價僅為些微延遲（備份用途可接受）。
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: false,
        webExperimentalForceLongPolling: true,
      );
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
