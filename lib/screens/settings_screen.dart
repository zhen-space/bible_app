import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';

/// 設定：外觀主題、字級。
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final fontSize = ref.watch(fontSizeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        children: [
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
