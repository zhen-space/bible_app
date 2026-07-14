import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'firebase_options.dart';
import 'providers/providers.dart';
import 'screens/admin_dashboard_screen.dart';
import 'theme/app_theme.dart';

/// 獨立「內容後台」app 的進入點。
/// build：flutter build web -t lib/main_admin.dart（見 render-build-admin.sh）。
/// 與讀經 app 共用資料與程式，只是入口換成 AdminGate。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (kIsWeb) {
    try {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.web)
          .timeout(const Duration(seconds: 8));
    } catch (_) {
      // 後台一定要雲端；失敗時 AdminGate 會顯示提示。
    }
  }
  runApp(const ProviderScope(child: AdminApp()));
}

class AdminApp extends ConsumerWidget {
  const AdminApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    return MaterialApp(
      title: '聖經 App · 內容後台',
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      home: const AdminGate(),
    );
  }
}
