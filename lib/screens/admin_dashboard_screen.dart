import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/providers.dart';
import '../widgets/google_login_button_stub.dart'
    if (dart.library.js_interop) '../widgets/google_login_button_web.dart';
import 'admin_screen.dart';
import 'admin_knowledge_screen.dart';
import 'admin_study_content_screen.dart';
import 'admin_church_screen.dart';
import 'admin_daily_verse_screen.dart';
import 'qa_screen.dart';

/// 獨立後台 app 的進入點畫面：登入 → 只有管理者能進 → 管理儀表板。
class AdminGate extends ConsumerWidget {
  const AdminGate({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!ref.watch(firebaseReadyProvider)) {
      return const _Message('後台需要連上雲端（Firebase）才能使用。');
    }
    final user = ref.watch(authUserProvider).value;
    if (user == null) return const _AdminLogin();
    if (!ref.watch(isAdminProvider)) {
      return _Message(
        '此帳號（${user.email ?? ''}）不是管理者，無法進入後台。',
        action: TextButton(
          onPressed: () => ref.read(syncStatusProvider.notifier).signOut(),
          child: const Text('登出，換帳號'),
        ),
      );
    }
    return const AdminDashboard();
  }
}

class _AdminLogin extends ConsumerWidget {
  const _AdminLogin();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(syncStatusProvider.notifier);
    return Scaffold(
      appBar: AppBar(title: const Text('聖經 App · 內容後台')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.admin_panel_settings, size: 56),
              const SizedBox(height: 12),
              const Text('請用管理者帳號登入',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 24),
              if (gisSupported) ...[
                googleLoginButton(),
                TextButton(
                  onPressed: notifier.signIn,
                  child: const Text('按鈕沒反應？改用備用方式登入'),
                ),
              ] else
                FilledButton.icon(
                  icon: const Icon(Icons.login),
                  label: const Text('使用 Google 登入'),
                  onPressed: notifier.signIn,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 管理儀表板：導讀/註解、公開註解審核、Q&A、知識架構。
class AdminDashboard extends ConsumerWidget {
  const AdminDashboard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authUserProvider).value;
    final pendingSubs =
        ref.watch(pendingSubmissionsProvider).value?.length ?? 0;
    final pendingQs = ref.watch(pendingQuestionsProvider).value?.length ?? 0;
    return Scaffold(
      appBar: AppBar(
        title: const Text('內容後台'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: '登出',
            onPressed: () => ref.read(syncStatusProvider.notifier).signOut(),
          ),
        ],
      ),
      body: ListView(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text('管理者：${user?.email ?? ''}',
                style: Theme.of(context).textTheme.bodySmall),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text('內容管理',
                style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          _tile(context, Icons.auto_stories, '研讀內容',
              '新版 study_content：逐項工作流＋學生可見度', const AdminStudyContentScreen()),
          _tile(context, Icons.category_outlined, '主題',
              '正式 study_topics：分類與學生可見度', const AdminTopicScreen()),
          _tile(context, Icons.today_outlined, '每日經文',
              'Draft→Review→Published；每日一則', const AdminDailyVerseScreen()),
          _tile(context, Icons.forum_outlined, 'Q&A',
              '審核問題、親自回答、回答依據', const QaAdminScreen(), badge: pendingQs),
          _tile(context, Icons.inventory_2_outlined, 'Legacy Knowledge',
              '舊版 knowledge/data aggregate（內部維護，非新版研讀內容入口）',
              const KnowledgeAdminScreen()),
          const Divider(height: 24),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text('教會與教師', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          _tile(context, Icons.church_outlined, '教會',
              '建立／管理教會、Active 狀態', const AdminChurchesScreen()),
          _tile(context, Icons.how_to_reg_outlined, '教會會籍申請',
              '審核加入申請（通過／退回）', const AdminMembershipRequestsScreen()),
          const Divider(height: 24),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 4, 16, 4),
            child: Text('導讀／註解', style: TextStyle(fontWeight: FontWeight.w700)),
          ),
          _tile(context, Icons.menu_book_outlined, '導讀／註解編輯',
              '卷導讀、章導讀、每節註解（含公開註解審核）', const AdminHomeScreen(),
              badge: pendingSubs),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('⛔ 所有內容文字由你親寫；這裡只是編輯器。',
                style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }

  Widget _tile(BuildContext c, IconData icon, String title, String sub,
          Widget screen,
          {int badge = 0}) =>
      ListTile(
        leading: Icon(icon,
            color: Theme.of(c).colorScheme.secondary, size: 28),
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(sub),
        trailing: badge > 0
            ? CircleAvatar(
                radius: 12,
                backgroundColor: Theme.of(c).colorScheme.primary,
                child: Text('$badge',
                    style:
                        const TextStyle(fontSize: 12, color: Colors.white)))
            : const Icon(Icons.chevron_right),
        onTap: () =>
            Navigator.push(c, MaterialPageRoute(builder: (_) => screen)),
      );
}

class _Message extends StatelessWidget {
  final String text;
  final Widget? action;
  const _Message(this.text, {this.action});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('內容後台')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(text, textAlign: TextAlign.center),
              if (action != null) ...[const SizedBox(height: 16), action!],
            ],
          ),
        ),
      ),
    );
  }
}
