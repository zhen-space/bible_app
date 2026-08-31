import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/knowledge.dart';
import '../providers/providers.dart';
import '../services/app_links.dart';
import 'topics_screen.dart';

/// 依節位字串跳到讀經頁（統一走 AppLinks 原子化跳轉）。
void _jumpRef(BuildContext context, WidgetRef ref, String refStr) =>
    AppLinks.openVerseRef(context, ref, refStr);

Widget _empty(String msg) => Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(msg, textAlign: TextAlign.center),
      ),
    );

/// 知識架構首頁（hub）。
class KnowledgeScreen extends ConsumerWidget {
  const KnowledgeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kb = ref.watch(knowledgeProvider).value ?? KnowledgeBase.empty;
    return Scaffold(
      appBar: AppBar(title: const Text('研讀內容')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _hub(context, Icons.category_outlined, '主題',
              '依主題與人生情境探索經文', const TopicsScreen()),
          _hub(context, Icons.timeline, '聖經時間軸',
              '${kb.timeline.length} 個事件・依年代排列', const TimelineScreen()),
          _hub(context, Icons.people_alt_outlined, '人物',
              '${kb.people.length} 位・生平、重大事件、關係', const PeopleScreen()),
          _hub(context, Icons.compare_arrows, '平行經文對照',
              '${kb.parallels.length} 組', const ParallelsScreen()),
          _hub(context, Icons.link, '預表與應驗',
              '${kb.types.length} 組・舊約預表→新約應驗', const TypesScreen()),
        ],
      ),
    );
  }

  Widget _hub(BuildContext context, IconData icon, String title,
          String subtitle, Widget screen) =>
      Card(
        margin: const EdgeInsets.symmetric(vertical: 6),
        child: ListTile(
          leading: Icon(icon,
              color: Theme.of(context).colorScheme.secondary, size: 28),
          title: Text(title,
              style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(subtitle),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.push(
              context, MaterialPageRoute(builder: (_) => screen)),
        ),
      );
}

/// 聖經時間軸：依分期分組，事件依 order 排。
class TimelineScreen extends ConsumerWidget {
  const TimelineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kb = ref.watch(knowledgeProvider).value ?? KnowledgeBase.empty;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('聖經時間軸')),
      body: kb.timeline.isEmpty
          ? _empty('時間軸還沒有內容。\n可在 assets/knowledge/knowledge.json 的 timeline 補上。')
          : ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: kb.timeline.length,
              itemBuilder: (context, i) {
                final e = kb.timeline[i];
                final showEra =
                    i == 0 || kb.timeline[i - 1].era != e.era;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (showEra && e.era.isNotEmpty)
                      Padding(
                        padding: EdgeInsets.only(top: i == 0 ? 0 : 20, bottom: 8),
                        child: Text(e.era,
                            style: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.copyWith(
                                    color: scheme.primary,
                                    fontWeight: FontWeight.w700)),
                      ),
                    IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Column(
                            children: [
                              Container(
                                width: 12,
                                height: 12,
                                margin: const EdgeInsets.only(top: 4),
                                decoration: BoxDecoration(
                                    color: scheme.secondary,
                                    shape: BoxShape.circle),
                              ),
                              Expanded(
                                child: Container(
                                    width: 2, color: scheme.outlineVariant),
                              ),
                            ],
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 18),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (e.when.isNotEmpty)
                                    Text(e.when,
                                        style: Theme.of(context)
                                            .textTheme
                                            .labelSmall
                                            ?.copyWith(color: scheme.outline)),
                                  Text(e.title,
                                      style: const TextStyle(
                                          fontWeight: FontWeight.w600,
                                          height: 1.5)),
                                  if (e.ref.isNotEmpty)
                                    TextButton(
                                      style: TextButton.styleFrom(
                                          padding: EdgeInsets.zero,
                                          minimumSize: const Size(0, 32),
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap),
                                      onPressed: () =>
                                          _jumpRef(context, ref, e.ref),
                                      child: Text('📖 ${e.ref}'),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
    );
  }
}

/// 人物列表。
class PeopleScreen extends ConsumerWidget {
  const PeopleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kb = ref.watch(knowledgeProvider).value ?? KnowledgeBase.empty;
    return Scaffold(
      appBar: AppBar(title: const Text('聖經人物')),
      body: kb.people.isEmpty
          ? _empty('人物還沒有內容。\n可在 assets/knowledge/knowledge.json 的 people 補上。')
          : ListView.separated(
              itemCount: kb.people.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final p = kb.people[i];
                return ListTile(
                  leading: CircleAvatar(
                      child: Text(p.name.isEmpty ? '?' : p.name.characters.first)),
                  title: Text(p.name),
                  subtitle: p.aka.isEmpty
                      ? null
                      : Text('又名：${p.aka.join('、')}'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => PersonDetailScreen(personId: p.id)),
                  ),
                );
              },
            ),
    );
  }
}

