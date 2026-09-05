import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/church.dart';
import '../providers/providers.dart';

/// Admin：教會管理（list / create / edit / active-inactive）。⛔ 教會名稱由管理者親填。
class AdminChurchesScreen extends ConsumerWidget {
  const AdminChurchesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminAllChurchesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('教會')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('新增教會'),
        onPressed: () => _edit(context, ref, null),
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('載入失敗：$e')),
        data: (churches) => churches.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('尚無教會。右下角可新增。'),
                ),
              )
            : ListView(
                children: [
                  for (final c in churches)
                    ListTile(
                      leading: const Icon(Icons.church_outlined),
                      title: Text(
                        c.name.isEmpty ? c.id : c.name,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text(
                        '${c.region.isEmpty ? '' : '${c.region} · '}${c.active ? 'Active' : 'Inactive'}',
                      ),
                      trailing: Switch(
                        value: c.active,
                        onChanged: (v) async {
                          await ref
                              .read(churchRepositoryProvider)
                              .setChurchActive(c.id, v);
                          ref.invalidate(adminAllChurchesProvider);
                        },
                      ),
                      onTap: () => _edit(context, ref, c),
                    ),
                ],
              ),
      ),
    );
  }

  Future<void> _edit(BuildContext context, WidgetRef ref, Church? c) async {
    final repo = ref.read(churchRepositoryProvider);
    final capabilities = c == null
        ? ChurchCapabilities.disabled()
        : await repo.fetchChurchCapabilities(c.id);
    if (!context.mounted) return;
    final id = TextEditingController(text: c?.id ?? '');
    final name = TextEditingController(text: c?.name ?? '');
    final region = TextEditingController(text: c?.region ?? '');
    bool active = c?.active ?? false;
    bool teacherArea = capabilities.teacherArea;
    showDialog<void>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (context, setLocal) => AlertDialog(
          title: Text(c == null ? '新增教會' : '編輯教會'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: id,
                  enabled: c == null,
                  decoration: const InputDecoration(
                    labelText: 'ID / slug（建立後不可改）',
                    isDense: true,
                  ),
                ),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(
                    labelText: '教會名稱',
                    isDense: true,
                  ),
                ),
                TextField(
                  controller: region,
                  decoration: const InputDecoration(
                    labelText: '地區（選填，可公開）',
                    isDense: true,
                  ),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Active（可申請／可作為發佈對象）'),
                  value: active,
                  onChanged: (v) => setLocal(() => active = v),
                ),
                SwitchListTile(
                  key: const Key('church-teacher-area-switch'),
                  contentPadding: EdgeInsets.zero,
                  title: const Text('老師專區'),
                  subtitle: const Text('開放此教會的老師專區入口'),
                  value: teacherArea,
                  onChanged: (v) => setLocal(() => teacherArea = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () async {
                final cid = id.text.trim();
                if (cid.isEmpty) return;
                await repo.saveChurch(
                  Church(
                    id: cid,
                    name: name.text.trim(),
                    region: region.text.trim(),
                    active: active,
                    createdAt:
                        c?.createdAt ?? DateTime.now().millisecondsSinceEpoch,
                  ),
                );
                await repo.saveChurchCapabilities(
                  ChurchCapabilities(churchId: cid, teacherArea: teacherArea),
                );
                ref.invalidate(adminAllChurchesProvider);
                if (context.mounted) Navigator.pop(context);
              },
              child: const Text('儲存'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Admin：Membership 申請審核（pending approve/reject；active 可 revoke）。
/// doc-id=uid → 一人一 membership，因此**第二間教會的 approval 不可能覆蓋**（結構不變量）。
class AdminMembershipRequestsScreen extends ConsumerWidget {
  const AdminMembershipRequestsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(adminPendingMembershipsProvider);
    final email = ref.watch(adminEmailProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('教會會籍申請')),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('載入失敗：$e')),
        data: (list) => list.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text('目前沒有待審申請。'),
                ),
              )
            : ListView(
                children: [
                  for (final m in list)
                    Card(
                      margin: const EdgeInsets.all(8),
                      child: ListTile(
                        title: Text('使用者 ${m.uid}'),
                        subtitle: Text(
                          '申請加入：${m.churchId}｜狀態：${m.status?.label ?? ''}',
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton(
                              onPressed: () => _act(
                                ref,
                                () => ref
                                    .read(churchRepositoryProvider)
                                    .approveMembership(m.uid, email),
                              ),
                              child: const Text('通過'),
                            ),
                            TextButton(
                              onPressed: () => _act(
                                ref,
                                () => ref
                                    .read(churchRepositoryProvider)
                                    .rejectMembership(m.uid, email),
                              ),
                              child: const Text('退回'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      '註：每位使用者最多一筆會籍（doc-id=uid）。已有 Active 教會者不能被核准第二間；'
                      '需先 Revoke 目前會籍。',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Future<void> _act(WidgetRef ref, Future<void> Function() op) async {
    await op();
    ref.invalidate(adminPendingMembershipsProvider);
  }
}
