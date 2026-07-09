import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import 'admin_screen.dart';

/// 設定：外觀主題、字級。
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final fontSize = ref.watch(fontSizeProvider);
    final readingMode = ref.watch(readingModeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        children: [
          const _AccountSection(),
          const _SectionHeader('外觀'),
          RadioListTile<ThemeMode>(
            title: const Text('跟隨系統'),
            value: ThemeMode.system,
            groupValue: themeMode,
            onChanged: (v) =>
                ref.read(themeModeProvider.notifier).set(v!),
          ),
          RadioListTile<ThemeMode>(
            title: const Text('淺色'),
            value: ThemeMode.light,
            groupValue: themeMode,
            onChanged: (v) =>
                ref.read(themeModeProvider.notifier).set(v!),
          ),
          RadioListTile<ThemeMode>(
            title: const Text('深色'),
            value: ThemeMode.dark,
            groupValue: themeMode,
            onChanged: (v) =>
                ref.read(themeModeProvider.notifier).set(v!),
          ),
          const Divider(),
          const _SectionHeader('閱讀'),
          ListTile(
            title: const Text('內文字級'),
            subtitle: Slider(
              value: fontSize,
              min: FontSizeNotifier.min,
              max: FontSizeNotifier.max,
              divisions: 14,
              label: fontSize.toStringAsFixed(0),
              onChanged: (v) =>
                  ref.read(fontSizeProvider.notifier).set(v),
            ),
            trailing: Text('${fontSize.toStringAsFixed(0)}pt'),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              '起初，　神創造天地。',
              style: TextStyle(fontSize: fontSize, height: 1.7),
            ),
          ),
          SwitchListTile(
            title: const Text('整章連續閱讀'),
            subtitle: const Text('關閉為逐節分行；讀經畫面右上角也能切換'),
            value: readingMode == ReadingMode.flowing,
            onChanged: (_) =>
                ref.read(readingModeProvider.notifier).toggle(),
          ),
          SwitchListTile(
            title: const Text('中英對照'),
            subtitle: const Text('每節中文下方顯示英文（KJV）；讀經畫面右上角也能切換'),
            value: ref.watch(bilingualProvider),
            onChanged: (_) =>
                ref.read(bilingualProvider.notifier).toggle(),
          ),
          const Divider(),
          const AboutListTile(
            icon: Icon(Icons.info_outline),
            applicationName: '聖經 App',
            applicationVersion: '1.0.0',
            aboutBoxChildren: [
              Text('經文：和合本（繁體），公有領域。'),
            ],
          ),
        ],
      ),
    );
  }
}

/// 帳號與雲端備份（Firebase 未初始化時整段隱藏，離線功能不受影響）。
class _AccountSection extends ConsumerWidget {
  const _AccountSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(firebaseReadyProvider)) return const SizedBox.shrink();
    final user = ref.watch(authUserProvider).value;
    final status = ref.watch(syncStatusProvider);
    final notifier = ref.read(syncStatusProvider.notifier);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _SectionHeader('帳號與雲端備份'),
        if (user == null)
          ListTile(
            leading: const Icon(Icons.login),
            title: const Text('使用 Google 登入'),
            subtitle: const Text('登入後書籤、螢光筆、筆記、讀經紀錄會備份到雲端'),
            onTap: notifier.signIn,
          )
        else ...[
          ListTile(
            leading: const Icon(Icons.account_circle),
            title: Text(user.displayName ?? '已登入'),
            subtitle: Text(user.email ?? ''),
          ),
          ListTile(
            leading: const Icon(Icons.cloud_sync),
            title: const Text('立即同步'),
            onTap: notifier.syncNow,
          ),
          if (ref.watch(isAdminProvider))
            ListTile(
              leading: const Icon(Icons.admin_panel_settings),
              title: const Text('內容管理（後台）'),
              subtitle: const Text('撰寫導讀、統整、每節註解並發布'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const AdminHomeScreen()),
              ),
            ),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('登出'),
            onTap: notifier.signOut,
          ),
        ],
        if (status != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(status,
                style: Theme.of(context)
                    .textTheme
                    .bodySmall
                    ?.copyWith(color: Theme.of(context).colorScheme.primary)),
          ),
        const Divider(),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader(this.title);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        title,
        style: TextStyle(
          color: Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}
