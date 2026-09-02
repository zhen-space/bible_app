import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/church.dart';
import '../providers/providers.dart';

/// Me → 教會。完整 membership 狀態（none/pending/active/rejected/revoked）。
/// **authorization-first**：pending/rejected/revoked 皆不授權；前端不得 self-approve/switch/revoke。
class ChurchMembershipScreen extends ConsumerWidget {
  const ChurchMembershipScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ready = ref.watch(firebaseReadyProvider);
    final user = ref.watch(authUserProvider).value;
    final membershipAsync = ref.watch(myMembershipProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('教會')),
      body: !ready || user == null
          ? _pad(const Text('登入後才能設定教會。公開內容不受影響。'))
          : membershipAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, _) => _pad(Text('載入失敗：$e')),
              data: (m) => _body(context, ref, m),
            ),
    );
  }

  Widget _body(BuildContext context, WidgetRef ref, Membership? m) {
    final status = m?.status;
    switch (status) {
      case null:
        return _state(context, ref,
            icon: Icons.church_outlined,
            title: '尚未選擇教會',
            desc: '若你所屬的教會有提供研讀內容，可以選擇教會並提出加入申請。',
            action: _pickButton(context, '選擇教會'));
      case MembershipStatus.pending:
        return _churchState(context, ref, m!,
            badge: '申請審核中',
            desc: '你的加入申請正在審核。審核通過前，教會專屬內容不會開放。');
      case MembershipStatus.active:
        return _churchState(context, ref, m!,
            badge: '已加入',
            desc: '你現在可以閱讀這間教會提供給成員的內容。',
            extra: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 16),
              Text('需要更換教會？',
                  style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              const Text('你目前已有加入中的教會。更換教會須先由管理員處理目前的會籍，'
                  '不能在此直接切換。'),
            ]));
      case MembershipStatus.rejected:
        return _state(context, ref,
            icon: Icons.info_outline,
            title: '申請未通過',
            desc: '你可以重新提出加入申請。',
            action: _pickButton(context, '重新申請'));
      case MembershipStatus.revoked:
        return _churchState(context, ref, m!,
            badge: '教會存取權已結束',
            desc: '你目前無法再存取這間教會的教會專屬內容。公開內容與你的個人資料不受影響。',
            extra: Padding(
              padding: const EdgeInsets.only(top: 16),
              child: _pickButton(context, '重新申請'),
            ));
    }
  }

  Widget _churchState(BuildContext context, WidgetRef ref, Membership m,
      {required String badge, required String desc, Widget? extra}) {
    return _pad(FutureBuilder<Church?>(
      future: ref.read(churchRepositoryProvider).fetchChurch(m.churchId),
      builder: (context, snap) {
        final name = snap.data?.name.isNotEmpty == true
            ? snap.data!.name
            : m.churchId;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(name,
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(badge,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.onSecondaryContainer,
                    fontWeight: FontWeight.w600)),
          ),
          const SizedBox(height: 12),
          Text(desc),
          if (extra != null) extra,
        ]);
      },
    ));
  }

  Widget _state(BuildContext context, WidgetRef ref,
      {required IconData icon,
      required String title,
      required String desc,
      required Widget action}) {
    return _pad(Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Icon(icon, size: 28),
        const SizedBox(width: 10),
        Text(title,
            style: Theme.of(context)
                .textTheme
                .titleLarge
                ?.copyWith(fontWeight: FontWeight.w700)),
      ]),
      const SizedBox(height: 12),
      Text(desc),
      const SizedBox(height: 20),
      action,
    ]));
  }

  Widget _pickButton(BuildContext context, String label) => FilledButton.icon(
        icon: const Icon(Icons.search),
        label: Text(label),
        onPressed: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const ChurchPickerScreen())),
      );

  Widget _pad(Widget child) =>
      Padding(padding: const EdgeInsets.all(20), child: child);
}

/// Church Picker：只列 active churches 的公開表示；選擇→確認→提出 pending 申請（非立即授權）。
class ChurchPickerScreen extends ConsumerStatefulWidget {
  const ChurchPickerScreen({super.key});

  @override
  ConsumerState<ChurchPickerScreen> createState() => _ChurchPickerScreenState();
}

class _ChurchPickerScreenState extends ConsumerState<ChurchPickerScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final churchesAsync = ref.watch(activeChurchesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('選擇教會')),
      body: Column(children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.search),
              hintText: '搜尋教會名稱',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (v) => setState(() => _q = v.trim()),
          ),
        ),
        Expanded(
          child: churchesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('載入失敗：$e')),
            data: (churches) {
              final list = churches
                  .where((c) => _q.isEmpty || c.name.contains(_q))
                  .toList();
              if (list.isEmpty) {
                return const Center(
                    child: Padding(
                        padding: EdgeInsets.all(32),
                        child: Text('目前沒有可加入的教會。')));
              }
              return ListView(
                children: [
                  for (final c in list)
                    ListTile(
                      leading: const Icon(Icons.church_outlined),
                      title: Text(c.name.isEmpty ? c.id : c.name),
                      subtitle: c.region.isEmpty ? null : Text(c.region),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () => _confirm(context, c),
                    ),
                ],
              );
            },
          ),
        ),
      ]),
    );
  }

  Future<void> _confirm(BuildContext context, Church c) async {
    final m = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('申請加入「${c.name.isEmpty ? c.id : c.name}」'),
        content: const Text('送出後會由管理員審核。選擇教會不代表已取得教會專屬內容權限，'
            '審核通過後才會開放。'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('提出加入申請')),
        ],
      ),
    );
    if (ok != true) return;
    final uid = ref.read(authUserProvider).value?.uid;
    if (uid == null) return;
    try {
      await ref.read(churchRepositoryProvider).requestMembership(uid, c.id);
      ref.invalidate(myMembershipProvider);
      m.showSnackBar(const SnackBar(content: Text('已提出加入申請，等待管理員審核')));
      nav.pop();
    } catch (e) {
      m.showSnackBar(SnackBar(content: Text('申請失敗：$e')));
    }
  }
}
