import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase_options.dart';
import 'providers/providers.dart';
import 'screens/app_shell.dart';
import 'theme/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Firebase 目前只設定了 Web；init 失敗或卡住都不能擋 App。
  // 保留既有 8 秒 timeout 與 Firestore long-polling，避免 UI 重構造成
  // 已驗證可用的登入／同步／離線能力倒退。
  if (kIsWeb) {
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.web)
          .timeout(const Duration(seconds: 8));
      FirebaseFirestore.instance.settings = const Settings(
        persistenceEnabled: false,
        webExperimentalForceLongPolling: true,
      );
    } catch (_) {
      // 沒網路、設定問題或逾時：登入/同步功能不可用，但離線讀經照常。
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
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      home: const AppShell(),
    );
  }
}
