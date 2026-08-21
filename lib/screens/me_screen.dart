import 'package:flutter/material.dart';

import 'prayers_screen.dart';
import 'settings_screen.dart';

/// 低頻與個人管理功能集中在「我的」，避免主導航變成工具箱。
class MeScreen extends StatelessWidget {
  const MeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('我的')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          _sectionTitle(context, '我的讀經'),
          Card(
            child: Column(children: [
              ListTile(
                leading: const Icon(Icons.volunteer_activism_outlined),
                title: const Text('禱告事項'),
                subtitle: const Text('記錄正在禱告的事情'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PrayersScreen())),
              ),
              const Divider(height: 1),
              const ListTile(
                enabled: false,
                leading: Icon(Icons.history),
                title: Text('閱讀紀錄與進度'),
                subtitle: Text('新版整合頁準備中；既有閱讀紀錄仍持續保存'),
              ),
            ]),
          ),
          const SizedBox(height: 24),
          _sectionTitle(context, 'App'),
          Card(
            child: ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('設定'),
              subtitle: const Text('外觀、閱讀、登入與同步'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 12, 4, 8),
    child: Text(text, style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
  );
}
