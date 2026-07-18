import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/models.dart';
import '../providers/providers.dart';

/// 禱告事項：分類 → 子分類 → 內容。使用者自行新增/編輯/刪除，
/// **不設打勾**（禱告不是待辦清單）。
class PrayersScreen extends ConsumerWidget {
  const PrayersScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final prayers = ref.watch(allPrayersProvider).value ?? const <Prayer>[];
    final scheme = Theme.of(context).colorScheme;

    // 分類 → 子分類 → 條目（保留 DB 排序：分類、子分類、新到舊）
    final byCategory = <String, Map<String, List<Prayer>>>{};
    for (final p in prayers) {
      final cat = p.category.isEmpty ? '未分類' : p.category;
      final sub = p.subcategory;
      ((byCategory[cat] ??= {})[sub] ??= []).add(p);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('禱告事項')),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('新增'),
        onPressed: () => showPrayerEditor(context, ref, null),
      ),
      body: prayers.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Text('還沒有禱告事項。\n點右下角新增，可自訂分類與子分類。',
                    textAlign: TextAlign.center),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                for (final cat in byCategory.entries) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 14, bottom: 6),
                    child: Text(cat.key,
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(
                                color: scheme.primary,
                                fontWeight: FontWeight.w700)),
                  ),
                  for (final sub in cat.value.entries) ...[
                    if (sub.key.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 2),
                        child: Text(sub.key,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(color: scheme.secondary)),
                      ),
                    for (final p in sub.value)
                      Card(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        child: ListTile(
                          leading: Icon(Icons.volunteer_activism_outlined,
                              color: scheme.secondary),
                          title: Text(p.content,
                              style: const TextStyle(height: 1.5)),
                          onTap: () => showPrayerEditor(context, ref, p),
                        ),
                      ),
                  ],
                ],
              ],
            ),
    );
  }
}

/// 新增／編輯禱告事項（底部表單）。[existing] 為 null 表示新增。
void showPrayerEditor(
    BuildContext context, WidgetRef ref, Prayer? existing) {
  final category = TextEditingController(text: existing?.category ?? '');
  final subcategory =
      TextEditingController(text: existing?.subcategory ?? '');
  final content = TextEditingController(text: existing?.content ?? '');
  // 既有分類做成快速選擇 chips，免重打
  final prayers = ref.read(allPrayersProvider).value ?? const <Prayer>[];
  final cats = {
    for (final p in prayers)
      if (p.category.isNotEmpty) p.category
  }.toList();

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(ctx).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(existing == null ? '新增禱告事項' : '編輯禱告事項',
              style: Theme.of(ctx).textTheme.titleMedium),
          const SizedBox(height: 12),
          if (cats.isNotEmpty) ...[
            Wrap(
              spacing: 6,
              children: [
                for (final c in cats)
                  ActionChip(
                      label: Text(c),
                      onPressed: () => category.text = c),
              ],
            ),
            const SizedBox(height: 8),
          ],
          TextField(
            controller: category,
            decoration: const InputDecoration(
              labelText: '分類（例：家人、教會、宣教）',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: subcategory,
            decoration: const InputDecoration(
              labelText: '子分類（可空，例：爸爸）',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: content,
            maxLines: 3,
            autofocus: existing == null,
            decoration: const InputDecoration(
              labelText: '禱告內容',
              border: OutlineInputBorder(),
              alignLabelWithHint: true,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              if (existing != null)
                TextButton(
                  onPressed: () async {
                    Navigator.pop(ctx);
                    try {
                      await ref
                          .read(databaseServiceProvider)
                          .deletePrayer(existing.id!);
                    } finally {
                      ref.invalidate(allPrayersProvider);
                    }
                  },
                  child: const Text('刪除'),
                ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () async {
                  final text = content.text.trim();
                  Navigator.pop(ctx);
                  if (text.isEmpty) return;
                  try {
                    await ref.read(databaseServiceProvider).savePrayer(
                          Prayer(
                            id: existing?.id,
                            category: category.text.trim(),
                            subcategory: subcategory.text.trim(),
                            content: text,
                            createdAt: existing?.createdAt ?? 0,
                            updatedAt: existing?.updatedAt ?? 0,
                          ),
                        );
                  } finally {
                    ref.invalidate(allPrayersProvider);
                  }
                },
                child: const Text('儲存'),
              ),
            ],
          ),
          const SizedBox(height: 16),
        ],
      ),
    ),
  );
}
