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
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              children: [
                // 每個「分類」＝一張獨立卡片；子分類、內容在卡內縮排巢狀
                for (final cat in byCategory.entries)
                  Card(
                    margin: const EdgeInsets.only(bottom: 14),
                    clipBehavior: Clip.antiAlias,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // 分類標題條（實心底色，最顯眼那層）
                        Container(
                          color: scheme.primary,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 10),
                          child: Row(
                            children: [
                              const Icon(Icons.folder_outlined,
                                  size: 18, color: Colors.white),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(cat.key,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 16)),
                              ),
                              Text(
                                  '${cat.value.values.fold<int>(0, (a, b) => a + b.length)} 則',
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 12)),
                            ],
                          ),
                        ),
                        // 子分類 + 內容
                        for (final sub in cat.value.entries)
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (sub.key.isNotEmpty)
                                Container(
                                  width: double.infinity,
                                  color: scheme.primary.withValues(alpha: 0.08),
                                  padding: const EdgeInsets.fromLTRB(
                                      16, 6, 16, 6),
                                  child: Row(
                                    children: [
                                      Icon(Icons.subdirectory_arrow_right,
                                          size: 16, color: scheme.secondary),
                                      const SizedBox(width: 6),
                                      Text(sub.key,
                                          style: TextStyle(
                                              color: scheme.secondary,
                                              fontWeight: FontWeight.w600)),
                                    ],
                                  ),
                                ),
                              for (final p in sub.value)
                                InkWell(
                                  onTap: () =>
                                      showPrayerEditor(context, ref, p),
                                  child: Padding(
                                    // 有子分類→再縮排；沒有→只縮一層
                                    padding: EdgeInsets.fromLTRB(
                                        sub.key.isNotEmpty ? 34 : 16,
                                        10,
                                        16,
                                        10),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Padding(
                                          padding:
                                              const EdgeInsets.only(top: 6),
                                          child: Icon(Icons.circle,
                                              size: 6,
                                              color: scheme.secondary),
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(p.content,
                                              style: const TextStyle(
                                                  height: 1.5)),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              const Divider(height: 1),
                            ],
                          ),
                      ],
                    ),
                  ),
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
