import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/providers.dart';
import '../theme/app_theme.dart';
import '../widgets/google_login_button_stub.dart'
    if (dart.library.js_interop) '../widgets/google_login_button_web.dart';

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
            title: const Text('段落分段閱讀'),
            subtitle: const Text('依自然斷句分段呈現；關閉為逐節分行。讀經畫面右上角也能切換'),
            value: readingMode == ReadingMode.paragraph,
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
          const _SectionHeader('首頁'),
          ListTile(
            title: const Text('禱告事項區塊位置'),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                      value: 'top', label: Text('繼續閱讀下面')),
                  ButtonSegment(
                      value: 'bottom', label: Text('整頁下面')),
                ],
                selected: {ref.watch(prayerPositionProvider)},
                onSelectionChanged: (s) => ref
                    .read(prayerPositionProvider.notifier)
                    .set(s.first),
              ),
            ),
          ),
          const Divider(),
          const _SectionHeader('螢光筆命名'),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Text('給每個顏色一個意義（例：黃＝應許、綠＝命令），'
                '劃記時就會顯示這個標籤。',
                style: TextStyle(fontSize: 13)),
          ),
          const _HighlightLabelsSection(),
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
        if (user == null) ...[
          const ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('尚未登入'),
            subtitle: Text('登入後才會顯示帳號、雲端同步與投稿功能'),
          ),
          const ListTile(
            leading: Icon(Icons.cloud_outlined),
            title: Text('登入以備份到雲端'),
            subtitle: Text('書籤、螢光筆、筆記、讀經紀錄會自動同步'),
          ),
          if (gisSupported) ...[
            // 網頁版：Google 官方登入按鈕（GIS）
            googleLoginButton(),
            // GIS 換憑證若失敗，把錯誤顯示出來（不再靜默看起來像空白）
            ValueListenableBuilder<String?>(
              valueListenable: googleLoginError,
              builder: (context, err, _) => err == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding:
                          const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      child: Text(err,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                              fontSize: 13)),
                    ),
            ),
            // 備用：signInWithPopup（官方按鈕視窗打不開/空白時用這個）
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextButton(
                onPressed: notifier.signIn,
                child: const Text('上面的按鈕沒反應？改用備用視窗登入'),
              ),
            ),
          ] else
            ListTile(
              leading: const Icon(Icons.login),
              title: const Text('使用 Google 登入'),
              onTap: notifier.signIn,
            ),
        ]
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
            const ListTile(
              leading: Icon(Icons.admin_panel_settings),
              title: Text('內容管理已移到獨立後台'),
              subtitle: Text('請用「內容後台」網站（main_admin）登入管理'),
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

/// 螢光筆命名區：每個顏色一格圓點 + 輸入框，邊打邊存。
class _HighlightLabelsSection extends ConsumerWidget {
  const _HighlightLabelsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final labels = ref.watch(highlightLabelsProvider);
    return Column(
      children: [
        for (final c in HighlightColor.values)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Row(
              children: [
                CircleAvatar(
                    radius: 12, backgroundColor: AppTheme.highlightSwatch(c)),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    initialValue: labels[c] ?? '',
                    decoration: const InputDecoration(
                      isDense: true,
                      border: OutlineInputBorder(),
                      hintText: '未命名',
                    ),
                    onChanged: (v) => ref
                        .read(highlightLabelsProvider.notifier)
                        .setLabel(c, v),
                  ),
                ),
              ],
            ),
          ),
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