/// 人物詳情：生平＋重大事件＋關係（關係可跳到對方）。
class PersonDetailScreen extends ConsumerWidget {
  final String personId;
  const PersonDetailScreen({super.key, required this.personId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kb = ref.watch(knowledgeProvider).value ?? KnowledgeBase.empty;
    final p = kb.personById(personId);
    if (p == null) {
      return Scaffold(
        appBar: AppBar(),
        body: _empty('找不到這個人物'),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(p.name)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (p.aka.isNotEmpty)
            Text('又名：${p.aka.join('、')}',
                style: Theme.of(context).textTheme.bodySmall),
          if (p.bio.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(p.bio, style: const TextStyle(height: 1.8)),
          ],
          if (p.events.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('重大事件',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: scheme.primary)),
            const SizedBox(height: 8),
            for (final ev in p.events)
              ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(Icons.event_note, color: scheme.secondary),
                title: Text(ev.title),
                subtitle: ev.ref.isEmpty ? null : Text('📖 ${ev.ref}'),
                onTap: ev.ref.isEmpty
                    ? null
                    : () => _jumpRef(context, ref, ev.ref),
              ),
          ],
          if (p.relations.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text('關係',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(color: scheme.primary)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final r in p.relations)
                  ActionChip(
                    avatar: const Icon(Icons.people_outline, size: 16),
                    label: Text('${r.type}：${r.name}'),
                    onPressed: kb.personById(r.personId) == null
                        ? null
                        : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) =>
                                    PersonDetailScreen(personId: r.personId),
                              ),
                            ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// 平行經文對照。
class ParallelsScreen extends ConsumerWidget {
  const ParallelsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kb = ref.watch(knowledgeProvider).value ?? KnowledgeBase.empty;
    return Scaffold(
      appBar: AppBar(title: const Text('平行經文對照')),
      body: kb.parallels.isEmpty
          ? _empty('平行經文還沒有內容。\n可在 assets/knowledge/knowledge.json 的 parallels 補上。')
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: kb.parallels.length,
              separatorBuilder: (_, _) => const Divider(height: 28),
              itemBuilder: (context, i) {
                final p = kb.parallels[i];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (p.title.isNotEmpty)
                      Text(p.title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, height: 1.5)),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final r in p.refs)
                          ActionChip(
                            avatar: const Icon(Icons.menu_book, size: 16),
                            label: Text(r),
                            onPressed: () => _jumpRef(context, ref, r),
                          ),
                      ],
                    ),
                  ],
                );
              },
            ),
    );
  }
}

/// 舊約預表 → 新約應驗。
class TypesScreen extends ConsumerWidget {
  const TypesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final kb = ref.watch(knowledgeProvider).value ?? KnowledgeBase.empty;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('預表與應驗')),
      body: kb.types.isEmpty
          ? _empty('預表／應驗還沒有內容。\n可在 assets/knowledge/knowledge.json 的 types 補上。')
          : ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: kb.types.length,
              separatorBuilder: (_, _) => const Divider(height: 28),
              itemBuilder: (context, i) {
                final t = kb.types[i];
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (t.title.isNotEmpty)
                      Text(t.title,
                          style: const TextStyle(
                              fontWeight: FontWeight.w700, height: 1.5)),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        if (t.otRef.isNotEmpty)
                          _refChip(context, ref, '預表', t.otRef,
                              scheme.primaryContainer),
                        if (t.otRef.isNotEmpty && t.ntRef.isNotEmpty)
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 6),
                            child: Icon(Icons.arrow_forward, size: 18),
                          ),
                        if (t.ntRef.isNotEmpty)
                          _refChip(context, ref, '應驗', t.ntRef,
                              scheme.secondaryContainer),
                      ],
                    ),
                    if (t.note.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(t.note, style: const TextStyle(height: 1.6)),
                    ],
                  ],
                );
              },
            ),
    );
  }

  Widget _refChip(BuildContext context, WidgetRef ref, String label,
          String refStr, Color bg) =>
      ActionChip(
        backgroundColor: bg,
        label: Text('$label $refStr'),
        onPressed: () => _jumpRef(context, ref, refStr),
      );
}
